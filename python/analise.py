"""Análise descritiva da base compartilhada de processos judiciais."""

from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean


RAIZ = Path(__file__).resolve().parents[1]
ARQUIVO_DADOS = RAIZ / "dados" / "exemplo" / "processos.csv"
PASTA_RESULTADOS = RAIZ / "resultados" / "python"


def carregar_processos() -> list[dict[str, str | int | float]]:
    """Carrega a base CSV e converte as colunas numéricas."""
    with ARQUIVO_DADOS.open(encoding="utf-8", newline="") as arquivo:
        processos = list(csv.DictReader(arquivo))

    for processo in processos:
        processo["id_processo"] = int(processo["id_processo"])
        processo["duracao_dias"] = int(processo["duracao_dias"])
        processo["valor_causa"] = float(processo["valor_causa"])

    return processos


def resumir_por_tribunal(
    processos: list[dict[str, str | int | float]],
) -> list[dict[str, str | int | float]]:
    """Calcula contagem, taxa de procedência e médias por tribunal."""
    grupos: dict[str, list[dict[str, str | int | float]]] = defaultdict(list)
    for processo in processos:
        grupos[str(processo["tribunal"])].append(processo)

    resumo = []
    for tribunal, casos in sorted(grupos.items()):
        procedentes = sum(caso["resultado"] == "procedente" for caso in casos)
        resumo.append(
            {
                "tribunal": tribunal,
                "n_processos": len(casos),
                "taxa_procedencia": round(procedentes / len(casos), 3),
                "duracao_media_dias": round(
                    mean(float(caso["duracao_dias"]) for caso in casos), 1
                ),
                "valor_medio_causa": round(
                    mean(float(caso["valor_causa"]) for caso in casos), 2
                ),
            }
        )
    return resumo


def salvar_resumo(resumo: list[dict[str, str | int | float]]) -> Path:
    """Grava o resumo em CSV na pasta de resultados do Python."""
    PASTA_RESULTADOS.mkdir(parents=True, exist_ok=True)
    destino = PASTA_RESULTADOS / "resumo_por_tribunal.csv"
    with destino.open("w", encoding="utf-8", newline="") as arquivo:
        escritor = csv.DictWriter(arquivo, fieldnames=resumo[0].keys())
        escritor.writeheader()
        escritor.writerows(resumo)
    return destino


def main() -> None:
    processos = carregar_processos()
    resumo = resumir_por_tribunal(processos)
    procedentes = sum(p["resultado"] == "procedente" for p in processos)

    print(f"Total de processos: {len(processos)}")
    print(f"Taxa de procedência: {procedentes / len(processos):.1%}")
    print(
        "Duração média: "
        f"{mean(float(p['duracao_dias']) for p in processos):.1f} dias"
    )
    destino = salvar_resumo(resumo)
    print(f"Resumo salvo em: {destino.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
