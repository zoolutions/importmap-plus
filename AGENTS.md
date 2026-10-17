# importmap-plus

Project instructions for every agent: Claude Code (`CLAUDE.md` `@`-imports this file), Grok, Cursor,
Copilot and Codex read it directly. Claude-only extras (commands, plugin settings) live under `.claude/`; the delivery workflow comes from the `flow` and `ruby-gem` plugins of the shared marketplace (`.claude/settings.json`).

A drop-in replacement for [rails/importmap-rails](https://github.com/rails/importmap-rails) — repo `zoolutions/importmap-plus`, published on rubygems.org as `importmap-plus`. Same `Importmap::` constants, same engine, same helpers and pin DSL; an app switches by changing one `Gemfile` line. Everything this gem adds lives in the vendoring path: `bin/importmap pin --minify`, `--from esm.run` for jsDelivr's bundled builds, version locks, `update` by package name, and a pin comment that records where each package came from.

This is a **maintained fork that still tracks upstream**. The `upstream` remote points at rails/importmap-rails, `Importmap::UPSTREAM_VERSION` names the release currently merged in, and `Importmap::VERSION` is this gem's own semver. The per-file merge rules are in `.claude/commands/upstream-sync.md`.

## Tech Stack

- **Ruby**: >= 3.1 (CI: 3.1–4.0) | **Rails**: >= 6.0 (CI: 6.1 → main, sprockets and propshaft)
- **Runtime deps**: railties, activesupport, actionpack — nothing else. Thor comes with railties.
- **CLI**: Thor (`lib/importmap/commands.rb`, installed into apps as `bin/importmap`)
- **Testing**: Minitest via `ActiveSupport::TestCase` against `test/dummy`; the CI matrix is Appraisal gemfiles under `gemfiles/`
- **Linting**: RuboCop at the gem root checks only what conformance-kit holds the gem to — the thread-safety cops and `# frozen_string_literal: true` (`.rubocop.yml`, `DisabledByDefault`). Never turn style cops on there: upstream-owned files stay diff-minimal. `docs/` has its own RuboCop.
- **Docs**: `docs/` — a docs-kit Rails app deployed to https://importmap-plus.zoolutions.llc

## Critical Rules

### Never Do

1. **NO breaking the importmap-rails surface** — every constant, helper, DSL method, option, generator and rake task importmap-rails ships must keep working unchanged. Additions only; a rename or removal is a fork-breaking change.
2. **NO new runtime dependencies** — the gemspec lists railties, activesupport and actionpack. Minification shells out to a bun/esbuild/terser already on the machine; it does not bundle one.
3. **NO touching import specifiers in vendored files** — minification is transform-only (`--no-bundle`, `--format=esm`), so bare specifiers stay exactly as the CDN resolved them and the import map keeps resolving them. There are two deliberate exceptions, both turning a URL the import map can't resolve into a bare key it can: `rewrite_esm_run_imports`, for a jsDelivr bundle's `/npm/dep@ver/+esm` imports, and `Importmap::PackageGraph#rewrite_specifiers`, for the relative imports of a package vendored with its file graph.
4. **NO losing a pin's provenance or options on rewrite** — the `# @<version> (<provider>[, minified][, vendored][, remote[: <reason>]][, locked])` comment plus `preload:` and `integrity:` must survive `pin`, `update`, `pristine` and `unpin`. Dropping them silently drifts a package back to jspm on the next update.
5. **NO raw `Net::HTTP` calls in Packager or Npm** — every outbound request goes through `with_retries` (`Importmap::HttpRetries`) and raises the class's own `HTTPError` once the attempts are spent.
6. **NO network access on the request path** — engine → `Map` → helpers never reach a CDN or registry. Only the CLI (`Commands` → `Packager` / `Npm`) does.
7. **NO hand-merging `Gemfile.lock`, `docs/Gemfile.lock` or `docs/bun.lock`** — regenerate them (Workflow → Conflicts). `gemfiles/*.lock` are gitignored; CI deletes and re-resolves them.
8. **NO moving `UPSTREAM_VERSION` outside a sync PR** — it names the importmap-rails release merged in, and only `/upstream-sync` changes it. `VERSION` is different: a feature PR that opens a new minor bumps it (that is how 1.1.0 landed), and `bin/release X.Y.Z` then tags the version already in the file. Never bump it twice for one release.

### Always Do

1. **TDD** — a failing Minitest first, then the code (Testing below)
2. **Keep upstream-owned files diff-minimal** — new behaviour goes in new files (`minifier.rb`, `http_retries.rb` are the precedent) or in small, clearly bounded additions, so the next `git merge upstream/main` stays mergeable
3. **Match upstream's Ruby style in upstream-owned files** — `[ a, b ]` array spacing, `private` followed by indented methods, `# :nodoc:` on internals. A style-only diff is conflict surface for no gain.
4. **A pin this gem writes must be a pin importmap-rails can read** — an app can go back to importmap-rails and its `config/importmap.rb` must still parse. Comments carry the fork's metadata precisely because upstream ignores them.
5. **Document user-facing changes** — update the matching page under `docs/app/views/docs/pages/` and add a `CHANGELOG.md` entry under the next version heading
6. **Run the CDN-backed tests before pushing** anything that touches `commands.rb`, `packager.rb` or `npm.rb` — `test/commands_test.rb` and the two `*_integration_test.rb` files are the only coverage of the real jspm, jsDelivr and npm-registry contracts
7. **Go through the existing helpers** — pin lines match with `Importmap::Map.pin_line_regexp_for` and re-emit via `vendored_pin_for` / `pin_for`, options read back with `extract_existing_pin_options`; vendored paths come from `vendored_package_path`; shell-outs are `Open3.capture3(executable, *argv)`, never a string (package names arrive from the network); write the final `vendor/javascript` file last, from a `Dir.mktmpdir`
8. **Fix upstream's bug in both places** — a bug in a file this fork leaves unchanged is fixed here and opened against rails/importmap-rails, so the next sync shrinks the diff

### Code style

Upstream-owned files (`map.rb`, `engine.rb`, `reloader.rb`, `npm.rb`, `commands.rb`, `packager.rb`, helpers, `lib/install/`) are matched exactly: add, never rearrange or reformat; past a few dozen lines extract a fork-only collaborator. Fork-only files (`minifier.rb`, `http_retries.rb`, `CHANGELOG.md`, `docs/`) own their shape. `bin/release`, `rakelib/release.rake`, `release.yml` (all but its `test` job), `bin/labels` and `.github/LABELS.md` are kits, byte-identical across the gems: change docs-kit, then run its `script/release-kit sync` / `script/labels-kit sync`. Comments say why, never what; no `TODO` without an issue; one class per file under `Importmap::`, ~400 lines (`packager.rb` is at the limit). A CLI failure is a sentence via `Thor::Error` / `Packager::Error` (`Commands.exit_on_failure?` is `false` on purpose); never `rescue` a CDN call to quiet a test.

### Testing

Minitest only (`ActiveSupport::TestCase`, `test "…" do`, `Minitest::Mock` / `Object#stub`) — no RSpec. The default is a unit test with the network stubbed (`Net::HTTP.stub`, `packager.stub(:post_json, …)`, `npm.stub(:get_json, …)`); a live `commands_test.rb` case only for a new CDN contract, with exact versions (`md5@2.2.0`). Anything that writes takes `vendor_path:` inside `Dir.mktmpdir` (the default resolves against the cwd and leaves `vendor/javascript` at the repo root); class-level accessors (`HttpRetries.attempts`/`wait`, `Packager.endpoint`, `Npm.base_uri`) are restored in `ensure` (`without_retry_wait`). `CommandsTest` forks per test, copies `test/dummy` and runs the real `bin/importmap`: assert the printed sentences and the resulting files. A new pin-line shape gets a fixture, `test/fixtures/files/<shape>_import_map.rb`. CI cells to remember: `ASSETS_PIPELINE` branches in `importmap_test.rb`; Rails 6.1 needs `logger`/`mutex_m`/`drb`/`bigdecimal` (`Appraisals`); Ruby 3.1 has no `Data.define` or anonymous `*`/`**` forwarding. A red live test is not a flake until the matrix and `with_retries` are ruled out; never `retry`, `sleep` or `skip` it. Coverage: 80% overall, 100% for Packager pin-line rewriting, `Minifier`, `HttpRetries`, `Map#to_json` / `preloaded_module_paths`.

### Git

`origin` is this gem (`gh repo set-default zoolutions/importmap-plus`, or `gh` targets the fork parent); `upstream` is rails/importmap-rails, read-only. Work branches `feat|fix|chore|docs|ci|sync/*` off fresh `origin/main`; stacked PRs only when the second builds on the first (say so in the body); published branches take `main` merged forward, never rebased. Commit prefixes add `sync:` (`sync: merge importmap-rails 2.3.0`). Tags are plain `vX.Y.Z`, no `-rc`, never `git push --tags`.

## Commands

```bash
bundle exec rake test                                   # full suite (talks to live CDNs: jspm, jsDelivr, npm registry)
bundle exec ruby -Itest test/packager_test.rb           # one file (bin/test, upstream's rails/plugin/test runner, runs 0 tests on Rails 8.1 — don't use it)
bundle exec ruby -Itest test/commands_test.rb -n /minify/   # tests matching a name pattern
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install && \
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test   # one CI matrix cell
bundle exec appraisal generate                          # regenerate gemfiles/ after editing Appraisals
bundle exec rubocop                                     # thread-safety cops + the frozen-string magic comment (root bundle, Ruby 3.2+)
bundle exec conformance-kit check                       # the conformance gate CI runs on Ruby 4.0: doctor, the Ractor canary, conformance-audit --strict
cd docs && bundle exec rake lint && bundle exec rspec   # docs site: RuboCop + request specs (render every registered page)
cd docs && bin/dev                                      # docs site locally
bin/release --dry-run                                   # next version + changes since the last tag (`bin/release list` for the history)
bin/release [minor|major|X.Y.Z]                         # bump version + lockfile pins, commit, push, GitHub Release → release.yml publishes the gem, deploy-docs.yml ships the docs
```

The `--minify` tests **skip** unless bun, esbuild or terser is on `PATH` or in `node_modules/.bin`. CI installs bun; install it locally or those paths go unexercised.

Command output is condensed by rtk (PreToolUse hook). `docs/.rtk/filters.toml` covers the docs
site's `rake lint` / `rake lint:fix` task (it must live under `docs/`, not the repo root — rtk
resolves project filters against the directory the command actually runs from, and that task only
runs with `docs/` as the working directory); every edit to it needs `rtk trust --yes` + `rtk verify`
run from inside `docs/`. Write commands in hook-rewritable shapes: no `for`/subshell wrappers, no
`| head` on rtk-handled commands, `bundle exec rubocop` not `bin/rubocop`.

