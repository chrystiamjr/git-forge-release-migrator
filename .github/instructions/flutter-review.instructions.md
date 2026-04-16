---
applyTo: "gui/lib/**/*.dart,gui/test/**/*.dart,gui/pubspec.yaml,gui/analysis_options.yaml"
---

# Flutter GUI Review Rules

- Treat `AGENTS.md` as the source of truth for product contract and invariants.
- The GUI is a Flutter desktop app (macOS, Windows, Linux) using Riverpod for state management.
- Shared Dart runtime lives in `dart_cli/` and is imported via path dependency — do not duplicate logic.

## Architecture

- **Riverpod only** — no `setState`, no `ChangeNotifier`, no `Provider` package, no BLoC.
- Controllers own `StreamController<Snapshot>` and emit immutable snapshots.
- Riverpod providers expose controllers and snapshot streams to the widget tree.
- Widgets are render-only — no business logic in `build()` methods.
- Mapper functions (`map_*.dart`) are pure — no side effects, no I/O.

Flag when you see:

- `StatefulWidget` with business logic in `State` — extract to controller + Riverpod provider.
- `setState()` for anything beyond trivial local UI state (animation, focus) — use Riverpod.
- `Provider.of(context)` or `context.read/watch` from the `provider` package — wrong package, use `ref.watch/read`.
- Logic inside `build()` — data transformation, filtering, API calls belong in controllers or providers.
- Mutable state in widget classes — snapshot pattern requires immutable data with `copyWith`.

## Riverpod Patterns

- Use `@Riverpod` annotation with code generation (`*.g.dart`).
- `keepAlive: true` only for app-scoped singletons (controller instances). Page-scoped data should auto-dispose.
- Stream providers must handle all `AsyncValue` states: loading, error, data.
- Test providers using `ProviderContainer` with overrides — never mock Riverpod internals.

Flag when you see:

- `keepAlive: true` on providers that serve a single page — should auto-dispose on navigation.
- `AsyncValue` consumed without `.when()` or equivalent — must handle loading and error states.
- Provider that directly calls APIs — should delegate to a controller or service.
- Missing `.g.dart` import after adding `@Riverpod` annotation — run `build_runner`.
- Circular provider dependencies — restructure to break the cycle.
- `ref.read` inside `build()` for reactive data — should be `ref.watch`.
- `ref.watch` inside callbacks or event handlers — should be `ref.read`.

## Widget Conventions

- All custom widgets use `Gfrm` prefix: `GfrmSidebar`, `GfrmShellPage`, etc.
- Prefer `StatelessWidget` with `const` constructor when possible.
- One widget per file. File name matches class name in snake_case.
- Use `Theme.of(context)` to access theme — never hard-code colors or text styles.
- Desktop layout uses fixed sidebar (220pt) + scrollable content (max 1120pt).

Flag when you see:

- Widget without `Gfrm` prefix (unless it is a generic reusable widget).
- Hard-coded `Color(0xFF...)` or `TextStyle(...)` — use `GfrmColors`, `GfrmTypography`, or `Theme.of(context)`.
- Hard-coded user-facing strings — should use localization (i18n).
- Widget file containing multiple public widget classes — split into separate files.
- Missing `const` on constructors where all fields are final and no mutable state exists.
- `MediaQuery` for responsive layout without considering desktop window resize.
- Scaffold without considering platform-specific chrome (macOS title bar, Windows title bar).

## Theme and Styling

- Theme is defined in `gfrm_theme.dart` — Material3 disabled, custom `ColorScheme` with indigo primary.
- Colors in `GfrmColors` (static class), typography in `GfrmTypography`.
- Fonts: IBM Plex Sans (UI), IBM Plex Mono (logs/artifacts), Inter (wordmark only).

Flag when you see:

- `useMaterial3: true` — project uses Material2 theme intentionally.
- Direct `GoogleFonts` or font family strings — use the declared theme fonts.
- Color values not from `GfrmColors` or `Theme.of(context).colorScheme`.
- Typography not from `GfrmTypography` or `Theme.of(context).textTheme`.

