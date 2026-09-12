---
description: "Use when a PR needs a full review pass — resolves merge conflicts with the base first, then fixes CI failures, then addresses unresolved review comments. Conflicts first so CI diagnoses the post-merge reality; failures before comments because comment fixes trigger new CI runs that bury the original failures."
model: opus
argument-hint: "PR number (e.g., 5 or #5)"
allowed-tools: Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr checkout:*), Bash(gh pr diff:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git blame:*), Bash(git diff:*), Bash(git status:*), Bash(git switch:*), Bash(git fetch:*), Bash(git merge:*), Bash(git merge-tree:*), Bash(git rev-parse:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(git checkout:*), Bash(bundle exec:*), Bash(bundle install:*), Bash(BUNDLE_GEMFILE=*), Bash(bun install:*), Bash(cd:*), Read, Write, Edit, Glob, Grep, Agent
---

# Review GitHub PR (full pass): $ARGUMENTS

Repo: `zoolutions/importmap-plus`. If `gh` resolves to `rails/importmap-rails` (the fork parent), run `gh repo set-default zoolutions/importmap-plus` first.

The pass has three phases that MUST run in this order:

1. **Phase A0: merge conflicts** — bring the branch up to date with its base and resolve conflicts before anything else.
2. **Phase A: CI failures** — fix anything red before touching review comments.
3. **Phase B: review comments** — only after Phase A leaves CI green (or pending green after a push).

## Why this order matters

**Conflicts before failures**: CI results only matter for the code that will actually merge. On a stale branch you'd diagnose failures against a base that no longer exists, and the resolution itself changes code, invalidating the run you just fixed. Resolving first means Phase A reads CI for the post-merge reality and you spend one extra CI cycle instead of two.

**Failures before comments**: every commit pushes a new matrix (up to ~40 cells, all hitting live CDNs). Fix comments first and the failure log you needed is buried under later runs; a comment fix may accidentally repair or introduce a failure and you can't tell which. Failures-first keeps CI red or green on a known commit.

## Phase 0: Determine the PR number

Parse `$ARGUMENTS` flexibly: `PR5`, `pr 5`, `#5`, `5` → PR 5. Empty → auto-detect:

```bash
gh pr list --author=@me --head="$(git branch --show-current)" --state=open --json number,title
```

Exactly one open PR → use it; none or several → ask. Then confirm:

```bash
gh pr view <PR> --json title,state,url,baseRefName,headRefName
```

`state: MERGED` → nothing to do; report and stop. Note `baseRefName`: a **stacked PR** (base is another feature branch, not `main`) merges its own base in Phase A0 — not `main`.

---

## Phase A0: Merge conflicts

```bash
gh pr view <PR> --json mergeable,mergeStateStatus,baseRefName
```

| `mergeable` | Action |
|---|---|
| `MERGEABLE` | Skip to Phase A. |
| `UNKNOWN` | GitHub is recomputing; don't poll. Verify **locally** against the PR's actual head, not `HEAD`: `git fetch origin <base>` and `git fetch origin pull/<PR>/head`; confirm both resolve (`git rev-parse --verify origin/<base>^{commit}`, `git rev-parse --verify FETCH_HEAD^{commit}` — a bad ref also exits 1 from merge-tree); then `git merge-tree --write-tree --name-only origin/<base> FETCH_HEAD`. Clean → Phase A. Exit 1 with conflict output → resolve below; the file list is your work list. |
| `CONFLICTING` | Resolve below. |

### Resolution procedure

1. `gh pr checkout <PR>` with a clean tree (`git status`). Dirty tree → stop and ask; stash nothing. Note: the repo root may show an untracked `docs/` from switching branches — that is ignored build output, not dirt, as long as `git status --short` shows nothing else.
2. `git fetch origin <base>` then **`git merge origin/<base>`** — MERGE, never rebase. The branch is published.
3. Resolve every conflicted file **semantically** — read both sides, keep both intents. Never blanket `--ours`/`--theirs` a source file. Repo-specific rules:
   - **`CHANGELOG.md`**: union. Entries live under version headings (`## 1.1.0` → `### Added` / `### Changed` / `### Fixed`); both sides usually appended bullets under the same heading. Keep both sets, don't duplicate the subheading, keep this branch's bullets adjacent to their siblings. Losing either side is a regression reviewers rarely catch.
   - **`lib/importmap/version.rb`**: `VERSION` moves only via `bin/release` on `main`; `UPSTREAM_VERSION` only in a `sync:` PR. A conflict here means the branch edited it against convention — take the base's file unless the branch's commits show a deliberate, explained bump. Unsure → stop and ask.
   - **`Gemfile.lock`** (root, tracked): never hand-merge — `git checkout origin/<base> -- Gemfile.lock && bundle install`. Confirm the diff afterwards is only what the branch's Gemfile/gemspec changes imply.
   - **`gemfiles/*.gemfile.lock`**: gitignored; if one is somehow in the conflict, `git rm --cached` it. `gemfiles/*.gemfile` themselves are generated from `Appraisals` — resolve `Appraisals`, then `bundle exec appraisal generate` and take the output.
   - **`docs/Gemfile.lock`**: never hand-merge — take the base's, then `cd docs && bundle install`. The `importmap-plus (X.Y.Z)` pin must equal `Importmap::VERSION` or the frozen docs CI install fails.
   - **`docs/bun.lock`**: take the base's, then `cd docs && bun install`.
   - **`docs/app/models/doc.rb`** (page registry) and **`docs/config/routes.rb`**: append-only — keep both sides' lines, base order first.
   - **`docs/app/views/docs/pages/*.rb`**: prose; merge semantically so the page still describes both changes.
   - **`test/fixtures/files/*_import_map.rb`**: fixtures are exact inputs — if both sides changed one, prefer adding a second fixture for one side's shape over merging lines into a fixture that no longer tests either shape.
   - **`lib/importmap/packager.rb`, `commands.rb`, `npm.rb`**: the fork's hot files; both sides likely added to the same method. Keep both additions, in the order the base has them, and re-run the touched tests before trusting it.
4. Run the gates BEFORE pushing the merge, scoped to what the conflict touched — at minimum:
   ```bash
   bundle exec ruby -Itest test/<touched>_test.rb
   bundle exec rake test                                   # the live command tests if commands/packager/npm were involved
   cd docs && bundle exec rake lint && bundle exec rspec   # if docs/ was involved (its CI is a separate workflow)
   ```
5. Commit the merge (git's standard message; add a body line naming any non-obvious choice) and `git push` — a merge commit never needs force.

### Phase A0 exit criteria

- `MERGEABLE` (or a clean local `merge-tree`), merge commit pushed if one was needed.
- CI is re-running on the merge — expected; Phase A reads the fresh run.
- A conflict you cannot resolve with confidence → **stop and ask**. A guessed resolution that compiles is worse than a question.

---

## Phase A: Run `/github-review-failures`

Invoke `/github-review-failures` with the same `$ARGUMENTS` and follow its runbook (`.claude/commands/github-review-failures.md`): identify failing checks → fetch logs → diagnose → fix locally → verify → commit and push.

### Phase A exit criteria

One of:

- All checks green on the latest pushed commit.
- All checks pending on the latest commit and none failed in the last completed run on it.
- A persistent failure **not caused by this branch** — a CDN outage across the whole matrix, a flaky cell on `main`, the `Build & test` docs job failing on a pre-existing `docs/Gemfile.lock` pin drift. Report it explicitly and proceed to Phase B with the caveat.

Failures caused by this branch's changes persist → do NOT proceed. Report what's failing, what was tried, ask.

---

## Phase B: Run `/github-review-comments`

Invoke `/github-review-comments` with the same `$ARGUMENTS` (`.claude/commands/github-review-comments.md`): fetch unresolved threads → categorise against the codebase and `CLAUDE.md` → implement accepted fixes → verify → commit and push → reply with SHAs or reasoning → resolve threads → verify none remain.

### Phase B exit criteria

- Every unresolved thread replied to and resolved (or the user explicitly agreed to leave one open).
- The branch is pushed with all accepted fixes.

---

## Phase C: Final report

Re-check mergeability once more (`gh pr view <PR> --json mergeable`, or local `merge-tree` if UNKNOWN) — the base can move under a long pass. A new conflict → loop back to Phase A0.

Report:

1. **Phase A0** — conflicted or clean; which files, how each was resolved, the merge commit SHA.
2. **Phase A** — which failures were diagnosed and fixed, with commit SHAs; any not-this-branch failure carried as a caveat.
3. **Phase B** — comments accepted (SHAs), pushed back (reasoning), final unresolved count (should be 0).
4. **End state** — mergeability + CI status on the latest commit, per workflow (`CI` matrix, `Docs site`).
5. **Outstanding** — e.g. CI pending after the comment fixes; the `docs/Gemfile.lock` pin needing a follow-up on `main`.

---

## Important notes

- **Do not interleave phases.** A new CI failure during Phase B → loop back to Phase A. A new conflict mid-pass → loop back to Phase A0. Those are the only reverse moves.
- **Stacked PR**: merge and diagnose against its declared base, not `main`. When its base merges into `main`, GitHub retargets the PR — re-run Phase A0 then.
- **Already merged** → report and stop. **Clean, green, no comments** → report "PR is clean" and stop.
- **Don't re-implement the child commands** — invoke them. This command is the orchestrator.
- **Don't trigger CI for nothing.** Every push runs the full matrix against live CDNs. Batch fixes into one commit per phase.
