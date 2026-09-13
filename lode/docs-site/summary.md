# Docs site (`docs/`)

The authoring contract is `../../docs/AGENTS.md`; this file does not repeat it, only maps what exists today. See also `../lode-map.md`.

## What it is

`docs/` is a self-contained [docs-kit](https://github.com/zoolutions/docs-kit) Rails app: a Phlex/daisyUI chrome where every page is a `DocsUI::Page` subclass (`docs/AGENTS.md`). It has its own `Gemfile`, `Gemfile.lock`, RuboCop config and RSpec suite, separate from the gem root (`CLAUDE.md`).

Pages are registered in `docs/app/models/doc.rb` via `Doc` (`extend DocsKit::Registry`, `path_prefix "/docs"`, `view_namespace "Views::Docs::Pages"`). Each `page "Title", group: "..."` line is what makes a page routed and appear in the sidebar nav (`docs/app/models/doc.rb`); an unwritten registry entry (no resolvable view class) is silently skipped everywhere, including `/llms.txt` and search.

## Pages (`docs/app/views/docs/pages/*.rb`)

One class per file, title/eyebrow read from each file's own declarations, mapped to the gem behaviour it documents and the lib file that behaviour lives in:

| File | Title (group) | Documents | Lives in |
|---|---|---|---|
| `overview.rb` | Overview (Getting started) | what importmap-plus adds over importmap-rails | the whole gem |
| `installation.rb` | Installation (Getting started) | adding the gem, fresh app vs. existing importmap-rails app | `lib/install/`, `Gemfile` |
| `how_import_maps_work.rb` | How import maps work (Getting started) | bare specifiers, browser substitution, local module pins | `lib/importmap/map.rb` |
| `pinning.rb` | Pinning packages (Vendoring) | `pin`: vendoring, CDN choice, remote/custom URLs, option survival on rewrite | `lib/importmap/commands.rb`, `lib/importmap/packager.rb` |
| `esm_run.rb` | esm.run bundles (Vendoring) | `--from esm.run`, the bundle import rewrite, dependency pinning | `lib/importmap/packager.rb` (`rewrite_esm_run_imports`, `ESM_RUN_PROVIDER`) |
| `minifying.rb` | Minifying (Vendoring) | `pin --minify` / `pristine --minify`, which tool runs, custom minifiers | `lib/importmap/minifier.rb` |
| `provenance.rb` | Provenance (Vendoring) | the `# @version (provider, minified, locked)` pin comment and its grammar | `lib/importmap/packager.rb` (`PIN_PROVENANCE_REGEXP`) |
| `locking.rb` | Locking versions (Vendoring) | `pin --lock`, `lock`/`unlock`, what other commands do to a locked pin | `lib/importmap/commands.rb`, `lib/importmap/packager.rb` |
| `updating.rb` | Updating & auditing (Vendoring) | `update`, `outdated`, `audit`, `pristine`, `packages`, `json` | `lib/importmap/commands.rb`, `lib/importmap/npm.rb` |
| `preloading.rb` | Preloading (Serving) | `modulepreload` links, `preload: false`, per-entry-point preloading | `lib/importmap/map.rb` (`preloaded_module_paths`) |
| `integrity.rb` | Subresource integrity (Serving) | `enable_integrity!`, automatic and explicit integrity hashes | `lib/importmap/map.rb` (`enable_integrity!`, `digest`) |
| `composing.rb` | Composing import maps (Serving) | combining import map files via `config.importmap.paths` | `lib/importmap/engine.rb` |
| `selective_imports.rb` | Selective imports (Serving) | `preload: false` + `javascript_import_module_tag` for page-specific modules | `app/helpers/importmap/importmap_tags_helper.rb` |
| `caching.rb` | Caching & ETags (Serving) | ETag from the import map digest, dev cache sweeper | `app/controllers/importmap/freshness.rb`, `lib/importmap/engine.rb` (cache sweeper initializer) |
| `cli.rb` | CLI reference (Reference) | every `bin/importmap` command, option, exit status | `lib/importmap/commands.rb` |
| `configuration.rb` | Configuration (Reference) | `Rails.application.config.importmap.*` and Packager class-level knobs | `lib/importmap/engine.rb`, `lib/importmap/packager.rb`, `lib/importmap/http_retries.rb` |
| `upgrading.rb` | Upgrading from importmap-rails (Reference) | what an app coming from importmap-rails sees change vs. doesn't | `lib/importmap/commands.rb`, `lib/importmap/packager.rb` |
| `changelog.rb` | Changelog (Reference) | renders the gem's own `CHANGELOG.md` verbatim (minus its `# Changelog` heading, to avoid duplicating the page title) | `../../CHANGELOG.md` |

18 registry entries in `docs/app/models/doc.rb` and 18 page files under `docs/app/views/docs/pages/` — one to one, though `changelog.rb` renders the root `CHANGELOG.md` rather than describing a lib file.

## Authoring contract (from `docs/AGENTS.md`)

- Scaffold with `rails g docs_kit:page "Title" --group=...` — it writes the page file **and** the `Doc` registry line in one step; a hand-written page must add the registry line itself or it is unrouted and absent from the nav.
- `DocsUI::Section` owns page structure and the "On this page" TOC — one per part of a page; Markdown `##`/`###` is for prose sub-headings only, never page structure.
- Prose is Markdown via a **single-quoted** heredoc (`<<~'MD'`) so `#{...}` in fenced code examples stays literal; Phlex escapes author text, so never `html_safe` or interpolate directly.
- Reference material (props, fields, request/response shape) uses dedicated helpers (`DocsUI::PropTable`, `DocsUI::FieldTable`, `DocsUI::RequestExample`, `DocsUI::Callout`) rather than prose tables.
- Pages must render fully server-side; the `docs-nav` Stimulus controller only enhances — the contract explicitly requires the page to read correctly with JavaScript off.
- No inline `rubocop:disable` to force layout.

## Lint and test

- `docs/Rakefile` defines `rake lint` (and `lint:fix`): runs RuboCop over `app/**/*.rb spec/**/*.rb config/**/*.rb lib/**/*.rb lib/**/*.rake Rakefile config.ru`, with the file list passed explicitly so this app is linted regardless of what the gem root's RuboCop setup (there isn't one) would otherwise exclude.
- `docs/.rubocop.yml` inherits `rubocop-rails-omakase` and docs-kit's own cop config (`docs_kit/rubocop`), plus `rubocop-rspec`; it turns off `Style/Documentation`, `RSpec/ExampleLength`, `RSpec/MultipleExpectations` and `RSpec/DescribeClass` (request specs read top to bottom and legitimately assert more than once), and `RSpec/SpecFilePathFormat` (pages/views aren't spec'd by class path).
- `docs/spec/requests/docs_spec.rb` iterates `Doc.all.select(&:view_class)` and, per page, asserts: the HTML route returns 200 and its `<h1>` includes the page's title (parsed via Nokogiri, so an escaped `&` still matches); the `.md` route returns 200 with `text/markdown`. It also asserts an unknown slug 404s, the landing page renders and mentions "importmap-plus", and the overview page's body includes `v#{Importmap::VERSION}`. Two more request specs exist: `ai_surfaces_spec.rb`, `mcp_spec.rb`.
- Run from inside `docs/`: `bundle exec rake lint && bundle exec rspec` (`CLAUDE.md`).

