---
sidebar_position: 3
title: CI e Release
---

## Pipelines principais

- `.github/workflows/quality-checks.yml` roda em `pull_request`
- `.github/workflows/release.yml` roda em `push` para `main`
- `.github/workflows/docs.yml` faz build e deploy do site Docusaurus

## Progresso da revisão automatizada

Cada PR tem um comentário **Required tests** do bot que também mostra o progresso da revisão: aguardando CI,
preparando, avaliação na fila ou em execução, publicando e concluída/com falha/cancelada/ignorada. Cada atualização
inclui horário UTC e um link para os checks ou o workflow da revisão. O status descreve etapas do workflow, não uma
porcentagem nem a atividade do modelo em tempo real.

As atualizações acompanham o commit e a tentativa atuais, preservam as evidências dos testes e não substituem a revisão
humana. O bot edita o mesmo comentário em vez de publicar outro a cada etapa. Alterações no revisor entram em vigor após
merge na branch padrão. Se o status não puder ser atualizado, consulte o estado atual pelo link do workflow.

## Comportamento de release

- artefatos são gerados para Linux, Windows, macOS Intel e macOS Apple Silicon
- semantic-release publica a partir de `main`
- a documentação pública é gerada a partir de `website/`

## Gates de entrega de tickets

Validação local não conclui o ticket. A entrega para em Review com links PR/YouTrack verificados até o mantenedor revisar o head atual e realizar merge manual. No modo solo, um comentário humano `/reviewed` permite à automação registrar o SHA do head atual em um check persistente; `/reviewed <sha>` seleciona a revisão explicitamente; aprovação do bot é auxiliar. Um novo head invalida ambos os modos de revisão; captura automática atrasada fica pendente até novo comentário ou SHA explícito.

Quality Checks compara cobertura de produção com uma medição isolada do commit-base, compila docs EN/PT-BR alteradas antes do merge e executa comparação de goldens da GUI no ambiente canônico. O check agregado `ticket-validation` exige sucesso de core e visual. Relatórios e imagens ficam em artefatos do CI; alterações de baseline precisam de revisão humana.

O workflow Ticket Delivery usa apenas metadados e código confiável da branch padrão. Sua ativação exige secret/opt-in do YouTrack e configuração de checks obrigatórios pelo proprietário após deploy. Desktop nativo e smoke real em forges continuam como evidências de aceitação separadas.

Veja o [playbook de testes](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/testing-playbook.md) e o [contrato de entrega](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/ticket-delivery.md).
