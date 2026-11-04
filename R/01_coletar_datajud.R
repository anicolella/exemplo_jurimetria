# ==============================================================================
# Coleta retomável de processos públicos no DataJud
# ==============================================================================
#
# Objetivo:
#   Coletar processos da classe 7 e do assunto 12495 no TJSP, TJMT e TJSC,
#   mantendo os resultados brutos separados por tribunal.
#
# Execução, a partir da raiz do projeto:
#   Rscript R/01_coletar_datajud.R
#
# Teste de conexão (um registro por tribunal, sem salvar dados):
#   Rscript R/01_coletar_datajud.R --teste
#
# Decisões de implementação:
#   1. a API é consultada por `datajud::search_slice()`, disponível na versão
#      atualizada do pacote e capaz de rejeitar respostas incompletas;
#   2. a chave pública padrão do pacote é usada quando `DATAJUD_API_KEY` não
#      estiver definida; nenhuma chave é impressa ou salva;
#   3. cada página bruta é salva como Parquet. Cada linha representa um hit e
#      preserva seu conteúdo integral em JSON, além dos identificadores básicos;
#   4. o manifesto registra as fatias mensais concluídas, permitindo retomar a
#      coleta sem repetir intervalos já validados;
#   5. cada fatia usa `datajud::search_slice()`, que confere total, timeout e
#      falhas de shards antes de devolver a resposta;
#   6. a coleta e o tratamento permanecem separados: este script não transforma
#      campos nem combina tribunais;
#   7. o relatório Quarto nunca executará este arquivo automaticamente.
#   8. a contagem exata ocorre apenas dentro de cada fatia mensal, reduzindo o
#      custo que anteriormente provocava timeout na consulta global do TJSP.
#
# Saídas:
#   dados/brutos/tjsp/pagina_000001.parquet e manifesto.json
#   dados/brutos/tjmt/pagina_000001.parquet e manifesto.json
#   dados/brutos/tjsc/pagina_000001.parquet e manifesto.json
# ==============================================================================


# 1. Configuração -------------------------------------------------------------

pacotes_necessarios <- c("arrow", "datajud", "jsonlite")

tribunais <- c("TJSP", "TJMT", "TJSC")
classe_codigo <- 7L
assunto_codigo <- 12495L
data_inicial <- as.Date("2022-01-01")
data_final <- Sys.Date()

tamanho_maximo_fatia <- 10000L
pausa_entre_fatias <- 0.5
tentativas_por_fatia <- 5L

diretorio_bruto <- file.path("dados", "brutos")
# 2. Funções de apoio ---------------------------------------------------------

# Emite mensagens com horário para que uma coleta longa possa ser auditada.
informar_etapa <- function(texto) {
  horario <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  message(sprintf("[%s] %s", horario, texto))
}

# Interrompe com mensagem objetiva e sem imprimir a pilha de chamadas.
interromper <- function(texto) {
  stop(texto, call. = FALSE)
}

# Garante que o script está sendo executado na raiz correta do projeto.
verificar_raiz_projeto <- function() {
  arquivos_esperados <- c("_quarto.yml", "CODEX.md")
  ausentes <- arquivos_esperados[!file.exists(arquivos_esperados)]

  if (length(ausentes) > 0L) {
    interromper(
      paste0(
        "Execute o script a partir da raiz do projeto. Ausentes: ",
        paste(ausentes, collapse = ", "), "."
      )
    )
  }
}

# Verifica todas as dependências antes da primeira requisição HTTP.
verificar_pacotes <- function(pacotes) {
  ausentes <- pacotes[
    !vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(ausentes) > 0L) {
    interromper(
      paste0(
        "Pacotes R ausentes: ", paste(ausentes, collapse = ", "),
        ". Restaure o ambiente antes de iniciar a coleta."
      )
    )
  }
}

# Obtém a credencial sem expô-la. A variável de ambiente permite substituir a
# chave pública quando necessário; na ausência dela, usa-se a chave do pacote.
obter_chave_api <- function() {
  chave <- Sys.getenv("DATAJUD_API_KEY", unset = "")
  if (!nzchar(chave)) {
    chave <- datajud::get_default_api_key()
  }
  if (!nzchar(chave)) {
    interromper("Não foi possível obter uma chave para a API pública do DataJud.")
  }
  chave
}

# Monta a consulta comum aos três tribunais. `match` replica os filtros usados
# pelo pacote datajud para classe e assunto. O intervalo de ajuizamento começa
# em 2022, exatamente como no tratamento, evitando baixar histórico que seria
# posteriormente excluído e reduzindo o custo da consulta ao TJSP.
# Gera intervalos mensais fechados. Fatias menores reduzem timeouts e permitem
# que `datajud::search_slice()` confirme que todos os hits foram devolvidos.
gerar_fatias <- function(inicio = data_inicial, fim = data_final) {
  inicios <- seq(as.Date(inicio), as.Date(fim), by = "month")
  data.frame(
    inicio = inicios,
    fim = pmin(as.Date(fim), seq(as.Date(inicio), by = "month", length.out = length(inicios) + 1L)[-1L] - 1L)
  )
}