## Slash Commands

The delivery workflow is the `flow` plugin (`/flow:lfg`, `/flow:plan`, `/flow:tdd`, `/flow:review-pr`, `/flow:github-review-pr`, `/flow:finish-prs`, `/flow:follow-through`, `/flow:debug-flaky`) and `ruby-gem` (`/ruby-gem:release`, `/ruby-gem:perf`), driven by the Workflow section below. Local:

| Command | Purpose |
|---------|---------|
| `/architect` | Order multi-layer work across engine → Map → helpers → CLI → Packager/Npm → docs |
| `/security` | Audit CDN and registry input handling, vendored-file paths, shell-outs, SRI |
| `/upstream-sync` | Merge a new importmap-rails release, bump `UPSTREAM_VERSION`, re-sync the docs |

## Architecture

```
Rails engine   lib/importmap/engine.rb                          config.importmap, draws config/importmap.rb, reloader, cache sweeper, asset paths, helpers
Map (DSL)      lib/importmap/map.rb                             pin / pin_all_from, to_json, preloaded_module_paths, integrity, digest, per-request cache
Reloader       lib/importmap/reloader.rb                        re-draws the map when config/importmap.rb changes
View helpers   app/helpers/importmap/importmap_tags_helper.rb   javascript_importmap_tags and friends
Freshness      app/controllers/importmap/freshness.rb           stale_when_importmap_changes — ETag from the map digest
CLI            lib/importmap/commands.rb                        Thor: pin, unpin, pristine, json, audit, outdated, update, packages
Packager       lib/importmap/packager.rb                        resolves via api.jspm.io or esm.run (jsDelivr), downloads to vendor/javascript, rewrites pin lines
Npm            lib/importmap/npm.rb                             registry.npmjs.org: outdated, audit, packages_with_versions
Minifier       lib/importmap/minifier.rb                        bun / esbuild / terser, transform-only                (fork-only file)
HttpRetries    lib/importmap/http_retries.rb                    bounded retries shared by Packager and Npm            (fork-only file)
ModuleInspector lib/importmap/module_inspector.rb               whether a download can be served as one file          (fork-only file)
PackageGraph   lib/importmap/package_graph.rb                   crawls a chunked package's siblings, rewrites them    (fork-only file)
VendoredGraph  lib/importmap/vendored_graph.rb                  the graph directory and the pin_all_from line         (fork-only file)
EsmRun         lib/importmap/esm_run.rb                          the esm.run provider: URLs, import rewrite, versions  (fork-only file)
Installer      lib/install/, lib/tasks/importmap_tasks.rake     rails importmap:install
```

