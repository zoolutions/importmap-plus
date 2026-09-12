# Changelog

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
- **`outdated` shows locks.** A new Locked column marks packages held at
  their version, and the command exits 1 only when an unlocked package is
  outdated, so CI stays green for the versions the app chose.
- **`integrity: true` and `integrity: false` survive a rewrite.** An
  `update`, `pristine` or `pin` used to drop the option; only an integrity
  hash, which belongs to the old file, is still removed when the URL changes.

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
