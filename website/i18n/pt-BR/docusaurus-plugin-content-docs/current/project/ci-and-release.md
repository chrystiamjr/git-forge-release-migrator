---
sidebar_position: 3
title: CI e Release
---

## Pipelines principais

- `.github/workflows/quality-checks.yml` roda em `pull_request`
- `.github/workflows/release.yml` roda em `push` para `main`
- `.github/workflows/docs.yml` faz build e deploy do site Docusaurus

## Comportamento de release

- artefatos são gerados para Linux, Windows, macOS Intel e macOS Apple Silicon
- semantic-release publica a partir de `main`
- a documentação pública é gerada a partir de `website/`

## Gates de entrega de tickets

Validação local não conclui o ticket. A entrega para em Review com links PR/YouTrack verificados até o mantenedor revisar o head atual e realizar merge manual. No modo solo, um comentário humano `/reviewed <sha>` registra a decisão; aprovação do bot é auxiliar.

Quality Checks compara cobertura de produção com uma medição isolada do commit-base, compila docs EN/PT-BR alteradas antes do merge e executa comparação de goldens da GUI no ambiente canônico. O check agregado `ticket-validation` exige sucesso de core e visual. Relatórios e imagens ficam em artefatos do CI; alterações de baseline precisam de revisão humana.

O workflow Ticket Delivery usa apenas metadados e código confiável da branch padrão. Sua ativação exige secret/opt-in do YouTrack e configuração de checks obrigatórios pelo proprietário após deploy. Desktop nativo e smoke real em forges continuam como evidências de aceitação separadas.

Veja o [playbook de testes](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/testing-playbook.md) e o [contrato de entrega](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/ticket-delivery.md).
