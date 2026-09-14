# Changelog

## 1.2.0

### Added

- **`pin` resolves the version on the npm registry, then falls back from jspm
  to esm.run to jsDelivr.** jspm is the default CDN and was the only one `pin`
  asked, so a package its generator can't build — `mermaid@10.6.0` fails on a
  cytoscape subpath, `@mui/material@5.15.0` on a module it can't find — ended
  in `Couldn't find any packages`, and a bare `pin foo` took whatever version
  jspm had indexed, which lags npm. A package that names no CDN of its own is
  now asked of each in turn, and its version is settled against the registry
  before any of them is asked:

  ```
  $ bin/importmap pin mermaid
  Resolved "mermaid" to 10.6.0 from the npm registry
  jspm couldn't resolve "mermaid@10.6.0" (No './dist/cytoscape.umd.js' exports subpath defined in cytoscape@3.34.3); trying esm.run
  Pinning "mermaid" to vendor/javascript/mermaid.js via download from https://cdn.jsdelivr.net/npm/mermaid@10.6.0/+esm
  ```
  ```ruby
  pin "mermaid" # @10.6.0 (esm.run)
  ```

  The pin comment already records a CDN that isn't jspm, so `update` and
  `pristine` stay on esm.run from then on with no new state anywhere. An
  explicit `--from`, and a provider a pin already names, are choices somebody
  made: those are asked once and never fall back. When no CDN has the package,
  each one's reason is printed and the summary names all three.
- **A download that isn't an ES module is kept remote instead of vendored.**
  The CDNs that serve a package's own `dist` file hand back the UMD bundle
  plenty of packages still publish; vendored into an import map it runs and
  exports nothing, so `import x from "pkg"` fails to link in the browser and
  nowhere else. `pin google-libphonenumber --from jsdelivr` now keeps the pin
  remote and records `(remote: not an ES module)`. `--vendor` downloads it
  anyway, and the default `pin` never sees it, since jspm converts the package.
