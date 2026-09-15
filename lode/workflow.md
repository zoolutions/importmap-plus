# Workflow profile

Everything the shared workflow skills (`/lode:lfg`, `/lode:review-pr`, `/lode:finish-prs`, `/lode:debug-flaky`, `/lode:tdd`, `/lode:plan`) need to know about this repository that is not already in `../CLAUDE.md`, `../.claude/rules/` or the rest of `lode/`. The skills are the same in every repository; this file is what makes them behave like they were written for this one. Keep every heading, even when its body is one line saying "none".

## Commands

| Purpose | Command | Notes |
|---|---|---|
| fast loop (one file) | `bundle exec ruby -Itest test/<file>_test.rb` (add `-n /<pattern>/` for one case) | the default loop. `bin/test` is upstream's rails/plugin runner and runs 0 tests on Rails 8.1 — don't use it |
| full suite | `bundle exec rake test` (= `rake`, the default task) | **talks to live jspm, jsDelivr and the npm registry** via `test/commands_test.rb` and the two `*_integration_test.rb` files, and `installer_test.rb` runs a real `bundle install` in a generated app. Not safe in two worktrees at once: parallel runs are exactly the CDN burst `ci.yml`'s `push: branches: [main]` guard exists to prevent |
| lint | none at the gem root | upstream has no RuboCop; adding one would reformat upstream-owned files. `docs/` has its own |
| one CI cell locally | `BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install && BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test` | pick the cell that failed; `gemfiles/*.gemfile` are generated from `Appraisals` by `bundle exec appraisal generate` |
| docs build / check | `cd docs && bundle exec rake lint && bundle exec rspec` | separate app, separate bundle; run from inside `docs/` |
| run the app | `cd docs && bin/dev` (the docs site). The gem itself is exercised through `test/dummy` and `bin/importmap` inside it | |
| release | `bin/release --dry-run`, then `bin/release [minor|major|X.Y.Z]` | refuses a dirty tree or a non-`main` branch; only the user runs it |

A `--minify` test **skips** unless bun, esbuild or terser is on `PATH` or in `node_modules/.bin`. CI installs bun, so a run that skips them locally has not exercised those paths — install one before claiming the suite is green.

## Branches and PRs

- Default branch: `main`. Remotes: `origin` = `zoolutions/importmap-plus`, `upstream` = `rails/importmap-rails` (read-only; never pushed to). `gh repo set-default zoolutions/importmap-plus` once per clone or `gh pr create` targets the fork parent and fails with "No commits between main and …".
- Work branches: `feat/*`, `fix/*`, `chore/*`, `docs/*`, `ci/*`, `sync/*`, rooted off fresh `origin/main` (`git fetch origin main && git switch -c <type>/<slug> origin/main`). Never branch from an already-merged feature branch; cherry-pick across if you did.
- Stacked PRs are allowed when the second genuinely builds on the first — say so in the body, and `/lode:finish-prs` walks them base-first. When the base merges, GitHub retargets the child to `main`; verify with `gh pr view <PR> --json baseRefName` and `gh pr edit <PR> --base main` if it did not.
- Commits: conventional (`feat:`, `fix:`, `refactor:`, `perf:`, `test:`, `docs:`, `ci:`, `chore:`, `sync:` for an upstream merge); the body says **why**, not what.
- PR body sections, in order: Summary, Test plan, Deviations & judgment calls, Gate. Write the body to a file and pass `--body-file` — bodies here quote pin lines and commands, and with a single-quoted heredoc backticks pass through verbatim, so never escape them.
- Merge policy: squash on `main` when green and approved. Never rebase a published branch — merge `main` forward. Never bare `--force`; `--force-with-lease` only inside `/lode:finish-prs` on a branch nobody else has.
- Attribution: never `Co-Authored-By: Claude`, "Generated with Claude Code" or any similar line, in a commit, a PR body or an issue comment. Add the session's `Claude-Session:` trailer when the harness supplies one.

## Layers

