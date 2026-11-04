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
#   1. a API é consultada diretamente com `httr`, pois a versão 0.1.0 do pacote
#      `datajud` não oferece coleta retomável e suas funções paginadas não
#      percorrem corretamente todas as páginas;
#   2. a chave pública padrão do pacote é usada quando `DATAJUD_API_KEY` não
#      estiver definida; nenhuma chave é impressa ou salva;
#   3. cada página bruta é salva como Parquet. Cada linha representa um hit e
#      preserva seu conteúdo integral em JSON, além dos identificadores básicos;
#   4. o manifesto registra o último valor de `search_after`, permitindo retomar
#      a coleta sem baixar novamente páginas concluídas;
#   5. a consulta usa ordenação estável por `numeroProcesso.keyword`. O sufixo
#      `.keyword` é exigido pelo Elasticsearch para ordenar esse campo textual;
#      o número processual é único dentro de cada tribunal e permite a retomada;
#   6. a coleta e o tratamento permanecem separados: este script não transforma
#      campos nem combina tribunais;
#   7. o relatório Quarto nunca executará este arquivo automaticamente.
#   8. não se solicita contagem exata global (`track_total_hits`), pois essa
#      operação provocou timeout no TJSP; o manifesto registra a contagem local
#      efetivamente coletada e o fim é identificado pela última página.
#
# Saídas:
#   dados/brutos/tjsp/pagina_000001.parquet e manifesto.json
#   dados/brutos/tjmt/pagina_000001.parquet e manifesto.json
#   dados/brutos/tjsc/pagina_000001.parquet e manifesto.json
# ==============================================================================


# 1. Configuração -------------------------------------------------------------

pacotes_necessarios <- c("arrow", "datajud", "httr", "jsonlite")

tribunais <- c("TJSP", "TJMT", "TJSC")
classe_codigo <- 7L
assunto_codigo <- 12495L
data_inicial <- "2022-01-01T00:00:00.000Z"

tamanho_pagina <- 1000L
limite_registros <- 100000L
limite_paginas <- 1000L
pausa_entre_paginas <- 0.5
timeout_segundos <- 120
tentativas_por_pagina <- 3L

diretorio_bruto <- file.path("dados", "brutos")
url_base <- "https://api-publica.datajud.cnj.jus.br"


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
montar_consulta <- function() {
  list(
    bool = list(
      must = list(
        list(match = list("classe.codigo" = classe_codigo)),
        list(match = list("assuntos.codigo" = assunto_codigo)),
        list(range = list(
          dataAjuizamento = list(gte = data_inicial)
        ))
      )
    )
  )
}

# Converte a sigla humana (por exemplo, TJSP) no índice aceito pela API.
montar_url <- function(tribunal) {
  indice <- datajud::normalize_tribunal(tribunal)
  paste0(url_base, "/", indice, "/_search")
}

