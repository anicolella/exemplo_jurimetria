# ==============================================================================
# Coleta retomável de processos públicos no DataJud
# ==============================================================================
#
# Objetivo:
#   Coletar processos do TJSP, TJMT e TJSC em diretórios separados, preservando
#   os arquivos brutos produzidos pelo pacote datajud.
#
# Entradas:
#   API pública do DataJud, consultada pelo pacote datajud.
#
# Saídas:
#   dados/brutos/tjsp/
#   dados/brutos/tjmt/
#   dados/brutos/tjsc/
#
# Execução, a partir da raiz do projeto:
#   Rscript R/01_coletar_datajud.R
#
# Observações:
#   - a coleta é retomável (`retomar = TRUE`);
#   - páginas já concluídas não devem ser baixadas novamente;
#   - este script não trata nem combina os dados;
#   - este script não deve ser executado pelo relatório Quarto.
#
# ATENÇÃO — compatibilidade pendente:
#   A versão local do pacote `datajud` (0.1.0) não exporta atualmente as
#   funções `datajud_coletar_processos()` e `datajud_cliente()` usadas abaixo.
#   Portanto, este arquivo registra o desenho pretendido da coleta, mas não
#   deve ser executado até sua adaptação e validação por uma consulta mínima em
#   cada tribunal. Essa pendência é explícita para evitar uma falsa impressão
#   de que o coletor já está operacional.
# ==============================================================================

# 1. Configuração -------------------------------------------------------------

pacotes_necessarios <- c("datajud")

tribunais <- c("TJSP", "TJMT", "TJSC")
classe_codigo <- 7L
assunto_codigo <- 12495L

# Decisão de escopo: a mesma consulta será aplicada separadamente aos três
# tribunais. A separação física permite auditar diferenças de cobertura e
# retomar apenas o tribunal interrompido.

# Tamanho de cada página solicitada ao DataJud.
tamanho_pagina <- 1000L

# Limites de segurança da coleta. Devem ser revisados antes da coleta principal
# se a consulta indicar volume superior ao previsto.
limite_registros <- 100000L
limite_paginas <- 1000L

pausa_entre_paginas <- 0.5
timeout_segundos <- 120

diretorio_bruto <- file.path("dados", "brutos")


# 2. Funções auxiliares -------------------------------------------------------

informar_etapa <- function(texto) {
  horario <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  message(sprintf("[%s] %s", horario, texto))
}

verificar_raiz_projeto <- function() {
  arquivos_esperados <- c("_quarto.yml", "CODEX.md")
  ausentes <- arquivos_esperados[!file.exists(arquivos_esperados)]

  if (length(ausentes) > 0L) {
    stop(
      "Execute o script a partir da raiz do projeto. Arquivos não encontrados: ",
      paste(ausentes, collapse = ", "),
      call. = FALSE
    )
  }
}

verificar_pacotes <- function(pacotes) {
  ausentes <- pacotes[
    !vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(ausentes) > 0L) {
    stop(
      "Pacotes R ausentes: ", paste(ausentes, collapse = ", "),
      ". Restaure o ambiente antes de iniciar a coleta.",
      call. = FALSE
    )
  }
}

coletar_tribunal <- function(tribunal) {
  sigla <- tolower(tribunal)
  destino <- file.path(diretorio_bruto, sigla)
  manifesto <- file.path(destino, "manifesto.json")

  dir.create(destino, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(manifesto)) {
    informar_etapa(paste0(tribunal, ": manifesto encontrado; retomando a coleta."))
  } else {
    informar_etapa(paste0(tribunal, ": iniciando uma nova coleta."))
  }

  coleta <- datajud::datajud_coletar_processos(
    tribunal = tribunal,
    diretorio = destino,
    assunto_codigo = assunto_codigo,
    classe_codigo = classe_codigo,
    size = tamanho_pagina,
    limite_registros = limite_registros,
    limite_paginas = limite_paginas,
    pausa = pausa_entre_paginas,
    retomar = TRUE,
    cliente = datajud::datajud_cliente(timeout = timeout_segundos)
  )

  informar_etapa(
    sprintf(
      "%s: etapa encerrada; %d arquivo(s) de página registrado(s).",
      tribunal,
      length(coleta$arquivos)
    )
  )

  coleta
}


# 3. Verificações anteriores à coleta ----------------------------------------

verificar_raiz_projeto()
verificar_pacotes(pacotes_necessarios)
dir.create(diretorio_bruto, recursive = TRUE, showWarnings = FALSE)

informar_etapa(
  paste0(
    "Consulta configurada: classe ", classe_codigo,
    "; assunto ", assunto_codigo,
    "; tribunais ", paste(tribunais, collapse = ", "), "."
  )
)


# 4. Coleta por tribunal ------------------------------------------------------

coletas <- stats::setNames(
  lapply(tribunais, coletar_tribunal),
  tribunais
)


# 5. Encerramento -------------------------------------------------------------

informar_etapa("Coleta finalizada para todos os tribunais configurados.")
invisible(coletas)