- **The CDN's own reason reaches the terminal.** jspm answers 401 with its
  generator's message in the body, which `pin` discarded: `Couldn't find any
  packages in ["mermaid@10.6.0"] on jspm` said nothing about what went wrong.
  That message is now printed with the sentence, whichever CDN was asked.

- **`pin` keeps a package remote when its file can't stand alone, and says
  why.** A vendored package is one file served under a digested asset path,
  but plenty of packages ship a file that imports a sibling by relative path,
  spawns a `Worker`, reads `import.meta.url` or fetches a `.wasm` binary —
  every one of those 404s in the browser, and importmap-rails vendors it
  anyway. `pin` now reads the download before writing anything to
  `vendor/javascript`; a file that needs more than itself is pinned to its CDN
  URL and the reason goes on the pin:

  ```
  $ bin/importmap pin fflate@0.8.2
  Pinning "fflate" to https://ga.jspm.io/npm:fflate@0.8.2/esm/browser.js (kept remote: workers)
  ```
  ```ruby
  pin "fflate", to: "https://ga.jspm.io/npm:fflate@0.8.2/esm/browser.js" # @0.8.2 (remote: workers)
  ```

  The pin then behaves like any other remote pin — `pin` and `update`
  re-resolve it from the same CDN and keep the reason, `pristine` skips it.
  `pin --vendor` downloads the package anyway and records `(vendored)` on the
  pin, so a later `update` doesn't undo the override; it also converts a pin
  that was kept remote back to a download. Nothing an app already vendored is
  rewritten on its own — `pristine` redownloads those pins as it always has —
  but the next `pin` or `update` that touches one re-resolves it, and a package
  whose file can't stand alone converts to a remote pin then. That is the fix
  arriving, not a surprise: the vendored file it replaces was already 404ing
  for its siblings. pdf.js is the package most apps will see this on — see
  the upgrading page for what to expect and how `--vendor` puts it back.

- **A pin that stays remote carries a subresource-integrity hash.** A vendored
  file is served by the app; a remote pin is fetched from a CDN on every page
  load with nothing checking the bytes, and importmap-rails never wrote an
  `integrity:` value for one — the hash had to be computed by hand and redone
  on every update. `pin --remote`, and a package [kept remote] because its file
  can't stand alone, now fetch the URL they just resolved, hash it and write it
  with the pin:

  ```
  $ bin/importmap pin md5@2.2.0 --remote
  Pinning "md5" to https://ga.jspm.io/npm:md5@2.2.0/md5.js (integrity sha384-+wqk6m3DPZ6mVMgVZlXnGgDjDY2skGEZ3U9tBnRHiPJXLRLKBmYkKlX2urz9T61b)
  ```
  ```ruby
  pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js", integrity: "sha384-+wqk6m3DPZ6mVMgVZlXnGgDjDY2skGEZ3U9tBnRHiPJXLRLKBmYkKlX2urz9T61b"
  ```

  The hash is `sha384` of the bytes the CDN served, computed here rather than
  asked of any one CDN, so jspm, esm.run, jsDelivr, unpkg, esm.sh and skypack
  are all covered by one code path. `update` and a later `pin` fetch the new
  URL and rewrite the hash, so a pin never carries the hash of a file it no
  longer points at — where before an explicit hash was simply dropped.
  `enable_integrity!` in `config/importmap.rb` is still what puts the value in
  the import map and on the preload link; `--no-integrity` skips the fetch for
  a run, and `integrity: false` on a pin stays off for good. Vendored downloads
  are unaffected: `integrity: true`, the default, already computes theirs
  through the asset pipeline.

  [kept remote]: https://importmap-plus.zoolutions.llc/docs/pinning

- **`pin` vendors a package's whole file graph, so a chunked package no longer
  needs a CDN at runtime.** A package whose entry imports a sibling by relative
  path — `@popperjs/core`, `date-fns`, `lodash-es`, and every package built by
  a bundler that splits chunks — could not be vendored: the browser resolves
  `./enums.js` against a digested asset path, and neither Propshaft nor
  Sprockets rewrites `import` statements. Those packages were [kept remote].
  `pin` now downloads the closed set of files the entry reaches, rewrites every
  relative specifier to a bare key, and maps the directory with one
  `pin_all_from` line:

  ```
  $ bin/importmap pin @popperjs/core@2.11.8
  Pinning "@popperjs/core" to vendor/javascript/@popperjs/core.js via download from https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js (with 47 sibling files)
  ```
  ```ruby
  pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8
  pin_all_from "vendor/javascript/@popperjs--core", under: "@popperjs/core", to: "@popperjs--core" # @2.11.8 (graph of @popperjs/core)
  ```

  The entry keeps the flat file and the plain comment it always had, so
  `update`, `outdated`, `lock` and `pristine` read it exactly as before, and a
  `config/importmap.rb` written this way still parses under importmap-rails.
  Bare specifiers are untouched, and a file that is another pin's own entry is
  rewritten to that pin's key rather than copied, so the browser evaluates each
  module once. (Two pins of one package do each carry their own copy of a chunk
  they share; both write it under the same key, so one of the copies is what
  every importer gets and the other is dead weight.) `unpin` takes the directory and the line with the pin,
  `pristine` rebuilds the directory, `pin --minify` minifies every file in it,
  and `pin --vendor` downloads the entry on its own and drops the directory and
  line it had. A directory the import map doesn't map as one of ours is the
  app's: `pin` says so, writes nothing rather than renaming it away, and exits
  non-zero — as it does when a CDN fails partway through a crawl, where the pin
  and the files it had are left exactly as they were.

  Only jspm, jsDelivr and unpkg are crawled — their URLs say where a package's
  directory ends. A graph that can't be taken over whole (a relative path that
  climbs out of the package, a sibling the CDN hasn't got, a sibling that isn't
  JavaScript, two files that would collapse to one key) keeps the whole package
  remote, as does a download that also spawns a worker, reads
  `import.meta.url`, computes an `import()` or names a `.wasm` file. A pin
  importmap-plus had kept remote for its relative imports is converted back to
  a download by the next `pin` or `update`, on the CDN its URL names.

  Two things `pin` says out loud rather than doing quietly: a key some other
  package's graph already maps (a directory wins over a pin, so the pin would
  do nothing), and a second directory mapping a package one already maps at
  another version (a file they share resolves to one of them).

### Fixed

- **A CDN that fails mid-crawl leaves the pin alone.** Vendoring a graph makes
  one request per file — 250 of them for `date-fns` — so a 503 that outlives
  the retries is far likelier than it was for a single download. `pin` and
  `pristine` report it (`Skipping "date-fns": Unexpected response code (503)`)
  and change nothing, rather than taking it for "this package can't be
  vendored" and converting a working pin to a remote one, which would delete
  the very files that make it work.
- **`pristine` reports a package it can't restore and carries on.** It is the
  repair command, and a pin whose graph the CDN no longer serves the way the
  pin describes now raises where nothing used to — unrescued, that ended the
  whole run with a backtrace and left every package after it unrestored. Each
  one that fails is reported (`Couldn't restore "pdfjs-dist": it can't be
  vendored as a single file (workers)`), the rest are restored, and the command
  exits non-zero to say it didn't do all of it.
- **A download the CDN encoded in a way Net::HTTP can't undo is fetched
  again.** jspm answers some files with `content-encoding: br` whatever the
  request advertises, and Net::HTTP decompresses gzip and deflate only:
  `@popperjs/core@2.11.8/lib/utils/computeAutoPlacement.js` arrived as brotli
  bytes, which read as invalid UTF-8 and took the source inspection down with
  `ArgumentError: invalid byte sequence in UTF-8`. `pin` now repeats that one
  request asking for an unencoded body. It doesn't ask up front: supplying an
  `Accept-Encoding` at all stops Net::HTTP decoding the gzip it does
  understand. Inherited from importmap-rails, which downloads the same way.

- **`Importmap::Packager::ServiceError` is a class again.** It was assigned
  `Error.new(Error)` — an *instance* — so `rescue Packager::ServiceError`
  raised `TypeError: class or module required for rescue clause`, and every
  jspm service error arrived as a plain `Packager::Error`. Inherited from
  importmap-rails, where it is still the case.
- **A failed download no longer deletes the file an app already has.**
  `pin` and `pristine` removed `vendor/javascript/<package>.js` before
  fetching, so a CDN that answered 500 — or, now, a file that can't be
  vendored — left the app with no file at all. The existing file is replaced
  only once the new one has arrived and been found fit to serve.
- **`update <package>` moves every pin of that package, not just the bare
  one.** An app with `pin "pdfjs-dist"` and
  `pin "pdfjs-dist/build/pdf.worker.min.mjs"` ran `update pdfjs-dist` and got
  a new main file next to a worker still at the old version — the two are
  built together and don't tolerate that. A package name now means every
  key that carries it, the same set `outdated` reports and a bare `update`
  moves; `update pdfjs-dist/build/pdf.worker.min.mjs` still means that one
  key.
- **A subpath pin without a CDN in its comment resolves from the CDN its
  package's pin names.** The worker pin above, written before provenance
  existed, was sent to jspm — which can't resolve pdf.js at all — and
  reported "Couldn't find any packages" on every update while the main pin
  moved on from jsdelivr. Siblings pinned together come from the same place;
  the next update records it on the pin. A pin answers for itself first — its
  own comment, then its own `to:` URL — and only then does its package answer
  for it, whether that pin is vendored, recording the CDN in its comment, or
  remote, carrying it in the URL with no comment at all.

## 1.1.0

### Added

- **Version locks.** `bin/importmap pin luxon@3.7.2 --lock`, or
  `bin/importmap lock luxon` for a package already pinned, records the lock
  in the version comment — `pin "luxon" # @3.7.2 (locked)` — and `update`
  and a plain `pin` skip the package from then on, saying so. A remote pin
  gains the comment too, carrying the version from its URL. `pin --force`
  moves a locked package and keeps the lock at the new version; `--no-lock`
  drops it; `bin/importmap unlock luxon` removes it without touching the
  file. `pristine` still redownloads a locked vendored package, at the
  locked version; remote pins are skipped as always. Only the packages
  named on the command line are locked, never the dependencies a CDN
  resolves with them, and a locked dependency stays where it is when the
  package that needs it is pinned or updated.
