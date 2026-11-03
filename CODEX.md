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
- Registrar a data da extração, os parâmetros da consulta, os tribunais
  consultados e eventuais limitações de cobertura.
- Não armazenar tokens, credenciais ou dados pessoais sensíveis no Git.

Antes da coleta principal, realizar uma consulta pequena e reproduzível para
verificar se o pacote `datajud` e o acesso à API estão funcionando.

## 4. População do estudo

### Critérios de inclusão

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

- **Quarto** para organizar e publicar a análise reproduzível;
- **R** como linguagem principal para análise estatística;
- `tidyverse` para importação, transformação e descrição dos dados;
- `survival` e pacotes complementares para análise de sobrevivência;
- pacotes apropriados para incidência cumulativa, riscos concorrentes e
  visualização;
- **Python** para uma implementação paralela ou para tarefas de coleta e
  tratamento em que ofereça vantagem prática.

As análises em R e Python deverão usar a mesma base tratada e definições
equivalentes, permitindo comparar os resultados.

## 8. Estrutura reproduzível

Manter, sempre que possível, a seguinte organização:

```text
dados/           dados públicos brutos e tratados
R/               código e documentos Quarto em R
python/          código e documentos Quarto em Python
resultados/      tabelas, figuras e saídas geradas
index.qmd        apresentação do projeto
_quarto.yml      configuração do projeto Quarto
```

Dados intermediários e resultados gerados devem ser recriáveis a partir dos
scripts. Documentar dependências, versões e instruções de execução.

## 9. Credenciais e segurança

- O token do GitHub está no arquivo local `.env`.
- Disponibilizar o token como variável de ambiente para R, Python e demais
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

1. Configurar o projeto Quarto e os ambientes de R e Python.
2. Criar e configurar o repositório GitHub.
3. Instalar e testar o pacote `datajud` com uma consulta mínima.
4. Confirmar os códigos da classe e do assunto utilizados na consulta.
5. Confirmar e documentar o marco temporal do Tema 1234 em fonte oficial.
6. Definir e validar a regra de identificação da primeira decisão de tutela.
7. Coletar os dados públicos e preservar os parâmetros da consulta.
8. Limpar, deduplicar e construir a base analítica.
9. Classificar eventos, riscos concorrentes e censura.
10. Executar as análises descritivas e de sobrevivência.
11. Realizar análises de sensibilidade e comparar R e Python.
12. Renderizar e revisar o relatório final no Quarto.

## 12. Resultados esperados

- fluxo documentado de seleção dos processos;
- base analítica reproduzível, respeitando as limitações dos dados públicos;
- estimativas do tempo até a primeira decisão de tutela;
- curvas e tabelas por período de ajuizamento;
- análise de riscos concorrentes;
- comparação fundamentada entre os períodos anterior e posterior ao Tema 1234;
- relatório final reproduzível em Quarto.