montar_consulta <- function(inicio, fim) {
  list(
    bool = list(
      must = list(
        list(match = list("classe.codigo" = classe_codigo)),
        list(match = list("assuntos.codigo" = assunto_codigo)),
        datajud::date_range_query("dataAjuizamento", inicio, fim)
      )
    )
  )
}

# Consulta uma fatia e exige resposta completa. A função atualizada do pacote
# verifica timeout, shards com falha, total exato e quantidade de hits.
consultar_fatia <- function(tribunal, chave_api, inicio, fim) {
  datajud::search_slice(
    tribunal = tribunal,
    query = montar_consulta(inicio, fim),
    max_size = tamanho_maximo_fatia,
    parse = FALSE,
    api_key = chave_api,
    max_tries = tentativas_por_fatia
  )
}

# Converte os hits aninhados da API em uma tabela própria para Parquet. O JSON
# integral preserva a resposta bruta sem depender de um esquema fixo, enquanto
# as colunas auxiliares facilitam conferências sem desserializar todo o hit.
hits_para_parquet <- function(hits, tribunal, pagina) {
  extrair_texto <- function(hit, campo_fonte, campo_hit = NULL) {
    valor <- hit[["_source"]][[campo_fonte]]
    if (is.null(valor) && !is.null(campo_hit)) valor <- hit[[campo_hit]]
    if (is.null(valor) || length(valor) == 0L) NA_character_ else as.character(valor[[1L]])
  }

  data.frame(
    tribunal = rep(tribunal, length(hits)),
    pagina = rep(as.integer(pagina), length(hits)),
    id = vapply(hits, extrair_texto, character(1), campo_fonte = "id", campo_hit = "_id"),
    numero_processo = vapply(
      hits, extrair_texto, character(1), campo_fonte = "numeroProcesso"
    ),
    hit_json = vapply(
      hits,
      jsonlite::toJSON,
      character(1),
      auto_unbox = TRUE,
      null = "null",
      na = "null"
    ),
    stringsAsFactors = FALSE
  )
}

# Grava Parquet de maneira atômica: primeiro cria um arquivo temporário no mesmo
# diretório e só então o renomeia. Uma interrupção não deixa página parcial com
# o nome de uma página concluída.
salvar_parquet_atomico <- function(tabela, caminho) {
  temporario <- paste0(caminho, ".tmp")
  arrow::write_parquet(tabela, temporario, compression = "zstd")
  if (!file.rename(temporario, caminho)) {
    unlink(temporario)
    interromper(paste0("Não foi possível concluir a gravação de ", caminho, "."))
  }
}

