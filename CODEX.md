# Plano do projeto: tempo até a tutela de urgência

## 1. Objetivo

Estimar o número de dias entre o **ajuizamento da ação** e a **primeira decisão
sobre tutela de urgência** em processos relativos ao fornecimento de
medicamentos de alto custo.

O estudo comparará processos ajuizados antes e depois do marco temporal
associado ao **Tema 1234 do STF**. A data de corte e sua justificativa jurídica
deverão ser confirmadas em fonte oficial e documentadas antes da análise.

## 2. Pergunta de pesquisa

O tempo até a primeira decisão sobre tutela de urgência mudou após o marco do
Tema 1234 do STF nos processos de fornecimento de medicamento não padronizado?

## 3. Fonte e natureza dos dados

- Utilizar exclusivamente **dados públicos**.
- Obter os dados por meio do DataJud, preferencialmente com o pacote
  [`datajud`](https://github.com/ifusilva/datajud).
- Coletar separadamente os dados do **TJSP**, **TJMT** e **TJSC**.
- Registrar a data da extração, os parâmetros da consulta, os tribunais
  consultados e eventuais limitações de cobertura.
- Não armazenar tokens, credenciais ou dados pessoais sensíveis no Git.

Antes da coleta principal, realizar uma consulta pequena e reproduzível para
verificar se o pacote `datajud` e o acesso à API estão funcionando.

## 4. População do estudo

### Critérios de inclusão

- processos pertencentes ao TJSP, TJMT ou TJSC;
- data de ajuizamento igual ou posterior a **01/01/2022**;
- classe processual correspondente a **procedimento comum cível**;
- código de assunto **12495** da TPU/CNJ: fornecimento de medicamento não
  padronizado;
- presença das informações mínimas necessárias para estabelecer o início do
  acompanhamento e identificar os movimentos processuais relevantes.

### Critérios de exclusão

- processos fora do período definido;
- processos sem o assunto 12495;
- registros duplicados;
- processos sem data de ajuizamento válida;
- casos cuja sequência de eventos não permita determinar o tempo de
  acompanhamento, documentando-se o motivo da exclusão.

## 5. Definição das variáveis

### Marco inicial

A data de ajuizamento será o tempo zero de cada processo.

### Evento principal

A primeira decisão sobre tutela de urgência. A regra usada para identificar
essa decisão — códigos de movimentos, documentos ou textos — deverá ser
definida e validada em uma amostra antes da classificação de toda a base.

### Tempo até o evento

Número de dias corridos entre a data de ajuizamento e a primeira decisão sobre
tutela de urgência.

### Exposição principal

Indicador do período de ajuizamento:

- anterior ao marco do Tema 1234 do STF;
- posterior ao marco do Tema 1234 do STF.

### Desfechos concorrentes e censura

Investigar, entre outros eventos:

- acordo;
- desistência da ação;
- perda do objeto;
- extinção do processo antes da decisão de tutela;
- encerramento do período de observação sem decisão identificada.

A distinção entre evento concorrente e censura deverá ser justificada de
acordo com a pergunta de pesquisa e com a qualidade dos movimentos disponíveis.

## 6. Estratégia de análise

1. Descrever a seleção da amostra e as perdas em cada etapa.
2. Avaliar qualidade, duplicidade e ausência de dados.
3. Apresentar estatísticas descritivas por tribunal, período e características
   processuais disponíveis.
4. Estimar curvas de tempo até a decisão de tutela.
5. Tratar acordo, desistência, perda do objeto e eventos semelhantes como
   riscos concorrentes quando metodologicamente adequado.
6. Comparar os períodos anterior e posterior ao Tema 1234.
7. Avaliar modelos ajustados se houver covariáveis suficientes e comparáveis.
8. Realizar análises de sensibilidade para definições alternativas do evento,
   da data de corte e do tratamento dos eventos concorrentes.

Não interpretar censura como ausência definitiva do evento. Informar claramente
o fim do período de observação e as limitações de acompanhamento.

## 7. Ferramentas

- **Quarto** para produzir o relatório reproduzível, prioritariamente em PDF e,
  quando útil para fins didáticos, também em HTML;
- **R** como linguagem da coleta, do tratamento e da análise estatística;
- `tidyverse` para importação, transformação e descrição dos dados;
- `survival` e pacotes complementares para análise de sobrevivência;
- pacotes apropriados para incidência cumulativa, riscos concorrentes e
  visualização;
- `renv` para registrar e restaurar as dependências do projeto.

## 8. Arquitetura dos dados e dos relatórios

O projeto deverá separar coleta, tratamento e apresentação dos resultados.

### Estrutura de arquivos

```text
R/
  01_coletar_datajud.R   coleta retomável por tribunal
  02_tratar_dados.R      construção integral da base analítica
dados/
  brutos/
    tjsp/
    tjmt/
    tjsc/
  tratados/
    base_analitica.rds
output/                  PDF e outros arquivos gerados
relatorio.qmd            fonte principal do relatório Quarto
referencias.bib          referências bibliográficas
tema-moderno.tex         identidade visual portátil do PDF
_quarto.yml              configuração do projeto Quarto
```

O arquivo `relatorio.qmd` deverá permanecer na raiz. A pasta `output/` conterá
somente arquivos gerados e poderá ser apagada e recriada sem perda do código-
fonte.

### Coleta

A coleta utilizará dados públicos do DataJud para TJSP, TJMT e TJSC. Os dados
brutos deverão ser armazenados separadamente por tribunal. A coleta deverá ser
retomável: arquivos já concluídos não serão baixados novamente.

A coleta não deverá ser executada automaticamente durante a renderização do
relatório Quarto.

### Tratamento da base

Deverá existir um script R executável do início ao fim que transforme os dados
brutos na base analítica consolidada.

O script deverá:

1. ler os dados dos três tribunais;
2. documentar cada etapa por comentários objetivos;
3. informar no console qual etapa está sendo executada;
4. aplicar os critérios de inclusão e exclusão;
5. padronizar datas, identificadores e nomes das variáveis;
6. eliminar duplicidades;
7. extrair os movimentos processuais necessários;
8. construir as variáveis analíticas;
9. preservar a identificação do tribunal;
10. combinar os tribunais;
11. executar verificações de consistência;
12. salvar a base tratada em formato RDS.

O script deverá produzir o mesmo banco quando executado novamente sobre os
mesmos dados brutos. Não deverão existir transformações manuais indispensáveis
à reprodução do resultado.

#### Documentação do script de tratamento

O arquivo `R/02_tratar_dados.R` deverá ser especialmente bem documentado e
compreensível para quem não participou da construção da base. A documentação
deverá explicar decisões e regras de negócio, e não apenas repetir em palavras
o que cada comando R já mostra.

O script deverá conter:

- cabeçalho com objetivo, arquivos de entrada, arquivo de saída, dependências e
  forma de execução;
- seções numeradas que correspondam às etapas do tratamento;
- descrição objetiva dos critérios de inclusão e exclusão antes de aplicá-los;
- justificativa dos códigos de classes, assuntos e movimentos processuais;
- explicação das regras usadas para eventos, censura e riscos concorrentes;
- indicação da unidade de análise e das chaves utilizadas em junções;
- explicação das variáveis analíticas criadas, incluindo tipo, unidade e
  categorias esperadas;
- mensagens de progresso no console, com número de registros antes e depois das
  principais filtragens;
- registro das exclusões por motivo, permitindo reconstruir o fluxo da amostra;
- verificações explícitas de duplicidade, datas inválidas, valores ausentes,
  ordem temporal impossível e consistência entre tribunais;
- interrupção com mensagem informativa quando uma condição essencial não for
  satisfeita;
- resumo final com número de processos por tribunal, período e tipo de evento;
- gravação da base somente depois que todas as verificações forem aprovadas.

Comentários deverão ser atualizados junto com o código. Números derivados dos
dados não deverão ser escritos manualmente nos comentários quando puderem ser
calculados e exibidos pelo próprio script.

### Relatório Quarto

O relatório será escrito em QMD e utilizará chunks R executáveis. Ele deverá
ler a base tratada e produzir diretamente as tabelas, estatísticas e figuras
apresentadas.

Os chunks deverão possuir:

- rótulos informativos;
- comentários quando a operação não for evidente;
- código organizado em etapas;
- resultados apresentados imediatamente após o cálculo correspondente;
- ausência de caminhos absolutos dependentes de um computador específico.

Por padrão, o código será mostrado no relatório didático. No HTML, deverá ser
possível expandir e recolher os chunks. A decisão de ocultar o código em versões
finais poderá ser tomada posteriormente sem eliminar o código-fonte do QMD.

#### Apresentação e leitura dos modelos

Cada método estatístico ou modelo utilizado deverá ser apresentado antes dos
resultados e acompanhado de referência bibliográfica registrada em
`referencias.bib`. O relatório não deverá mostrar apenas a saída do software.

Para cada método ou modelo, o texto deverá informar:

- qual pergunta ele responde e por que foi escolhido;
- qual quantidade está sendo estimada;
- como são definidos tempo, evento, censura e, quando aplicável, riscos
  concorrentes;
- quais são as principais hipóteses do método;
- quais grupos, categorias ou valores constituem a referência;
- como interpretar curvas, probabilidades, coeficientes, razões de risco,
  intervalos de confiança e valores-p;
- quais diagnósticos ou verificações foram realizados;
- quais limitações impedem uma interpretação causal ou mais ampla.

No mínimo, essa regra deverá ser aplicada a Kaplan-Meier, teste de log-rank,
incidência cumulativa de Aalen-Johansen, teste de Gray, modelo de Cox e modelo
de Fine-Gray, caso sejam utilizados. As diferenças entre risco instantâneo de
causa específica, subdistribuição e probabilidade acumulada deverão ser
explicadas em linguagem acessível.

Cada tabela ou figura deverá ser introduzida no texto e seguida de uma leitura
substantiva dos resultados. A interpretação deverá usar as unidades e o
contexto jurídico do estudo, evitando limitar-se a afirmar significância
estatística.

### Desempenho

A renderização não deverá repetir a coleta nem o tratamento completo dos dados.

O fluxo esperado será:

1. coletar ou atualizar os dados brutos;
2. executar o script de tratamento;
3. salvar a base consolidada;
4. renderizar o relatório a partir da base tratada.

Cálculos intermediários demorados deverão ser salvos quando isso não prejudicar
a reprodutibilidade. A coleta deverá ser retomável, e o projeto Quarto poderá
utilizar `freeze: auto` para reaproveitar resultados durante renderizações
gerais.

### Figuras e tabelas

As figuras e tabelas principais deverão ser geradas pelos chunks do relatório.
Não deverão ser substituídas por imagens criadas manualmente quando puderem ser
reproduzidas pelo código.

Arquivos de figuras poderão ser salvos quando forem necessários para outros
formatos, apresentações ou divulgação, mas o código que os produz deverá
permanecer no projeto.

### Identidade visual

O relatório deverá adotar identidade visual compatível com o livro
*Jurimetria: Dados, Métodos e Evidência para o Direito*.

O projeto terá seus próprios arquivos de estilo, derivados da paleta e da
tipografia do livro, para permanecer portátil. O relatório não deverá depender
de caminhos absolutos para arquivos localizados na pasta do livro.

A identidade visual local usará:

- azul-marinho `#071739` para títulos e elementos principais;
- azul médio `#4B6382` para elementos secundários;
- azul névoa `#A4B5C4` e cinza nuvem `#CDD5DB` para linhas e fundos leves;
- marrom suave `#A68868` e bege `#E3C39D` para destaques;
- marfim `#F8F5EF` e texto `#172033` como base neutra;
- TeX Gyre Pagella para títulos e TeX Gyre Heros para o corpo do PDF.

Gráficos produzidos em R deverão reutilizar essa paleta. A adaptação mínima para
PDF ficará centralizada em `tema-moderno.tex`, sem dependência da pasta do livro.

## 9. Credenciais e segurança

- O token do GitHub está no arquivo local `.env`.
- Disponibilizar o token como variável de ambiente para R e demais
  ferramentas que precisarem dele.
- No R, utilizar `.Renviron` com a variável `GITHUB_PAT`.
- Manter `.env`, `.Renviron` e outros arquivos com credenciais fora do Git.
- Nunca imprimir ou registrar o valor do token em logs, relatórios ou commits.

## 10. Controle de versão

- Criar um repositório GitHub para o projeto.
- Fazer um commit ao final de cada tarefa lógica concluída.
- Usar mensagens de commit claras, preferencialmente seguindo *Conventional
  Commits*, como `docs:`, `feat:`, `fix:`, `refactor:` e `test:`.
- Enviar os commits ao repositório remoto após validação.
- Não incluir credenciais, dados restritos ou arquivos gerados desnecessários.

## 11. Etapas de execução

1. Configurar o projeto Quarto e o ambiente de R.
2. Criar e configurar o repositório GitHub.
3. Instalar e testar o pacote `datajud` com uma consulta mínima em cada um dos
   três tribunais.
4. Confirmar os códigos da classe e do assunto utilizados na consulta.
5. Confirmar e documentar o marco temporal do Tema 1234 em fonte oficial.
6. Definir e validar a regra de identificação da primeira decisão de tutela.
7. Coletar de forma retomável os dados públicos do TJSP, TJMT e TJSC, mantendo
   os arquivos brutos separados por tribunal.
8. Executar o script integral de tratamento, deduplicar e construir a base RDS
   consolidada.
9. Classificar eventos, riscos concorrentes e censura.
10. Executar as análises descritivas e de sobrevivência.
11. Realizar análises de sensibilidade em R.
12. Renderizar o relatório a partir da base tratada e revisar o PDF final.

## 12. Resultados esperados

- fluxo documentado de seleção dos processos;
- base analítica reproduzível, respeitando as limitações dos dados públicos;
- estimativas do tempo até a primeira decisão de tutela;
- curvas e tabelas por período de ajuizamento;
- análise de riscos concorrentes;
- comparação fundamentada entre os períodos anterior e posterior ao Tema 1234;
- relatório final reproduzível em Quarto.
