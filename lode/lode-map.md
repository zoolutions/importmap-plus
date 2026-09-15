# Lode map

The index of this repository's durable memory. Read this first; it beats a directory listing. Every file describes the system as it is now, with rationale; `../CHANGELOG.md` records what changed.

- `summary.md` — what importmap-plus is, the three invariants, the fork stance
- `terminology.md` — the words this repo uses (pin line, provenance comment, provider chain, remote reason, appraisal cell…)
- `workflow.md` — the profile the shared `/lode:lfg`, `/lode:review-pr`, `/lode:finish-prs`, `/lode:debug-flaky`, `/lode:tdd` and `/lode:plan` commands read: the commands to run, branch and PR conventions, layer ownership, the input shapes every change is checked against, reviewer suggestions to push back on, docs and CHANGELOG duties, the CI matrix and how to read it, the real flake sources, per-file conflict rules, what verification means here, and the review tier each path buys (Rigor)
- `practices.md` — practices learned from review that `../.claude/rules/` does not state: grammar tables and safe failure direction for parsers, the pin-answers-for-itself rule, atomic writes, one-fact-every-page docs
- `plans/README.md` — plans live in `../docs/plans/` and GitHub issues; handovers in `tmp/` (not committed)

## Subsystems

- `request-path/summary.md` — engine → `Map` → helpers → freshness: the DSL, `to_json`, preloads, integrity, both asset pipelines, the reloader and sweeper; no network on a request
- `packager/summary.md` — `Packager` and `ProviderChain`: every parser regex quoted, the provenance grammar, the four rewrite paths and what each preserves, resolution and the provider fallback, esm.run rewriting, the atomic vendored write, retries
- `cli/summary.md` — `bin/importmap` command by command with the exact sentences it prints, `pin` and `update` in depth, provider grouping, `Npm`
- `inspection-and-tools/summary.md` — the fork-only collaborators: `ModuleInspector` (grammar table, safe failure direction), `Minifier`, `HttpRetries`
- `testing-and-ci/summary.md` — every test file and what it pins, live versus stubbed, process isolation in `CommandsTest`, fixtures, the Appraisal matrix, the workflows, `bin/release`
- `docs-site/summary.md` — the docs-kit app: page-to-behaviour mapping table, authoring contract, lint and specs, the `path: ".."` pin

## Review rules (`review/`)

Accepted review findings rewritten as rules about the system, verified against the code, each with the test that proves it. `/lode:gate` reads every file here before reviewing a diff; `/lode:learn` adds to them.

- `review/packager.md` — lock derivation, esm.run version conflicts, specifier-only rewriting, atomic writes, `name@version/subpath`, reload after write
- `review/cli.md` — `--vendor` scope and `--remote` precedence, locked dependencies kept, explicit `--from` moves a pin, `pristine` rewrites only on change, a pin answers for itself first, versioned keys only for bare `update`, registry errors recorded per package, one *Not a bug* (upstream's vendored-path message)
- `review/inspection-and-tools.md` — strings before comments, regex-literal contexts, qualified `Worker`, wasm forms, computed imports, non-ESM markers, keep-not-drop invariant, minifier tool normalisation
- `review/docs-and-changelog.md` — the `remote:` reason list, flag limits on every page, link-time SyntaxError wording, the minifier hook location, docs lint globs, `Retry-After`
- `review/workflows-and-deploy.md` — docs-ci path filters, release `tag` input, action and workflow SHA pins, the Bun image digest, the `version.rb` conflict rule
- `review/testing.md` — both halves of a provider split asserted, h1 assertions in docs specs

## Not memory

- `tmp/` — git-ignored: gate diffs and reports, handovers, scratch