Two paths, kept apart: the **request path** (engine → Map → helpers, no I/O beyond the asset resolver) and the **command path** (CLI → Packager/Npm → CDN or registry → `vendor/javascript` + `config/importmap.rb`).

## The pin-line contract

`config/importmap.rb` is both the app's source of truth and the file the CLI rewrites in place. The Packager's regexes — `PIN_REGEX`, `PRELOAD_OPTION_REGEXP`, `TO_OPTION_REGEXP`, `PIN_PROVENANCE_REGEXP`, `PACKAGE_SPEC_REGEXP` — are the parser; there is no AST. Every rewrite must:

- match the pin with `Importmap::Map.pin_line_regexp_for(package)` and replace only that line
- preserve `preload:` and `integrity:` exactly, including `preload: false` and array preloads
- keep a remote pin (`to: "https://…"`) remote and re-resolve it from the same CDN; leave a custom URL alone
- re-emit the provenance comment `# @<version> (<provider>[, minified][, locked])` — `jspm.io` is the default provider and is omitted
- name a vendored file `package.gsub("/", "--") + ".js"` (`@hotwired/stimulus` → `@hotwired--stimulus.js`)
- leave the one line that isn't a pin alone unless it is the graph directory being written: `pin_all_from "<vendor>/<file without .js>", under: "<package>"[, to: …][, preload: …] # @<version> (graph of <package>)`, matched by its own directory and its own comment (`Importmap::VendoredGraph`), and invisible to every regex above

