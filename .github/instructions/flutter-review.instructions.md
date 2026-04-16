---
applyTo: "gui/lib/**/*.dart,gui/test/**/*.dart,gui/pubspec.yaml,gui/analysis_options.yaml"
---

# Flutter GUI Review Rules

- Treat `AGENTS.md` as the source of truth for product contract and invariants.
- The GUI is a Flutter desktop app (macOS, Windows, Linux) using Riverpod for state management.
- Shared runtime lives in `dart_cli/`; do not duplicate migration logic in GUI.
- Ignore generated files, lock files, harmless formatting, and import ordering.

## Block Merge If Violated

- GUI imports CLI entry points such as `cli.dart` or `config/arg_parsers.dart`.
- Widgets call `RunService`, provider adapters, HTTP clients, or migration runtime directly.
- GUI duplicates migration rules already owned by `dart_cli`.
- Business logic lives in widget `build()` methods.
- Snapshot/request/value object imports Flutter or CLI UI dependencies.
- Raw tokens appear in UI, logs, errors, fixtures, or screenshots.

## Architecture

- `gui/lib/src/application/` owns GUI contracts and value objects.
- `gui/lib/src/runtime/` bridges GUI contracts to `gfrm_dart` runtime.
- `features/*/presentation/` renders state.
- Runtime mappers are pure and side-effect free.
- Controllers own stream state and emit immutable snapshots.
- Providers expose controllers and streams to widgets.
- Widgets render data and dispatch user intent only.

Flag when you see:

- Multiple public classes/widgets in one file.
- New file over 500 lines or method over 120 lines.
- Feature importing another feature's internals.
- Data models defined inside `features/*/presentation/`.
- Enum/value drift from runtime without mapper coverage.

## Riverpod

Flag when you see:

- `setState()` for business/application state.
- `ChangeNotifier`, provider package, BLoC, or `Provider.of(context)`.
- `ref.read` in `build()` for reactive data; use `ref.watch`.
- `ref.watch` inside callbacks; use `ref.read`.
- `keepAlive: true` on page-scoped providers.
- `AsyncValue` consumed without loading/error/data handling.
- Provider directly calling APIs instead of a controller/service.
- Missing `.g.dart` part after adding `@Riverpod`.
- Riverpod internals mocked instead of using `ProviderContainer` overrides.

## Testing

Flag when you see:

- New controller/provider without unit tests.
- Stream controller behavior without snapshot order tests.
- Riverpod provider without `ProviderContainer` tests when logic is non-trivial.
- Widget tests asserting provider internals instead of rendered output.
- Tests depending on real network, real timers, or local machine state.
- Mockito used where simple handwritten fakes would be clearer.

## Widgets And Desktop

Flag when you see:

- Missing `Gfrm` prefix on project widgets.
- Hard-coded colors/text styles instead of `GfrmColors`, `GfrmTypography`, or theme tokens.
- Hard-coded user-facing strings that should be localized.
- Missing `const` constructors for immutable widgets.
- Mobile-only navigation (`BottomNavigationBar`, phone `Drawer`) in desktop shell.
- Hardcoded path separators; use `path`.
- Window-size assumptions without resize handling.
- `useMaterial3: true`; project intentionally uses current custom theme.
- Direct font family strings outside theme; use declared fonts.

## Data Quality

Flag when you see:

- Mutable fields on request, snapshot, or summary classes.
- `Map<String, dynamic>` where a typed GUI value object should exist.
- `copyWith` for nullable fields without sentinel handling.
- Duplicate mapper logic across files.
- Runtime `broadcast` stream used for initial state without explicit initial snapshot/current snapshot.
