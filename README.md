# EAGOLD

Projeto de desenvolvimento de Expert Advisor (EA) para MetaTrader 4 (MT4).

## Objetivo

Construir o EA de forma incremental, modular e versionada, mantendo rastreabilidade entre especificação, implementação, backtests e observações operacionais.

## Estrutura inicial

- `EA/` — código principal do Expert Advisor.
- `Include/` — módulos reutilizáveis do EA.
- `Journal/` — especificação e estruturas de logging.
- `Backtest/` — configurações e resultados de testes.
- `Docs/` — arquitetura, estratégia e histórico do projeto.

## Princípios de desenvolvimento

1. Código completo e compilável em cada versão estável.
2. Alterações rastreáveis por commit.
3. Separação entre lógica de estratégia, execução, risco e observabilidade.
4. Journal detalhado para explicar decisões do EA durante backtests e operação.
5. Nenhuma regra operacional deve ser considerada definitiva sem validação.

## Status

**Fase 0 — Estrutura inicial do projeto.**

A estratégia e as regras de operação serão definidas nas próximas etapas.
