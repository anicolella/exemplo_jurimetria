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
#   dados/tratados/base_analitica.parquet
#
# Execução, a partir da raiz do projeto:
#   Rscript R/02_tratar_dados.R
#
# Reprodutibilidade:
#   O script não consulta a API, não depende de edição manual da base e deverá
#   produzir o mesmo arquivo quando executado sobre os mesmos dados brutos e a
#   mesma configuração. A saída somente é gravada após todas as validações.
#
# Decisões metodológicas registradas neste script:
#   1. a coorte é formada por processos da classe 7 e do assunto 12495;
#   2. a unidade de análise é o processo, e não cada movimento processual;
#   3. o tempo começa na data de ajuizamento informada pelo DataJud;
#   4. o evento de interesse é a primeira decisão sobre tutela, reunindo
#      concessão, concessão parcial e não concessão;
#   5. encerramentos sem uma decisão anterior de tutela são riscos concorrentes;
#   6. mera suspensão do processo não é tratada como risco concorrente;
#   7. processos sem evento são censurados em uma data administrativa fixa;
#   8. a comparação antes/depois usa a data de ajuizamento e 19/09/2024 como
#      marco do Tema 1234;
#   9. em duplicidades, conserva-se o registro processual mais atualizado;
#  10. nenhuma saída é salva quando uma verificação de consistência falha.
#
# Decisão ainda pendente:
#   - preencher `fim_observacao` com a data efetiva e documentada de fechamento
#     da coleta. O script para deliberadamente enquanto essa data for `NA`.
# ==============================================================================

# 1. Configuração -------------------------------------------------------------

pacotes_necessarios <- c(
  "arrow", "dplyr", "jsonlite", "lubridate", "purrr", "tibble"
)

tribunais <- c("TJSP", "TJMT", "TJSC")
classe_codigo <- 7L
assunto_codigo <- 12495L
data_inicial <- as.POSIXct("2022-01-01 00:00:00", tz = "UTC")

# Códigos da Tabela Processual Unificada (TPU/CNJ). A classificação abaixo
# deve ser confrontada com os nomes observados na amostra antes da coleta
# completa, pois a qualidade do preenchimento pode variar entre tribunais.
#
# Evento de interesse: concessão, concessão parcial ou não concessão de tutela
# provisória/liminar. O desfecho mede a primeira decisão sobre tutela, qualquer
# que seja o seu resultado; análises por resultado poderão ser acrescentadas
# depois, preservando o código original do movimento.
codigos_evento_tutela <- c(332L, 339L, 785L, 792L, 889L, 892L)

# Significado dos códigos de tutela na TPU/CNJ:
#   332 = concessão de tutela provisória;
#   339 = concessão de liminar;
#   785 = não concessão de tutela provisória;
#   792 = não concessão de liminar;
#   889 = concessão parcial de tutela provisória;
#   892 = concessão parcial de liminar.
# A agregação responde primeiro à pergunta "houve decisão sobre a tutela?".
# O código e o nome originais permanecem na base para análises posteriores do
# conteúdo da decisão (concedida, negada ou parcialmente concedida).

# Riscos concorrentes: encerramentos que impedem a observação posterior de uma
# decisão de tutela no processo. Incluem acordo/transação, cancelamento da
# distribuição e extinção sem resolução do mérito. Movimentos de suspensão,
# como os códigos 268 e 11013, não são eventos terminais e foram excluídos.
# Os códigos-pai 218 (sem resolução do mérito) e 456 (extinção), assim como
# seus subtipos relevantes, foram mantidos porque tribunais podem registrar o
# movimento em diferentes níveis da hierarquia da TPU. Eventuais repetições
# são resolvidas pela escolha cronológica do primeiro evento do processo.
codigos_riscos_concorrentes <- c(
  83L, 218L, 454L, 456L, 458L, 459L, 460L, 461L, 462L, 463L, 464L,
  466L, 488L, 11376L, 11378L, 11379L, 11380L, 11381L, 12256L, 12325L,
  14848L, 15238L
)

# Marco temporal principal: publicação da ata do julgamento de mérito do Tema
# 1234 no DJE. A variável de período compara processos ajuizados antes e a
# partir desse marco; ela não substitui a data administrativa de censura.
marco_tema_1234 <- as.POSIXct("2024-09-19 00:00:00", tz = "UTC")

# Definir uma data fixa torna a censura administrativa reproduzível. Substituir
# NA pela data efetiva de encerramento antes da primeira execução completa.
fim_observacao <- as.POSIXct(NA, tz = "UTC")