# Salva o manifesto como JSON após cada página concluída. Ele contém somente
# metadados operacionais e nunca armazena a credencial.
salvar_manifesto <- function(manifesto, caminho) {
  temporario <- paste0(caminho, ".tmp")
  jsonlite::write_json(
    manifesto,
    temporario,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  # No Windows, `file.rename()` não substitui de forma confiável um arquivo já
  # existente. `file.copy(overwrite = TRUE)` permite atualizar o manifesto.
  gravado <- if (file.exists(caminho)) {
    file.copy(temporario, caminho, overwrite = TRUE)
  } else {
    file.rename(temporario, caminho)
  }
  if (!gravado) {
    unlink(temporario)
    interromper(paste0("Não foi possível atualizar ", caminho, "."))
  }
  unlink(temporario)
}

# Lê um manifesto existente ou cria o estado inicial de uma nova coleta.
ler_ou_criar_manifesto <- function(tribunal, caminho) {
  if (file.exists(caminho)) {
    manifesto <- jsonlite::read_json(caminho, simplifyVector = FALSE)
    if (!identical(manifesto$tribunal, tribunal)) {
      interromper(paste0("Manifesto incompatível em ", caminho, "."))
    }
    # Uma nova execução em data posterior amplia a janela sem repetir as
    # fatias já concluídas.
    if (as.Date(manifesto$data_final) < data_final) {
      manifesto$data_final <- as.character(data_final)
      manifesto$estado <- "em_andamento"
    }
    return(manifesto)
  }

  list(
    versao = 1L,
    tribunal = tribunal,
    classe_codigo = classe_codigo,
    assunto_codigo = assunto_codigo,
    data_inicial = as.character(data_inicial),
    tamanho_maximo_fatia = tamanho_maximo_fatia,
    data_final = as.character(data_final),
    estado = "em_andamento",
    paginas_concluidas = 0L,
    registros_coletados = 0L,
    fatias_concluidas = character(),
    iniciada_em_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    atualizada_em_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
}

# Confirma que os parâmetros essenciais do manifesto antigo são iguais aos da
# execução atual. Isso impede retomar, no mesmo diretório, uma consulta diversa.
validar_manifesto <- function(manifesto) {
  esperados <- list(
    classe_codigo = classe_codigo,
    assunto_codigo = assunto_codigo,
    tamanho_maximo_fatia = tamanho_maximo_fatia,
    data_inicial = as.character(data_inicial)
  )

  for (campo in names(esperados)) {
    valor_manifesto <- manifesto[[campo]]
    valor_esperado <- esperados[[campo]]
    iguais <- if (is.numeric(valor_esperado)) {
      identical(as.integer(valor_manifesto), as.integer(valor_esperado))
    } else {
      identical(as.character(valor_manifesto), as.character(valor_esperado))
    }
    if (!iguais) {
      interromper(
        paste0(
          "O manifesto existente usa outro valor para `", campo,
          "`. Use outro diretório ou restaure a configuração original."
        )
      )
    }
  }
}


# 3. Coleta retomável ---------------------------------------------------------

# Coleta um tribunal por intervalos mensais completos. A retomada ignora as
# fatias registradas no manifesto, inclusive meses sem resultados.
coletar_tribunal <- function(tribunal, chave_api) {
  destino <- file.path(diretorio_bruto, tolower(tribunal))
  caminho_manifesto <- file.path(destino, "manifesto.json")
  dir.create(destino, recursive = TRUE, showWarnings = FALSE)

  manifesto <- ler_ou_criar_manifesto(tribunal, caminho_manifesto)
  validar_manifesto(manifesto)

  if (identical(manifesto$estado, "completa")) {
    informar_etapa(paste0(tribunal, ": coleta já completa; nada a baixar."))
    return(manifesto)
  }

  fatias <- gerar_fatias(manifesto$data_inicial, manifesto$data_final)
  concluidas <- unlist(manifesto$fatias_concluidas, use.names = FALSE)

  for (i in seq_len(nrow(fatias))) {
    rotulo <- paste(fatias$inicio[[i]], fatias$fim[[i]], sep = "_")
    if (rotulo %in% concluidas) next

    resposta <- consultar_fatia(
      tribunal, chave_api, fatias$inicio[[i]], fatias$fim[[i]]
    )
    hits <- resposta$hits$hits

    if (length(hits) > 0L) {
      proxima_pagina <- as.integer(manifesto$paginas_concluidas) + 1L
      caminho_pagina <- file.path(
        destino, sprintf("pagina_%06d.parquet", proxima_pagina)
      )
      if (file.exists(caminho_pagina)) {
        interromper(paste0("Arquivo inesperado já existente: ", caminho_pagina))
      }
      salvar_parquet_atomico(
        hits_para_parquet(hits, tribunal, proxima_pagina), caminho_pagina
      )
      manifesto$paginas_concluidas <- proxima_pagina
      manifesto$registros_coletados <-
        as.integer(manifesto$registros_coletados) + length(hits)
    }

    concluidas <- c(concluidas, rotulo)
    manifesto$fatias_concluidas <- concluidas
    manifesto$atualizada_em_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
    salvar_manifesto(manifesto, caminho_manifesto)
    informar_etapa(paste0(tribunal, ": fatia ", rotulo, " concluída."))
    Sys.sleep(pausa_entre_fatias)
  }

  manifesto$estado <- "completa"
  manifesto$atualizada_em_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  salvar_manifesto(manifesto, caminho_manifesto)
  manifesto
}


# 4. Teste mínimo -------------------------------------------------------------

# Consulta uma única fatia diária e não grava arquivos. `search_slice()` valida
# que a resposta é completa antes de devolvê-la.
testar_tribunal <- function(tribunal, chave_api) {
  dia <- data_final - 1L
  resposta <- consultar_fatia(tribunal, chave_api, dia, dia)
  hits <- resposta$hits$hits

  informar_etapa(
    paste0(
      tribunal, ": conexão válida; hits no teste = ", length(hits), "."
    )
  )
  invisible(TRUE)
}


# 5. Execução -----------------------------------------------------------------

# Encapsular a execução permite carregar as funções em testes locais sem
# iniciar acidentalmente consultas à API.
executar <- function(argumentos = commandArgs(trailingOnly = TRUE)) {
  modo_teste <- "--teste" %in% argumentos
  argumentos_desconhecidos <- setdiff(argumentos, "--teste")
  if (length(argumentos_desconhecidos) > 0L) {
    interromper(
      paste0(
        "Argumento(s) desconhecido(s): ",
        paste(argumentos_desconhecidos, collapse = ", "), "."
      )
    )
  }

  verificar_raiz_projeto()
  verificar_pacotes(pacotes_necessarios)
  chave_api <- obter_chave_api()

  informar_etapa(
    paste0(
      "Consulta configurada: classe ", classe_codigo,
      "; assunto ", assunto_codigo,
      "; tribunais ", paste(tribunais, collapse = ", "), "."
    )
  )

  if (modo_teste) {
    informar_etapa("Modo de teste: nenhum dado será salvo.")
    resultados <- lapply(tribunais, testar_tribunal, chave_api = chave_api)
    informar_etapa("Teste mínimo concluído para todos os tribunais.")
  } else {
    dir.create(diretorio_bruto, recursive = TRUE, showWarnings = FALSE)
    resultados <- stats::setNames(
      lapply(tribunais, coletar_tribunal, chave_api = chave_api),
      tribunais
    )
    informar_etapa("Coleta encerrada para todos os tribunais configurados.")
  }

  invisible(resultados)
}

if (sys.nframe() == 0L) executar()
