# Coleta e prepara o recorte inicial do DataJud para o TJSP.

biblioteca_local <- file.path(
  "renv", "library", "R-4.6", "x86_64-w64-mingw32"
)
if (dir.exists(biblioteca_local)) {
  .libPaths(c(normalizePath(biblioteca_local), .libPaths()))
}

pacotes <- c("datajud", "dplyr", "purrr", "readr", "jsonlite", "tibble")
ausentes <- pacotes[!vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)]
if (length(ausentes) > 0) {
  stop("Pacotes ausentes: ", paste(ausentes, collapse = ", "))
}

diretorio_bruto <- file.path(
  "dados", "brutos", "datajud_tjsp_classe7_assunto12495"
)
diretorio_tratado <- file.path("dados", "tratados")
dir.create(diretorio_tratado, recursive = TRUE, showWarnings = FALSE)

manifesto <- file.path(diretorio_bruto, "manifesto.json")
if (file.exists(manifesto)) {
  coleta <- datajud::datajud_abrir_coleta(diretorio_bruto)
} else {
  coleta <- datajud::datajud_coletar_processos(
    tribunal = "TJSP",
    diretorio = diretorio_bruto,
    assunto_codigo = 12495,
    classe_codigo = 7,
    size = 1000,
    limite_registros = 10000,
    limite_paginas = 20,
    pausa = 0.5,
    retomar = TRUE,
    cliente = datajud::datajud_cliente(timeout = 120)
  )
}

indices_paginas <- seq_along(coleta$arquivos)
paginas <- lapply(indices_paginas, function(indice) {
  datajud::datajud_ler_pagina(coleta, indice)
})

processos <- lapply(paginas, datajud::datajud_ler_processo) |>
  dplyr::bind_rows() |>
  dplyr::arrange(id, dplyr::desc(data_atualizacao)) |>
  dplyr::distinct(id, .keep_all = TRUE)

tem_assunto_12495 <- vapply(
  processos$assuntos,
  function(assuntos) any(assuntos$codigo == 12495L, na.rm = TRUE),
  logical(1)
)

if (!all(processos$tribunal == "TJSP")) {
  stop("A coleta contém registros de outro tribunal.")
}
if (!all(processos$classe_tpu == 7L)) {
  stop("A coleta contém registros de outra classe.")
}
if (!all(tem_assunto_12495)) {
  stop("A coleta contém registros sem o assunto 12495.")
}

data_corte <- as.POSIXct("2022-01-01 00:00:00", tz = "UTC")
processos_2022 <- processos |>
  dplyr::filter(!is.na(data_ajuizamento), data_ajuizamento >= data_corte)

extrair_movimentos_hit <- function(hit) {
  fonte <- hit[["_source"]]
  movimentos <- fonte[["movimentos"]]
  if (is.null(movimentos) || length(movimentos) == 0) {
    return(tibble::tibble())
  }

  purrr::map_dfr(movimentos, function(movimento) {
    tibble::tibble(
      id = as.character(fonte[["id"]]),
      numero_processo = as.character(fonte[["numeroProcesso"]]),
      movimento_codigo = as.integer(movimento[["codigo"]]),
      movimento_nome = as.character(movimento[["nome"]]),
      movimento_data = as.POSIXct(
        movimento[["dataHora"]],
        format = "%Y-%m-%dT%H:%M:%OSZ",
        tz = "UTC"
      ),
      complementos_json = as.character(jsonlite::toJSON(
        movimento[["complementosTabelados"]],
        auto_unbox = TRUE,
        null = "null"
      ))
    )
  })
}

saveRDS(processos, file.path(diretorio_tratado, "processos_tjsp_todos.rds"))
saveRDS(processos_2022, file.path(diretorio_tratado, "processos_tjsp_2022_mais.rds"))

processos_csv <- processos_2022 |>
  dplyr::select(-assuntos)
readr::write_csv(
  processos_csv,
  file.path(diretorio_tratado, "processos_tjsp_2022_mais.csv")
)
cat("Registros brutos únicos:", nrow(processos), "\n")
cat("Processos ajuizados desde 01/01/2022:", nrow(processos_2022), "\n")
cat(
  "Período de ajuizamento:",
  format(min(processos_2022$data_ajuizamento), "%Y-%m-%d"),
  "a",
  format(max(processos_2022$data_ajuizamento), "%Y-%m-%d"),
  "\n"
)
