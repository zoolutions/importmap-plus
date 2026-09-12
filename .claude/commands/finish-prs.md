---
description: "Drive a set of open PRs to merge-ready, one at a time, in a given order. Auto-resolves the recurring CHANGELOG and docs/Gemfile.lock conflicts, runs /github-review-pr (conflicts, CI failures, review comments) on each, then waits for the user to merge before syncing and advancing to the next. Handles stacked PRs (a PR based on another PR's branch)."
model: opus
argument-hint: "ordered PR list (e.g. '5 6 7'); optional 'automerge' to enable gh auto-merge; empty = auto-discover your open PRs"
allowed-tools: Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh pr comment:*), Bash(gh pr merge:*), Bash(gh pr edit:*), Bash(gh api:*), Bash(gh run view:*), Bash(git:*), Bash(bundle:*), Bash(bundle exec:*), Bash(bin/test:*), Bash(bun install:*), Bash(cd:*), Read, Write, Edit, Glob, Grep, Agent, Skill, TaskCreate, TaskUpdate, TaskGet, TaskList, ScheduleWakeup
---

# Finish PRs (ordered merge-ready loop): $ARGUMENTS

Repo: `zoolutions/importmap-plus`. You are driving a set of open pull requests to **merge-ready**, one at a time, in a defined order, minimising the sync/CI churn that parallel or stacked PRs create.

Two conflicts recur mechanically on this repo, so this command resolves them itself:

1. **`CHANGELOG.md`** — every feature PR appends bullets under the same next-version heading (`## 1.1.0` → `### Added`), so each merge re-conflicts the rest. Resolution is always a *union at a known anchor*.
2. **`docs/Gemfile.lock`** — `docs/` depends on the gem via `path: ".."`, so the lock pins `importmap-plus (X.Y.Z)`. `bin/release` doesn't update it, so after a release every `docs/**` PR fails its frozen install until the pin is bumped. The fix is `cd docs && bundle install` — **never revert the pin**.

**This command does NOT merge** unless `automerge` was passed. Default: make each PR merge-ready, pause for the user to merge, then sync the rest and continue.

---

## Phase 0: Parse the list and order

`$ARGUMENTS` may be:

- An ordered list: `5 6 7` (also `#5`, `PR5`).
- `automerge` anywhere → `gh pr merge --auto --squash` on each PR once green; strip it before parsing numbers.
- Empty → discover: `gh pr list --author=@me --state=open --limit 100 --json number,title,headRefName,baseRefName,createdAt`. Order **base-first, then oldest-first**: a PR whose branch is another PR's base goes before it; otherwise `createdAt` ascending. Show the order and proceed.

**Stacked PRs.** `baseRefName` that is not `main` means the PR is stacked on another open PR. It must come after its base in the order. When the base merges, GitHub retargets the stacked PR to `main` automatically — verify with `gh pr view <PR> --json baseRefName` before syncing it, and `gh pr edit <PR> --base main` if it didn't.

Create a task list, one task per PR in order. Confirm: `Finishing N PRs: #a → #b → #c. Mode: <pause-for-merge | automerge>.`

---

## Phase 1: A working tree per PR

Never operate on the branch checked out in the main working directory. For each PR, in order of preference:

1. An existing worktree on that branch (`git worktree list`)
2. `git fetch origin <branch> && git worktree add .claude/worktrees/finish-<PR> <branch>`

Each worktree needs its own `bundle install` before tests run. The command tests copy `test/dummy` into a tmpdir, so worktrees don't collide.

---

## Phase 2: Per-PR loop

### 2a. Sync onto the base (merge, never rebase)

```bash
cd <worktree>
git fetch origin <base> --quiet
git merge origin/<base>
```

This repo's branches are published; `.claude/rules/git-workflow.md` forbids rebasing them. A merge commit is fine — PRs squash on merge.

If the merge stops on a conflict:

- **`CHANGELOG.md`** — union. Both sides inserted bullets under the same `### Added` (or `### Changed` / `### Fixed`) beneath the next-version heading. For the plain same-anchor shape, strip the markers keeping both blocks:

  ```bash
  perl -0pi -e 's/^<<<<<<< HEAD\n//mg; s/^\|\|\|\|\|\|\| [^\n]*\n=======\n//mg; s/^>>>>>>> [^\n]*\n//mg;' CHANGELOG.md
  ```

  Then **read the result**: no markers left (`grep -n '^<<<<<<<\|^=======\|^>>>>>>>\|^|||||||' CHANGELOG.md`), this PR's bullets present once, no duplicated `###` subheading, nothing from the base dropped. The perl is a fast path, not a substitute for reading; any other shape is resolved by hand.

- **`docs/Gemfile.lock`** — take the base's side, then regenerate: `git checkout origin/<base> -- docs/Gemfile.lock && (cd docs && bundle install)`. Confirm the only resulting change is the `importmap-plus (X.Y.Z)` pin and whatever this PR's `docs/Gemfile` edits imply.

