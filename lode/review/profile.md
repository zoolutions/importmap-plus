# Review rules: the workflow profile and the `.claude/` prose

Accepted findings about `lode/workflow.md`, `CLAUDE.md`, `.claude/rules/` and `.gitignore`: the files the `/lode:*` skills and their agents read before touching code. A wrong sentence here is acted on by every later session.

### `lode/workflow.md` carries every heading the plugin's skills read by name, `## Rigor` included
- **Holds because:** the skills point at the profile's headings by name (`lfg` lists Commands, Branches and PRs, Layers, Shapes, Constraints, Docs, CI, Flake sources, Conflicts, Verification, Rigor), and a missing one degrades silently: `rigor.sh` prints `[lode:rigor] no ## Rigor heading` on stderr and falls back to `standard`, so the request path never got its second correctness pass and a heading nobody had written looked like a decision someone had made. The seeded profile shipped ten headings and the plugin template has eleven.
- **Where:** `lode/workflow.md` — the `## Rigor` section, with a `- Default:` line and a Paths/Tier table in the grammar `rigor.sh`'s header documents
- **Proven by:** no test — `bash "$LODE/scripts/rigor.sh" origin/main` prints a tier with nothing on stderr; `printf 'lib/importmap/map.rb\n' | rigor.sh --files` prints `critical`
- **Origin:** gate 2026-09-15 (PR #30)

### The request path is `critical`; nothing is `light`
- **Holds because:** `map.rb`, `engine.rb`, `reloader.rb` and `app/` run on every page render of every app, and a wrong import map is a broken site. `light` drops the claims and correctness agents, and those are the two that find prose drift: every finding on PR #30 came from the correctness agent, on `lode/workflow.md`. `lode/review/docs-and-changelog.md` names the claims agent as the enforcer of every `lode/**/*.md` and `docs/app/views/docs/pages/*.rb` statement, and `docs/` is a Rails app with accepted correctness findings of its own (the `Retry-After` arithmetic, the lint globs, the image digest). A `light` row for `docs/` or `lode/` would lower review on exactly the paths whose rules depend on the agents it removes.
- **Where:** `lode/workflow.md` → Rigor table
- **Proven by:** `printf 'docs/app/views/docs/pages/cli.rb\n' | rigor.sh --files` prints `standard`
- **Origin:** gate 2026-09-15 (PR #30)

### Gate evidence goes in `lode/tmp/`; the repo-root `tmp/` is not ignored
- **Holds because:** `.gitignore` has `/lode/tmp/` and no `tmp/` entry, and every other path in the profile's Verification section is repo-root-relative, so `tmp/` read as `<repo>/tmp/` and a `git add tmp/` would have committed stress logs and gate diffs. `/lode:lfg` writes its own notes to `lode/tmp/implementation-notes.md`.
- **Where:** `lode/workflow.md` → Verification; `.gitignore`
- **Proven by:** `git check-ignore -v tmp/x lode/tmp/x` matches only the second
- **Origin:** gate 2026-09-15 (PR #30)

### `docs/app/models/doc.rb` is the docs site's only per-page registry
- **Holds because:** `docs/config/routes.rb` holds one generic `get "docs/:doc(.:format)"` route and never changes when a page is added, so listing it as an append-only registry in the Conflicts table told a merge to preserve per-page lines that do not exist. The generator `bin/rails g docs_kit:page` writes the page file and the `doc.rb` entry.
- **Where:** `lode/workflow.md` → Conflicts; `docs/config/routes.rb`
- **Proven by:** `grep -c 'docs/' docs/config/routes.rb` — one route line
- **Origin:** gate 2026-09-15 (PR #30)

### A sentence that attributes a directory or a file to a command names the command that writes it now
- **Holds because:** `.gitignore`'s `/.claude/worktrees/` comment was reworded from the retired local `/finish-prs` to `/lode:finish-prs` in the same pass that retired the command, and the plugin's `/lode:finish-prs` never writes there (`git worktree add "$(mktemp -d)/finish-<PR>"`). A rename that keeps the sentence's shape can make it false; the plugin's behaviour is read from its `SKILL.md`, not assumed from the old command's.
- **Where:** `.gitignore`; any `lode/` or `.claude/` sentence naming a `/lode:*` command
- **Proven by:** no test — the plugin's `skills/finish-prs/SKILL.md` step 2
- **Origin:** gate 2026-09-15 (PR #30)

### A gate fix commit contains only the hunks its message names
- **Holds because:** `git add <file>` on a file carrying two findings' fixes put four fact corrections into the commit titled "add the Rigor heading" and left the commit titled "correct five profile facts" with two of them. `git blame` on a corrected line then points at a message that does not mention it, and the gate's per-commit delta review reads a message that lies about its content. Stage by hunk (or edit, commit, then edit again) so `git show --stat` matches the message; nothing pushed is ever rewritten, but an unpushed mis-split is re-split.
- **Where:** every fix commit `/lode:gate` and `/lode:review-pr` make
- **Proven by:** `git show --stat <sha>` lists only the files the message names
- **Origin:** gate 2026-09-15 (PR #30), rules agent round 2
