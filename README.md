# exemplo-R

Exemplo reproduzível em R e Quarto. O produto final será um relatório em PDF.

## Estrutura

```text
.
|-- R/                         # coleta, tratamento e análise
|-- dados/
|   |-- brutos/                # dados públicos coletados
|   `-- tratados/              # bases preparadas para análise
|-- output/                    # PDF e outros arquivos gerados
|-- relatorio.qmd              # fonte do relatório Quarto
|-- referencias.bib            # referências bibliográficas
|-- _quarto.yml                # configuração do PDF
|-- .env                       # credencial local; não versionada
`-- .Renviron                  # credencial local do R; não versionada
```

## Renderizar o projeto Quarto

```powershell
quarto render
```

O Quarto lê `relatorio.qmd` e grava o PDF final em `output/`. Essa pasta contém
somente arquivos gerados; o código-fonte permanece na raiz e em `R/`.

## Credencial do GitHub

O token permanece somente nos arquivos locais `.env` e `.Renviron`, que estão
ignorados pelo Git. Nunca inclua esses arquivos em commits.