| Layer | Files | Edit rule |
|---|---|---|
| Rails engine | `lib/importmap/engine.rb` | upstream-owned: additive only, upstream's style |
| Map (DSL) | `lib/importmap/map.rb` | upstream-owned; the request path — no network, no file I/O beyond the asset resolver |
| Reloader | `lib/importmap/reloader.rb` | upstream-owned |
| View helpers / freshness | `app/helpers/importmap/importmap_tags_helper.rb`, `app/controllers/importmap/freshness.rb` | upstream-owned |
| CLI | `lib/importmap/commands.rb` | upstream-owned, heavily modified here: a new option is a new `option` line plus a threaded keyword, never a rewritten method |
| Packager | `lib/importmap/packager.rb` | upstream-owned, heavily modified here and 706 lines against the 800-line ceiling in `.claude/rules/coding-style.md` — new behaviour goes in a collaborator |
| Registry | `lib/importmap/npm.rb` | upstream-owned, modified here |
| Fork-only collaborators | `lib/importmap/minifier.rb`, `http_retries.rb`, `module_inspector.rb`, `provider_chain.rb`, `integrity.rb`, `lib/importmap-plus.rb` | owned here — this is where any change bigger than a few lines belongs |
| Installer | `lib/install/`, `lib/tasks/importmap_tasks.rake` | upstream-owned (`install.rb` modified here) |
| Gemspec | `importmap-plus.gemspec` (ours); `importmap-rails.gemspec` deleted here | port an upstream gemspec change by hand; runtime deps stay railties, activesupport, actionpack |
| `gemfiles/*.gemfile` | generated from `Appraisals` | edit `Appraisals`, then `bundle exec appraisal generate` |
| Docs site | `docs/**` | owned here, own bundle and lint (`docs/AGENTS.md`) |

`git diff --name-status upstream/main main` is the authority on which files are upstream-owned; `../.claude/rules/upstream-sync.md` has the per-file merge rules.

## Shapes

Every change is checked against these before it is called done; a reviewer will name the one you forgot.

- Pin-line inputs: scoped package (`@scope/name`), a subpath key (`pkg/core`, `@scope/name/sub`), a single-quoted pin, a pin with no version comment, a pin with no provider comment, a malformed line (`Map::InvalidFile`), a pin already carrying `locked`.
- Pin options that must survive every rewrite (`pin`, `update`, `pristine`, `unpin`): `preload:` including `preload: false` and an array preload, `integrity:` as `false` only (`INTEGRITY_OPTION_REGEXP` captures `true`/`false`, so a literal SRI hash is never carried: a remote pin recomputes it from the new bytes, and `integrity: true` there becomes the computed hash too, or drops it with `pin --no-integrity`; a vendored pin drops it silently), `to:` a custom or remote URL, and the whole provenance comment.
- Pin states: a pin written before the feature existed (no new metadata); a remote pin (`to: "https://…"`) that must stay remote and re-resolve from the same CDN; a package present in `vendor/javascript` but absent from the map; an esm.run bundle with dependencies of its own.
- Downgrade story: a `config/importmap.rb` this change writes must still parse under importmap-rails — metadata rides in the comment, never in a new `pin` keyword.
- Environments: both asset pipelines (`ENV["ASSETS_PIPELINE"]` — `test/importmap_test.rb` branches on it for integrity and digest expectations, so a new asset-path assertion needs both branches); Ruby 3.1 (no `Data.define`, no anonymous `*`/`**` forwarding) through Ruby 4.0; Rails 6.1 (needs `logger`, `mutex_m`, `drb`, `bigdecimal` declared — see `Appraisals`) through Rails `main`; a machine with no minifier installed; Windows (`.cmd` shims in `Minifier`).
- Transport: a 429 or a reset followed by a 200 (`HttpRetries`), and the exhausted-attempts path that must raise the owning class's `HTTPError`.

## Constraints

Reviewer suggestions that are wrong in this repository. Push back on sight with the reason; do not implement them.