diretorio_bruto <- file.path("dados", "brutos")
diretorio_tratado <- file.path("dados", "tratados")
arquivo_saida <- file.path(diretorio_tratado, "base_analitica.parquet")


# 2. Funções de apoio e mensagens --------------------------------------------

informar_etapa <- function(numero, texto) {
  horario <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  message(sprintf("[%s] Etapa %02d - %s", horario, numero, texto))
}

# Exibe o efeito de uma transformação sobre o número de registros. Esta função
# não altera dados; ela torna auditáveis a deduplicação e os filtros da coorte.
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

# Interrompe a execução com uma mensagem curta, sem imprimir uma pilha de
# chamadas. É usada quando continuar poderia produzir uma base incorreta.
interromper <- function(texto) {
  stop(texto, call. = FALSE)
}

# Confirma que todas as dependências estão instaladas antes de ler arquivos.
# Entrada: vetor de nomes de pacotes. Saída: invisível; erro se houver ausentes.
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

# Valida decisões metodológicas que precisam estar definidas antes do uso.
# Também impede que um mesmo código seja simultaneamente evento de tutela e
# risco concorrente. Não lê nem modifica a base.
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

# Confirma a existência das três coletas e de seus manifestos. O manifesto é
# usado como evidência de que a etapa de coleta foi registrada; sua presença
# não substitui a checagem de estado completo feita em `ler_tribunal()`.
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

# Cada página Parquet contém uma linha por hit e preserva o hit integral em
# `hit_json`. O JSON é desserializado uma única vez e usado para construir duas
# tabelas: processos e movimentos.

# Retorna uma tabela vazia com tipos estáveis. Isso permite combinar processos
# sem movimentos com os demais sem criar colunas de tipos inconsistentes.
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

# Converte os movimentos aninhados de um único resultado (`hit`) em uma tabela
# longa: uma linha por movimento. `tribunal_esperado` vem do diretório lido e
# evita depender de eventual ausência ou inconsistência desse campo no hit.
# Os complementos são preservados como JSON para não perder informação bruta.
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

# Converte a lista de assuntos da fonte em uma pequena tabela por processo. A
# coluna permanece como lista durante o tratamento para permitir verificar o
# código 12495 sem perder os demais assuntos associados.
extrair_assuntos_hit <- function(hit) {
  assuntos <- hit[["_source"]][["assuntos"]]
  if (is.null(assuntos) || length(assuntos) == 0L) {
    return(tibble::tibble(codigo = integer(), nome = character()))
  }

  purrr::map_dfr(assuntos, function(assunto) {
    tibble::tibble(
      codigo = as.integer(assunto[["codigo"]]),
      nome = as.character(assunto[["nome"]])
    )
  })
}

# Extrai os campos processuais necessários de um único hit bruto. Campos que
# não participam da análise não são descartados na coleta: continuam íntegros
# no `hit_json` do Parquet bruto e podem ser recuperados posteriormente.
extrair_processo_hit <- function(hit, tribunal_esperado) {
  fonte <- hit[["_source"]]
  id <- fonte[["id"]]
  if (is.null(id)) id <- hit[["_id"]]

  tibble::tibble(
    tribunal = tribunal_esperado,
    id = as.character(id),
    numero_processo = as.character(fonte[["numeroProcesso"]]),
    grau = as.character(fonte[["grau"]]),
    nivel_sigilo = as.integer(fonte[["nivelSigilo"]]),
    data_ajuizamento = lubridate::as_datetime(
      fonte[["dataAjuizamento"]], tz = "UTC"
    ),
    data_atualizacao = lubridate::as_datetime(
      fonte[["dataHoraUltimaAtualizacao"]], tz = "UTC"
    ),
    classe_tpu = as.integer(fonte[["classe"]][["codigo"]]),
    classe_nome = as.character(fonte[["classe"]][["nome"]]),
    assuntos = list(extrair_assuntos_hit(hit))
  )
}

