# Git Workflow Rules

## Remotes and branches

| Remote / branch | Role | Rule |
|---|---|---|
| `origin` = `zoolutions/importmap-plus` | this gem | all PRs go here — `gh repo set-default zoolutions/importmap-plus` once per clone, or `gh` defaults to the fork parent and `gh pr create` fails with "No commits between main and …" |
| `upstream` = `rails/importmap-rails` | tracked upstream | read-only; merged in by `/upstream-sync`, never pushed to |
| `main` | the only long-lived branch; releases cut from here | lands via PR; never force-push; never commit to it directly |
| `feat/*`, `fix/*`, `chore/*`, `docs/*`, `ci/*`, `sync/*` | work branches | root off fresh `origin/main` |

Stacked PRs are allowed (a PR based on another feature branch) when the second genuinely builds on the first — say so in the PR body and let `/finish-prs` walk them in order. Never rebase a published branch: merge `main` forward into it.

## Starting work

```bash
git fetch origin main
git switch -c fix/<slug> origin/main
```

Never branch from an already-merged feature branch; if you did, cherry-pick across.

## Commit messages

Conventional commits, matching the existing history:

- `feat:` — user-visible addition (a new CLI option, a new provider)
- `fix:` — bug fix
- `refactor:` / `perf:` / `test:` / `docs:` / `ci:` / `chore:`
- `sync:` — an upstream merge (`sync: merge importmap-rails 2.3.0`)

```
feat(cli): pin --lock holds a package at a version

Why, not what. What the user sees, and which invariant made the design.

Refs #12
```

Small, focused commits — one logical change each. Test before committing.

## Lockfiles

| File | Tracked | On conflict / drift |
|---|---|---|
| `Gemfile.lock` | yes | never hand-merge — take `main`'s, then `bundle install` |
| `gemfiles/*.gemfile.lock` | **no** (gitignored; CI deletes and re-resolves) | nothing to do |
| `docs/Gemfile.lock` | yes — pins `importmap-plus (X.Y.Z)` via `path: ".."` | take `main`'s, then `cd docs && bundle install`; after a release the pin drifts until someone does this |
| `docs/bun.lock` | yes | take `main`'s, then `cd docs && bun install` |

## Pre-commit checklist

```bash
bin/test test/<the files you touched>_test.rb   # fast loop
bundle exec rake test                            # before pushing — the command tests need the network
cd docs && bundle exec rake lint && bundle exec rspec   # only if docs/ changed
```

There is no RuboCop at the gem root. Don't add one in a feature PR; upstream files must stay diff-minimal.

## PR workflow

1. Branch off `main`
2. Commit in small steps; run the checklist
3. `git push -u origin <branch>` and `gh pr create` with a summary and a test plan. Write the body to a file and pass `--body-file` when it has code fences — with a single-quoted heredoc backticks pass through verbatim, so never escape them.
4. `/github-review-pr` when CI or a reviewer says something; `/finish-prs` for a stack
5. Squash merge on `main` when green and approved

A `feat:` PR also updates `CHANGELOG.md` under the next version heading and the relevant `docs/` page in the same PR.

## Releases

Only from `main`, only via `bin/release`:

```bash
bin/release --dry-run          # shows the next patch version
bin/release                    # patch
bin/release minor | major | 1.4.0
```

It refuses a dirty tree or a non-`main` branch, bumps `lib/importmap/version.rb` and `Gemfile.lock`, commits "Prepare for X.Y.Z", tags `vX.Y.Z` and publishes a GitHub Release. Publishing the release fires `release.yml` (test → build → RubyGems trusted publishing, no API key anywhere) and `deploy-docs.yml` (the docs site). Watch it with `gh run watch`.

- Tags are plain `vX.Y.Z`. Never `-rc` suffixes, never `git push --tags`.
- After the release, `cd docs && bundle install` and commit the `docs/Gemfile.lock` pin in a follow-up PR, or the next `docs/**` PR fails its frozen install.
- `UPSTREAM_VERSION` is not touched by a release; it moves only in a sync PR.

## Rules

- **NEVER** commit directly to `main`
- **NEVER** force-push a published branch (`--force-with-lease` only inside `/finish-prs`, on a branch nobody else has)
- **NEVER** push to `upstream`
- **NEVER** hand-merge a lockfile
- **ALWAYS** run the tests before pushing; the live ones too
- **ALWAYS** explain WHY in the commit body