- **`update` takes package names, `--all` and `--force`.**
  `bin/importmap update luxon stimulus-use` re-pins just those, asking the
  registry about them alone; `update --all` says explicitly what a bare
  `update` has always done. A named package that is up to date, or has no
  version to compare, is reported; a name with no pin stops the command
  before anything is touched. `--force` updates locked packages too and
  keeps each lock at the new version.
- **`outdated` shows locks.** A new Locked column marks packages held at
  their version, and the command exits 1 only when an unlocked package is
  outdated, so CI stays green for the versions the app chose.
- **`integrity: true` and `integrity: false` survive a rewrite.** An
  `update`, `pristine` or `pin` used to drop the option; only an integrity
  hash, which belongs to the old file, is still removed when the URL changes.

### Fixed

- **`update` no longer re-pins a package the registry couldn't be checked
  for.** A package whose registry lookup came back unusable has no latest
  version, so nothing established that it moved — but `update` re-pinned it
  anyway, letting a bad answer re-resolve the pin against the CDN and carry
  it to a version nobody asked for. Those packages are now reported —
  `Couldn't check "md5": Unexpected error response 500: …` — and left where
  they are; every other package still updates, and the command exits 1.
  Inherited from importmap-rails, where a bare `update` has always behaved
  this way.
- **`update` re-pins a subpath pin instead of appending a bare one.** The
  registry answers about `photoswipe`, the import map pins
  `photoswipe/lightbox`, and a bare `update` or `update --all` used to re-pin
  the name it was answered with: the subpath pin stayed at its old version and
  a `pin "photoswipe"` was appended beside it — vendored, since a fresh pin
  has no provenance to say otherwise. Every key carrying an outdated package
  is now re-pinned, and a package pinned under several keys moves all of them.
  Only pins that declare a version take part, the same ones `outdated`
  reports on, so an app file pinned under a package's namespace —
  `pin "md5/helpers", to: "md5/helpers.js"` — is left alone. Inherited from
  importmap-rails; `update photoswipe/lightbox` was fixed for the named form
  in 1.1.0.
