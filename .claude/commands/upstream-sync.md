---
description: "Merge a new rails/importmap-rails release into this fork: fetch the tag, merge it on a sync branch, resolve conflicts per the per-file rules, bump Importmap::UPSTREAM_VERSION, port upstream's changelog, re-sync the docs pages that describe upstream behaviour, and open a PR."
model: opus
argument-hint: "upstream version to merge (e.g. 2.3.0); empty = latest upstream tag"
allowed-tools: Bash(git fetch:*), Bash(git tag:*), Bash(git ls-remote:*), Bash(git switch:*), Bash(git merge:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git add:*), Bash(git rm:*), Bash(git checkout:*), Bash(git commit:*), Bash(git push:*), Bash(gh pr create:*), Bash(gh release view:*), Bash(bundle install:*), Bash(bundle exec:*), Bash(BUNDLE_GEMFILE=*), Bash(cd:*), Read, Write, Edit, Glob, Grep, Agent
---

# Upstream Sync: $ARGUMENTS

Merge an importmap-rails release into importmap-plus. The rules and the reasoning are in `.claude/rules/upstream-sync.md`; this is the runbook.

## Phase 0: Which version

```bash
git fetch upstream --tags
git tag -l 'v*' --sort=-v:refname | head -5
grep UPSTREAM_VERSION lib/importmap/version.rb
```

`$ARGUMENTS` names a version → merge `v<that>`. Empty → the newest upstream tag. Already at that version → report and stop. Skipping several releases at once is fine (merge the newest tag; git brings the intermediate commits) but read every skipped release's notes: `gh release view v<X.Y.Z> --repo rails/importmap-rails`.

## Phase 1: Branch and merge

```bash
git fetch origin main
git switch -c sync/importmap-rails-<X.Y.Z> origin/main
git merge v<X.Y.Z>
```

Never rebase. Never merge `upstream/main` — merge the tag, so `UPSTREAM_VERSION` names a real release.

## Phase 2: Resolve, file by file

`git status` lists the conflicts. Apply the table from the rule; the common ones:

| File | Resolution |
|---|---|
| `importmap-rails.gemspec` ("deleted by us") | keep deleted: `git rm importmap-rails.gemspec`. Then `git show v<X.Y.Z>:importmap-rails.gemspec` and port anything substantive (a raised `required_ruby_version`, a new dependency floor, a `files` glob) into `importmap-plus.gemspec` by hand |
| `lib/importmap/version.rb` | keep our `VERSION`; set `UPSTREAM_VERSION = "<X.Y.Z>"` |
| `README.md` | ours. Read upstream's diff (`git diff <merge-base> v<X.Y.Z> -- README.md`) for facts — supported versions, new commands, changed behaviour — and carry them into ours and into `docs/` |
| `bin/release`, `.github/workflows/ci.yml`, `.github/prompts/*` | ours; port a matrix change (new Ruby/Rails) into `ci.yml` and `Appraisals` |
| `Gemfile.lock` | `git checkout origin/main -- Gemfile.lock && bundle install` |
| `lib/importmap/commands.rb`, `packager.rb`, `npm.rb`, `lib/install/install.rb` | **semantic merge**. Both sides' intent, every method. Upstream's new code in upstream's style; the fork's additions stay additive. Spawn an Explore agent per file to summarise both sides before touching it |
| `test/commands_test.rb`, `test/packager_test.rb`, `test/npm_test.rb`, `test/installer_test.rb` | keep upstream's tests as upstream wrote them (they may need the fork's exact output sentences — fix the expectation to the fork's sentence, note it in the PR); keep the fork's tests |
| `test/fixtures/files/*` | if upstream changed a fixture the fork also changed, add a fork-specific fixture rather than merging content |

A conflict you can't resolve with confidence → stop and ask, with both sides quoted.

`git add` as you go; do not commit until Phase 3 passes.

## Phase 3: Make it green

```bash
bundle install
bundle exec appraisal generate          # if the gemspec or Appraisals changed
bundle exec rake test                   # live CDN tests included; confirm --minify cases ran
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test
```

A failure here is either an upstream behaviour change the fork must adopt, or a fork assumption upstream broke. Fix it at the root; don't patch the test.

Then commit the merge: `sync: merge importmap-rails <X.Y.Z>`, with a body listing each conflicted file and its resolution.

## Phase 4: Changelog and docs

1. `CHANGELOG.md`: under the next version heading add `### Upstream` with one bullet per upstream change that affects users, linking upstream's release notes.
2. Docs pages that describe upstream behaviour — read each against upstream's README diff and update what moved:
   `docs/app/views/docs/pages/`: `overview.rb`, `installation.rb`, `how_import_maps_work.rb`, `preloading.rb`, `integrity.rb`, `composing.rb`, `selective_imports.rb`, `caching.rb`, `cli.rb`, `configuration.rb`, `upgrading.rb` (the version table).
3. `cd docs && bundle exec rake lint && bundle exec rspec`.
4. Commit: `docs: sync with importmap-rails <X.Y.Z>`.

## Phase 5: PR

```bash
git push -u origin sync/importmap-rails-<X.Y.Z>
```

Body (`--body-file`):

- upstream release(s) merged, with links
- every conflicted file and how it was resolved
- upstream behaviour changes users will notice
- docs pages touched
- test plan: the full suite, the matrix cell, docs lint + rspec

`Importmap::VERSION` is **not** bumped here. Whether the sync warrants a release is decided after it merges.

## Checklist

- [ ] Merged the tag, not `upstream/main`
- [ ] `importmap-rails.gemspec` still deleted; its changes ported
- [ ] `UPSTREAM_VERSION` set; `VERSION` untouched
- [ ] No `--theirs`/`--ours` on a modified source file
- [ ] `bundle exec rake test` green with a minifier installed
- [ ] `### Upstream` changelog bullets
- [ ] Docs pages re-read against upstream's README diff
- [ ] PR body lists every conflict resolution
