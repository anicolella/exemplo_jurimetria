# ==============================================================================
# Tratamento reproduzível dos dados públicos do DataJud
# ==============================================================================
#
# Objetivo:
#   Transformar as coletas brutas do TJSP, TJMT e TJSC em uma base analítica
#   consolidada, com uma linha por processo, pronta para o relatório Quarto.
#
# Unidade de análise:
#   Processo judicial identificado pela combinação `tribunal` + `id`.
#
# Entradas:
#   dados/brutos/tjsp/
#   dados/brutos/tjmt/
#   dados/brutos/tjsc/
#
# Saída principal:
#   dados/tratados/base_analitica.rds
#
# Execução, a partir da raiz do projeto:
#   Rscript R/02_tratar_dados.R
#
# Reprodutibilidade:
#   O script não consulta a API, não depende de edição manual da base e deverá
#   produzir o mesmo arquivo quando executado sobre os mesmos dados brutos e a
#   mesma configuração. A saída somente é gravada após todas as validações.
#
# Decisões que devem ser validadas antes do primeiro uso:
#   1. códigos dos movimentos que identificam a decisão de tutela;
#   2. códigos dos movimentos tratados como riscos concorrentes;
#   3. data administrativa de encerramento do acompanhamento.
# ==============================================================================

# 1. Configuração -------------------------------------------------------------

pacotes_necessarios <- c(
  "datajud", "dplyr", "jsonlite", "lubridate", "purrr", "tibble"
)

tribunais <- c("TJSP", "TJMT", "TJSC")
classe_codigo <- 7L
assunto_codigo <- 12495L
data_inicial <- as.POSIXct("2022-01-01 00:00:00", tz = "UTC")

# PREENCHER somente depois da validação jurídica e empírica dos movimentos.
# Enquanto esses vetores estiverem vazios, o script interromperá antes de ler os
# dados para evitar a criação silenciosa de uma base analítica incorreta.
codigos_evento_tutela <- integer()
codigos_riscos_concorrentes <- integer()

# Definir uma data fixa torna a censura administrativa reproduzível. Substituir
# NA pela data efetiva de encerramento antes da primeira execução completa.
fim_observacao <- as.POSIXct(NA, tz = "UTC")

diretorio_bruto <- file.path("dados", "brutos")
diretorio_tratado <- file.path("dados", "tratados")
arquivo_saida <- file.path(diretorio_tratado, "base_analitica.rds")


# 2. Funções de apoio e mensagens --------------------------------------------

informar_etapa <- function(numero, texto) {
  horario <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  message(sprintf("[%s] Etapa %02d - %s", horario, numero, texto))
}

informar_contagem <- function(rotulo, n_antes, n_depois) {
  message(
    sprintf(
      "  %s: %s antes; %s depois; %s removido(s).",
      rotulo,
      format(n_antes, big.mark = "."),
      format(n_depois, big.mark = "."),
      format(n_antes - n_depois, big.mark = ".")
    )
  )
}

interromper <- function(texto) {
  stop(texto, call. = FALSE)
}

verificar_pacotes <- function(pacotes) {
  ausentes <- pacotes[
    !vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(ausentes) > 0L) {
    interromper(
      paste0(
        "Pacotes R ausentes: ", paste(ausentes, collapse = ", "),
        ". Restaure o ambiente antes de tratar os dados."
      )
    )
  }
}

verificar_configuracao <- function() {
  if (length(codigos_evento_tutela) == 0L) {
    interromper(
      "Defina e valide `codigos_evento_tutela` antes de executar o tratamento."
    )
  }

  if (length(codigos_riscos_concorrentes) == 0L) {
    interromper(
      paste0(
        "Defina e valide `codigos_riscos_concorrentes` antes de executar ",
        "o tratamento."
      )
    )
  }

  codigos_repetidos <- intersect(
    codigos_evento_tutela,
    codigos_riscos_concorrentes
  )
  if (length(codigos_repetidos) > 0L) {
    interromper(
      paste0(
        "Os mesmos códigos foram classificados como tutela e risco ",
        "concorrente: ", paste(codigos_repetidos, collapse = ", "), "."
      )
    )
  }

  if (is.na(fim_observacao)) {
    interromper("Defina `fim_observacao` antes de executar o tratamento.")
  }

  if (fim_observacao < data_inicial) {
    interromper("`fim_observacao` não pode ser anterior a `data_inicial`.")
  }
}

verificar_entradas <- function() {
  diretorios <- file.path(diretorio_bruto, tolower(tribunais))
  manifestos <- file.path(diretorios, "manifesto.json")

  ausentes <- diretorios[!dir.exists(diretorios)]
  if (length(ausentes) > 0L) {
    interromper(
      paste0("Diretórios brutos ausentes: ", paste(ausentes, collapse = ", "))
    )
  }

  sem_manifesto <- manifestos[!file.exists(manifestos)]
  if (length(sem_manifesto) > 0L) {
    interromper(
      paste0(
        "Coletas sem manifesto: ", paste(sem_manifesto, collapse = ", "),
        ". Execute primeiro R/01_coletar_datajud.R."
      )
    )
  }
}


