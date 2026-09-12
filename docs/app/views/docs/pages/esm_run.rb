# frozen_string_literal: true

# --from esm.run: jsDelivr's bundled builds, the import rewrite, and how the
# bundle's dependencies get pinned.
class Views::Docs::Pages::EsmRun < DocsUI::Page
  title "esm.run bundles"
  eyebrow "Vendoring"

  def lead = "jsDelivr serves one minified ES module per package, whatever the package ships on npm. --from esm.run vendors it."

  def content
    what_esm_run_is
    dependencies
    versions_and_subpaths
    remote
  end

  private

  def what_esm_run_is
    DocsUI::Section("Bundles instead of dist files") do
      md <<~'MD'
        [esm.run](https://www.jsdelivr.com/esm) is jsDelivr's bundling endpoint. Where
        jspm hands you a package's own `dist` file — unminified for plenty of
        packages, and split across several files for some — esm.run gives you one
        bundle, built with esbuild and minified:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin luxon --from esm.run
        Pinning "luxon" to vendor/javascript/luxon.js via download from https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "luxon" # @3.7.2 (esm.run)
      RUBY
      md <<~'MD'
        The CDN is recorded in the pin comment, so `update` and `pristine` fetch the
        bundle again rather than jspm's file. See [Provenance](/docs/provenance).
      MD
    end
  end

  def dependencies
    DocsUI::Section("Dependencies") do
      md <<~'MD'
        A bundle references the packages it depends on as absolute
        `/npm/dep@1.2.3/+esm` imports, which only resolve on jsDelivr. When the
        bundle is vendored those imports are rewritten to bare specifiers —
        `import { Controller } from "@hotwired/stimulus"` — so they resolve through
        your import map, and every dependency without a pin is pinned the same way:
        vendored from esm.run, at the version the bundle was built against.
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin stimulus-use --from esm.run
        Pinning "stimulus-use" to vendor/javascript/stimulus-use.js via download from https://cdn.jsdelivr.net/npm/stimulus-use@0.53.1/+esm
        Keeping existing pin for "@hotwired/stimulus" (bundle was built against @3.2.2)
      SHELL
      md <<~'MD'
        A dependency you already pin is left alone: the bundle then resolves to
        whatever your import map says, exactly as a jspm download would. If a bundle
        imports the same package at two versions, the first one wins and the command
        says so — an import map holds one version per specifier.
      MD
      DocsUI::Callout(:note) do
        plain "The rewrite is lexical, not a JavaScript parser: it matches import or from followed by a quoted /npm/…/+esm specifier, so the same text inside a string or a comment would be rewritten too. In practice that doesn't come up — a jsDelivr bundle is esbuild output whose only surviving comment is the banner, and a root-relative /npm/ URL is meaningless anywhere but in one of its own imports."
      end
    end
  end

  def versions_and_subpaths
    DocsUI::Section("Versions and subpaths") do
      md <<~'MD'
        Versions resolve through jsDelivr's data API, so a range and a subpath work
        the way they do on npm:
      MD
      DocsUI::Code(<<~SHELL, lexer: :shell)
        ./bin/importmap pin luxon@3 --from esm.run
        ./bin/importmap pin apexcharts/core --from esm.run
      SHELL
    end
  end

  def remote
    DocsUI::Section("Without vendoring") do
      md <<~'MD'
        With `--from esm.run --remote` the pin points at the bundle URL and its
        imports load from jsDelivr as-is — no rewrite, no dependency pins:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "luxon", to: "https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm"
      RUBY
    end
  end
end
