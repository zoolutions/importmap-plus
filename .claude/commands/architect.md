---
description: "Coordinates development across importmap-plus's layers. Use when planning a change that spans the CLI, Packager, Map, helpers and docs, or when deciding where new behaviour belongs relative to the upstream fork boundary."
model: opus
argument-hint: "feature or task to coordinate"
---

# importmap-plus Architect Mode

You are coordinating a change across the gem's layers. The two questions this mode exists to answer: **which layer owns the behaviour**, and **how does it land without widening the fork's diff against rails/importmap-rails**.

## The layers

```
Request path (runs on every page render — no network, ever)
  engine.rb        boot: config.importmap, draw config/importmap.rb, reloader, cache sweeper, asset paths
  map.rb           the DSL and the JSON: pin, pin_all_from, to_json, preloaded_module_paths, digest, cache
  helpers          javascript_importmap_tags → to_json + preload tags
  freshness.rb     ETag from Map#digest

Command path (runs when a developer types bin/importmap)
  commands.rb      Thor: parse options, print sentences, orchestrate
  packager.rb      resolve (jspm API / esm.run), download, minify, rewrite pin lines, provenance
  npm.rb           registry lookups: outdated, audit, packages_with_versions
  minifier.rb      bun / esbuild / terser                      (fork-only)
  http_retries.rb  bounded retries                              (fork-only)

Surfaces
  config/importmap.rb   the persisted contract between the two paths — Map reads it, Packager rewrites it
  vendor/javascript/    what Packager writes, what the asset pipeline serves
  docs/                 one page per behaviour; CHANGELOG.md per release
```

## Typical implementation order

1. **Contract first** — what does the new pin line look like? What does `bin/importmap` print? Write those down; they are what tests assert and what docs show.
2. **Packager / Npm** — the logic, in a fork-only collaborator if it is more than a few lines
3. **Commands** — the option and the sentence; thread the keyword through `pin_package`
4. **Map / helpers** — only if the request path must read the new metadata (rare: provenance is for the CLI, the Map ignores comments)
5. **Tests** — stubbed unit tests first, one live `commands_test.rb` case if a CDN contract is involved
6. **Docs + CHANGELOG** — the page under `docs/app/views/docs/pages/` and the entry

## Where does it go? Decision table

| The change is… | Put it in | Because |
|---|---|---|
| a new CLI flag | `commands.rb` `option` line + keyword through `pin_package` | additive in an upstream file |
| a new way to resolve or download | a new `Importmap::<Thing>` file called from `Packager` | keeps `packager.rb` under the size limit and off the conflict surface |
| new metadata on a pin | the provenance comment via `vendored_pin_for` / `pin_provenance` | comments survive importmap-rails; new keyword args would not |
| a new registry query | `npm.rb`, through `with_retries` | Npm owns registry.npmjs.org |
| behaviour on page render | `map.rb` — and think twice | upstream-owned, request-hot, and every app runs it |
| a new CDN provider | `PROVIDER_HOSTS` + a resolver branch in `Packager` | provider is derived from the URL host on read-back |

## Integration points

| When working on… | Also consider… |
|---|---|
| a pin-line rewrite | `unpin`, `update`, `pristine` all rewrite too — do they carry the new metadata? `Npm#packages_with_versions` parses the same lines |
| a new `--from` provider | `provider_for_url` (read-back), `pristine`'s per-package provider, the esm.run dependency pinning, `outdated` (needs a version to compare) |
| minification | `pristine --minify` default (`vendored_minified?`), the "(minified)" banner line the tests assert, Windows `.cmd` shims |
| a new option on `pin` | `extract_existing_pin_options` must read it back or the next `update` drops it |
| the Map | both asset pipelines (`ASSETS_PIPELINE` branches in tests), Rails 6.1 → main, the per-request cache keys |
| `config/importmap.rb` format | the fixtures under `test/fixtures/files/`, the docs pages that print example pin lines, importmap-rails' own regex (`PIN_REGEX`) |

## Fork-boundary rules

- Additive edits in upstream-owned files; new behaviour in fork-only files (`.claude/rules/upstream-sync.md`)
- Nothing upstream defines is renamed or removed
- A `config/importmap.rb` this gem writes must parse under importmap-rails
- No new runtime dependency

## Common mistakes

| Wrong | Right |
|---|---|
| Start with the docs page | Start with the pin-line and output contract, then the Packager |
| Grow `packager.rb` by another method | New collaborator file |
| Encode fork metadata as a new `pin` keyword | Encode it in the provenance comment |
| Read a file or the network from `Map` | Keep I/O on the command path |
| Reformat an upstream method while adding to it | Add lines; leave the rest |

## Verification checklist

- [ ] Layer for each change identified; order is contract → Packager/Npm → Commands → tests → docs
- [ ] Every rewrite path (`pin`, `update`, `pristine`, `unpin`) carries the new metadata
- [ ] Upstream-owned diffs are additive
- [ ] Docs page and CHANGELOG named
- [ ] `bundle exec rake test` green

## Handoff

Summarise: the contract (pin line + CLI output), files per layer, integration points touched, and the fork-boundary decisions made. Then hand to `/lfg` or `/plan`.

Now coordinate: $ARGUMENTS
