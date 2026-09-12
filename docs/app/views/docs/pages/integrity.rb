# frozen_string_literal: true

# Subresource Integrity: enable_integrity!, automatic hashes for local assets,
# explicit hashes for CDN packages, and what ends up in the import map.
class Views::Docs::Pages::Integrity < DocsUI::Page
  title "Subresource integrity"
  eyebrow "Serving"

  def lead = "Integrity hashes in the import map and the preload links, so the browser refuses a module that was tampered with."

  def content
    enabling
    propshaft
    how_it_renders
    on_rewrite
  end

  private

  def enabling
    DocsUI::Section("Enabling integrity", description: "Opt in globally, then control it per pin.") do
      md <<~'MD'
        Integrity calculation is off until you call `enable_integrity!` in
        `config/importmap.rb`. With it on, `integrity: true` (the default for every
        pin) computes a hash for each local asset through the asset pipeline;
        `integrity: "sha384-…"` uses the value you give; `integrity: false` or `nil`
        turns it off for that pin.
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        # Enable integrity calculation globally
        enable_integrity!

        # With integrity enabled, these auto-calculate integrity hashes
        pin "application"                                               # auto-calculated
        pin "admin", to: "admin.js"                                     # auto-calculated
        pin_all_from "app/javascript/controllers", under: "controllers" # auto-calculated

        # Explicit control
        pin "cdn_package", to: "https://cdn.example.com/cdn_package.js", integrity: "sha384-abc123..." # pre-calculated hash
        pin "no_integrity_package", integrity: false     # explicitly disabled
        pin "nil_integrity_package", integrity: nil      # explicitly disabled
      RUBY
      md <<~'MD'
        This is particularly useful for local JavaScript files managed by the asset
        pipeline, for bulk `pin_all_from` pins where computing hashes by hand would
        be tedious, and in development where file contents change often. External
        CDN packages should provide their own hashes.
      MD
    end
  end

  def propshaft
    DocsUI::Section("Propshaft") do
      md <<~'MD'
        SRI needs Propshaft 1.2+ and an integrity hash algorithm configured in your
        application; without it integrity is disabled by default under Propshaft.
        Sprockets has integrity support out of the box.
      MD
      DocsUI::Code(<<~RUBY, filename: "config/application.rb")
        config.assets.integrity_hash_algorithm = "sha256" # or "sha384", "sha512"
      RUBY
    end
  end

  def how_it_renders
    DocsUI::Section("What the browser gets") do
      md <<~'MD'
        The hashes are included in the import map's `integrity` section and on each
        module preload link, and the browser validates them as it loads the modules:
      MD
      DocsUI::Code(<<~JSON, lexer: :json)
        {
          "imports": {
            "lodash": "https://ga.jspm.io/npm:lodash@4.17.21/lodash.js",
            "application": "/assets/application-abc123.js",
            "controllers/hello_controller": "/assets/controllers/hello_controller-def456.js"
          },
          "integrity": {
            "https://ga.jspm.io/npm:lodash@4.17.21/lodash.js": "sha384-PkIkha4kVPRlGtFantHjuv+Y9mRefUHpLFQbgOYUjzy247kvi16kLR7wWnsAmqZF",
            "/assets/application-abc123.js": "sha256-xyz789...",
            "/assets/controllers/hello_controller-def456.js": "sha256-uvw012..."
          }
        }
      JSON
      DocsUI::Code(<<~HTML, lexer: :html)
        <link rel="modulepreload" href="https://ga.jspm.io/npm:lodash@4.17.21/lodash.js" integrity="sha384-PkIkha4kVPRlGtFantHjuv+Y9mRefUHpLFQbgOYUjzy247kvi16kLR7wWnsAmqZF">
        <link rel="modulepreload" href="/assets/application-abc123.js" integrity="sha256-xyz789...">
      HTML
    end
  end

  def on_rewrite
    DocsUI::Section("When bin/importmap rewrites a pin") do
      md <<~'MD'
        `integrity: true` and `integrity: false` are settings, and they survive a
        rewrite by `pin`, `update` or `pristine` the way `preload:` does. An explicit
        hash string belongs to one particular file, so it is dropped when the URL
        changes — the old hash would no longer match. Pin a fresh hash after an
        update of a remote pin that carried one.
      MD
    end
  end
end
