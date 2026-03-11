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

## Compatibilidade legada

Quando uma tag de origem do Bitbucket não tem manifesto, essa condição sozinha não deve falhar a migração.

## Implicação operacional

Trate downloads e manifesto sintético como a mesma unidade ao validar ou depurar uma migração com Bitbucket.
