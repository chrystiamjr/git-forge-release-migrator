---
sidebar_position: 3
title: Comportamento do Bitbucket
---

O Bitbucket Cloud não mapeia um-para-um com a semântica nativa de release do GitHub ou GitLab.

## Modelo sintético de release

Uma release no Bitbucket é representada por:

- uma tag
- notas
- downloads
- um manifesto chamado `.gfrm-release-<tag>.json`

Os downloads do Bitbucket compartilham um único namespace por repositório, então os assets migrados são enviados como
`<tag>-<nome do asset>` (por exemplo `v1.2.0-app.zip`). Isso impede que assets com o mesmo nome em releases diferentes
se substituam. O manifesto mantém o nome original do asset e aponta para o download com o prefixo da tag.

## Compatibilidade legada

Quando uma tag de origem do Bitbucket não tem manifesto, essa condição sozinha não deve falhar a migração.

## Implicação operacional

Trate downloads e manifesto sintético como a mesma unidade ao validar ou depurar uma migração com Bitbucket.