# 3. Leitura dos processos e movimentos --------------------------------------

# `datajud_ler_processo()` padroniza os campos gerais, mas não materializa os
# movimentos. Por isso, cada página é lida uma vez e usada para construir duas
# tabelas: processos e movimentos.

movimentos_vazios <- function() {
  tibble::tibble(
    tribunal = character(),
    id = character(),
    numero_processo = character(),
    movimento_codigo = integer(),
    movimento_nome = character(),
    movimento_data = as.POSIXct(character(), tz = "UTC"),
    complementos_json = character()
  )
}

extrair_movimentos_hit <- function(hit, tribunal_esperado) {
  fonte <- hit[["_source"]]
  movimentos <- fonte[["movimentos"]]

  if (is.null(movimentos) || length(movimentos) == 0L) {
    return(movimentos_vazios())
  }

  purrr::map_dfr(movimentos, function(movimento) {
    tibble::tibble(
      tribunal = tribunal_esperado,
      id = as.character(fonte[["id"]]),
      numero_processo = as.character(fonte[["numeroProcesso"]]),
      movimento_codigo = as.integer(movimento[["codigo"]]),
      movimento_nome = as.character(movimento[["nome"]]),
      movimento_data = lubridate::as_datetime(
        movimento[["dataHora"]], tz = "UTC"
      ),
      complementos_json = as.character(
        jsonlite::toJSON(
          movimento[["complementosTabelados"]],
          auto_unbox = TRUE,
          null = "null"
        )
      )
    )
  })
}

ler_tribunal <- function(tribunal) {
  diretorio <- file.path(diretorio_bruto, tolower(tribunal))
  coleta <- datajud::datajud_abrir_coleta(diretorio)

  if (!identical(coleta$metadados$estado, "completa")) {
    interromper(
      paste0(
        "A coleta de ", tribunal, " não está completa. Estado informado: ",
        coleta$metadados$estado, "."
      )
    )
  }

  paginas <- lapply(
    seq_along(coleta$arquivos),
    function(indice) datajud::datajud_ler_pagina(coleta, indice)
  )

  processos <- purrr::map_dfr(paginas, datajud::datajud_ler_processo)
  movimentos <- purrr::map_dfr(paginas, function(pagina) {
    purrr::map_dfr(
      pagina$hits,
      extrair_movimentos_hit,
      tribunal_esperado = tribunal
    )
  })

  list(processos = processos, movimentos = movimentos)
}


# 4. Padronização e deduplicação ---------------------------------------------

padronizar_processos <- function(processos, tribunal_esperado) {
  processos |>
    dplyr::mutate(
      tribunal = toupper(as.character(tribunal)),
      id = as.character(id),
      numero_processo = as.character(numero_processo),
      data_ajuizamento = lubridate::as_datetime(data_ajuizamento, tz = "UTC"),
      data_atualizacao = lubridate::as_datetime(data_atualizacao, tz = "UTC")
    ) |>
    dplyr::filter(tribunal == tribunal_esperado) |>
    dplyr::arrange(tribunal, id, dplyr::desc(data_atualizacao)) |>
    dplyr::distinct(tribunal, id, .keep_all = TRUE)
}

padronizar_movimentos <- function(movimentos) {
  movimentos |>
    dplyr::mutate(
      tribunal = toupper(as.character(tribunal)),
      id = as.character(id),
      movimento_codigo = as.integer(movimento_codigo),
      movimento_data = lubridate::as_datetime(movimento_data, tz = "UTC")
    ) |>
    dplyr::distinct(
      tribunal, id, movimento_codigo, movimento_data, movimento_nome,
      .keep_all = TRUE
    )
}


# 5. Critérios de inclusão e exclusão ----------------------------------------

possui_assunto <- function(assuntos, codigo) {
  if (is.null(assuntos) || nrow(assuntos) == 0L) {
    return(FALSE)
  }
  any(assuntos$codigo == codigo, na.rm = TRUE)
}

aplicar_criterios <- function(processos) {
  avaliacao <- processos |>
    dplyr::mutate(
      assunto_elegivel = vapply(
        assuntos, possui_assunto, logical(1), codigo = assunto_codigo
      ),
      motivo_exclusao = dplyr::case_when(
        !tribunal %in% tribunais ~ "tribunal não configurado",
        is.na(classe_tpu) ~ "classe ausente",
        classe_tpu != classe_codigo ~ "classe não elegível",
        !assunto_elegivel ~ "assunto 12495 ausente",
        is.na(data_ajuizamento) ~ "data de ajuizamento ausente",
        data_ajuizamento < data_inicial ~ "ajuizamento anterior ao recorte",
        data_ajuizamento > fim_observacao ~ "ajuizamento após o fim do estudo",
        TRUE ~ "incluído"
      )
    )

  list(
    base = avaliacao |>
      dplyr::filter(motivo_exclusao == "incluído") |>
      dplyr::select(-motivo_exclusao),
    fluxo = avaliacao |>
      dplyr::count(motivo_exclusao, name = "processos") |>
      dplyr::arrange(dplyr::desc(processos))
  )
}