## Feature Module Structure

Features live under `gui/lib/src/features/<name>/presentation/`.

Expected structure per feature:
- `<feature>_page.dart` — top-level page widget.
- `<feature>_controller.dart` — Riverpod controller (if stateful).
- `widgets/` — feature-specific widgets.
- No `model/` or `data/` inside feature — shared models live in `application/`.

Flag when you see:

- Data models defined inside a feature module — should live in `application/` or `core/`.
- Feature importing another feature's internal widgets — extract to `core/widgets/`.
- Circular imports between features.

## Data Models and Contracts

- Snapshots and DTOs are `final class` with `copyWith` using sentinel pattern for nullable fields.
- Request/response types are immutable — all fields `final`.
- Enums shared with dart_cli define the runtime contract — do not duplicate or diverge.

Flag when you see:

- Mutable fields on snapshot or DTO classes.
- `copyWith` that does not handle nullable fields with sentinel values.
- Enum values in GUI that differ from dart_cli equivalents — must stay in sync.
- `Map<String, dynamic>` where a typed class should be used.

## Testing

- Unit tests for controllers: verify snapshot emissions and state transitions.
- Widget tests with `WidgetTester`: verify rendering and interaction.
- Riverpod tests use `ProviderContainer` with overrides.
- Fakes over mocks — prefer custom fake classes in `test/support/`.
- Test file location mirrors source: `test/unit/` for logic, `test/widget/` for UI.

Flag when you see:

- `when(...).thenReturn(...)` from mockito for simple interfaces — prefer handwritten fakes.
- Widget tests that test implementation details (provider internals) instead of rendered output.
- Missing tests for new controllers or providers.
- Tests that depend on real timers or network — use fakes or `FakeAsync`.
- Generated files (`*.g.dart`) included in test assertions.

## Desktop-Specific

- Support macOS, Windows, Linux — no mobile-only assumptions.
- Window management via `window_manager` package.
- Consider keyboard navigation and focus traversal.
- File paths must work cross-platform (use `path` package, not string concatenation).

Flag when you see:

- Mobile-only widgets (`BottomNavigationBar`, `Drawer` for phone layout) in desktop context.
- Hardcoded `/` or `\` path separators — use `path` package.
- Missing keyboard shortcut support for common actions.
- Window size assumptions without `LayoutBuilder` or `MediaQuery`.

## SOLID and Clean Architecture

Flag when you see:

- Multiple public classes in one `.dart` file — one public class per file (SRP).
- Widget doing data fetch + transform + render — split into controller (data) + widget (render).
- Controller with 500+ lines — likely violating SRP, break into focused sub-controllers.
- `if (provider is GitHub)` type checks — use polymorphism via interfaces (OCP).
- Riverpod provider that directly calls HTTP — introduce a service/repository layer between provider and API (DIP).
- Same widget subtree copy-pasted across features — extract to `core/widgets/` (DRY).
- Same data transformation duplicated in multiple mappers — consolidate into a single mapper function (DRY).
- Feature module importing another feature's internals — extract shared code to `core/` or `application/` (ISP).
- New file over 500 lines or method over 120 lines — decompose.

## Boundary with dart_cli

- GUI imports dart_cli as a path dependency for runtime types and services.
- GUI must NOT import dart_cli's CLI-specific code (`cli.dart`, `config/arg_parsers.dart`).
- GUI has its own entry point and orchestration via `DesktopRunController`.
- Mapper functions in `runtime/run/map_*.dart` bridge dart_cli types to GUI types.

Flag when you see:

- GUI importing `package:gfrm_dart/src/cli.dart` or CLI argument parsers.
- Dart_cli code importing Flutter or GUI-specific packages.
- Duplicated business logic that already exists in dart_cli.
- GUI directly calling provider API adapters — should go through the controller.
