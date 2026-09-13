# frozen_string_literal: true

# bin/importmap pin: vendoring from a CDN, choosing the CDN, pinning to a
# remote URL, and what happens to a pin's options on a rewrite.
class Views::Docs::Pages::Pinning < DocsUI::Page
  title "Pinning packages"
  eyebrow "Vendoring"

  def lead = "bin/importmap pin resolves a package on a CDN, downloads it to vendor/javascript and writes the pin."

  def content
    vendoring
    choosing_a_cdn
    cant_be_vendored_alone
    remote_pins
    custom_urls
    options_survive
  end

  private

  def vendoring
    DocsUI::Section("Vendoring from a CDN") do
      md <<~'MD'
        `bin/importmap` pins, unpins and updates npm packages in your import map. By
        default it asks [JSPM](https://jspm.org)'s API to resolve a package and its
        dependencies, downloads each file and adds the pins to `config/importmap.rb`:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin react
        Pinning "react" to vendor/javascript/react.js via download from https://ga.jspm.io/npm:react@19.1.0/index.js
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "react" # @19.1.0
      RUBY
      md <<~'MD'
        The files land in `vendor/javascript`, which you check into source control;
        the asset pipeline serves them like any other asset. A package with a `/` in
        its name is stored with `--` instead (`@hotwired/stimulus` becomes
        `@hotwired--stimulus.js`) and the pin gets a `to:` pointing at that file.

        A version goes in the spec: `pin react@18`, `pin luxon@3.7.2`. A subpath works
        the way it does on npm: `pin apexcharts/core`.

        To remove a downloaded pin and its file:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap unpin react
        Unpinning and removing "react"
      SHELL
    end
  end

  def choosing_a_cdn
    DocsUI::Section("Choosing a CDN") do
      md <<~'MD'
        Other CDNs are one flag away. `--from` takes `jspm` (the default), `unpkg`,
        `jsdelivr`, `esm.sh`, `skypack`, or `esm.run` for jsDelivr's bundled builds
        (see [esm.run bundles](/docs/esm-run)):
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin react --from unpkg
        Pinning "react" to vendor/javascript/react.js via download from https://unpkg.com/react@19.1.0/index.js

        $ ./bin/importmap pin react --from jsdelivr
        Pinning "react" to vendor/javascript/react.js via download from https://cdn.jsdelivr.net/npm/react@19.1.0/index.js
      SHELL
      md <<~'MD'
        The CDN is recorded in the pin comment when it isn't jspm, and later commands
        go back to it — an unpkg download stays on unpkg through `update` and
        `pristine`. Pass `--from` again to move a package to another CDN. See
        [Provenance](/docs/provenance).
      MD
    end
  end

  def cant_be_vendored_alone
    DocsUI::Section("Packages that can't be vendored alone",
                    description: "Pinned to the CDN instead of downloaded, with the reason on the pin.") do
      md <<~'MD'
        A vendored package is exactly one file, served under a digested asset path.
        Plenty of packages ship a file that expects the rest of the package beside
        it — it imports a sibling by relative path, spawns a worker, or reads
        `import.meta.url` to find its own directory. Downloaded on its own, every one
        of those references 404s in the browser, and you find out on the page.

        `pin` reads what it downloaded before writing anything to
        `vendor/javascript`. A file that can't stand alone is pinned to its CDN URL
        instead, and the pin comment records why:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin @popperjs/core@2.11.8
        Pinning "@popperjs/core" to https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js (kept remote: relative imports)
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports)
      RUBY
      md <<~'MD'
        From then on the pin behaves like any other remote pin: `pin` and `update`
        re-resolve it from the same CDN and keep the reason, and `pristine` skips it.
        The vendored file an app already has is never removed by a refusal — the
        download is inspected before anything on disk is touched.

        Five things are looked for, and all of them are reported:
      MD
      DocsUI::Table(
        [ "Reason", "What was found" ],
        [
          [ [ :code, "relative imports" ], [ :md, 'An `import` or `export` from `"./x"` or `"../x"` — a sibling file that was never downloaded.' ] ],
          [ [ :code, "dynamic imports" ], [ :md, "An `import()` of something other than a string literal, so what it loads isn't knowable here." ] ],
          [ [ :code, "workers" ], [ :md, "`new Worker(…)` or `new SharedWorker(…)`. A worker is fetched as its own script and never goes through the import map." ] ],
          [ [ :code, "import.meta.url" ], [ :md, "The file asking for its own URL, which is a digested asset path, not the directory the package was published to." ] ],
          [ [ :code, "wasm" ], [ :md, "A string naming a `.wasm` binary, fetched at runtime from a path that isn't there." ] ]
        ]
      )
      md <<~'MD'
        The check reads the source with regular expressions rather than parsing
        JavaScript. Block comments are discounted first — a published bundle is full
        of `/** @typedef {import('./slide.js').Slide} Slide */`, naming files it
        never loads — but string literals are read as they stand, so a package that
        merely mentions `"./x.js"` in a string is kept remote too.

        That asymmetry is deliberate, because the two mistakes are not equal: a
        package wrongly kept remote still works, while one wrongly vendored 404s in
        the browser. When you know better, `--vendor` downloads it anyway:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin @popperjs/core@2.11.8 --vendor
        Pinning "@popperjs/core" to vendor/javascript/@popperjs/core.js via download from https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8 (vendored)
      RUBY
      md <<~'MD'
        The sentence names the package, `@popperjs/core`, while the file on disk is
        `@popperjs--core.js` — a `/` in a package name becomes `--`, as the pin's
        `to:` shows.

        `--vendor` also converts a pin that was kept remote back to a download. The
        `vendored` mark is what makes the override stick: without it the next
        `update` would inspect the new download, refuse it again and quietly undo
        your decision.

        Packages an app already vendored before this check existed are not rewritten
        on their own, and `bin/importmap pristine` downloads them again exactly as
        their pins say. The next `pin` or `update` that touches one does re-resolve
        it, though, and converts it if its file can't stand alone — which is the fix
        arriving rather than a surprise, since that vendored file was already
        404ing for the siblings it wanted.
      MD
    end
  end

  def remote_pins
    DocsUI::Section("Pinning to a remote URL", description: "--remote pins the CDN URL instead of vendoring a download.") do
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin react --remote
        Pinning "react" to https://ga.jspm.io/npm:react@19.1.0/index.js
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "react", to: "https://ga.jspm.io/npm:react@19.1.0/index.js"
      RUBY
      md <<~'MD'
        A remote pin is respected from then on, no flag needed. When the package is
        pinned again or picked up by `update` — directly or as a dependency of
        another package — the pin stays remote: the URL is re-resolved from the CDN
        provider it already points at (`ga.jspm.io`, `unpkg.com`, `cdn.jsdelivr.net`,
        `cdn.skypack.dev` or `esm.sh`) instead of being replaced with a download.
        `pristine` skips remote pins, since there is nothing to redownload.

        An explicit `--from` moves a remote pin to that CDN; without it the current
        provider wins. `--remote` on a package that is vendored today converts it:
        the pin gets the URL and the file in `vendor/javascript` is removed.
      MD
    end
  end

  def custom_urls
    DocsUI::Section("Custom URLs") do
      md <<~'MD'
        A pin pointing at any other host is yours: `pin` and `update` leave it
        completely untouched and report it as skipped.
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin md5
        Skipping "md5" pinned to custom URL https://cdn.example.com/md5.js
      SHELL
    end
  end

  def options_survive
    DocsUI::Section("Pin options survive a rewrite") do
      md <<~'MD'
        When a pin is rewritten — by `pin`, `update` or `pristine` — the options on
        it are carried over: `preload: false`, `preload: "admin"`, `integrity: true`
        and `integrity: false` all stay. An explicit `integrity:` *hash* is dropped
        when the URL changes, since the old hash would no longer match the new file;
        see [Subresource integrity](/docs/integrity) for pinning fresh hashes.

        Pins that a resolution touches only as dependencies keep their options the
        same way. Pinning `md5` re-resolves `charenc` and `crypt` with it, but a
        `pin "crypt", preload: false` you wrote stays `preload: false`.
      MD
    end
  end
end
