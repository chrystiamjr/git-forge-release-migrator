---
sidebar_position: 2
title: Retomar e Repetir
---

Use `gfrm resume` sempre que uma execução for interrompida ou falhar parcialmente.

## Resume padrão

```bash
gfrm resume
```

## Arquivo de sessão explícito

```bash
gfrm resume --session-file ./sessions/last-session.json
```

## O que é ignorado

- itens concluídos permanecem concluídos
- estados terminais de checkpoint evitam trabalho duplicado
- itens incompletos são tentados novamente

## Retry pela tela Results do desktop

**Retry Failed Tags** aparece após uma execução com falha retentável quando o controller ainda possui o contexto
da execução, tags com falha e os arquivos `failed-tags.txt` e checkpoint existentes. A ação fica desabilitada durante
o envio do retry. Execuções vazias, em andamento, bem-sucedidas ou com falha não retentável não oferecem essa ação.

A ação usa o fluxo tipado compartilhado de execução `resume`. Preserva repositórios, contexto de tokens já
resolvidos, perfil de settings, intervalo de tags, opções de migração, workers, raiz de saída e checkpoint originais.
Seleciona apenas as tags com falha; itens concluídos no checkpoint continuam ignorados. Progress e Results
acompanham a nova execução. O comando de terminal exibido não é interpretado para reconstruir credenciais ou parâmetros.

O contexto de retry fica em memória no controller desktop atual. Reiniciar o aplicativo não o restaura.
Se os arquivos de retry desaparecerem, o controller rejeita a ação e Results exibe uma mensagem de falha.
Caminhos informados, por si só, não comprovam disponibilidade. O resume pelo terminal permanece disponível quando
você possui o contexto de sessão necessário.

## Triagem de falhas

Inspecione:

- `failed-tags.txt`
- `summary.json`
- `migration-log.jsonl`

Quando existem falhas, `summary.json` inclui um `retry_command` com `gfrm resume`. Trate esse comando e os artefatos
gravados como caminho autoritativo de retry, mesmo quando eventos internos de completion ou failure também estiverem
disponíveis para consumidores internos.

## Histórico ausente no destino

Se `resume` ou `migrate` parar antes da criação das tags porque o forge de destino não contém o objeto de commit
referenciado por uma tag da origem:

- leia a dica de preflight em `summary.json`
- inspecione `failed-tags.txt` para ver quais tags foram bloqueadas
- inspecione `migration-log.jsonl` quando precisar do contexto passo a passo da execução
- alinhe o histórico do repositório antes de tentar novamente

Padrões seguros de remediação:

- espelhar o repositório de origem no destino quando o destino puder receber o histórico completo
- publicar uma branch auxiliar com os objetos de commit ausentes quando a branch default atual precisar ser preservada
- usar `--skip-tags` somente quando o forge de destino já contiver todas as tags que você planeja migrar; essa restrição é enforçada em runtime