- **`Gemfile.lock`** (root) — same shape: `git checkout origin/<base> -- Gemfile.lock && bundle install`.

- **`docs/bun.lock`** — `git checkout origin/<base> -- docs/bun.lock && (cd docs && bun install)`.

- **`docs/app/models/doc.rb`** — append-only page registry; keep both sides' `page` lines, base order first.

- **Anything else** — this command auto-resolves only the mechanical files above. For `packager.rb`, `commands.rb`, a docs page, a test: STOP (`git merge --abort`), report the file(s), and ask. Don't guess a semantic merge.

`git add` the resolved files, `git commit` (git's default merge message), repeat if needed.

### 2b. Ensure the docs pin is current even without a conflict

If this PR touches `docs/**`:

```bash
grep -m1 'VERSION = ' lib/importmap/version.rb
grep -m1 '^    importmap-plus (' docs/Gemfile.lock
```

Differ → `cd docs && bundle install`, commit on this branch:

```
fix(docs): pin docs/Gemfile.lock to importmap-plus <version>

The frozen docs bundle install fails when the path-gem pin drifts from the gemspec.
```

No `docs/**` change → the `Docs site` workflow doesn't run; skip.

### 2c. Push

```bash
git push origin <branch>
```

A merge commit needs no force. If a force is ever unavoidable (it shouldn't be), `--force-with-lease`, never bare `--force`.

### 2d. Full review pass

Invoke `/github-review-pr <PR>` (Skill tool). It runs conflicts → CI failures → review comments; don't re-implement it. Wait for it. A persistent failure it couldn't fix, or a thread needing a human decision → mark this PR `needs-user`, continue the queue, return to it in the final report. One stuck PR must not block the rest.

### 2e. Verify merge-ready

```bash
gh pr view <PR> --json mergeable,mergeStateStatus,reviewDecision,baseRefName --jq '{mergeable,mergeStateStatus,reviewDecision,baseRefName}'
gh pr checks <PR>
```

Merge-ready: `mergeable=MERGEABLE`, no failing checks (green or pending-green across the whole matrix — and `Build & test` if `docs/**` changed), `reviewDecision` not `CHANGES_REQUESTED`. `BLOCKED` with everything else green means "awaiting required approval" — that's the user's gate, not a defect.

### 2f. Hand off

- **automerge:** `gh pr merge <PR> --auto --squash`, then Phase 3.
- **default:** report ✅ merge-ready with URL and a one-line "what's in it", tell the user it's ready, then wait (Phase 3).

Mark the task `completed` (merge-ready) or note `needs-user`.

---

## Phase 3: Wait for the merge, then advance

Each merge is what invalidates the next PR's base, so the loop gates on it.

- **automerge:** poll `gh pr view <PR> --json state --jq .state` with `ScheduleWakeup` — the matrix takes several minutes (up to ~40 cells against live CDNs), so ~300s between checks, not a busy loop.
- **default:** the user merges and tells you (or you're re-invoked). Next turn: re-check `state`. `MERGED` → advance; otherwise report status and stop — don't spin.

On advance: if the next PR was stacked on the one that just merged, confirm GitHub retargeted it to `main` (`gh pr view --json baseRefName`; `gh pr edit --base main` if not), then **always** re-run 2a against the new base before anything else.

Out-of-order merge by the user → drop it from the list, sync whatever is now next.

---

## Phase 4 (optional): fix the docs-lock drift at its source

The drift originates in `bin/release`, which bumps the root `Gemfile.lock` but not `docs/Gemfile.lock`. The durable fix is a `bundle install` inside `docs/` as part of the release script, so the pin lands on `main` with the version bump. Mention this once if the drift recurs; don't change `bin/release` unprompted.

---

## Phase 5: Final report

| PR | Result | Note |
|---|---|---|
| #5 | ✅ merged / ✅ merge-ready / ⏳ awaiting-merge / ⚠️ needs-user | one line |

Then: what the user does next (merge the ready ones, decide on `needs-user` items), and whether the CHANGELOG or docs-lock drift is worth fixing at the source.

---

## Important notes

- **Never rebase** a published branch; merge the base forward.
- **Never bare `--force`.**
- **Never touch the main working directory's checkout** — worktrees only.
- **Never auto-resolve outside the mechanical files** (`CHANGELOG.md`, `Gemfile.lock`, `docs/Gemfile.lock`, `docs/bun.lock`, `docs/app/models/doc.rb`).
- **Never merge in default mode.**
- **Don't re-implement `/github-review-pr`** — invoke it.
- **One stuck PR doesn't block the queue.**
- **Read every auto-resolved CHANGELOG** before pushing.
- **Clean up** `git worktree remove` for worktrees you created once their PR merges.
