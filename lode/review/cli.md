How `bin/importmap` decides what to pin, where to resolve it from, and what to leave alone.

### `--vendor` applies only to the packages named on the command line, and `--remote` overrides it
- **Holds because:** a CDN resolves a package together with its dependency graph, so `pin bootstrap --vendor` would otherwise force-vendor `@popperjs/core` too — a file the single-file check refused, now 404ing for its siblings in production, because of an override the user made about a different package. `pin` passes `vendor: requested.include?(package) && options[:vendor]`, and `pin_esm_run_dependencies` passes no `vendor:` at all. In `pin_package` a true `vendor` only defeats the first condition (`existing_url && !vendor`); the `elsif remote` test then decides, so `--remote --vendor` pins the URL and `--vendor` alone falls through to `pin_vendored_package`: `--remote` names a destination, `--vendor` only overrides a check.
- **Where:** `lib/importmap/commands.rb#pin`, `#pin_package`, `#pin_esm_run_dependencies`
- **Proven by:** `test/commands_test.rb:"pin command with --vendor downloads a package that can't stand alone anyway"` covers the named-package half; no test covers a dependency being left alone or `--remote` beating `--vendor` (documented in `docs/app/views/docs/pages/pinning.rb`)
- **Origin:** cubic learnings ca51aed7, 4f5d437a

### A locked pin that was not named on the command line is kept as it is, never re-pinned
- **Holds because:** `pin react` resolves react *and* its dependencies; if one of them is locked, re-pinning it would move a version the app deliberately froze, without the user ever naming it. `keep_locked_dependency` returns true for any resolved package that is locked and absent from the requested list, printing `Keeping existing pin for "<pkg>" (locked at <version>)`. Both `pin` and `update` call it before `pin_package`.
- **Where:** `lib/importmap/commands.rb#keep_locked_dependency`, called from `#pin` and `#update`
- **Proven by:** `test/commands_test.rb:"pin command leaves a locked dependency pin alone"`, `:"pin command with --from esm.run leaves a locked dependency pin alone"`, `:"update command leaves a locked dependency pin alone"`
- **Origin:** cubic learning bd5c617e

### An explicit `--from` moves an existing remote pin to that CDN instead of being overruled by its current provider
- **Holds because:** `repin_remote_package` normally re-resolves a remote pin from the provider its current URL names, so a pin keeps its CDN across updates. But `url` was already resolved from the CDN the user asked for, so honouring the old provider would make `pin md5 --from jsdelivr` silently a no-op on a jspm-pinned package. The method returns straight to `pin_remote_package` when `from` is present.
- **Where:** `lib/importmap/commands.rb#repin_remote_package` (first line), reached from `#pin_package`
- **Proven by:** `test/commands_test.rb:"pin command with an explicit --from moves a remote pin to that CDN"`
- **Origin:** cubic learning be0d6024

### `pristine` rewrites a vendored pin's line only when the CDN or the minified state it records changed
- **Holds because:** `pristine` restores files, it does not re-resolve pins. Rewriting the line unconditionally would re-emit it from `vendored_pin_for`, which cannot reproduce options the parser does not round-trip — an integrity *hash*, for instance, is dropped by design. `provenance_changed?` compares only `:provider` and `:minified` against `provenance_for(url, minify:)` and `record_provenance` runs only when they differ.
- **Where:** `lib/importmap/commands.rb#pristine`, `#provenance_changed?`, `#record_provenance`; `lib/importmap/packager.rb#provenance_for`
- **Proven by:** `test/commands_test.rb:"pristine command with --from records the new CDN in the pin"`, `:"pristine command with --minify minifies every vendored package"`
- **Origin:** cubic learning b974e620

