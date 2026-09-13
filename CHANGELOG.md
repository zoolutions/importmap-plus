# Changelog

## 1.2.0

### Added

- **`pin` keeps a package remote when its file can't stand alone, and says
  why.** A vendored package is one file served under a digested asset path,
  but plenty of packages ship a file that imports a sibling by relative path,
  spawns a `Worker`, reads `import.meta.url` or fetches a `.wasm` binary —
  every one of those 404s in the browser, and importmap-rails vendors it
  anyway. `pin` now reads the download before writing anything to
  `vendor/javascript`; a file that needs more than itself is pinned to its CDN
  URL and the reason goes on the pin:

  ```
  $ bin/importmap pin @popperjs/core@2.11.8
  Pinning "@popperjs/core" to https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js (kept remote: relative imports)
  ```
  ```ruby
  pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports)
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

### Fixed

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
  the next update records it on the pin. The package's pin answers whether it
  is vendored, which records the CDN in its comment, or remote, which carries
  it in the URL and, unlocked, has no comment at all.

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
