# Teste mínimo da API Pública do DataJud.
#
# A consulta recebe somente um registro e não grava dados processuais. Seu
# objetivo é validar o pacote, a conectividade e os códigos TPU usados no
# projeto.

biblioteca_local <- file.path(
  "renv", "library", "R-4.6", "x86_64-w64-mingw32"
)

if (dir.exists(biblioteca_local)) {
  .libPaths(c(normalizePath(biblioteca_local), .libPaths()))
}

if (!requireNamespace("datajud", quietly = TRUE)) {
  stop("O pacote datajud não está instalado.")
}

classe <- datajud::datajud_buscar_classe(
  "procedimento comum civel",
  limite = 1
)
assunto <- datajud::datajud_buscar_assunto(12495, ativos = NULL)

stopifnot(classe$codigo[[1]] == 7L)
stopifnot(assunto$codigo[[1]] == 12495L)

resultado <- datajud::datajud_pesquisar_processos(
  tribunal = "TJSP",
  classe_codigo = 7,
  assunto_codigo = 12495,
  size = 1,
  cliente = datajud::datajud_cliente(timeout = 60)
)

if (length(resultado$hits) != 1L) {
  stop("A API não devolveu o único registro solicitado.")
}

cat("DataJud funcionando.\n")
cat("Tribunal: TJSP; classe: 7; assunto: 12495.\n")
