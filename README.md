# exemplo_jurimetria

Projeto reproduzível em Quarto para estudar o tempo entre o ajuizamento e a
primeira decisão sobre tutela de urgência em ações de fornecimento de
medicamentos não padronizados. R e Python compartilham as mesmas definições e a
mesma base analítica.

Enquanto a coleta pública do DataJud está sendo implementada, o arquivo em
`dados/exemplo/` contém somente dados sintéticos para validar o fluxo.

## Estrutura

```text
.
|-- dados/
|   |-- brutos/                # extrações públicas, não versionadas
|   |-- tratados/              # bases analíticas, não versionadas
|   `-- exemplo/
|       `-- processos.csv      # base sintética versionada
|-- python/
|   |-- analise.py             # análise em Python
|   `-- analise.qmd            # relatório Quarto/Python
|-- R/
|   |-- analise.R              # análise em R
|   `-- analise.qmd            # relatório Quarto/R
|-- resultados/
|   |-- python/                # saídas geradas pelo Python
|   `-- r/                     # saídas geradas pelo R
|-- index.qmd                  # página inicial
|-- _quarto.yml                # configuração do Quarto
|-- pyproject.toml             # configuração do Python
|-- .env                       # credencial local; não versionada
`-- .Renviron                  # credencial local do R; não versionada
```

## Exemplo analisado

A base sintética contém decisões fictícias com tribunal, assunto, resultado,
duração do processo e valor da causa. Ambos os scripts calculam:

1. número total de processos;
2. taxa de procedência;
3. duração média em dias;
4. estatísticas agrupadas por tribunal.

Cada execução gera um arquivo `resumo_por_tribunal.csv` na pasta de resultados
da respectiva linguagem.

## Executar em Python

Na raiz do projeto:

```powershell
python python/analise.py
```

O exemplo usa apenas a biblioteca padrão do Python.

## Executar em R

Na raiz do projeto:

```powershell
Rscript R/analise.R
```

O exemplo usa apenas funções do R base.

## Renderizar o projeto Quarto

```powershell
quarto render
```

O relatório R usa `knitr`. O relatório Python usa o kernel Jupyter configurado
no ambiente virtual do projeto.

## Testar o DataJud

Com o R disponível no `PATH`, execute:

```powershell
Rscript R/testar_datajud.R
```

O teste consulta apenas um registro público do TJSP usando a classe TPU `7`
(Procedimento Comum Cível) e o assunto `12495` (Não padronizado). Nenhum dado
processual é salvo pelo teste.

## Coletar o recorte completo do TJSP

```powershell
Rscript R/coletar_tjsp.R
```

O script coleta de forma retomável todos os processos do TJSP com classe TPU
`7` e assunto `12495`, preserva a extração em NDJSON e cria bases tratadas com
ajuizamento a partir de 01/01/2022. Os dados ficam em `dados/brutos/` e
`dados/tratados/`, fora do Git.

## Credencial do GitHub

O token permanece somente nos arquivos locais `.env` e `.Renviron`, que estão
ignorados pelo Git. Nunca inclua esses arquivos em commits.
