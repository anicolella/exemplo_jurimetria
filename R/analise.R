# Análise descritiva da base compartilhada de processos judiciais.

argumentos <- commandArgs(trailingOnly = FALSE)
marcador_arquivo <- "--file="
caminho_script <- sub(marcador_arquivo, "", argumentos[grep(marcador_arquivo, argumentos)])

if (length(caminho_script) == 0) {
  raiz <- normalizePath(".")
} else {
  raiz <- normalizePath(file.path(dirname(caminho_script), ".."))
}

arquivo_dados <- file.path(raiz, "dados", "exemplo", "processos.csv")
pasta_resultados <- file.path(raiz, "resultados", "r")

processos <- read.csv(arquivo_dados, stringsAsFactors = FALSE, encoding = "UTF-8")

taxa_procedencia <- mean(processos$resultado == "procedente")
duracao_media <- mean(processos$duracao_dias)

tribunais <- sort(unique(processos$tribunal))
resumos <- lapply(tribunais, function(tribunal) {
  casos <- processos[processos$tribunal == tribunal, ]
  data.frame(
    tribunal = tribunal,
    n_processos = nrow(casos),
    taxa_procedencia = round(mean(casos$resultado == "procedente"), 3),
    duracao_media_dias = round(mean(casos$duracao_dias), 1),
    valor_medio_causa = round(mean(casos$valor_causa), 2)
  )
})
resumo <- do.call(rbind, resumos)

dir.create(pasta_resultados, recursive = TRUE, showWarnings = FALSE)
destino <- file.path(pasta_resultados, "resumo_por_tribunal.csv")
write.csv(resumo, destino, row.names = FALSE, fileEncoding = "UTF-8")

cat(sprintf("Total de processos: %d\n", nrow(processos)))
cat(sprintf("Taxa de procedência: %.1f%%\n", taxa_procedencia * 100))
cat(sprintf("Duração média: %.1f dias\n", duracao_media))
cat(sprintf("Resumo salvo em: resultados/r/resumo_por_tribunal.csv\n"))
