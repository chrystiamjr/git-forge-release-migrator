---
sidebar_position: 5
title: demo
---

Executa uma simulação local que percorre o fluxo da CLI e gera artefatos sem precisar de credenciais reais.

## Sintaxe

```bash
gfrm demo [opções]
```

## Uso típico

```bash
gfrm demo --demo-releases 10 --demo-sleep-seconds 0.5
```

## Por que usar

- verificar empacotamento local e comportamento da CLI
- inspecionar a estrutura de artefatos em `migration-results/`
- testar sumário e retry sem tocar repositórios reais