# Executa uma página da consulta. `search_after` é enviado no corpo apenas a
# partir da segunda página. `httr::RETRY` repete erros transitórios, enquanto
# erros HTTP definitivos são apresentados sem revelar a chave da API.
consultar_pagina <- function(
    tribunal,
    chave_api,
    tamanho = tamanho_pagina,
    search_after = NULL) {
  corpo <- list(
    query = montar_consulta(),
    size = as.integer(tamanho),
    sort = list(list(`numeroProcesso.keyword` = "asc")),
    track_total_hits = FALSE
  )

  if (!is.null(search_after)) {
    corpo$search_after <- search_after
  }

  resposta <- httr::RETRY(
    verb = "POST",
    url = montar_url(tribunal),
    httr::add_headers(
      Authorization = paste("APIKey", chave_api),
      `Content-Type` = "application/json"
    ),
    body = jsonlite::toJSON(corpo, auto_unbox = TRUE, null = "null"),
    encode = "raw",
    httr::timeout(timeout_segundos),
    times = tentativas_por_pagina,
    pause_base = 1,
    pause_cap = 8,
    terminate_on = c(400, 401, 403, 404)
  )

  if (httr::http_error(resposta)) {
    mensagem <- httr::content(resposta, as = "text", encoding = "UTF-8")
    interromper(
      paste0(
        tribunal, ": API respondeu HTTP ", httr::status_code(resposta),
        ". ", substr(mensagem, 1L, 500L)
      )
    )
  }

  jsonlite::fromJSON(
    httr::content(resposta, as = "text", encoding = "UTF-8"),
    simplifyVector = FALSE
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
    return(manifesto)
  }

  list(
    versao = 1L,
    tribunal = tribunal,
    classe_codigo = classe_codigo,
    assunto_codigo = assunto_codigo,
    data_inicial = data_inicial,
    tamanho_pagina = tamanho_pagina,
    estado = "em_andamento",
    paginas_concluidas = 0L,
    registros_coletados = 0L,
    search_after = NULL,
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
    tamanho_pagina = tamanho_pagina,
    data_inicial = data_inicial
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

# Coleta um tribunal até esgotar resultados ou atingir os limites de segurança.
# Ao retomar, começa na página seguinte e reutiliza o último `search_after`.
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

  informar_etapa(
    paste0(
      tribunal, ": retomando após ", manifesto$paginas_concluidas,
      " página(s) e ", manifesto$registros_coletados, " registro(s)."
    )
  )

  repeat {
    proxima_pagina <- as.integer(manifesto$paginas_concluidas) + 1L
    if (proxima_pagina > limite_paginas ||
        as.integer(manifesto$registros_coletados) >= limite_registros) {
      manifesto$estado <- "limite_atingido"
      salvar_manifesto(manifesto, caminho_manifesto)
      informar_etapa(paste0(tribunal, ": limite de segurança atingido."))
      break
    }

    tamanho_solicitado <- min(
      tamanho_pagina,
      limite_registros - as.integer(manifesto$registros_coletados)
    )
    resposta <- consultar_pagina(
      tribunal = tribunal,
      chave_api = chave_api,
      tamanho = tamanho_solicitado,
      search_after = manifesto$search_after
    )
    hits <- resposta$hits$hits

    if (is.null(hits) || length(hits) == 0L) {
      manifesto$estado <- "completa"
      manifesto$atualizada_em_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
      salvar_manifesto(manifesto, caminho_manifesto)
      informar_etapa(paste0(tribunal, ": não há mais resultados; coleta completa."))
      break
    }

    caminho_pagina <- file.path(
      destino,
      sprintf("pagina_%06d.parquet", proxima_pagina)
    )
    if (file.exists(caminho_pagina)) {
      interromper(
        paste0(
          "A página ", caminho_pagina,
          " já existe, mas não consta como concluída no manifesto."
        )
      )
    }

    # Salva todos os hits brutos; o manifesto preserva os metadados operacionais.
    pagina_parquet <- hits_para_parquet(hits, tribunal, proxima_pagina)
    salvar_parquet_atomico(pagina_parquet, caminho_pagina)

    ultimo_hit <- hits[[length(hits)]]
    if (is.null(ultimo_hit$sort)) {
      interromper(
        paste0(tribunal, ": a API não devolveu `sort`; retomada inviável.")
      )
    }

    manifesto$paginas_concluidas <- proxima_pagina
    manifesto$registros_coletados <-
      as.integer(manifesto$registros_coletados) + length(hits)
    manifesto$search_after <- ultimo_hit$sort
    manifesto$atualizada_em_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)

    # Uma página menor que o solicitado já é a última página.
    if (length(hits) < tamanho_solicitado) {
      manifesto$estado <- "completa"
    }
    salvar_manifesto(manifesto, caminho_manifesto)

    informar_etapa(
      paste0(
        tribunal, ": página ", proxima_pagina, " salva; total local = ",
        manifesto$registros_coletados, "."
      )
    )

    if (identical(manifesto$estado, "completa")) break
    Sys.sleep(pausa_entre_paginas)
  }

  manifesto
}


# 4. Teste mínimo -------------------------------------------------------------

# Consulta somente um registro e não grava arquivos. O teste verifica acesso,
# filtros, estrutura da resposta e presença do campo `sort` usado na retomada.
testar_tribunal <- function(tribunal, chave_api) {
  resposta <- consultar_pagina(
    tribunal = tribunal,
    chave_api = chave_api,
    tamanho = 1L
  )
  hits <- resposta$hits$hits
  possui_sort <- length(hits) == 0L || !is.null(hits[[1L]]$sort)

  if (!possui_sort) {
    interromper(paste0(tribunal, ": resposta sem o campo `sort`."))
  }

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
