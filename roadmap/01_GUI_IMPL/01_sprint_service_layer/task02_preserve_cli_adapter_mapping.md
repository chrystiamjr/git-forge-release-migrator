# Task

Preserve CLI adapter mapping on top of the new application service.

## Intent

Keep the CLI as a thin adapter that translates parsed command-line inputs into typed application requests and maps
typed results back into the exact process behavior users already rely on.

## Detailed scope

- Update CLI command handlers so they delegate orchestration to the new service instead of coordinating execution
  directly.
- Define a stable mapping from existing parsed CLI inputs into `RunRequest`.
- Define a stable mapping from `RunResult.exit_code` and `RunResult.status` back into current CLI process outcomes.
- Preserve token-resolution rules already documented in `AGENTS.md`, including:
  - `migrate`: settings (`token_env`, then `token_plain`) and then environment aliases
  - `resume`: session token context, then settings, then environment aliases
- Preserve hidden legacy override behavior for:
  - `--source-token`
  - `--target-token`
- Ensure CLI rendering remains an adapter concern and does not leak back into the application contract.

## Expected changes

- CLI handlers become thin wrappers that:
  - parse arguments
  - build `RunRequest`
  - invoke the application service
  - render results
  - return exit code
- Existing token precedence remains deterministic and identical from the user perspective.
- Existing resume flows still recover token context from session data before falling back to settings or env aliases.
- Existing artifact outputs and summary generation remain reachable through the same user-facing commands.
- Any CLI-only wording or terminal formatting is isolated from the typed service contracts.

## Non-goals and guardrails

- Do not redesign CLI UX or rename commands.
- Do not remove or change the hidden legacy token override flags.
- Do not let the CLI bypass the application service for special cases.
- Do not let GUI concerns introduce new CLI-only branches.
- Do not encode terminal presentation details inside `RunResult`.

## Test and validation

- Add feature tests for:
  - `gfrm migrate` success path
  - `gfrm resume` success path
  - validation failure exit behavior
  - runtime failure exit behavior
- Add targeted tests for token precedence across:
  - settings token env
  - settings token plain
  - environment aliases
  - resume session token context
  - explicit legacy token override flags
- Add regression checks proving retry-command generation still points to `gfrm resume`.
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- CLI command handlers delegate to the application service instead of owning orchestration.
- `migrate` and `resume` preserve current token-resolution semantics.
- Existing exit-code behavior remains unchanged.
- The CLI remains a presentation adapter, not a second orchestration layer.
