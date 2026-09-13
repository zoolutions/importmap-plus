# Practices

The binding rules live in `../CLAUDE.md` and `../.claude/rules/` (coding-style, git-workflow, testing, agents, upstream-sync, striving-for-excellence). This file adds the practices those do not state, learned from review. The specific rules with their proofs are in `review/`.

## Parsing external text

- Before writing or changing a regex over JavaScript, a pin line, a URL or a package spec, write the grammar table: one row per form the real language allows, with the example input and what the code does. `inspection-and-tools/summary.md` holds the current table for `ModuleInspector`. A row without a test will be broken by the next edit.
- Decide the safe failure direction first and put it in a comment above the regex. For the inspector, a span it is unsure about is kept, never dropped, so an over-eager read keeps a package needlessly remote (harmless) and can never vendor a file that 404s (the failure the class exists to prevent).
- Match string literals first and keep them whole, then strip block comments, then scan. A comment opener inside a string is not a comment.

## The pin-line contract, beyond the regexes

- A pin answers for itself first (its own comment, then its own `to:` URL), then its package answers for it. This ordering decides which CDN a batch goes to, and a CDN that cannot answer for one spec fails the whole batch.
- Only pins that declare a version are eligible for a bare `update`; an unversioned local pin sharing a namespace is left alone.
- Provenance is rewritten only when the recorded provider or minification state changed; otherwise the existing line is preserved byte for byte.

## Files

- Download and validate in a pid-suffixed partial beside the target, `File.rename` over the target last, remove the partial on every failure. The existing vendored file is untouched until the rename.

## Prose

- A fact about a flag (scope, precedence, what it does not touch) is stated in every page that mentions the flag: the CLI reference, the guide, the CHANGELOG and the upgrading page. Grep before finishing.
- Describe the failure the browser actually produces. A default import from a module with no exports is a link-time SyntaxError, not a silent undefined.
- Transcripts in docs are the exact strings the CLI prints, including upstream's imperfect ones; document a discrepancy rather than editing the transcript.

## Review

- Review-bot findings are evaluated, not accepted or ignored by default. Half-right is the common case: the reported failure is not the one that happens, but there is one. Confirm the actual failing input before fixing, and record the real one.
- Every accepted finding becomes a rule in `review/` in the same PR (`/lode:learn`). Every rejected one with a good reason becomes a `Not a bug:` entry, so the next reviewer does not raise it again.