### A subpath pin answers for its own CDN first — its comment, then its own `to:` URL — and only then falls back to its package's pin; a bare package pin stops at its comment
- **Holds because:** `pin "photoswipe" # (skypack)` next to `pin "photoswipe/lightbox", to: "https://cdn.jsdelivr.net/…"` must not send the subpath to skypack: asking the package first groups both specs into one request, and one spec the CDN cannot answer for fails the whole batch, taking the subpath down with the package. The URL fallback is deliberately scoped to a subpath asking about itself or its package — resolving `to:` with `provider_for_url` for *every* pin would change where a plain remote pin's dependency graph is resolved from, and jsdelivr and jspm return different graphs. The lookup keys off `package_key_for(spec)`, so a versioned subpath spec (`photoswipe@5.4.4/lightbox`) still finds the pin's saved CDN.
- **Where:** `lib/importmap/commands.rb#vendored_provider_for`, `#provider_of_pin`, `#for_each_import_grouped_by_provider`
- **Proven by:** `test/commands_test.rb:"update command resolves a subpath pin from its own CDN, not its package's"`, `:"update command resolves a subpath pin from the CDN its package's pin names"`, `:"update command resolves a subpath pin from the CDN its package's remote pin points at"`, `:"pin command keeps a subpath package on its CDN when the spec carries a version"`
- **Origin:** cubic learnings 7f299cb2, c4764e68; PR #23

### A bare `update` (and `update --all`) re-pins only import-map keys whose own pin declares a version
- **Holds because:** an app file pinned under a package's namespace — `pin "md5/helpers", to: "md5/helpers.js"` — names no version and is none of the registry's business. Sending it to a CDN alongside the real outdated packages makes jspm 404 the whole batch, so *nothing* updates. `versioned_keys_by_package` filters `pinned_packages` through `pin_version` before grouping by `package_name_for`, so unversioned namespace-sharing local pins are left exactly as they are.
- **Where:** `lib/importmap/commands.rb#versioned_keys_by_package`, `#outdated_keys_for`, `#requested_keys_for`; `lib/importmap/packager.rb#pin_version`
- **Proven by:** `test/commands_test.rb:"update command leaves a local pin that shares a namespace with an outdated package"`, `:"update command with --all re-pins every key carrying an outdated package"`
- **Origin:** cubic learning e6d25495; PR #13

### A registry error is recorded on the package it happened to, so `outdated` and `update` continue with the rest — `audit` is not covered
- **Holds because:** one package the registry will not answer for must not end a whole run. `Npm#get_package` turns a spent-retries `HTTPError` into `{ "error" => … }` and a `JSON::ParserError` into nil; `outdated_packages` records either on that package's `OutdatedPackage#error` and keeps going. `update` partitions on `latest_version`, prints `Couldn't check "<pkg>"` for the unchecked ones, updates the rest, and exits 1 — nothing established that an unchecked package moved, so re-pinning it would let a registry blip re-resolve it onto a different CDN result. `audit` goes through `get_audit` → `post_json`, which raises: an audit that silently skipped packages would report a clean bill of health it cannot vouch for.
- **Where:** `lib/importmap/npm.rb#get_package`, `#outdated_packages`, `#get_audit`; `lib/importmap/commands.rb#update`, `#outdated`
- **Safe direction:** for `outdated`/`update` the harmless failure is reporting a package as unchecked; for `audit` the harmless failure is raising, because a partial audit read as complete hides a real vulnerability.
- **Proven by:** `test/npm_test.rb:"outdated packages carries a registry error instead of a latest version"`, `:"outdated packages asks about every package when one can't be reached"`; `test/commands_test.rb:"update command leaves a package alone when the registry couldn't be checked"`, `:"update command updates the rest when a named package couldn't be checked"`, `:"outdated command reports a package the registry couldn't answer for"`
- **Origin:** cubic learning 395ab7a5

### A vendored pin with no `(vendored)` mark converts to a remote pin on the next `pin` or `update` that touches it when its file can't stand alone; `pristine` never converts
- **Holds because:** the single-file check postdates those pins, and the vendored file they point at was already 404ing for its siblings — the conversion is the fix arriving. `pin_vendored_package` rescues `Unvendorable` / `NotAnEsModule` and falls through to `pin_remote_package` with the reason. `pristine` passes `force: true` to `download`, so it restores what each pin already says rather than re-deciding, and once a pin is remote `pristine` prints `Skipping "<pkg>" (pinned to remote URL)`. `pin --vendor` writes `(vendored)`, which `pin_package` reads back (`vendor ||= packager.vendored?(package)`) so a later update cannot quietly undo the override.
- **Where:** `lib/importmap/commands.rb#pin_vendored_package`, `#pin_package`, `#pristine`; `lib/importmap/packager.rb#ensure_servable`, `#vendored?`
- **Proven by:** `test/commands_test.rb:"pin command keeps a package remote when its file can't stand alone, and says why"`, `:"pin command with --vendor converts a pin that was kept remote back to a download"`, `:"update command keeps a package vendored with --vendor vendored"`, `:"pristine command skips packages pinned to remote URLs"`
- **Origin:** PR #22