| Suggestion | Why it is wrong here |
|---|---|
| "Rename or remove this constant/method" (anything importmap-rails defines) | the `Importmap::` surface is frozen — the gem is a drop-in replacement |
| "Add gem X for this" | runtime deps are railties, activesupport, actionpack and nothing else |
| "Bundle the minifier" / "call it with a shell string" | the minifier is found on the machine and invoked with `Open3.capture3(executable, *argv)` |
| "Pass this as a new `pin` keyword" (for fork metadata) | metadata lives in the provenance comment so importmap-rails still parses the file |
| "Reformat / reorder this method" (upstream-owned file) | conflict surface on the next sync; additive edits only |
| "Move `UPSTREAM_VERSION` here" | only a `sync:` PR moves it, after merging the upstream tag |
| "Bump `VERSION` too" | a feature PR may open a new minor, but only one of the PR and `bin/release` moves a given release's number |
| "Add RuboCop to the gem root" | upstream has none; a root lint would reformat upstream-owned files |
| "Rebase on main and force-push" | published branch — merge forward |
| "Mock this in `commands_test.rb`" | those tests run the real `bin/importmap` in a forked process against live CDNs by design; logic tests belong in `packager_test.rb` with `Net::HTTP.stub` |
| "Retry / skip / sleep around this flaky live test" | `HttpRetries` is the only retry in the codebase; an intermittent failure is `/lode:debug-flaky`'s job |
| "Rewrite the import specifiers in the vendored file" | minification is transform-only — each tool's argv in `Minifier::TOOLS` minifies one file without bundling — so bare specifiers stay as the CDN resolved them; the one deliberate rewrite is `rewrite_esm_run_imports` |
| "Reach the registry from `Map` or a helper" | no network on the request path — only `Commands` → `Packager`/`Npm` |

## Docs

- User-facing docs live in `docs/app/views/docs/pages/*.rb`; `docs-site/summary.md` holds the page-to-behaviour-to-lib-file table that makes "the matching page" findable. A page is routed and in the nav only if `docs/app/models/doc.rb` registers it; scaffold with `cd docs && bin/rails g docs_kit:page "Title" --group=…`, which writes both.
- Changelog: `CHANGELOG.md` at the repo root, entries under the next version heading (`## X.Y.Z` → `### Added` / `### Changed` / `### Fixed`). Upstream's entries arrive in a sync PR as `### Upstream` bullets.
- A user-visible change always updates the matching `docs/` page **and** `CHANGELOG.md` in the same PR. A fact about a flag — its scope, its precedence, what it does not touch — is stated in every page that mentions the flag (CLI reference, the guide page, the changelog, the upgrading page): grep the subject before finishing.
- Transcripts in docs are the exact strings the CLI prints, including upstream's imperfect ones.
- Files that pin a version and drift after a release: `docs/Gemfile.lock` pins `importmap-plus (X.Y.Z)` through `path: ".."`. `bin/release` does not update it, so the next `docs/**` PR fails its frozen install until someone runs `cd docs && bundle install` and commits the lock. Never revert the pin.

## CI

- Workflows: `.github/workflows/ci.yml` (the gem's Minitest suite; `on: push: branches: [main]` + `pull_request` — the narrow push trigger stops a PR branch running two full matrices against the same CDNs, don't widen it); `docs-ci.yml` (`Build & test`, only when `docs/**`, `app/**`, `lib/**`, `importmap-plus.gemspec`, `CHANGELOG.md`, `.bun-version` or itself changed — frozen `bundle install`, icon sync, `bun run build:css`, `rake lint`, `rspec`, inside `docs/`); `release.yml` and `deploy-docs.yml` (both fire on a published GitHub Release).
- Matrix: Ruby `3.1 3.2 3.3 3.4 4.0` × Rails `6.1 7.0 7.1 7.2 8.0 8.1 main` × `sprockets|propshaft`, minus 25 excluded combinations — **45 cells**, each installing bun and running `bundle exec rake` with `BUNDLE_GEMFILE=gemfiles/rails_<v>_<pipeline>.gemfile` and `ASSETS_PIPELINE` set. The cell's `.gemfile.lock` is deleted before `bundle install`, so every cell resolves fresh.
- Read the matrix before reading a log: every cell red on the same test is a deterministic regression (or a CDN outage — check the error text); one Rails version red is a compatibility break for it; one Ruby version red is the 3.1 floor or a Ruby 4.0 change; `sprockets` cells only is the `ASSETS_PIPELINE` branch; one random cell with a `429`/`ECONNRESET`/`Net::ReadTimeout` on a live test is a probable CDN flake.
- Fetch a failure: `gh pr checks <PR>`, then `gh run view <RUN_ID> --job=<JOB_ID> --log-failed` (run and job ids are in the check URL); `gh run view <RUN_ID> --job=<JOB_ID> --log 2>&1 | grep -n -B5 -A30 'Failure:\|Error:'` when `--log-failed` is too thin. Extract the test name and file, the error class, the Minitest seed (`Run options: --seed N`), the cell, and — for `commands_test.rb` — the CLI's own stdout, which the flunk message carries.
- "Green" means every matrix cell on the latest commit, plus `Build & test` when the PR touches the paths `docs-ci.yml` watches. Pending-green counts for merge-readiness; `BLOCKED` with everything else green is the awaiting-approval gate, not a defect.
- Known not-this-branch failures: a `docs/Gemfile.lock` pin drift after a release (fix is `cd docs && bundle install` on the branch); a CDN outage hitting the whole matrix; a cell already red on `main`. Report these as caveats; do not "fix" them into the branch.
- Shared, rate-limited services the checks hit: jspm's generate API, jsDelivr/esm.run and the npm registry, from one runner pool, on every cell. Batch fixes into one commit per pass and let PRs run one at a time.

