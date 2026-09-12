---
description: "Use when a CI test failure looks intermittent — takes a failed Actions run, PR, or test path; drives evidence → reproduction → root cause → stress-proofed fix → knowledge capture. Never masks with skip/retry/sleep. Knows this suite's two real flake sources: live CDNs and per-test process isolation."
model: opus
argument-hint: "Actions run URL/ID, PR number, or test path (e.g. test/commands_test.rb)"
allowed-tools: Bash(gh run view:*), Bash(gh run download:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh issue create:*), Bash(gh issue edit:*), Bash(gh label list:*), Bash(gh label create:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git blame:*), Bash(bin/test:*), Bash(bundle exec:*), Bash(bundle install:*), Bash(BUNDLE_GEMFILE=*), Bash(curl:*), Read, Write, Edit, Glob, Grep, Agent
---

# Debug Flaky Test: $ARGUMENTS

You are root-causing an intermittent test failure. The deliverable is the **mechanism, stated in one sentence**, then a fix proven by a stress gate — never a `skip`, a retry wrapper, a `sleep`, or a loosened assertion.

## Phase 0: Parse the input

- **Actions run URL/ID** (`https://github.com/zoolutions/importmap-plus/actions/runs/<RUN_ID>`) → Phase 1
- **PR number** → `gh pr checks <N>` to find the failed run(s), then Phase 1
- **Test path** (a locally observed flake) → Phase 2

## Phase 1: Extract the CI evidence

```bash
gh run view <RUN_ID> --json jobs --jq '.jobs[] | {name, conclusion, databaseId}'
gh run view <RUN_ID> --job <JOB_ID> --log-failed
```

From the failing job's log extract ALL of:

| Evidence | Where | Why it matters |
|---|---|---|
| Failed test names + files | `Failure:` / `Error:` blocks | the targets |
| Minitest seed | `Run options: --seed N` | exact-order reproduction |
| Matrix cell | job name `Tests (Ruby X, Rails Y, pipeline)` | version-dependence vs true flake |
| The CLI's own output | `commands_test.rb` flunks with `bin/importmap … failed (…):` followed by stdout/stderr | a `429`/`503`/reset from a CDN vs a Ruby exception |
| Skip count | the summary line | a minifier missing on the runner changes which tests ran |
| Branch/SHA | `gh run view <RUN_ID> --json headBranch,headSha` | what actually ran |

**Read the matrix.** The same test red in every cell → deterministic (a regression, not a flake). Red in one cell with a transport error → CDN. Red only in `sprockets` cells or one Rails version → compatibility, not flakiness.

## Phase 2: Consult the knowledge base

1. `test/flaky-tests.md` if it exists — a recorded recipe for this test or pattern
2. `git log --oneline -i --grep=flak --grep=retry --grep=429 --grep=timeout -20` — the fork added `HttpRetries` precisely because of CDN flakes; the history says what was already hardened
3. `gh issue list --repo zoolutions/importmap-plus --label flaky-test --state all --search "<test name>"`

## Phase 3: Is it actually flaky?

"Intermittent across builds" is compatible with "deterministic on any given commit".

1. Run the test on the run's commit 3×: `bin/test <file> -n /<name>/`. Fails every time → regression. Find the commit pair: `git log` the test and the code under test.
2. Same cell locally? `BUNDLE_GEMFILE=gemfiles/rails_<v>_<pipeline>.gemfile ASSETS_PIPELINE=<pipeline> bin/test <file>`. Fails only there → compatibility break, fix as a regression.
3. Is a minifier installed locally? If the test is a `--minify` case it may have been **skipping** locally and only running in CI (bun is installed there). `bin/test <file> -v` shows S for skipped.

## Phase 4: Classify the signature

