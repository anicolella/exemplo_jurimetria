# Auditoria inicial dos movimentos candidatos a tutela de urgência.

biblioteca_local <- file.path(
  "renv", "library", "R-4.6", "x86_64-w64-mingw32"
)
if (dir.exists(biblioteca_local)) {
  .libPaths(c(normalizePath(biblioteca_local), .libPaths()))
}

if (!requireNamespace("dplyr", quietly = TRUE) ||
    !requireNamespace("readr", quietly = TRUE)) {
  stop("Os pacotes dplyr e readr são necessários.")
}

arquivo_movimentos <- file.path(
  "dados", "tratados", "movimentos_tjsp_2022_mais.rds"
)
arquivo_processos <- file.path(
  "dados", "tratados", "processos_tjsp_2022_mais.rds"
)
diretorio_saida <- file.path("resultados", "validacao")
dir.create(diretorio_saida, recursive = TRUE, showWarnings = FALSE)

movimentos <- readRDS(arquivo_movimentos)
processos <- readRDS(arquivo_processos)

codigos_concedida <- c(332L, 339L)
codigos_parcial <- c(889L, 892L)
codigos_nao_concedida <- c(785L, 792L)
codigos_revogada <- c(347L, 348L)
codigos_decisao_tutela <- c(
  codigos_concedida,
  codigos_parcial,
  codigos_nao_concedida
)
codigos_tutela <- c(codigos_decisao_tutela, codigos_revogada)

frequencia <- movimentos |>
  dplyr::count(movimento_codigo, movimento_nome, sort = TRUE)

candidatos <- frequencia |>
  dplyr::filter(movimento_codigo %in% codigos_tutela)

complementos_candidatos <- movimentos |>
  dplyr::filter(movimento_codigo %in% codigos_tutela) |>
  dplyr::count(
    movimento_codigo, movimento_nome, complementos_json,
    sort = TRUE
  )

movimentos_classificados <- movimentos |>
  dplyr::mutate(
    resultado_tutela = dplyr::case_when(
      movimento_codigo %in% codigos_concedida ~ "concedida",
      movimento_codigo %in% codigos_parcial ~ "parcialmente_concedida",
      movimento_codigo %in% codigos_nao_concedida ~ "nao_concedida",
      movimento_codigo %in% codigos_revogada ~ "revogada",
      TRUE ~ NA_character_
    )
  )

primeiro_candidato <- movimentos_classificados |>
  dplyr::filter(movimento_codigo %in% codigos_decisao_tutela) |>
  dplyr::arrange(id, movimento_data) |>
  dplyr::group_by(id) |>
  dplyr::slice_head(n = 1) |>
  dplyr::ungroup()

base_auditoria <- processos |>
  dplyr::select(id, numero_processo, data_ajuizamento, orgao_julgador_nome) |>
  dplyr::left_join(
    primeiro_candidato |>
      dplyr::select(
        id, movimento_codigo, movimento_nome, movimento_data,
        complementos_json, resultado_tutela
      ),
    by = "id"
  ) |>
  dplyr::mutate(
    grupo_tema1234 = ifelse(
      data_ajuizamento > as.POSIXct("2024-09-19", tz = "UTC"),
      "depois",
      "antes"
    ),
    classificacao_manual = NA_character_,
    data_manual = as.Date(NA),
    observacao_manual = NA_character_
  )

set.seed(1234)
amostra_positiva <- base_auditoria |>
  dplyr::filter(!is.na(resultado_tutela)) |>
  dplyr::group_by(grupo_tema1234, resultado_tutela) |>
  dplyr::slice_sample(n = 30) |>
  dplyr::ungroup()

amostra_negativa <- base_auditoria |>
  dplyr::filter(is.na(resultado_tutela)) |>
  dplyr::group_by(grupo_tema1234) |>
  dplyr::slice_sample(n = 30) |>
  dplyr::ungroup()

amostra <- dplyr::bind_rows(amostra_positiva, amostra_negativa) |>
  dplyr::arrange(grupo_tema1234, is.na(resultado_tutela), numero_processo)

base_sobrevivencia <- base_auditoria |>
  dplyr::mutate(
    evento_tutela = as.integer(!is.na(resultado_tutela)),
    fim_observacao = dplyr::if_else(
      evento_tutela == 1L,
      movimento_data,
      as.POSIXct("2026-11-03 23:59:59", tz = "UTC")
    ),
    tempo_dias = as.numeric(difftime(
      fim_observacao,
      data_ajuizamento,
      units = "days"
    )),
    inconsistencia_tempo = is.na(tempo_dias) | tempo_dias < 0
  )

revogacoes <- movimentos_classificados |>
  dplyr::filter(movimento_codigo %in% codigos_revogada) |>
  dplyr::group_by(id) |>
  dplyr::summarise(primeira_revogacao = min(movimento_data), .groups = "drop")

controle_qualidade <- base_sobrevivencia |>
  dplyr::left_join(revogacoes, by = "id") |>
  dplyr::summarise(
    processos = dplyr::n(),
    com_decisao_tutela = sum(evento_tutela == 1L),
    sem_decisao_tutela = sum(evento_tutela == 0L),
    tempo_negativo_ou_ausente = sum(inconsistencia_tempo),
    revogacao_sem_decisao_tabelada = sum(
      !is.na(primeira_revogacao) & evento_tutela == 0L
    ),
    revogacao_anterior_decisao = sum(
      !is.na(primeira_revogacao) & evento_tutela == 1L &
        primeira_revogacao < movimento_data
    )
  )

readr::write_csv(
  frequencia,
  file.path(diretorio_saida, "frequencia_movimentos.csv")
)
readr::write_csv(
  candidatos,
  file.path(diretorio_saida, "movimentos_candidatos_tutela.csv")
)
readr::write_csv(
  complementos_candidatos,
  file.path(diretorio_saida, "complementos_candidatos_tutela.csv")
)
readr::write_csv(
  amostra,
  file.path(diretorio_saida, "amostra_validacao_manual.csv")
)
readr::write_csv(
  controle_qualidade,
  file.path(diretorio_saida, "controle_qualidade.csv")
)
saveRDS(
  base_sobrevivencia,
  file.path("dados", "tratados", "base_sobrevivencia_tjsp.rds")
)
readr::write_csv(
  base_sobrevivencia,
  file.path("dados", "tratados", "base_sobrevivencia_tjsp.csv")
)

cat("Movimentos:", nrow(movimentos), "\n")
cat("Combinações distintas de código e nome:", nrow(frequencia), "\n")
cat("Combinações candidatas:", nrow(candidatos), "\n")
cat("Processos com candidato:", nrow(primeiro_candidato), "\n")
cat("Processos sem candidato:", nrow(processos) - nrow(primeiro_candidato), "\n")
cat("Processos na amostra manual:", nrow(amostra), "\n\n")
print(candidatos, n = Inf)
cat("\nComplementos dos candidatos:\n")
print(complementos_candidatos, n = Inf)
cat("\nControle de qualidade:\n")
print(controle_qualidade)
