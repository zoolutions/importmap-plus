# importmap-plus

Project instructions for every agent: Claude Code (`CLAUDE.md` `@`-imports this file), Grok, Cursor,
Copilot and Codex read it directly. Claude-only extras (rules, skills, commands) live under `.claude/`.

A drop-in replacement for [rails/importmap-rails](https://github.com/rails/importmap-rails) — repo `zoolutions/importmap-plus`, published on rubygems.org as `importmap-plus`. Same `Importmap::` constants, same engine, same helpers and pin DSL; an app switches by changing one `Gemfile` line. Everything this gem adds lives in the vendoring path: `bin/importmap pin --minify`, `--from esm.run` for jsDelivr's bundled builds, version locks, `update` by package name, and a pin comment that records where each package came from.

This is a **maintained fork that still tracks upstream**. The `upstream` remote points at rails/importmap-rails, `Importmap::UPSTREAM_VERSION` names the release currently merged in, and `Importmap::VERSION` is this gem's own semver. The fork rules are in `.claude/rules/upstream-sync.md`.

## Tech Stack

- **Ruby**: >= 3.1 (CI: 3.1–4.0) | **Rails**: >= 6.0 (CI: 6.1 → main, sprockets and propshaft)
- **Runtime deps**: railties, activesupport, actionpack — nothing else. Thor comes with railties.
- **CLI**: Thor (`lib/importmap/commands.rb`, installed into apps as `bin/importmap`)
- **Testing**: Minitest via `ActiveSupport::TestCase` against `test/dummy`; the CI matrix is Appraisal gemfiles under `gemfiles/`
- **Linting**: none at the gem root (upstream has none — don't introduce one in a feature PR). `docs/` has its own RuboCop.
- **Docs**: `docs/` — a docs-kit Rails app deployed to https://importmap-plus.zoolutions.llc

## Critical Rules

### Never Do

1. **NO breaking the importmap-rails surface** — every constant, helper, DSL method, option, generator and rake task importmap-rails ships must keep working unchanged. Additions only; a rename or removal is a fork-breaking change.
2. **NO new runtime dependencies** — the gemspec lists railties, activesupport and actionpack. Minification shells out to a bun/esbuild/terser already on the machine; it does not bundle one.
3. **NO touching import specifiers in vendored files** — minification is transform-only (`--no-bundle`, `--format=esm`), so bare specifiers stay exactly as the CDN resolved them and the import map keeps resolving them. There are two deliberate exceptions, both turning a URL the import map can't resolve into a bare key it can: `rewrite_esm_run_imports`, for a jsDelivr bundle's `/npm/dep@ver/+esm` imports, and `Importmap::PackageGraph#rewrite_specifiers`, for the relative imports of a package vendored with its file graph.
4. **NO losing a pin's provenance or options on rewrite** — the `# @<version> (<provider>[, minified][, vendored][, remote[: <reason>]][, locked])` comment plus `preload:` and `integrity:` must survive `pin`, `update`, `pristine` and `unpin`. Dropping them silently drifts a package back to jspm on the next update.
5. **NO raw `Net::HTTP` calls in Packager or Npm** — every outbound request goes through `with_retries` (`Importmap::HttpRetries`) and raises the class's own `HTTPError` once the attempts are spent.
6. **NO network access on the request path** — engine → `Map` → helpers never reach a CDN or registry. Only the CLI (`Commands` → `Packager` / `Npm`) does.
7. **NO hand-merging `Gemfile.lock`, `docs/Gemfile.lock` or `docs/bun.lock`** — regenerate them (`.claude/rules/git-workflow.md`). `gemfiles/*.lock` are gitignored; CI deletes and re-resolves them.
8. **NO moving `UPSTREAM_VERSION` outside a sync PR** — it names the importmap-rails release merged in, and only `/upstream-sync` changes it. `VERSION` is different: a feature PR that opens a new minor bumps it (that is how 1.1.0 landed), and `bin/release X.Y.Z` then tags the version already in the file. Never bump it twice for one release.

### Always Do

1. **TDD** — a failing Minitest first, then the code (`.claude/rules/testing.md`)
2. **Keep upstream-owned files diff-minimal** — new behaviour goes in new files (`minifier.rb`, `http_retries.rb` are the precedent) or in small, clearly bounded additions, so the next `git merge upstream/main` stays mergeable
3. **Match upstream's Ruby style in upstream-owned files** — `[ a, b ]` array spacing, `private` followed by indented methods, `# :nodoc:` on internals. A style-only diff is conflict surface for no gain.
4. **A pin this gem writes must be a pin importmap-rails can read** — an app can go back to importmap-rails and its `config/importmap.rb` must still parse. Comments carry the fork's metadata precisely because upstream ignores them.
5. **Document user-facing changes** — update the matching page under `docs/app/views/docs/pages/` and add a `CHANGELOG.md` entry under the next version heading
6. **Run the CDN-backed tests before pushing** anything that touches `commands.rb`, `packager.rb` or `npm.rb` — `test/commands_test.rb` and the two `*_integration_test.rb` files are the only coverage of the real jspm, jsDelivr and npm-registry contracts

## Commands

```bash
bundle exec rake test                                   # full suite (talks to live CDNs: jspm, jsDelivr, npm registry)
bundle exec ruby -Itest test/packager_test.rb           # one file (bin/test, upstream's rails/plugin/test runner, runs 0 tests on Rails 8.1 — don't use it)
bundle exec ruby -Itest test/commands_test.rb -n /minify/   # tests matching a name pattern
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install && \
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test   # one CI matrix cell
bundle exec appraisal generate                          # regenerate gemfiles/ after editing Appraisals
cd docs && bundle exec rake lint && bundle exec rspec   # docs site: RuboCop + request specs (render every registered page)
cd docs && bin/dev                                      # docs site locally
bin/release --dry-run                                   # print the next patch version
bin/release [minor|major|X.Y.Z]                         # bump + tag vX.Y.Z + GitHub Release → release.yml publishes the gem, deploy-docs.yml ships the docs
```

The `--minify` tests **skip** unless bun, esbuild or terser is on `PATH` or in `node_modules/.bin`. CI installs bun; install it locally or those paths go unexercised.

Command output is condensed by rtk (PreToolUse hook). `docs/.rtk/filters.toml` covers the docs
site's `rake lint` / `rake lint:fix` task (it must live under `docs/`, not the repo root — rtk
resolves project filters against the directory the command actually runs from, and that task only
runs with `docs/` as the working directory); every edit to it needs `rtk trust --yes` + `rtk verify`
run from inside `docs/`. Write commands in hook-rewritable shapes: no `for`/subshell wrappers, no
`| head` on rtk-handled commands, `bundle exec rubocop` not `bin/rubocop`.

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/lfg` | Full autonomous workflow: branch off `main` → understand → explore → plan → TDD → verify → PR |
| `/plan` | Fable-powered, read-only planning → GitHub issue or `docs/plans/` markdown (execute with `/lfg`) |
| `/architect` | Order multi-layer work across engine → Map → helpers → CLI → Packager/Npm → docs |
| `/tdd` | Enforce RED → GREEN → REFACTOR with Minitest |
| `/security` | Audit CDN and registry input handling, vendored-file paths, shell-outs, SRI |
| `/perf` | Baseline the request path (`Map#to_json`, preload resolution) against `main` in a worktree |
| `/review-pr` | Review a PR for pattern and fork-constraint compliance |
| `/github-review-pr` | Full PR pass: resolve conflicts with `main`, fix CI failures, then process review comments |
| `/github-review-failures` | Diagnose and fix CI failures until green |
| `/github-review-comments` | Process unresolved PR review comments |
| `/finish-prs` | Drive a stack of open PRs to merge-ready, one at a time, in order |
| `/debug-flaky` | Root-cause an intermittent test — evidence → repro → stress-proofed fix; never skip/retry |
| `/upstream-sync` | Merge a new importmap-rails release, bump `UPSTREAM_VERSION`, re-sync the docs |

Commands pin a model tier via frontmatter aliases — `sonnet` for pattern-following implementation, `opus` for orchestration, security and full review, `fable` for read-only planning — so they track the latest model per tier. Subagents doing mechanical work (file finding, pattern scans) get a cheaper model passed explicitly.

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
| Release | `bin/release` pushed from a laptop with an API key | `bin/release` → GitHub Release → trusted publishing (`release.yml`) |
| Fork-only files | — | `minifier.rb`, `http_retries.rb`, `module_inspector.rb`, `package_graph.rb`, `vendored_graph.rb`, `provider_chain.rb`, `integrity.rb`, `esm_run.rb`, `CHANGELOG.md`, `release.yml`, `deploy-docs.yml`, `docs-ci.yml`, `docs/` |

Upstream files this fork has modified heavily, which WILL conflict on sync: `commands.rb`, `packager.rb`, `npm.rb`, `README.md`, `ci.yml`, `test/commands_test.rb`, `test/packager_test.rb`. Per-file resolution rules: `.claude/rules/upstream-sync.md`.

## Docs site (`docs/`)

A self-contained docs-kit Rails app with its own bundle, RuboCop and RSpec. `docs-ci.yml` runs it only when `docs/**` changes; `deploy-docs.yml` ships it on every GitHub Release, so the docs go live with the gem. Pages are registered in `docs/app/models/doc.rb`; add one with `cd docs && bin/rails g docs_kit:page "Title" --group=…`. The authoring contract is `docs/AGENTS.md`.

`docs/Gemfile` depends on the gem through `path: ".."`, so `docs/Gemfile.lock` pins `importmap-plus (X.Y.Z)`. `bin/release` bumps the root `Gemfile.lock` but not this one — after a release, `cd docs && bundle install` and commit the new pin, or the frozen docs bundle install fails on the next `docs/**` PR.

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

- `.claude/rules/` — coding-style, git-workflow, testing, agents, upstream-sync, striving-for-excellence
- `.claude/commands/` — the slash commands above
- `CHANGELOG.md` — what each release adds over importmap-rails
- Upstream README (shared basics): https://github.com/rails/importmap-rails#readme