# 6. Construção dos eventos analíticos ---------------------------------------

construir_eventos <- function(processos, movimentos) {
  movimentos_interesse <- movimentos |>
    dplyr::filter(
      movimento_codigo %in% c(
        codigos_evento_tutela,
        codigos_riscos_concorrentes
      )
    ) |>
    dplyr::mutate(
      tipo_evento = dplyr::if_else(
        movimento_codigo %in% codigos_evento_tutela,
        "tutela",
        "risco_concorrente"
      )
    ) |>
    dplyr::arrange(tribunal, id, movimento_data) |>
    dplyr::group_by(tribunal, id) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::select(
      tribunal, id, tipo_evento, movimento_codigo, movimento_nome,
      data_evento = movimento_data
    )

  processos |>
    dplyr::left_join(movimentos_interesse, by = c("tribunal", "id")) |>
    dplyr::mutate(
      status_evento = dplyr::case_when(
        tipo_evento == "tutela" ~ 1L,
        tipo_evento == "risco_concorrente" ~ 2L,
        TRUE ~ 0L
      ),
      data_final = dplyr::coalesce(data_evento, fim_observacao),
      tempo_dias = as.numeric(
        difftime(data_final, data_ajuizamento, units = "days")
      )
    )
}


# 7. Verificações de consistência --------------------------------------------

validar_base <- function(base) {
  problemas <- character()

  if (anyDuplicated(base[c("tribunal", "id")]) > 0L) {
    problemas <- c(problemas, "existem processos duplicados")
  }
  if (any(is.na(base$data_ajuizamento))) {
    problemas <- c(problemas, "existem datas de ajuizamento ausentes")
  }
  if (any(is.na(base$tempo_dias))) {
    problemas <- c(problemas, "existem tempos de acompanhamento ausentes")
  }
  if (any(base$tempo_dias < 0, na.rm = TRUE)) {
    problemas <- c(problemas, "existem eventos anteriores ao ajuizamento")
  }
  if (!all(base$tribunal %in% tribunais)) {
    problemas <- c(problemas, "existem tribunais não configurados")
  }
  if (!all(base$status_evento %in% 0:2)) {
    problemas <- c(problemas, "existem códigos de status inválidos")
  }

  if (length(problemas) > 0L) {
    interromper(
      paste0(
        "A base não foi salva porque falhou nas verificações: ",
        paste(problemas, collapse = "; "), "."
      )
    )
  }

  invisible(TRUE)
}


# 8. Execução integral --------------------------------------------------------

informar_etapa(1, "Verificando dependências e configuração.")
verificar_pacotes(pacotes_necessarios)
verificar_configuracao()
verificar_entradas()

informar_etapa(2, "Lendo as coletas completas dos três tribunais.")
bases_por_tribunal <- stats::setNames(lapply(tribunais, ler_tribunal), tribunais)

informar_etapa(3, "Padronizando e deduplicando processos e movimentos.")
n_processos_lidos <- sum(
  purrr::map_int(bases_por_tribunal, ~ nrow(.x$processos))
)
n_movimentos_lidos <- sum(
  purrr::map_int(bases_por_tribunal, ~ nrow(.x$movimentos))
)
processos <- purrr::imap_dfr(
  bases_por_tribunal,
  function(base, tribunal) padronizar_processos(base$processos, tribunal)
)
movimentos <- bases_por_tribunal |>
  purrr::map("movimentos") |>
  purrr::list_rbind() |>
  padronizar_movimentos()

informar_contagem("Deduplicação de processos", n_processos_lidos, nrow(processos))
informar_contagem("Deduplicação de movimentos", n_movimentos_lidos, nrow(movimentos))

informar_etapa(4, "Aplicando os critérios de inclusão e exclusão.")
resultado_criterios <- aplicar_criterios(processos)
base_elegivel <- resultado_criterios$base
informar_contagem("Critérios da coorte", nrow(processos), nrow(base_elegivel))
message("  Fluxo da amostra por motivo:")
print(resultado_criterios$fluxo, n = Inf)

informar_etapa(5, "Construindo eventos, censura e tempo de acompanhamento.")
base_analitica <- construir_eventos(base_elegivel, movimentos)

informar_etapa(6, "Executando verificações de consistência.")
validar_base(base_analitica)

informar_etapa(7, "Apresentando o resumo final da base.")
resumo_final <- base_analitica |>
  dplyr::count(tribunal, status_evento, name = "processos") |>
  dplyr::arrange(tribunal, status_evento)
print(resumo_final, n = Inf)

informar_etapa(8, "Salvando a base analítica consolidada.")
dir.create(diretorio_tratado, recursive = TRUE, showWarnings = FALSE)
saveRDS(base_analitica, arquivo_saida, compress = "xz")

message(
  "Base salva em ", arquivo_saida, " com ",
  format(nrow(base_analitica), big.mark = "."), " processo(s)."
)
