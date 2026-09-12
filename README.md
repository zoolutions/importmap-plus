# importmap-plus

A drop-in replacement for [importmap-rails](https://github.com/rails/importmap-rails) with vendoring that keeps its promises: `bin/importmap pin --minify`, `--from esm.run` for jsDelivr's bundled builds, `--lock` to hold a package at a version, `update` by package name, and a pin comment that remembers where each package came from so later updates respect it. Everything else is importmap-rails, constants included, so an app switches by changing one line in its `Gemfile`.

**Documentation: [importmap-plus.zoolutions.llc](https://importmap-plus.zoolutions.llc)** — also as [llms.txt](https://importmap-plus.zoolutions.llc/llms.txt) and a read-only MCP endpoint at `https://importmap-plus.zoolutions.llc/mcp`.

**Install this gem or importmap-rails, never both** — they define the same `Importmap::` constants and the same engine.

## Installation

Replace `gem "importmap-rails"` with `gem "importmap-plus"` in your `Gemfile` and run `bundle install`. An app already on importmap-rails needs nothing else: the pins, `config/importmap.rb`, the helpers and the `Importmap::` constants are unchanged.

An app without an import map yet:

```bash
./bin/bundle add importmap-plus
./bin/rails importmap:install
```

## What it adds

| | |
|---|---|
| `pin --minify` | Runs a download through bun, esbuild or terser before it lands in `vendor/javascript`; later updates keep minifying it. |
| `--from esm.run` | Vendors jsDelivr's one-file bundle, rewrites its imports to bare specifiers, and pins the dependencies it needs. |
| `pin --lock`, `lock`, `unlock` | Holds a package at a version. `update`, `pristine` and `pin` leave it there until you unlock it or pass `--force`. |
| `update [PACKAGES] --all --force` | Update by name, or everything explicitly; `--force` moves locked packages and re-locks them. |
| Provenance | The pin comment records the CDN, minification and lock — `pin "luxon" # @3.7.2 (esm.run, minified, locked)` — so nothing silently drifts back to jspm. |
| Remote pins stay remote | A pin with a CDN URL is re-resolved from that CDN; `preload:` and a boolean `integrity:` survive every rewrite; a custom URL is left alone. |
| Requests retry | A reset connection, a timeout or a 429/5xx is tried three times with a growing pause before the command gives up. |

```bash
./bin/importmap pin luxon --from esm.run --minify
./bin/importmap pin @hotwired/stimulus@3.2.2 --lock
./bin/importmap update stimulus-use
./bin/importmap outdated
```

```ruby
# config/importmap.rb
pin "luxon" # @3.7.2 (esm.run, minified)
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2 (locked)
```

The full guide — every command, option and behaviour, plus importmap-rails' own documentation for the parts that are unchanged — is at [importmap-plus.zoolutions.llc](https://importmap-plus.zoolutions.llc).

## Tracking importmap-rails

This gem tracks importmap-rails at the release named in `Importmap::UPSTREAM_VERSION`; its own version is `Importmap::VERSION`. Upstream changes are merged as they land, and the parts of the documentation that describe upstream behaviour are kept in step. See [CHANGELOG.md](CHANGELOG.md) for what each release adds.

## Development

```bash
bundle install
bundle exec rake test          # the command tests talk to live CDNs (jspm, jsDelivr)
cd docs && bin/dev             # the docs site, a docs-kit app at docs/
```

Releases are cut with `bin/release`, which tags a version and publishes a GitHub Release; that fires `.github/workflows/release.yml` (RubyGems trusted publishing) and `.github/workflows/deploy-docs.yml` (the docs site).

## License

Importmap for Rails is released under the [MIT License](https://opensource.org/licenses/MIT), and so is importmap-plus.
