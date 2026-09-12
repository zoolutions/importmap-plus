# importmap-plus

A drop-in replacement for [importmap-rails](https://github.com/rails/importmap-rails) with better vendoring: `bin/importmap pin --minify`, `--from esm.run` for jsDelivr's bundled builds, `--lock` to hold a package at a version, and a pin comment that remembers all of it so later updates respect it. Everything else is importmap-rails, constants included, so an app switches by changing one line in its `Gemfile`.

**Install this gem or importmap-rails, never both** — they define the same `Importmap::` constants and the same engine.

See [what this adds](#loading-bundles-from-esmrun) below; the rest of this README is importmap-rails' own, which this gem tracks at the version in `Importmap::UPSTREAM_VERSION`.

---

[Import maps](https://github.com/WICG/import-maps) let you import JavaScript modules using logical names that map to versioned/digested files – directly from the browser. So you can [build modern JavaScript applications using JavaScript libraries made for ES modules (ESM) without the need for transpiling or bundling](https://world.hey.com/dhh/modern-web-apps-without-javascript-bundling-or-transpiling-a20f2755). This frees you from needing Webpack, Yarn, npm, or any other part of the JavaScript toolchain. All you need is the asset pipeline that's already included in Rails.

With this approach you'll ship many small JavaScript files instead of one big JavaScript file. Thanks to HTTP/2 that no longer carries a material performance penalty during the initial transport, and in fact offers substantial benefits over the long run due to better caching dynamics. Whereas before any change to any JavaScript file included in your big bundle would invalidate the cache for the whole bundle, now only the cache for that single file is invalidated.

[Import maps are supported natively in all major, modern browsers](https://caniuse.com/?search=importmap). If you need to work with legacy browsers without native support, you can explore using [the shim available](https://github.com/guybedford/es-module-shims).


## Installation

Rails 7+ ships importmap-rails for new applications. To use importmap-plus instead:

1. Replace `gem "importmap-rails"` with `gem "importmap-plus"` in your `Gemfile`, or run `./bin/bundle add importmap-plus` in an app that has neither
2. Run `./bin/rails importmap:install` if the app has no `config/importmap.rb` yet

An app already on importmap-rails needs nothing else: the pins, the `config/importmap.rb`, the helpers and the `Importmap::` constants are unchanged.

Note: In order to use JavaScript from Rails frameworks like Action Cable, Action Text, and Active Storage, you must be running Rails 7.0+. This was the first version that shipped with ESM compatible builds of these libraries.

You can pin those libraries manually by relying on the compiled versions included in Rails like this:

```ruby
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "@rails/actiontext", to: "actiontext.esm.js"
pin "trix"
```

## How do importmaps work?

At their core, importmaps are essentially a string substitution for what are referred to as "bare module specifiers". A "bare module specifier" looks like this: `import React from "react"`. This is not compatible with the ES Module loader spec. Instead, to be ESM compatible, you must provide 1 of the 3 following types of specifiers:

- Absolute path:
```js
import React from "/Users/DHH/projects/basecamp/node_modules/react"
```

- Relative path:
```js
import React from "./node_modules/react"
```

- HTTP path:
```js
import React from "https://ga.jspm.io/npm:react@17.0.1/index.js"
```

Importmap-rails provides a clean API for mapping "bare module specifiers" like `"react"`
to 1 of the 3 viable ways of loading ES Module javascript packages.

For example:

```rb
# config/importmap.rb
pin "react", to: "https://ga.jspm.io/npm:react@17.0.2/index.js"
```

means "every time you see `import React from "react"`
change it to `import React from "https://ga.jspm.io/npm:react@17.0.2/index.js"`"

```js
import React from "react"
// => import React from "https://ga.jspm.io/npm:react@17.0.2/index.js"
```

## Usage

The import map is setup through `Rails.application.importmap` via the configuration in `config/importmap.rb`. This file is automatically reloaded in development upon changes, but note that you must restart the server if you remove pins and need them gone from the rendered importmap or list of preloads.

This import map is inlined in the `<head>` of your application layout using `<%= javascript_importmap_tags %>`, which will setup the JSON configuration inside a `<script type="importmap">` tag. Then the application entrypoint is imported via `<script type="module">import "application"</script>`. That logical entrypoint, `application`, is mapped in the importmap script tag to the file `app/javascript/application.js`.

It's in `app/javascript/application.js` you setup your application by importing any of the modules that have been defined in the import map. You can use the full ESM functionality of importing any particular export of the modules or everything.

It makes sense to use logical names that match the package names used by npm, such that if you later want to start transpiling or bundling your code, you won't have to change any module imports.

### Local modules

If you want to import local js module files from `app/javascript/src` or other sub-folders of `app/javascript` (such as `channels`), you must pin these to be able to import them. You can use `pin_all_from` to pick all files in a specific folder, so you don't have to `pin` each module individually.

```rb
# config/importmap.rb
pin_all_from 'app/javascript/src', under: 'src', to: 'src'

# With automatic integrity calculation for enhanced security
enable_integrity!
pin_all_from 'app/javascript/controllers', under: 'controllers', integrity: true
```

The `:to` parameter is only required if you want to change the destination logical import name. If you drop the :to option, you must place the :under option directly after the first parameter.

The `enable_integrity!` call enables integrity calculation globally, and `integrity: true` automatically calculates integrity hashes for all files in the directory, providing security benefits without manual hash management.

Allows you to:

```js
// app/javascript/application.js
import { ExampleFunction } from 'src/example_function'
```
Which imports the function from `app/javascript/src/example_function.js`.

Note: Sprockets used to serve assets (albeit without filename digests) it couldn't find from the `app/javascripts` folder with logical relative paths, meaning pinning local files wasn't needed. Propshaft doesn't have this fallback, so when you use Propshaft you have to pin your local modules.

## Using npm packages via JavaScript CDNs

Importmap for Rails downloads and vendors your npm package dependencies via JavaScript CDNs that provide pre-compiled distribution versions.

You can use the `./bin/importmap` command that's added as part of the install to pin, unpin, or update npm packages in your import map. By default this command uses an API from [JSPM.org](https://jspm.org) to resolve your package dependencies efficiently, and then add the pins to your `config/importmap.rb` file.

```bash
./bin/importmap pin react
Pinning "react" to vendor/javascript/react.js via download from https://ga.jspm.io/npm:react@19.1.0/index.js
```

This will produce a pin in your `config/importmap.rb` like so:

```ruby
pin "react" # @19.1.0
```

Other CDNs like [unpkg.com](https://unpkg.com) and [jsdelivr.com](https://www.jsdelivr.com) can be specified with `--from`:

```bash
./bin/importmap pin react --from unpkg
Pinning "react" to vendor/javascript/react.js via download from https://unpkg.com/react@19.1.0/index.js
```

```bash
./bin/importmap pin react --from jsdelivr
Pinning "react" to vendor/javascript/react.js via download from https://cdn.jsdelivr.net/npm/react@19.1.0/index.js
```

The packages are downloaded to `vendor/javascript`, which you can check into your source control, and they'll be available through your application's own asset pipeline serving.

If you later wish to remove a downloaded pin:

```bash
./bin/importmap unpin react
Unpinning and removing "react"
```

### Updating packages

`./bin/importmap update` re-pins every package the npm registry has a newer version of. Name packages to update just those, or pass `--all` to say explicitly that you mean everything:

```bash
./bin/importmap update luxon stimulus-use
./bin/importmap update --all
```

A named package that isn't outdated, or has no version to compare, is reported and left alone; a name with no pin at all stops the command before anything is updated. A package is re-resolved together with the dependencies its CDN lists for it, so those move as well, keeping their own pin options. [Locked](#locking-a-package-at-a-version) packages are skipped; `--force` updates them too and keeps each lock at the new version.

### Pinning to remote CDN URLs

If you'd rather load a package straight from the CDN instead of vendoring a download, pass `--remote`:

```bash
./bin/importmap pin react --remote
Pinning "react" to https://ga.jspm.io/npm:react@19.1.0/index.js
```

This will produce a pin in your `config/importmap.rb` like so:

```ruby
pin "react", to: "https://ga.jspm.io/npm:react@19.1.0/index.js"
```

Remote pins are respected from then on — no `--remote` flag needed. When a remote-pinned package is pinned again or picked up by `./bin/importmap update` (whether directly or as a dependency of another package), the pin stays remote: the URL is re-resolved from the same CDN provider it already points to (`ga.jspm.io`, `unpkg.com`, `cdn.jsdelivr.net`, `cdn.skypack.dev`, or `esm.sh`) instead of being replaced with a download. Pins pointing at any other host are left completely untouched and reported as skipped, and `./bin/importmap pristine` skips remote pins since there is nothing to redownload.

Options on existing pins, like `preload: false` and `integrity: false`, are preserved when a pin is rewritten. An explicit `integrity:` hash is dropped when the URL changes, since the old hash would no longer match — see the SRI section below for pinning fresh integrity hashes.

### Loading bundles from esm.run

[esm.run](https://www.jsdelivr.com/esm) is jsDelivr's bundling endpoint: it serves one minified ES module per package, no matter what the package ships on npm. Where jspm hands you a package's own `dist` file (unminified for plenty of packages), `--from esm.run` gives you the bundle:

```bash
./bin/importmap pin luxon --from esm.run
Pinning "luxon" to vendor/javascript/luxon.js via download from https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm
```

A bundle references the packages it depends on as absolute `/npm/dep@1.2.3/+esm` imports, which only resolve on jsDelivr. When the bundle is vendored, those imports are rewritten to bare specifiers (`import { Controller } from "@hotwired/stimulus"`) so they resolve through your import map, and every dependency without a pin is pinned the same way — vendored from esm.run, at the version the bundle was built against:

```bash
./bin/importmap pin stimulus-use --from esm.run
Pinning "stimulus-use" to vendor/javascript/stimulus-use.js via download from https://cdn.jsdelivr.net/npm/stimulus-use@0.53.1/+esm
Keeping existing pin for "@hotwired/stimulus" (bundle was built against @3.2.2)
```

A dependency you already pin is left alone: the bundle then resolves to whatever your import map says, exactly like a jspm download would. With `--remote`, the pin points at the bundle URL and its imports load from jsDelivr as-is.

Versions are resolved through jsDelivr's data API, so `pin luxon@3 --from esm.run` and subpaths like `pin apexcharts/core --from esm.run` work the way they do on npm.

### Where a package came from is remembered

The version comment on a vendored pin also names the CDN when it isn't jspm:

```ruby
pin "luxon" # @3.7.2 (esm.run)
pin "react" # @19.1.0 (unpkg)
```

`./bin/importmap update` and `./bin/importmap pristine` read it and go back to the same CDN — an esm.run bundle stays a bundle, an unpkg download stays on unpkg — and so does `pin` when you leave out `--from`. Pass `--from` to move a package to another CDN; an explicit `--from` moves a remote pin too, which is otherwise re-resolved from the CDN it already points at.

### Locking a package at a version

Some packages you want to hold: a major you haven't migrated to yet, a release that broke something. Pass `--lock` when pinning, or lock what is already pinned, and the version comment says so:

```bash
./bin/importmap pin luxon@3.7.2 --lock
./bin/importmap lock @hotwired/stimulus
./bin/importmap unlock luxon
```

```ruby
pin "luxon" # @3.7.2 (locked)
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2 (esm.run, locked)
pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)
```

A locked package is skipped by `./bin/importmap update` and by a plain `pin` of the same package, each saying so. `update --force` and `pin luxon@4.0.0 --force` move it and keep the lock at the new version; `pin luxon@4.0.0 --lock` does the same; `--no-lock` moves it and drops the lock. `pristine` redownloads a locked vendored package at the version it is locked at; a remote pin is skipped, locked or not. Only the packages you name are locked — the dependencies a CDN resolves alongside them keep floating. `outdated` still lists a locked package that has a newer version, marked in its Locked column, but doesn't count it as drift: it exits 1 only when an unlocked package is outdated.

### Minifying vendored packages

Lighthouse's unminified-javascript audit will tell you which packages ship unminified builds. Pass `--minify` to run a download through a JavaScript minifier before it lands in `vendor/javascript`:

```bash
./bin/importmap pin luxon --minify
Pinning "luxon" to vendor/javascript/luxon.js via download from https://ga.jspm.io/npm:luxon@3.7.2/build/es6/luxon.mjs (minified)
```

The first of [bun](https://bun.sh), [esbuild](https://esbuild.github.io) or [terser](https://terser.org) found in `node_modules/.bin` or on your `PATH` is used, always in transform-only mode so bare import specifiers are left exactly as the CDN resolved them. The pin records it (`pin "luxon" # @3.7.2 (minified)`, or `(esm.run, minified)` for a bundle), and from then on `update`, `pristine` and a plain `pin` keep minifying that package; `--no-minify` turns it off again, and `./bin/importmap pristine --minify` minifies everything you have vendored in one go.

To use a different minifier, assign anything that responds to `call(source)` and returns the minified source. `bin/importmap` loads `config/application.rb` but not your initializers, so the assignment has to happen there (or in a file it requires):

```ruby
# config/application.rb
require "importmap/packager"

Importmap::Packager.minifier = ->(source) { MyMinifier.minify(source) }
```

## Subresource Integrity (SRI)

For enhanced security, importmap-plus supports [Subresource Integrity (SRI)](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity) hashes for packages loaded from external CDNs.

### Automatic integrity for local assets

To enable automatic integrity calculation for local assets served by the Rails asset pipeline, you must first call `enable_integrity!` in your importmap configuration:

```ruby
# config/importmap.rb

# Enable integrity calculation globally
enable_integrity!

# With integrity enabled, these will auto-calculate integrity hashes
pin "application"                                               # Auto-calculated integrity
pin "admin", to: "admin.js"                                     # Auto-calculated integrity
pin_all_from "app/javascript/controllers", under: "controllers" # Auto-calculated integrity

# Mixed usage - explicitly controlling integrity
pin "cdn_package", integrity: "sha384-abc123..." # Pre-calculated hash
pin "no_integrity_package", integrity: false     # Explicitly disable integrity
pin "nil_integrity_package", integrity: nil      # Explicitly disable integrity
```

This is particularly useful for:
* **Local JavaScript files** managed by your Rails asset pipeline
* **Bulk operations** with `pin_all_from` where calculating hashes manually would be tedious
* **Development workflow** where asset contents change frequently

**Note:** Integrity calculation is opt-in and must be enabled with `enable_integrity!`. This behavior can be further controlled by setting `integrity: false` or `integrity: nil` on individual pins.

**Important for Propshaft users:** SRI support requires Propshaft 1.2+ and you must configure the integrity hash algorithm in your application:

```ruby
# config/application.rb or config/environments/*.rb
config.assets.integrity_hash_algorithm = 'sha256'  # or 'sha384', 'sha512'
```

Without this configuration, integrity will be disabled by default when using Propshaft. Sprockets includes integrity support out of the box.

**Example output with `enable_integrity!` and `integrity: true`:**
```json
{
  "imports": {
    "application": "/assets/application-abc123.js",
    "controllers/hello_controller": "/assets/controllers/hello_controller-def456.js"
  },
  "integrity": {
    "/assets/application-abc123.js": "sha256-xyz789...",
    "/assets/controllers/hello_controller-def456.js": "sha256-uvw012..."
  }
}
```

### How integrity works

The integrity hashes are automatically included in your import map and module preload tags:

**Import map JSON:**
```json
{
  "imports": {
    "lodash": "https://ga.jspm.io/npm:lodash@4.17.21/lodash.js",
    "application": "/assets/application-abc123.js",
    "controllers/hello_controller": "/assets/controllers/hello_controller-def456.js"
  },
  "integrity": {
    "https://ga.jspm.io/npm:lodash@4.17.21/lodash.js": "sha384-PkIkha4kVPRlGtFantHjuv+Y9mRefUHpLFQbgOYUjzy247kvi16kLR7wWnsAmqZF"
    "/assets/application-abc123.js": "sha256-xyz789...",
    "/assets/controllers/hello_controller-def456.js": "sha256-uvw012..."
  }
}
```

**Module preload tags:**
```html
<link rel="modulepreload" href="https://ga.jspm.io/npm:lodash@4.17.21/lodash.js" integrity="sha384-PkIkha4kVPRlGtFantHjuv+Y9mRefUHpLFQbgOYUjzy247kvi16kLR7wWnsAmqZF">
<link rel="modulepreload" href="/assets/application-abc123.js" integrity="sha256-xyz789...">
<link rel="modulepreload" href="/assets/controllers/hello_controller-def456.js" integrity="sha256-uvw012...">
```

Modern browsers will automatically validate these integrity hashes when loading the JavaScript modules, ensuring the files haven't been modified.

## Preloading pinned modules

To avoid the waterfall effect where the browser has to load one file after another before it can get to the deepest nested import, importmap-plus uses [modulepreload links](https://developers.google.com/web/updates/2017/12/modulepreload) by default. If you don't want to preload a dependency, because you want to load it on-demand for efficiency, append `preload: false` to the pin.

Example:

```ruby
# config/importmap.rb
pin "@github/hotkey", to: "@github--hotkey.js" # file lives in vendor/javascript/@github--hotkey.js
pin "md5", preload: false # file lives in vendor/javascript/md5.js

# app/views/layouts/application.html.erb
<%= javascript_importmap_tags %>

# will include the following link before the importmap is setup:
<link rel="modulepreload" href="/assets/javascript/@github--hotkey.js">
...
```

You can also specify which entry points to preload a particular dependency in by providing `preload:` a string or array of strings.

Example:

```ruby
# config/importmap.rb
pin "@github/hotkey", to: "@github--hotkey.js", preload: 'application'
pin "md5", preload: ['application', 'alternate']

# app/views/layouts/application.html.erb
<%= javascript_importmap_tags 'alternate' %>

# will include the following link before the importmap is setup:
<link rel="modulepreload" href="/assets/javascript/md5.js">
...
```



## Composing import maps

By default, Rails loads import map definition from the application's `config/importmap.rb` to the `Importmap::Map` object available at `Rails.application.importmap`.

You can combine multiple import maps by adding paths to additional import map configs to `Rails.application.config.importmap.paths`. For example, appending import maps defined in Rails engines:

```ruby
# my_engine/lib/my_engine/engine.rb

module MyEngine
  class Engine < ::Rails::Engine
    # ...
    initializer "my-engine.importmap", before: "importmap" do |app|
      app.config.importmap.paths << Engine.root.join("config/importmap.rb")
      # ...
    end
  end
end
```

And pinning JavaScript modules from the engine:

```ruby
# my_engine/config/importmap.rb

pin_all_from File.expand_path("../app/assets/javascripts", __dir__)
```


## Selectively importing modules

You can selectively import your javascript modules on specific pages.

Create your javascript in `app/javascript`:

```js
// /app/javascript/checkout.js
// some checkout specific js
```

Pin your js file:

```rb
# config/importmap.rb
# ... other pins...
pin "checkout", preload: false
```

Import your module on the specific page. Note: you'll likely want to use a `content_for` block on the specific page/partial, then yield it in your layout.

```erb
<% content_for :head do %>
  <%= javascript_import_module_tag "checkout" %>
<% end %>
```

**Important**: The `javascript_import_module_tag` should come after your `javascript_importmap_tags`

```erb
<%= javascript_importmap_tags %>
<%= yield(:head) %>
```


## Include a digest of the import map in your ETag

If you're using [ETags](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/ETag) generated by Rails helpers like `stale?` or `fresh_when`, you need to include the digest of the import map into this calculation. Otherwise your application will return [304](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/304) cache responses even when your JavaScript assets have changed. You can avoid this using the `stale_when_importmap_changes` method:

```ruby
class ApplicationController < ActionController::Base
  stale_when_importmap_changes
end
```

This will add the digest of the importmap to the etag calculation when the request format is HTML.


## Sweeping the cache in development and test

Generating the import map json and modulepreloads may require resolving hundreds of assets. This can take a while, so these operations are cached, but in development and test, we watch for changes to both `config/importmap.rb` and files in `app/javascript` to clear this cache. This feature can be controlled in an environment configuration file via the boolean `config.importmap.sweep_cache`.

If you're pinning local files from outside of `app/javascript`, you'll need to add them to the cache sweeper configuration or restart your development server upon changes to those external files. For example, here's how you can do it for Rails engine:

```ruby
# my_engine/lib/my_engine/engine.rb

module MyEngine
  class Engine < ::Rails::Engine
    # ...
    initializer "my-engine.importmap", before: "importmap" do |app|
      # ...
      app.config.importmap.cache_sweepers << Engine.root.join("app/assets/javascripts")
    end
  end
end
```

## Checking for outdated or vulnerable packages

Importmap for Rails provides two commands to check your pinned packages:
- `./bin/importmap outdated` checks the NPM registry for new versions. A [locked](#locking-a-package-at-a-version) package is listed with `yes` in the Locked column and doesn't make the command exit 1 — only an unlocked outdated package does.
- `./bin/importmap audit` checks the NPM registry for known security issues

## Supporting legacy browsers such as Safari on iOS 15

If you want to support [legacy browsers that do not support import maps](https://caniuse.com/import-maps) such as [iOS 15.8.1 released on 22 Jan 2024](https://support.apple.com/en-us/HT201222), insert [`es-module-shims`](https://github.com/guybedford/es-module-shims) before `javascript_importmap_tags` as below.

```erb
<script async src="https://ga.jspm.io/npm:es-module-shims@1.8.2/dist/es-module-shims.js" data-turbo-track="reload"></script>
<%= javascript_importmap_tags %>
```

## License

Importmap for Rails is released under the [MIT License](https://opensource.org/licenses/MIT).
