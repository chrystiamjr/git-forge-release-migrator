## [0.2.0](https://github.com/chrystiamjr/git-forge-release-migrator/compare/v0.1.0...v0.2.0) (2026-03-12)

### Features

* **ci:** add coverage reporting, smoke tests, SHA256 checksums, and Dependabot ([a585e22](https://github.com/chrystiamjr/git-forge-release-migrator/commit/a585e22aef79be547a941664718bbfe9f044ad40))
* **ci:** improve workflow efficiency and Dependabot configuration ([81cdd2e](https://github.com/chrystiamjr/git-forge-release-migrator/commit/81cdd2e581523edd38ccf5363090df75e1d74918))
* **dart:** improve HTTP resilience, error handling, and diagnostic logging ([43e76d2](https://github.com/chrystiamjr/git-forge-release-migrator/commit/43e76d26703f366cb133fd74ef07b51c2d15abad))
* **docs:** configure custom domain gfrm.envolvosystems.com.br ([f705248](https://github.com/chrystiamjr/git-forge-release-migrator/commit/f705248ebf237318457fafa8dce5fcac3b9ef3e9))
* **docs:** launch Docusaurus 3 website at gfrm.envolvosystems.com.br ([6ca0ba5](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6ca0ba56a4e2461ec291117b62ea7e8d5c920252))
* **i18n:** add PT-BR translations for landing page and download component ([6b5571e](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6b5571e8acc1e42607974e45754c2a737fb33ea2))
* **website:** add floating locale switcher for mobile doc pages ([d0cef14](https://github.com/chrystiamjr/git-forge-release-migrator/commit/d0cef14efeb6043e25f99ae5801e91eddcbaaed8))
* **website:** add locale switcher to landing page and PT-BR translation pre-commit check ([84b4f71](https://github.com/chrystiamjr/git-forge-release-migrator/commit/84b4f719c60cc06aae7c7c6ab2f25c38430c49d1))
* **website:** add modern landing page with dynamic download component ([18b95ec](https://github.com/chrystiamjr/git-forge-release-migrator/commit/18b95ec33d81bbc64d437cfe7ef4a280a0cd2b83))

### Bug Fixes

* address PR review comments from Copilot ([63c6050](https://github.com/chrystiamjr/git-forge-release-migrator/commit/63c60502c783cad25f3cb20670826bd656c64d49))
* address second round of PR review comments ([d215701](https://github.com/chrystiamjr/git-forge-release-migrator/commit/d215701ab4f68153d4ca05d9c5898d85dfdbda85))
* **ci:** align release tooling and harden test infra ([a51629e](https://github.com/chrystiamjr/git-forge-release-migrator/commit/a51629eb0eab7a198ebbb949c3defbc6d525542f))
* **ci:** enforce --fatal-infos, 80% coverage threshold, and trim release rules ([04213dd](https://github.com/chrystiamjr/git-forge-release-migrator/commit/04213dda33fbbfd395a639a7131e80fb474f00d8))
* **i18n:** translate all PT-BR page titles and sidebar categories ([d05e911](https://github.com/chrystiamjr/git-forge-release-migrator/commit/d05e911c840ecf01994230c9e629926b9f5db739))
* **website:** address code review findings ([1daef54](https://github.com/chrystiamjr/git-forge-release-migrator/commit/1daef54b5f02b91c367440058c190af15e8494ff))
* **website:** address remaining PR review comments ([6b01457](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6b01457ab520ee173a06e5bd5560cec9ba9ebc58))
* **website:** fix locale switching, platform detection, and footer year ([67a3a3c](https://github.com/chrystiamjr/git-forge-release-migrator/commit/67a3a3cf6ffc0f7f2af8294da73e39263a5b1d95))
* **website:** fix navbar logo flash and add trademark notice ([6a4427b](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6a4427b837d22b0585fb7af667f7eb99da561abe))

## [0.1.0](https://github.com/chrystiamjr/git-forge-release-migrator/compare/v0.0.0...v0.1.0) (2026-03-10)

### ⚠ BREAKING CHANGES

* cut over to Dart CLI and remove Python runtime

### Features

* **bitbucket:** add cross-forge migration
  support ([6f2fb02](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6f2fb02359f035957ce6b83650a57db1be301f98))
* cut over to Dart CLI and remove Python
  runtime ([6c021f8](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6c021f839c9da95942fc87231824ce58d1c91f02))
* **settings:** add profile-based token configuration
  system ([ae84006](https://github.com/chrystiamjr/git-forge-release-migrator/commit/ae84006a28dab7edcbc093dc6056c82867077ef7))

### Bug Fixes

* **ci,pr:** restore workflow parsing and harden http
  tests ([9a9f9e8](https://github.com/chrystiamjr/git-forge-release-migrator/commit/9a9f9e82146cc49bae6968b6f6a8db9de072b1db))
* **ci:** bootstrap pre-1.0 release and remove duplicate cli build
  trigger ([25e3fe5](https://github.com/chrystiamjr/git-forge-release-migrator/commit/25e3fe51984577dfdfa7e278616f12b7e565b113))
* **ci:** bootstrap v0.0.0 from non-workflow commit for PAT
  compatibility ([d5dcd60](https://github.com/chrystiamjr/git-forge-release-migrator/commit/d5dcd60206d8d620db06c8298067c7a2a3815c97))
* **ci:** create bootstrap tag via API and serialize release
  runs ([6e1c273](https://github.com/chrystiamjr/git-forge-release-migrator/commit/6e1c2731a259c8f5b44d61014e96b80689389346))
* **ci:** detect workflow file changes in merge commits during bootstrap
  scan ([2631f28](https://github.com/chrystiamjr/git-forge-release-migrator/commit/2631f286aceb05901168c2f60ce692e25f386473))
* **ci:** harden bootstrap commit scan and avoid local tag
  divergence ([572e6c9](https://github.com/chrystiamjr/git-forge-release-migrator/commit/572e6c9a15c49fcdf52d734af1f1d1c026c27dc2))
* **ci:** make bootstrap tag creation
  race-safe ([17933a4](https://github.com/chrystiamjr/git-forge-release-migrator/commit/17933a4422b611168497ba1ea71a41109af4934b))
* **ci:** stabilize dart checks and build output
  directory ([8f75605](https://github.com/chrystiamjr/git-forge-release-migrator/commit/8f756052d3a2755c96ff4288300635fe23da16ba))
* **ci:** use lightweight bootstrap tag to avoid git identity
  requirement ([ef64e1d](https://github.com/chrystiamjr/git-forge-release-migrator/commit/ef64e1dbc4d76c006a93f143f9c247e415900252))
* **ci:** use local semantic-release config without extends
  install ([258c4a5](https://github.com/chrystiamjr/git-forge-release-migrator/commit/258c4a56eb571044f411cd18041dc796289cef8f))
* **ci:** use topo-order when selecting bootstrap
  commit ([fea64d0](https://github.com/chrystiamjr/git-forge-release-migrator/commit/fea64d0e9454eacb86612497814d4c4471514e2a))
* **pr:** address latest review
  comments ([e854d2d](https://github.com/chrystiamjr/git-forge-release-migrator/commit/e854d2dd9b41cb3640ea317fbd0ab930231e2d44))
* **pr:** address latest review
  round ([33cc619](https://github.com/chrystiamjr/git-forge-release-migrator/commit/33cc61958fabc2f45230142a6e59272acf2a6b4b))
* **pr:** address latest review
  threads ([9cf0a19](https://github.com/chrystiamjr/git-forge-release-migrator/commit/9cf0a19945b7ee97e3fbf5ff9d811b76916f4c1c))
* **pr:** address latest review
  threads ([1f46db0](https://github.com/chrystiamjr/git-forge-release-migrator/commit/1f46db02173df54c629c6fc293f707eea54c24f8))
* **pr:** address latest review
  threads ([69128dd](https://github.com/chrystiamjr/git-forge-release-migrator/commit/69128dd8b76aea297339a430d3635694433ae3a0))
* **pr:** address review comments on caching, security, and
  docs ([df0df16](https://github.com/chrystiamjr/git-forge-release-migrator/commit/df0df16756f0ba854e37f40ef0ebaabca891b99b))
* **pr:** resolve latest workflow and github provider
  comments ([4403e68](https://github.com/chrystiamjr/git-forge-release-migrator/commit/4403e68f9102b288c693f2976078ec80428024cf))
* **release:** attach CLI assets and keep pre-1.0
  versioning ([89945eb](https://github.com/chrystiamjr/git-forge-release-migrator/commit/89945eb293a9f5d41a965f68fe3edadfb9cf45b2))
* **review:** handle semver parse errors and honor
  retry-after ([b3ffafb](https://github.com/chrystiamjr/git-forge-release-migrator/commit/b3ffafbf0653aecdca3b7e76bf3c7bf1854c0bf1))
* **review:** move invalid_annotation_target to analyzer
  errors ([f3dd7a2](https://github.com/chrystiamjr/git-forge-release-migrator/commit/f3dd7a21584ae61ba01f3fc5642d9666331538a5))
* **review:** tighten keychain cleanup guard and document pre-1.0
  rule ([fc08c0d](https://github.com/chrystiamjr/git-forge-release-migrator/commit/fc08c0d561d2bb4c7d85be634b198cb004dd6a6c))

All notable changes to this project will be documented in this file.

This file is managed by semantic-release.