## Fork tracking

| | Upstream (rails/importmap-rails) | This gem |
|---|---|---|
| Version | `Importmap::UPSTREAM_VERSION` | `Importmap::VERSION` (own semver) |
| Gemspec | `importmap-rails.gemspec` (deleted here) | `importmap-plus.gemspec` |
| Entry point | `lib/importmap-rails.rb` (kept — still the real entry) | `lib/importmap-plus.rb` requires it |
| Release | `bin/release` pushed from a laptop with an API key | `bin/release` → `rake release[X.Y.Z]` → GitHub Release → trusted publishing (`release.yml`), the zoolutions release kit |
| Fork-only files | — | `minifier.rb`, `http_retries.rb`, `module_inspector.rb`, `package_graph.rb`, `vendored_graph.rb`, `provider_chain.rb`, `integrity.rb`, `esm_run.rb`, `CHANGELOG.md`, `release.yml`, `deploy-docs.yml`, `docs-ci.yml`, `docs/` |

Upstream files this fork has modified heavily, which WILL conflict on sync: `commands.rb`, `packager.rb`, `npm.rb`, `README.md`, `ci.yml`, `test/commands_test.rb`, `test/packager_test.rb`. Per-file resolution rules: `.claude/rules/upstream-sync.md`.

## Labels

Every pull request carries exactly one `type` label and at least one `area`
label from `.github/labels.yml` — never a `status` label. `/flow:plan` labels the
issue, `/flow:lfg` copies the issue's `type` and `area` labels onto the PR (never
`plan` or another status label). Without an issue, the type comes from the
change's conventional-commit prefix and the areas from
`bin/labels infer $(git diff --name-only origin/main...HEAD)`. Labels change in
the manifest and reach GitHub with `bin/labels sync`, never through the UI.
Rules: `.github/LABELS.md`. `bin/labels` + `.github/LABELS.md` are the shared
labels kit (canonical copy in docs-kit): never edit them in place.

## Docs site (`docs/`)

A self-contained docs-kit Rails app with its own bundle, RuboCop and RSpec. `docs-ci.yml` runs it only when `docs/**` changes; `deploy-docs.yml` ships it on every GitHub Release, so the docs go live with the gem. Pages are registered in `docs/app/models/doc.rb`; add one with `cd docs && bin/rails g docs_kit:page "Title" --group=…`. The authoring contract is `docs/AGENTS.md`.

`docs/Gemfile` depends on the gem through `path: ".."`, so `docs/Gemfile.lock` pins `importmap-plus (X.Y.Z)`. `rake release` bumps that pin with the root one, in the release commit. A feature PR that moves `VERSION` itself must still `cd docs && bundle install` and commit the pin, or the frozen docs bundle install fails on the next `docs/**` PR.

## Screenshots on PRs and issues (always)

`gh` ≥ 2.99 uploads images and videos itself. The gem's CLI has no visual output, but `docs/` is a
live Phlex/docs-kit Rails site — any `docs/app/views/**`, `docs/app/components/**` or
`docs/app/assets/**` change ships with before/after pictures **on the PR**, attached from the
terminal. Never a local path, a base64 blob, or "screenshot available on request".