| Class | Tell | Where to look |
|---|---|---|
| **CDN / registry transport** | `429`, `502`/`503`, `ECONNRESET`, `Net::ReadTimeout`, `SSL_read`, in `commands_test.rb` or `*_integration_test.rb`; passes on re-run | `HttpRetries` already retries 3× with a growing pause. Is the failing call actually inside `with_retries`? (`grep -n "Net::HTTP\." lib/`.) Was it a burst — two matrices at once? (`ci.yml` runs pushes only on `main` to prevent that.) |
| **CDN content drift** | assertion on a URL or file content fails consistently from a date onward | the test pinned a package without an exact version, or jspm changed a resolution. Pin the version. |
| **Process isolation** | teardown errors, a tmpdir missing, `Dir.chdir` warnings, a test passing alone and failing in the suite | `CommandsTest` uses `ActiveSupport::Testing::Isolation` (fork per test) + `Dir.mktmpdir` + `chdir`. Look for state set at class level, a `chdir` not undone, a fixture copied once. |
| **Order / state leakage** | passes alone, fails after certain files; `--seed N` reproduces | `Importmap::HttpRetries.attempts`/`wait`, `Packager.endpoint`, `Npm.base_uri` are **class-level accessors** — a test that sets one and doesn't restore it in `ensure` poisons later tests |
| **Environment** | only on CI, or only on one machine | a minifier present/absent; `ASSETS_PIPELINE` unset locally; Windows `.cmd` shim paths; a proxy |
| **Time / rate dependence** | clusters when many cells run at once | jspm's generate API rate-limits per IP; the full matrix is ~40 cells from one runner pool |

## Phase 5: Reproduce (escalation ladder)

Stop at the first rung that reproduces; the rung narrows the class.

```bash
# 1. Exact: same seed as the failing run, same cell
BUNDLE_GEMFILE=gemfiles/rails_<v>_<p>.gemfile ASSETS_PIPELINE=<p> bin/test <file> --seed <N>

# 2. Whole suite with the seed (order dependence)
bundle exec rake test TESTOPTS="--seed <N>"

# 3. Stress loop; exits non-zero if ANY run failed
status=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  bin/test <file> -n /<name>/ || { echo "FAIL i=$i"; status=1; }
done
exit "$status"
```

Live tests: each iteration is real CDN traffic — start with 3, scale up only if green, and space them out; hammering jspm to reproduce a rate limit proves nothing except that rate limits exist. Judge stress runs by **exit code**, not by grepping output.

## Phase 6: Root-cause systematically

- Instrument before hypothesising: for a CDN failure, `curl -sI <url>` the exact URL the CLI printed; for isolation, print `Dir.pwd` and the tmpdir at the assertion.
- `git log` / `git blame` the test and the code under test — when written, what invariant it fenced, what changed since (an upstream sync? a new `--from` provider?).
- Map every moving part: `setup`/`teardown`, the class-level accessors, the fixture files, `ENV["ASSETS_PIPELINE"]`.
- **Write the mechanism in ONE sentence before touching code.** If you can't, you haven't found it.

Hard rules: no `skip`, no retry around the assertion, no `sleep`, no assertion loosening, no `rescue nil`. Bounded retries around a genuinely external operation belong in `HttpRetries`, never in a test.

## Phase 7: Fix and stress-prove

1. Fix at the root. Prefer mechanisms that cannot be silently defeated: an `ensure` that restores a class-level accessor; an exact version in the pin; a call moved inside `with_retries`.
2. **Fence check**: if the test is a regression fence, temporarily reintroduce the bug and confirm the test goes red; restore.
3. **Stress gate**: ≥10 consecutive green runs (≥3 for live tests), by exit code, plus the exact original repro if Phase 5 found one.
4. Standard gates: `bundle exec rake test`.

## Phase 8: Record

1. Append a dated entry to `test/flaky-tests.md` (create it if missing): test, class, the one-sentence mechanism, fix, reproduction recipe. Prune entries whose tests no longer exist.
2. If the fix ships now, close any open `flaky-test` issue in the PR (`Closes #N`). If it can't ship now: `gh issue create --repo zoolutions/importmap-plus --label flaky-test` with the evidence and recipe (`gh label create flaky-test` first if needed).
3. Something systemic (a CDN that rate-limits the matrix, an isolation leak in the test harness) gets its own issue.

Now begin with Phase 0 for: $ARGUMENTS
