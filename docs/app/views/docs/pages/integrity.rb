# frozen_string_literal: true

# Subresource Integrity: enable_integrity!, automatic hashes for local assets,
# explicit hashes for CDN packages, and what ends up in the import map.
class Views::Docs::Pages::Integrity < DocsUI::Page
  title "Subresource integrity"
  eyebrow "Serving"

  def lead = "Integrity hashes in the import map and the preload links, so the browser refuses a module that was tampered with."

  def content
    enabling
    remote_pins
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

  def remote_pins
    DocsUI::Section("Remote pins hash themselves", description: "bin/importmap computes the hash of a pin it leaves on a CDN.") do
      md <<~'MD'
        A vendored file is served by your app; a remote pin is fetched from a CDN on
        every page load, and it is the one place the app trusts a third party at
        runtime. So when `bin/importmap` writes a pin that stays remote — `--remote`,
        or a package [kept remote](/docs/pinning) because its file can't stand alone —
        it fetches the URL it just resolved, hashes those bytes and writes the hash
        with the pin:
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin md5@2.2.0 --remote
        Pinning "md5" to https://ga.jspm.io/npm:md5@2.2.0/md5.js (integrity sha384-+wqk6m3DPZ6mVMgVZlXnGgDjDY2skGEZ3U9tBnRHiPJXLRLKBmYkKlX2urz9T61b)
      SHELL
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "md5", to: "https://ga.jspm.io/npm:md5@2.2.0/md5.js", integrity: "sha384-+wqk6m3DPZ6mVMgVZlXnGgDjDY2skGEZ3U9tBnRHiPJXLRLKBmYkKlX2urz9T61b"
      RUBY
      md <<~'MD'
        The hash is `sha384` of the bytes the CDN served, computed by this gem rather
        than asked of any one CDN, so every provider — jspm, esm.run, jsDelivr, unpkg,
        esm.sh, skypack — is hashed the same way. `update` and a later `pin` fetch the
        new URL and rewrite the hash, so the pin never carries a hash for a file it no
        longer points at.

        Writing the hash is not the same as sending it to the browser: like every other
        integrity value, it reaches the import map only when `config/importmap.rb` calls
        `enable_integrity!`. Without that call the pin still records it and nothing is
        rendered.

        Two ways to turn it off. `integrity: false` on the pin is your decision and
        survives every rewrite, hash included. `--no-integrity` skips the fetch for this
        run and writes no hash — for a CDN that serves different bytes per request
        (a compression or edge variant would fail the check in the browser), or when the
        extra request per remote pin isn't wanted.
      MD
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin md5@2.2.0 --remote --no-integrity
        Pinning "md5" to https://ga.jspm.io/npm:md5@2.2.0/md5.js
      SHELL
      md <<~'MD'
        Vendored downloads are untouched by all of this: their hash is the asset
        pipeline's to compute from the file in `vendor/javascript`, which `integrity:
        true` — the default on every pin — already does.
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
        rewrite by `pin`, `update` or `pristine` the way `preload:` does — with one
        exception: `integrity: true` on a remote pin asks the asset pipeline to hash a
        URL, which it can't, so a rewrite replaces it with the computed hash. An
        explicit hash string belongs to one particular file, so it never survives a
        change of URL — the old hash would no longer match. On a remote pin a fresh
        hash is computed and written in its place (`--no-integrity` says so when it
        drops one instead); on any other pin the option is simply gone, and a hash you
        wrote by hand has to be written again.
      MD
    end
  end
end
