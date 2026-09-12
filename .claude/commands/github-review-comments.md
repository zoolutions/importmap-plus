---
description: "Use when a PR has unresolved review comments that need responses — evaluates each comment against the codebase and the fork's constraints, implements valid fixes, pushes back on incorrect suggestions, and resolves all threads."
model: sonnet
argument-hint: "PR number (e.g., 5 or #5)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(git log:*), Bash(git blame:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(bundle exec:*), Bash(bin/test:*), Bash(cd:*), Read, Write, Edit, Glob, Grep, Agent
---

# Review GitHub PR Comments: $ARGUMENTS

Repo: `zoolutions/importmap-plus`. Review and respond to every unresolved review comment. Evaluate each against the actual code and this fork's constraints before accepting or rejecting it.

## Phase 0: Determine the PR number

Parse `$ARGUMENTS` flexibly (`PR5`, `#5`, `5`); empty → auto-detect:

```bash
gh pr list --author=@me --head="$(git branch --show-current)" --state=open --json number,title
gh pr view <PR> --json title,state,url,baseRefName
```

---

## Phase 1: Fetch unresolved review threads

```bash
gh api "repos/zoolutions/importmap-plus/pulls/<PR>/comments" --paginate

gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first: 20) {
              nodes { id databaseId body author { login } createdAt }
            }
          }
        }
      }
    }
  }
' -f owner=zoolutions -f repo=importmap-plus -F pr=<PR>
```

For each unresolved thread: thread node ID (to resolve), body, path and line, author. Skip resolved threads and PR-description comments. Bot reviewers (CodeRabbit, cubic, dependabot) get the same treatment as humans — evaluated, not auto-accepted, not auto-ignored.

No unresolved threads → report and stop.

---

## Phase 2: Read and categorise each comment

| Category | Action |
|---|---|
| Valid fix | Implement |
| Valid test gap | Add the Minitest case (stubbed unless it's a CDN contract) |
| Valid docs gap | Update the page under `docs/app/views/docs/pages/` and/or `CHANGELOG.md` |
| Valid style — in a fork-only file | Fix |
| Style — in an upstream-owned file | Push back: upstream's style stays, diff-minimal (`.claude/rules/coding-style.md`) |
| Suggestion conflicts with a fork constraint | Push back with the constraint (table below) |
| Over-engineering / YAGNI | Push back |
| Unclear | Ask; do NOT implement |

**Before categorising**, always:

1. Read the actual file and line
2. Check the suggestion is right for THIS codebase — the pin-line contract, both asset pipelines, Ruby 3.1 and Rails 6.1 floors
3. Check what else would break: every rewrite path (`pin`, `update`, `pristine`, `unpin`) and `Npm`'s parsing share the regexes
4. Check `CLAUDE.md` and `.claude/rules/*.md` — project conventions override reviewer preference
5. Check the fork constraints — a suggestion fine in a normal gem can be wrong here

### Fork constraints (push back on sight)

| Reviewer suggestion | Why it's wrong here |
|---|---|
| "Rename/remove this constant/method" (anything importmap-rails defines) | The `Importmap::` surface is frozen — drop-in replacement |
| "Add gem X for this" | Runtime deps are railties, activesupport, actionpack — nothing else |
| "Bundle the minifier / call it with a shell string" | Minifier is found on the machine and called with an argv array |
| "Pass this as a new `pin` keyword" (fork metadata) | Metadata lives in the provenance comment so importmap-rails still parses the file |
| "Reformat / reorder this method" (upstream-owned file) | Conflict surface on the next upstream sync; additive edits only |
| "Bump `VERSION` in this PR" | `bin/release` owns it |
| "Add RuboCop to the gem" | Upstream has none; root lint would reformat upstream-owned files |
| "Rebase on main and force-push" | Published branch — merge forward |
| "Mock this in `commands_test.rb`" | Those tests run the real `bin/importmap` in a forked process against live CDNs by design; logic tests belong in `packager_test.rb` with `Net::HTTP.stub` |
| "Retry/skip this flaky live test" | `/debug-flaky`; `HttpRetries` is the only retry |

---

## Phase 3: Implement accepted fixes

1. Edit
2. Verify:
   ```bash
   bin/test test/<relevant>_test.rb
   bundle exec rake test                                   # if commands/packager/npm changed
   cd docs && bundle exec rake lint && bundle exec rspec   # if docs/ changed
   ```
3. One commit for the pass:
   ```bash
   git commit -m "$(cat <<'EOF'
   fix: address PR review feedback

   - <fix 1>
   - <fix 2>
   EOF
   )"
   git push
   ```

---

## Phase 4: Reply to every thread

**Accepted:**

```bash
gh api "repos/zoolutions/importmap-plus/pulls/<PR>/comments/<COMMENT_ID>/replies" --method POST \
  -f 'body=Fixed in <SHA>. <What changed.>'
```

**Rejected:**

```bash
gh api "repos/zoolutions/importmap-plus/pulls/<PR>/comments/<COMMENT_ID>/replies" --method POST \
  -f 'body=<Technical reasoning grounded in the code, the pin-line contract, or the fork constraint.>'
```

**Resolve** (after replying):

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
  }
' -f threadId=<THREAD_NODE_ID>
```

**General PR comments** (not inline): `gh pr comment <PR> --body "…"`.

---

## Phase 5: Verify completion

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) { reviewThreads(first: 100) { totalCount nodes { isResolved } } }
    }
  }
' -f owner=zoolutions -f repo=importmap-plus -F pr=<PR>
```

Report: accepted/fixed count, pushed-back count, and that no unresolved threads remain.

---

## Response style

- **No performative agreement** — never "Great point!" or "You're absolutely right"
- **No gratitude**
- **Direct** — the fix or the reasoning, nothing more
- **Reference the commit** — short SHA on every accepted fix
- **Specific when pushing back** — name the file, the regex, the rewrite path, or the rule; not a principle

---

## Important notes

- Always read the code before judging a comment — reviewers misread diffs
- A comment that reveals a real bug → fix it without defensiveness
- Several comments asking for the same thing → one fix, referenced in every reply
- A new round of comments after your push → report it rather than looping

Now begin by determining the PR number from `$ARGUMENTS` or the current branch.
