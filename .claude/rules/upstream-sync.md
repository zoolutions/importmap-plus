# Upstream Sync — Live

importmap-plus is a fork of rails/importmap-rails that **keeps merging upstream**. `Importmap::UPSTREAM_VERSION` (`lib/importmap/version.rb`) names the upstream release currently merged in; `Importmap::VERSION` is this gem's own number and moves independently. The promise in the README is that upstream changes land as they ship and the docs stay in step — this rule is how.

`/upstream-sync` runs the procedure. This file is the reasoning and the per-file rules it relies on.

## The shape of the divergence

`git diff --name-status upstream/main main` is short and stable — keep it that way:

| Category | Files | Sync rule |
|---|---|---|
| **Fork-only** (added here, absent upstream) | `lib/importmap-plus.rb`, `importmap-plus.gemspec`, `minifier.rb`, `http_retries.rb`, `test/minifier_test.rb`, `CHANGELOG.md`, `release.yml`, `deploy-docs.yml`, `docs-ci.yml`, `docs/`, `.claude/` | never conflict; nothing to do |
| **Deleted here** | `importmap-rails.gemspec` | git reports "deleted by us, modified by them" whenever upstream touches it. Keep it deleted; port the change (a new dependency floor, a new file glob) into `importmap-plus.gemspec` by hand. |
| **Rewritten here** | `README.md`, `bin/release`, `.github/workflows/ci.yml`, `.github/prompts/*` | take ours; read upstream's diff for anything factual (a new supported Rails, a new command in the README) and port it |
| **Modified here** | `commands.rb`, `packager.rb`, `npm.rb`, `lib/install/install.rb`, `test/commands_test.rb`, `test/packager_test.rb`, `test/npm_test.rb`, `test/installer_test.rb`, `test/dummy/config/application.rb`, `test/fixtures/files/outdated_import_map.rb`, `Gemfile` | **semantic merge** — both sides' intent, every time |
| **Version** | `lib/importmap/version.rb` | keep our `VERSION`; set `UPSTREAM_VERSION` to the release being merged |
| **Lockfile** | `Gemfile.lock` | take ours, `bundle install` |
| **Untouched** | everything else (`map.rb`, `engine.rb`, `reloader.rb`, helpers, most tests) | fast-forwards cleanly |

## Rules that keep the next sync cheap

1. **Additive edits to upstream files.** A new option on a Thor command is a new `option` line and a new keyword argument threaded through — not a rewrite of the method. When a change wants to restructure an upstream method, extract the new behaviour into a fork-only collaborator and leave a one-line call.
2. **Upstream's style in upstream's files.** Whitespace, ordering and naming as upstream wrote them (`.claude/rules/coding-style.md`).
3. **Tests append.** New cases go at the end of the upstream test file or in a fork-only test file; never reorder or rename upstream's tests.
4. **Fixtures fork, don't mutate.** If a test needs a fixture upstream also uses but with different content, add a new fixture file rather than editing upstream's.
5. **The README is ours** but its factual content (supported versions, command list) must not contradict upstream's for the shared behaviour.
6. **Constant surface is frozen.** Nothing upstream defines may be renamed or removed here — the whole point is that `Importmap::` is the same.

## Merging a release

Merge the **tag**, not `upstream/main`, so `UPSTREAM_VERSION` names something an app can look up:

```bash
git fetch upstream --tags
git switch -c sync/importmap-rails-<X.Y.Z> origin/main
git merge v<X.Y.Z>          # upstream tags are vX.Y.Z
```

Resolve by the table above. Then:

- set `UPSTREAM_VERSION = "<X.Y.Z>"`
- `bundle install`; `bundle exec appraisal generate` if the gemspec or `Appraisals` changed
- `bundle exec rake test` — the live command tests included
- port upstream's changelog entries into `CHANGELOG.md` under the next version as `### Upstream` bullets (this gem has its own changelog; upstream's arrives through the merge but users read ours)
- re-read every docs page describing upstream behaviour (`docs/app/views/docs/pages/` — overview, installation, how-import-maps-work, preloading, integrity, composing, selective-imports, caching, cli, configuration, upgrading) against upstream's README diff and update what moved
- PR titled `sync: merge importmap-rails <X.Y.Z>`; the body lists every conflicted file and how it was resolved

## What a sync must never do

- Rebase `main` onto upstream — history is shared, and the fork's commits stay on top of the merge
- Bump `Importmap::VERSION` — that is a release decision, made after the sync merges
- Take `--theirs` on a modified file wholesale — every one of those files has fork behaviour in it
- Push anything to `upstream`

## Contributing back

A fix that is not fork-specific (a bug in `map.rb`, a CI matrix update) belongs upstream first. Open it against rails/importmap-rails from a clean branch off `upstream/main`; when it merges it comes back through the next sync and the fork's diff shrinks.
