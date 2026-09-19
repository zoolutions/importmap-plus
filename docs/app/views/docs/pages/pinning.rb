# frozen_string_literal: true

# bin/importmap pin: vendoring from a CDN, choosing the CDN, pinning to a
# remote URL, and what happens to a pin's options on a rewrite.
class Views::Docs::Pages::Pinning < DocsUI::Page
  title "Pinning packages"
  eyebrow "Vendoring"

  def lead = "bin/importmap pin resolves a package on a CDN, downloads it to vendor/javascript and writes the pin."

  def content
    vendoring
    resolving_a_version
    choosing_a_cdn
    multi_file_packages
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

  def resolving_a_version
    DocsUI::Section("The version a bare name gets",
                    description: "Resolved against the npm registry before any CDN is asked.") do
      md <<~'MD'
        `pin react` means the latest React, and the npm registry is what knows which
        that is. A CDN answers with the latest version it has got round to indexing,
        which can lag npm by hours or by a major release, so the version is resolved
        first and every CDN is then asked for that exact one:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin md5
        Resolved "md5" to 2.3.0 from the npm registry
        Pinning "md5" to vendor/javascript/md5.js via download from https://ga.jspm.io/npm:md5@2.3.0/md5.js
      SHELL
      md <<~'MD'
        A spec that names a version — `pin luxon@3.7.2`, `pin react@18` — is passed
        through untouched, and so is one the registry couldn't be asked about: the
        CDN then chooses, as it always did. Nothing else changes, and `outdated`
        already read the same registry.
      MD
    end
  end

  def choosing_a_cdn
    DocsUI::Section("Choosing a CDN") do
      md <<~'MD'
        A package that names no CDN of its own is asked of three, in order: jspm,
        then `esm.run`, then jsDelivr. jspm is first because its generator builds an
        ES module for packages that ship none — which is the thing an import map
        needs, and the reason it is the default. That same generator also gives up
        on packages it can't build, and when it does it says why:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin mermaid@10.6.0
        jspm couldn't resolve "mermaid@10.6.0" (No './dist/cytoscape.umd.js' exports subpath defined in cytoscape@3.34.3); trying esm.run
        Pinning "mermaid" to vendor/javascript/mermaid.js via download from https://cdn.jsdelivr.net/npm/mermaid@10.6.0/+esm
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "mermaid" # @10.6.0 (esm.run)
      RUBY
      md <<~'MD'
        That is a fact about the generator, not about the package: jsDelivr publishes
        a bundle of the very same version. The CDN that answered is recorded in the
        pin comment, so `update` and `pristine` go straight back to it and never
        retry the jspm that couldn't build it. Nothing new is stored anywhere else.

        If no CDN in the chain has the package, each one's reason is printed and the
        command says so:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin no-such-package
        jspm couldn't resolve "no-such-package" (Unable to resolve npm:no-such-package@ to a valid version); trying esm.run
        esm.run couldn't resolve "no-such-package"; trying jsdelivr
        jsdelivr couldn't resolve "no-such-package" (Unable to resolve npm:no-such-package@ to a valid version)
        Couldn't find any packages in ["no-such-package"] on jspm, esm.run or jsdelivr
      SHELL
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
        `--from` is a choice you made, so it is asked once and never falls back: the
        CDN you named either has the package or reports why it hasn't. The same goes
        for a package whose pin already records a CDN.

        The CDN is recorded in the pin comment when it isn't jspm, and later commands
        go back to it — an unpkg download stays on unpkg through `update` and
        `pristine`. Pass `--from` again to move a package to another CDN. See
        [Provenance](/docs/provenance).
      MD
    end
  end

  def multi_file_packages
    DocsUI::Section("Packages that need more than one file",
                    description: "Vendored with their file graph, or kept on the CDN with the reason on the pin.") do
      md <<~'MD'
        Not every package can be served as the single file an import map entry points
        at. `pin` reads every download before it writes one, and a package whose entry
        imports siblings by relative path is vendored together with the files it
        needs; one that spawns a worker, reads `import.meta.url`, computes an
        `import()` or fetches a `.wasm` is left on its CDN, with the reason recorded
        on the pin:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8
        pin_all_from "vendor/javascript/@popperjs--core", under: "@popperjs/core", to: "@popperjs--core" # @2.11.8 (graph of @popperjs/core)

        pin "fflate", to: "https://ga.jspm.io/npm:fflate@0.8.2/esm/browser.js" # @0.8.2 (remote: workers)
      RUBY
      md <<~'MD'
        [Multi-file packages](/docs/multi-file-packages) is the whole story: what the
        check looks for, how the file graph is vendored and mapped, when a package
        stays remote, and how `--vendor` and `doctor` fit around it.
      MD
    end
  end

  def remote_pins
    DocsUI::Section("Pinning to a remote URL", description: "--remote pins the CDN URL instead of vendoring a download.") do
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin react --remote
        Pinning "react" to https://ga.jspm.io/npm:react@19.1.0/index.js (integrity sha384-TtdSzSbIb/Umu/UA9WoDsfoMftva85E4FjTOLHn7E6GcaWaHx3METoF40cBklJJj)
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "react", to: "https://ga.jspm.io/npm:react@19.1.0/index.js", integrity: "sha384-TtdSzSbIb/Umu/UA9WoDsfoMftva85E4FjTOLHn7E6GcaWaHx3METoF40cBklJJj"
      RUBY
      md <<~'MD'
        The URL is fetched once to hash it, so the pin carries a
        [subresource-integrity](/docs/integrity) hash of the bytes the browser will
        get; `--no-integrity` skips that, and `enable_integrity!` is what puts the
        hash on the page.

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