```bash
gh pr create --attach './after.png#Pinning page: locked-version badge' --title … --body …   # picture in hand already
gh pr comment <n> --attach './after.png#Pinning page: locked-version badge' --body 'Before/after for the docs page.'
gh pr comment <n> --attach ./before.png --attach ./after.png   # repeat the flag, up to 50 files
gh issue comment <n> --attach ./repro.mp4                       # video renders as a player
```

- Quote the whole argument: the alt text has spaces and bare `<`/`>` would redirect. `<file>#<alt text>`
  sets the alt text; without it the filename is used. A body that already
  references the file (`![alt](./after.png)`) gets that reference rewritten to the uploaded
  asset, so images can sit inline; unreferenced attachments are appended at the end.
- `create`, `edit` and `comment` all take `--attach` (all three landed in gh 2.99). Attach at create time when
  the picture already exists; comment when it comes later, as it does after a verification run.
- rtk condenses the reply to `ok commented #<n>`; the comment URL is
  `gh pr view <n> --json comments --jq '.comments[-1].url'`.
- Capture with `agent-browser screenshot <file>` or the Playwright MCP `browser_take_screenshot`
  against `cd docs && bin/dev`. Save under the scratchpad, never in the repo.
- No `--attach` flag means an old `gh`: `brew upgrade gh`.

## More Documentation

- `CHANGELOG.md` — what each release adds over importmap-rails
- Upstream README (shared basics): https://github.com/rails/importmap-rails#readme

## Workflow

- **Verify:** `bundle exec rake test` · `bundle exec rubocop` · `bundle exec conformance-kit check` · `cd docs && bundle exec rake lint && bundle exec rspec` if `docs/` changed
- **Specs:** fast `bundle exec ruby -Itest test/<file>_test.rb [-n /name/]`; full `bundle exec rake test` (live CDNs, bun for `--minify`); one cell `BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test`; two worktrees: yes, one full suite at a time (CDN rate limits)
- **CI:** required `cubic · AI code reviewer`, `conformance / Conformance (Ruby 4.0)`, `conformance / Conformance settings`, ten `Tests (Ruby 3.1|3.2, …)` cells; jobs `Tests (Ruby X, Rails Y, pipeline)`, `Lint`, `Build & test` (docs paths only); full suite on the PR (pushes: `main` only); failure report none
- **Review bot:** cubic
- **Merge:** squash — `gh pr merge <PR> --squash --delete-branch` (ruleset: 1 approval, threads resolved, signed commits, linear history)
- **PR contract:** `## Summary`, `## Test plan`, last `## Deviations & judgment calls`; one `type` + ≥1 `area` label, no `status` (`bin/labels infer <paths>`); `feat:` updates `CHANGELOG.md` and its `docs/` page; `docs/app/**` changes attach screenshots
- **Conflicts:** `CHANGELOG.md` union, no duplicated `###`; `Gemfile.lock` / `docs/Gemfile.lock` (pin = `Importmap::VERSION`) / `docs/bun.lock` take main's, then `bundle install` / `bun install` (docs in `docs/`); `gemfiles/*.gemfile` → `bundle exec appraisal generate`; `version.rb`: higher `VERSION` only if the branch's commits explain it, else main's, `UPSTREAM_VERSION` always main's outside `sync:`; `docs/app/models/doc.rb`, `docs/config/routes.rb` append-only; `packager.rb`/`commands.rb`/`npm.rb` keep both, rerun tests
- **Worktree setup:** `bundle install`; for docs work `cd docs && bundle install && bun install`
- **Release:** `bin/release [minor|major|X.Y.Z]`; changelog `CHANGELOG.md`, heading `## X.Y.Z (YYYY-MM-DD)` under `## Unreleased`; prep none; lockfiles `Gemfile.lock` `docs/Gemfile.lock`; docs `deploy-docs.yml` on release; human none. A feature PR opening a minor bumps `VERSION` itself and `bin/release X.Y.Z` tags it
- **Main health:** `gh run list -b main -w CI -L 1 --json conclusion --jq '.[0].conclusion'`
- **Upstream:** libraries we own `zoolutions/*`; scrub none
- **Bench:** none; request path only (`Map#to_json`, `preloaded_module_paths`, `digest`, `pin_all_from` expansion, cache sweeper) via `bin/rails runner` in `test/dummy`; the command path needs no measurement