## Flake sources

- **CDN / registry transport** — `429`, `5xx`, `ECONNRESET`, `Net::ReadTimeout`, `SSL_read` in `test/commands_test.rb` or a `*_integration_test.rb`, passing on re-run. `HttpRetries` already retries with a growing pause; the question is whether the failing call is actually inside `with_retries` (`grep -n "Net::HTTP\." lib/`).
- **CDN content drift** — an assertion on a URL or file body that fails consistently from a date onward: the live test pinned a package without an exact version, or the CDN changed a resolution. Pin the version.
- **Process isolation** — `CommandsTest` and `InstallerTest` `include ActiveSupport::Testing::Isolation`, so each test forks, copies `test/dummy` into a fresh `Dir.mktmpdir` and `chdir`s in. Teardown errors, a missing tmpdir, or a test that passes alone and fails in the suite point here: class-level setup, a `chdir` not undone, a fixture copied once.
- **Order / state leakage** — `Importmap::HttpRetries.attempts`/`wait`, `Importmap::Packager.endpoint`, `Importmap::Packager.esm_run_resolver`, `Importmap::Packager.minifier` (`test/packager_test.rb` sets it) and `Importmap::Npm.base_uri` are class-level accessors. A test that sets one without restoring it in an `ensure` poisons later tests; `--seed N` reproduces it.
- **Environment** — a minifier present or absent changes which tests run (`-v` shows `S` for skipped); `ASSETS_PIPELINE` unset locally; Windows `.cmd` shim lookup.
- **Rate dependence** — failures that cluster when many cells run at once are jspm rate-limiting the whole matrix from one IP pool, not a bug in the test.

Never `skip`, `retry`, `sleep` or loosen an assertion. A bounded retry around a genuinely external call belongs in `HttpRetries` and nowhere else.

## Conflicts

