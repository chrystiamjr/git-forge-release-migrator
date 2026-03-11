---
sidebar_position: 3
title: setup
---

Bootstrap interativo para configuração de tokens.

## Sintaxe

```bash
gfrm setup [opções]
```

## Opções principais

- `--profile <nome>`
- `--local`
- `--yes`
- `--force`

## O que o setup faz

1. lê arquivos comuns de shell em modo somente leitura para procurar nomes conhecidos de variáveis de token
2. pergunta qual estratégia de token usar por provider
3. grava um arquivo YAML global ou local

## Exemplo

```bash
gfrm setup --profile work
```

Use `--yes` apenas quando os defaults já forem aceitáveis e você não quiser prompts.