## Dependency on the gem

`docs/Gemfile` depends on the gem with `gem "importmap-plus", path: ".."` (`docs/Gemfile:43`), so `docs/Gemfile.lock` pins an exact `importmap-plus (X.Y.Z)` version resolved from the local checkout (currently `1.2.0`, per `docs/Gemfile.lock:4`, matching `Importmap::VERSION` in `lib/importmap/version.rb` at the time this was read). Consequence: whenever `Importmap::VERSION` moves — a feature PR opening a new minor, or `bin/release` — `docs/Gemfile.lock`'s pin is now stale, and the next PR touching `docs/**` fails its frozen `bundle install` until someone runs `cd docs && bundle install` and commits the updated lock (`.claude/rules/git-workflow.md`).

## Deployment

- `docs/Dockerfile` is a multi-stage build (`docs-kit Dockerfile v1.1.1`, regenerated via `bin/rails g docs_kit:install`). Because the app depends on the gem via `path: ".."`, the build context is the **repo root**, not `docs/` — built with `docker build -f docs/Dockerfile .` from the root, so the gem source is available at build time. `ARG RUBY_VERSION` / `ARG BUN_VERSION` are declared before the first `FROM` so every stage sees them; the final stage carries only the Ruby runtime and installed bundle, not the build toolchain (build-essential, git, bun).
- `.github/workflows/deploy-docs.yml` fires on a published GitHub Release (or manual dispatch) and calls docs-kit's reusable `deploy.yml` workflow (pinned to a specific commit SHA, not a moving branch ref, because the call is handed `packages: write` and inherited secrets) with `image: zoolutions/importmap-plus`, `service: importmap-plus`.
- `docs/config/deploy.yml` (dash-based) names `service: importmap-plus`, `image: zoolutions/importmap-plus`, deploys to a single `web` host from `ENV["DEPLOY_HOST"]`/`ENV["DEPLOY_DOMAIN"]`, terminates TLS at Cloudflare (proxy reached over plain HTTP through a tunnel), and serves static `public/502.html`/`503`/`504` during a deploy gap.

## Invariant

Every user-facing gem change updates the matching docs page **and** `CHANGELOG.md` in the same PR (`CLAUDE.md`, `.claude/rules/git-workflow.md`: "A `feat:` PR also updates `CHANGELOG.md` ... and the relevant `docs/` page in the same PR"). The page-to-lib-file table above is what makes "the matching page" findable for a given change.

## See also

- `../lode-map.md`
- `../../docs/AGENTS.md`