# Lê integralmente os Parquets de um tribunal e retorna duas tabelas: processos
# e movimentos. A função confere o estado e o número de páginas do manifesto e
# recusa coletas incompletas para impedir análises parciais.
ler_tribunal <- function(tribunal) {
  diretorio <- file.path(diretorio_bruto, tolower(tribunal))
  caminho_manifesto <- file.path(diretorio, "manifesto.json")
  manifesto <- jsonlite::read_json(caminho_manifesto, simplifyVector = TRUE)

  if (!identical(manifesto$estado, "completa")) {
    interromper(
      paste0(
        "A coleta de ", tribunal, " não está completa. Estado informado: ",
        manifesto$estado, "."
      )
    )
  }

  arquivos <- sort(list.files(
    diretorio,
    pattern = "^pagina_[0-9]{6}\\.parquet$",
    full.names = TRUE
  ))
  if (length(arquivos) != as.integer(manifesto$paginas_concluidas)) {
    interromper(
      paste0(
        tribunal, ": manifesto informa ", manifesto$paginas_concluidas,
        " página(s), mas foram encontrados ", length(arquivos),
        " arquivo(s) Parquet."
      )
    )
  }

  paginas <- lapply(arquivos, arrow::read_parquet, as_data_frame = TRUE)
  hits <- paginas |>
    purrr::map("hit_json") |>
    purrr::list_flatten() |>
    purrr::map(jsonlite::fromJSON, simplifyVector = FALSE)

  processos <- purrr::map_dfr(hits, extrair_processo_hit, tribunal_esperado = tribunal)
  movimentos <- purrr::map_dfr(hits, extrair_movimentos_hit, tribunal_esperado = tribunal)

  list(processos = processos, movimentos = movimentos)
}


# 4. Padronização e deduplicação ---------------------------------------------

# Padroniza identificadores e datas e remove duplicidades de processos.
# Decisão: a chave é `tribunal + id`; quando a mesma chave aparece mais de uma
# vez, conserva-se o registro com a `data_atualizacao` mais recente.
# Registros atribuídos a tribunal diferente do diretório lido são descartados.
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

# Padroniza a tabela longa de movimentos e remove repetições exatas pela chave
# tribunal, processo, código, data e nome. Movimentos distintos na mesma data
# são preservados quando possuem código ou nome diferentes.
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

# Verifica se a lista de assuntos de um processo contém o código solicitado.
# Ausência de assuntos é interpretada como não elegibilidade, e não como prova
# de que o processo pertence ao assunto pesquisado.
possui_assunto <- function(assuntos, codigo) {
  if (is.null(assuntos) || nrow(assuntos) == 0L) {
    return(FALSE)
  }
  any(assuntos$codigo == codigo, na.rm = TRUE)
}

# Aplica critérios em ordem explícita e atribui um único motivo principal de
# exclusão a cada processo. Retorna `base`, com os elegíveis, e `fluxo`, tabela
# de auditoria com as contagens de inclusão e exclusão.
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

# Constrói as variáveis da análise de sobrevivência e riscos concorrentes.
#
# Para cada processo, ordena cronologicamente todos os movimentos de interesse
# e conserva somente o primeiro. Assim, uma decisão de tutela anterior a uma
# extinção é evento de tutela; uma extinção anterior impede observar tutela e é
# risco concorrente. Processos sem ambos são censurados em `fim_observacao`.
#
# Codificação do desfecho:
#   0 = censura administrativa;
#   1 = primeira decisão sobre tutela;
#   2 = risco concorrente anterior à decisão de tutela.
#
# `tempo_dias` é contado do ajuizamento até evento ou censura. A variável
# `periodo_tema_1234` descreve quando o processo foi ajuizado; ela não altera o
# relógio, o evento nem a data de censura.
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
      periodo_tema_1234 = dplyr::if_else(
        data_ajuizamento < marco_tema_1234,
        "antes",
        "depois"
      ),
      data_final = dplyr::coalesce(data_evento, fim_observacao),
      tempo_dias = as.numeric(
        difftime(data_final, data_ajuizamento, units = "days")
      )
    )
}


# 7. Verificações de consistência --------------------------------------------

# Executa verificações mínimas antes de salvar a base. A função acumula todos
# os problemas encontrados para que a correção não dependa de sucessivas
# execuções. Retorna invisivelmente `TRUE` apenas quando a base é consistente.
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

# Converte colunas-lista em JSON antes da gravação. Parquet funciona melhor
# neste exemplo didático com colunas escalares; a serialização preserva o
# conteúdo aninhado e mantém o arquivo interoperável com R e Python.
preparar_para_parquet <- function(base) {
  colunas_lista <- names(base)[vapply(base, is.list, logical(1))]
  if (length(colunas_lista) == 0L) return(base)

  base |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(colunas_lista),
        ~ vapply(
          .x,
          jsonlite::toJSON,
          character(1),
          auto_unbox = TRUE,
          null = "null",
          na = "null"
        )
      )
    )
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
base_para_salvar <- preparar_para_parquet(base_analitica)
arrow::write_parquet(base_para_salvar, arquivo_saida, compression = "zstd")

message(
  "Base salva em ", arquivo_saida, " com ",
  format(nrow(base_analitica), big.mark = "."), " processo(s)."
)