### Not a bug: `Pinning "<pkg>" to <vendor_path>/<pkg>.js` prints a path that differs from the file actually written for a subpath
- **Holds because:** the vendored file is named `package.gsub("/", "--") + ".js"`, so `photoswipe/lightbox` lands in `vendor/javascript/photoswipe--lightbox.js` while the message says `vendor/javascript/photoswipe/lightbox.js`. This is upstream importmap-rails' line, left unchanged on purpose: the fork keeps upstream-owned files diff-minimal, and the tests assert the upstream wording. Changing it is an upstream fix, not a fork fix.
- **Where:** `lib/importmap/commands.rb#pin_vendored_package` (and the same sentence in `#pristine`); `lib/importmap/packager.rb#package_filename`
- **Proven by:** `test/commands_test.rb:"update command resolves a subpath pin from the CDN its package's pin names"` asserts the upstream wording verbatim
- **Origin:** PR #23

### `pristine` reports the packages it can't restore, restores the rest, and exits non-zero
- **Holds because:** it is the repair command, and a graphed pin now re-crawls, so one sibling URL the CDN has stopped serving raises `Unvendorable` where nothing used to raise at all. Left unrescued that took the whole batch down with a backtrace and every package after it went unrestored. `restore_package` rescues `Unvendorable`/`NotAnEsModule` per package, prints `Couldn't restore "<pkg>": it …`, and the command exits 1 having done the rest — the same shape as `update`'s treatment of a package the registry couldn't answer for.
- **Where:** `lib/importmap/commands.rb#pristine`, `#restore_package`
- **Safe direction:** a printed sentence and a non-zero exit says what didn't happen; a backtrace halfway through a repair leaves an app half-repaired and no list of what is missing.
- **Origin:** gate round 1 (correctness), PR #30

### A `pristine` that moves a graphed package to a CDN that bundles takes the graph line with the directory
- **Holds because:** `pristine --from esm.run` on a jspm-graphed pin downloads a `+esm` bundle, which has no relative imports, so no graph is built and the directory is removed — and the `pin_all_from` line was left mapping a directory that no longer exists, with `mapped?` still answering true on every later run. `restore_package` calls `remove_graph` whenever the download came back without one.
- **Where:** `lib/importmap/commands.rb#restore_package`; `lib/importmap/packager.rb#remove_graph`
- **Proven by:** `test/commands_test.rb:"pristine command with --from esm.run drops the graph a jspm pin had"`
- **Origin:** gate round 1 (correctness), PR #30

### A pin whose key a vendored graph already maps is pinned, and said out loud
- **Holds because:** `Importmap::Map#expanded_packages_and_directories` expands directories *over* packages, so a key a `pin_all_from` defines resolves to that file however the pin beside it is written — `pin date-fns/format@2.29.3` next to a graph of `date-fns@2.30.0` writes a line that never takes effect. The graph itself refuses to define a key an existing pin owns (`forbidden`), but nothing can stop the reverse, so `pin` prints `Note: the graph of "<package>" already maps "<key>", and a mapped directory wins over a pin`.
- **Where:** `lib/importmap/commands.rb#report_graph_shadowing`; `lib/importmap/vendored_graph.rb#mapping_for`; `lib/importmap/map.rb#expanded_packages_and_directories`
- **Proven by:** `test/vendored_graph_test.rb:"mapping_for names the package whose directory already maps a key"` (the note itself is not asserted)
- **Origin:** gate round 1 (correctness), PR #30
