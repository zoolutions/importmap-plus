---
description: Review a GitHub pull request on zoolutions/importmap-plus for code quality, project patterns and fork constraints
model: opus
argument-hint: "PR number or URL (e.g. 5 or https://github.com/zoolutions/importmap-plus/pull/5)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(git diff:*), Bash(git log:*), Bash(git fetch:*), Bash(bin/test:*), Bash(bundle exec:*), Read, Grep, Glob
---

# PR Review

Review the PR for pattern compliance, fork-constraint violations and real bugs. Be concise: the reader knows the codebase.

## Workflow

1. `gh pr view <N> --json title,body,baseRefName,headRefName,files,mergeable` and `gh pr diff <N>` — read the body's "Deviations & judgment calls" section first if it has one
2. Classify each changed file: request path, command path, tests, docs, fork-only, upstream-owned (`git diff --name-status upstream/main main` lists the upstream-owned modified set)
3. Check fork constraints (blocking), then patterns, then bugs
4. Run the touched tests locally when feasible: `gh pr checkout`-free via `git fetch origin pull/<N>/head && git worktree add /tmp/pr-<N> FETCH_HEAD`, then `bin/test test/<file>_test.rb` inside it
5. Output the structured review

## Fork constraints (check first — these block merge regardless of code quality)

| Check | Violation | Why |
|---|---|---|
| Constant surface | Renames or removes anything importmap-rails defines; changes a public method's signature | drop-in replacement — `Importmap::` must be the same |
| Runtime deps | `importmap-plus.gemspec` gains a dependency | railties, activesupport, actionpack only |
| Version | `Importmap::VERSION` changed in a feature PR; `UPSTREAM_VERSION` changed outside a `sync:` PR | `bin/release` owns one, the sync procedure the other |
| Upstream-owned file rewritten | a method in `commands.rb` / `packager.rb` / `npm.rb` / `map.rb` restructured or reformatted rather than added to | conflict surface on the next sync |
| Downgrade story | a `config/importmap.rb` this PR writes would not parse under importmap-rails (new keywords on `pin`, non-comment metadata) | apps must be able to switch back |
| Lockfile | hand-merged `Gemfile.lock` / `docs/Gemfile.lock` / `docs/bun.lock`; a `gemfiles/*.lock` committed | regenerate; the appraisal locks are gitignored |
| Root RuboCop | a `.rubocop.yml` or lint job added at the gem root | upstream has none; `docs/` has its own |

## Pattern violations

```
Net::HTTP call outside with_retries              -> route through Importmap::HttpRetries
Pin line rebuilt with string interpolation       -> vendored_pin_for / pin_for with options read back via extract_existing_pin_options
preload: / integrity: / provenance lost on rewrite -> carry them through every path: pin, update, pristine, unpin
Hand-joined vendor path                          -> vendored_package_path
system("…#{x}") / backticks                      -> Open3.capture3(executable, *argv)
Network or file I/O in Map or a helper           -> command path only
rescue StandardError => nil around a CDN call    -> let HTTPError surface after retries
Live commands_test case for stub-able logic      -> packager_test / npm_test with Net::HTTP.stub
Unpinned version in a live test ("md5")          -> exact version ("md5@2.2.0")
New pin-line shape without a fixture             -> test/fixtures/files/<shape>_import_map.rb
User-visible change without docs page + CHANGELOG -> both, in the same PR
Comment that restates the code                   -> delete, or say why
```

## Architecture sanity check

```
request path   engine.rb → map.rb → helpers / freshness.rb      (no network)
command path   commands.rb → packager.rb / npm.rb → minifier.rb, http_retries.rb
surface        config/importmap.rb (regex-parsed, regex-rewritten) + vendor/javascript
```

Logic on the wrong side of that line is the most common finding.

## Test and lint verification

```bash
bin/test test/<touched>_test.rb          # in the PR worktree
bundle exec rake test                    # if the change is in commands/packager/npm — live CDN tests
cd docs && bundle exec rake lint && bundle exec rspec   # if docs/ changed
gh pr checks <N>                         # every matrix cell, plus "Build & test" when docs/ changed
```

## Output format

```
## Files requiring manual review

| File | Reason |
|---|---|
| lib/importmap/packager.rb | regex change to PIN_PROVENANCE_REGEXP — verify read-back of existing pins |

## Fork-constraint violations

- (none) / `lib/importmap/map.rb:72` — `pin` gained a keyword importmap-rails rejects

## Critical issues

- `lib/importmap/commands.rb:131` — `update` path drops `preload: false` (no test covers it)

## Suggestions (non-blocking)

- …

## Verdict

**Approve** / **Request Changes** — one line of reasoning
```

Now review: $ARGUMENTS