- **A remote subpath pin is re-resolved from the CDN it is on.** Moving
  `pin "photoswipe/lightbox", to: "https://cdn.jsdelivr.net/npm/photoswipe@5.3.0/…"`
  back onto jsDelivr asked for `photoswipe/lightbox@5.4.4`, a path no CDN
  has, so `update` gave up with `Keeping "photoswipe/lightbox" pinned to …
  (couldn't resolve it from jsdelivr)` and the pin never moved. The version
  now goes where a CDN expects it, ahead of the subpath —
  `photoswipe@5.4.4/lightbox`.
- **A registry that won't answer for one package no longer ends the run.**
  A 404, a 5xx or a connection that kept resetting used to escape
  `outdated_packages` once the retries were spent, so `outdated` and
  `update` died with a backtrace and checked nothing else. The failure is
  now recorded against that package alone — `outdated` prints the reason in
  its Latest column, which is what the column was always for — and every
  other package is still checked. `audit` is unchanged: a registry it can't
  reach still fails the command outright.

## 1.0.0

First release of importmap-plus, a drop-in replacement for
[importmap-rails](https://github.com/rails/importmap-rails) 2.2.3. The
`Importmap::` API, the pin DSL and the generated import map are unchanged;
`Importmap::UPSTREAM_VERSION` names the importmap-rails release this tracks.

### Added

- **`bin/importmap pin --minify`** runs a download through bun, esbuild or
  terser — the first found in `node_modules/.bin` or on `PATH`, including
  Windows `.cmd` shims — before it lands in `vendor/javascript`. Always
  transform-only, so bare import specifiers stay exactly as the CDN resolved
  them and the import map keeps resolving them. `pristine --minify` does the
  same for everything already vendored. Plenty of packages publish unminified
  ESM (pdfjs-dist, choices.js, luxon), and a CDN serving package files
  hands them out as published.
- **`--from esm.run`** pins jsDelivr's bundled builds instead of a package's
  own dist file. A bundle references its dependencies as absolute
  `/npm/dep@1.2.3/+esm` imports, which resolve only on jsDelivr; those are
  rewritten to bare specifiers on download and each dependency without a pin
  is vendored the same way. A dependency the app already pins is left alone,
  so the bundle resolves to the version the app chose. Versions resolve
  through jsDelivr's data API, so `pin luxon@3` and `pin apexcharts/core`
  work as they do on npm.
- **Provenance in the pin comment.** A vendored pin records the CDN when it
  isn't jspm and whether the file was minified — `pin "luxon" # @3.7.2
  (esm.run, minified)`. `update`, `pristine` and a plain `pin` read it back,
  so a package keeps its CDN and stays minified without repeating the flags.
  This extends to every CDN: an unpkg download no longer silently moves back
  to jspm on the next `update`.
- **An explicit `--from` moves a remote pin** to that CDN, instead of being
  overruled by the provider the pin already points at.
- **Requests retry.** A reset connection, a timeout or a 429/5xx from the
  CDN is tried up to three times with a growing pause before `bin/importmap`
  gives up, and the failure then names the URL instead of a raw backtrace.
  `Importmap::Packager.retry_attempts` / `retry_wait` tune it.

### Changed

- `bin/release` tags a version and publishes a GitHub Release, which fires
  `.github/workflows/release.yml` to push the gem over RubyGems trusted
  publishing. The upstream script pushed from a developer's machine with an
  API key.