| File | Rule |
|---|---|
| `CHANGELOG.md` | union at the same anchor: both sides appended bullets under the same `### Added`/`### Changed`/`### Fixed` beneath the next-version heading. Keep both sets, do not duplicate the subheading, drop nothing from the base. Re-read the result and grep for leftover markers — an automated strip also eats a setext `=======` underline |
| `lib/importmap/version.rb` | a higher `VERSION` on the branch is correct only when the branch's own commits explain it (`git log origin/<base>..HEAD -- lib/importmap/version.rb`: a feature opening that minor, or `bin/release`). Unexplained, or any `UPSTREAM_VERSION` difference outside a `sync:` PR → take the base's and ask. `bin/release` would tag an unexplained bump |
| `Gemfile.lock` | never hand-merge: `git checkout origin/<base> -- Gemfile.lock && bundle install` |
| `gemfiles/*.gemfile.lock` | gitignored; `git rm --cached` if one appears. `gemfiles/*.gemfile` are generated — resolve `Appraisals`, then `bundle exec appraisal generate` and take the output |
| `docs/Gemfile.lock` | never hand-merge: take the base's, then `cd docs && bundle install`. The `importmap-plus (X.Y.Z)` pin must equal `Importmap::VERSION` or the frozen docs install fails |
| `docs/bun.lock` | take the base's, then `cd docs && bun install` |
| `docs/app/models/doc.rb` | append-only registry: keep both sides' lines, base order first (`docs/config/routes.rb` has one generic `docs/:doc` route and never changes per page) |
| `docs/app/views/docs/pages/*.rb` | prose — merge semantically so the page describes both changes |
| `test/fixtures/files/*_import_map.rb` | fixtures are exact inputs: add a second fixture for one side's shape rather than merging two shapes into one that tests neither |
| `lib/importmap/packager.rb`, `commands.rb`, `npm.rb` | the fork's hot files; both sides likely added to the same method. Keep both additions in the base's order and re-run the touched tests before trusting it |
| anything else | resolve by hand, both intents, never a blanket `--ours`/`--theirs` on a source file. A resolution you cannot defend → `git merge --abort` and ask |

Mechanical files (the lockfiles, the CHANGELOG, the page registry) are the only ones an automated pass may resolve unattended.

## Verification

- The manual check a user of the change would do: run the CLI in a scratch copy of `test/dummy` and read what it left behind — `bin/importmap pin <pkg>@<version> [--flag]`, then `cat config/importmap.rb` and `ls vendor/javascript/`. The printed sentence and the resulting pin line are the contract `commands_test.rb` asserts and the docs quote.
- Before pushing: the touched test files, then `bundle exec rake test` with a minifier installed (confirm the `--minify` cases ran, not skipped), plus `cd docs && bundle exec rake lint && bundle exec rspec` if `docs/**` changed, plus the nearest matrix cell if the engine, `Map` or a helper changed.
- Stress iterations for a flake proof: **10** consecutive green runs judged by exit code, or **3** for a test that hits a live CDN — each iteration there is real traffic, and hammering jspm proves only that rate limits exist. Re-run the exact original repro (same seed, same cell) too.
- A regression fence is proven by reintroducing the bug and watching the test go red, then restoring.
- Where evidence goes: `lode/tmp/` (git-ignored; the repo-root `tmp/` is not) — stress logs, gate diffs, handovers. A flake's mechanism, in one sentence, plus its reproduction recipe, goes in a dated entry in `../test/flaky-tests.md` (create it if missing; it does not exist yet). A flake that is found but not yet fixed gets a GitHub issue labelled `flaky-test` (`gh issue create --label flaky-test`, creating the label once if absent); the fixing PR closes it with `Closes #N`.

## Rigor

How much review a change buys. `critical` is the request path: the code that runs on every page render of every app, where a wrong import map is a broken site — every gate agent plus a second correctness pass, up to five rounds, and no implementation without an issue or plan that carries a Decision section. `standard` is the default and covers everything else: the CLI, the Packager, the collaborators, the tests, the workflows, and every prose path. Nothing here is `light`: `light` drops the claims and correctness agents, and `lode/review/docs-and-changelog.md` makes the claims agent the enforcer of every `lode/**/*.md` and `docs/app/views/docs/pages/*.rb` statement, while `docs/` is also a Rails app with its own accepted correctness findings (the `Retry-After` arithmetic, the lint globs, the image digest).

- Default: `standard`

| Paths | Tier |
|---|---|
| `lib/importmap/map.rb`, `lib/importmap/engine.rb`, `lib/importmap/reloader.rb`, `app/` | critical |

A file no rule names counts as the default; the diff takes the highest tier over its files, so a docs page changed alongside `map.rb` is reviewed at critical. `${CLAUDE_PLUGIN_ROOT}/scripts/rigor.sh` prints the tier; `--tier <t>` on a skill overrides it, and lowering needs a stated reason.

## See also

- `lode-map.md` — the index
- `../CLAUDE.md`, `../.claude/rules/` — the binding rules this file does not repeat
- `testing-and-ci/summary.md` — every test file, what it pins, the fixtures, the workflows, `bin/release`
- `docs-site/summary.md` — the page-to-behaviour table
