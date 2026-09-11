# docs-kit synced: v1.1.1
# frozen_string_literal: true

# docs-kit configuration — everything that makes this site look like
# "importmap-plus" rather than any other docs site. The shared chrome
# (Shell/Sidebar/ThemeSwitcher/Code/Page) comes from the gem; only this config
# differs per site. The `themes` MUST match the @plugin "daisyui" { themes: ... }
# block in app/assets/stylesheets/application.tailwind.css, or the switcher
# offers a theme the compiled CSS never generated.
Rails.application.config.to_prepare do
  DocsKit.configure do |c|
    c.brand        = "importmap-plus"
    c.title_suffix = "importmap-plus"

    # The one-line summary agents read first in /llms.txt (the llmstxt.org
    # blockquote under the H1).
    c.tagline = "A drop-in replacement for importmap-rails: the same Importmap:: API and " \
                "pins, plus bin/importmap pin --minify, --from esm.run for jsDelivr's " \
                "bundled builds, --lock to hold a package at a version, update by name, " \
                "and a pin comment that remembers where each package came from."

    c.themes = %w[dark light synthwave retro cyberpunk dracula night nord sunset]

    # The version badge in the sidebar header tracks the documented gem. A lambda
    # (not a String) so it re-reads Importmap::VERSION on every reload — the gem
    # is a path dependency of this app (Gemfile), and it IS the app's import map
    # gem, so the constant is always loaded.
    c.version_badge = -> { "v#{Importmap::VERSION}" }

    # Code blocks: a light base with a dark override, so the highlight stays
    # readable when the switcher lands on a dark daisyUI theme. CSS-only scoping
    # ([data-theme=X]) — no JS, no flash.
    c.code_theme      = "Rouge::Themes::Github"  # light themes
    c.code_theme_dark = "Rouge::Themes::Monokai" # dark themes

    # A link to the source repo in the topbar, rendered with the shipped GitHub
    # brand mark.
    c.topbar_links = [
      { href: "https://github.com/zoolutions/importmap-plus", label: "GitHub", icon: :github },
      { href: "https://rubygems.org/gems/importmap-plus", label: "RubyGems", icon: :rubygems }
    ]

    # SEO + social sharing. docs-kit emits the full <head> (description, Open
    # Graph, Twitter Card, canonical, favicon, theme-color) from these knobs.
    # og_image resolves through THIS site's asset pipeline (app/assets/images/) to
    # the digested /assets URL — regenerate the card with `bin/rails docs_kit:og`.
    c.seo.description  = "importmap-plus is a drop-in replacement for importmap-rails " \
                         "with better vendoring: minified downloads, esm.run bundles, " \
                         "version locks, update by package name, and pins that " \
                         "remember which CDN they came from."
    c.seo.site_url     = "https://importmap-plus.zoolutions.llc"
    c.seo.og_image     = "og/og.png"
    c.seo.og_type      = "website"
    c.seo.twitter_card = "summary_large_image"
    c.seo.twitter_site = "@mhenrixon"
    c.seo.locale       = "en_US"
    c.seo.theme_color  = "#1d232a" # daisyUI dark base-100 (themes.first)
    # favicon href is used verbatim (not through the asset pipeline), so it's a
    # public/ path served at a stable root URL — see public/favicon.svg.
    c.seo.favicon      = "/favicon.svg"

    # The landing page (app/views/landings/show.rb renders DocsUI::Landing) — a
    # hero + feature grid + a registry-grouped doc index, all from these knobs.
    # Wrap a run in **double asterisks** to accent it in the primary color.
    c.landing.eyebrow = "importmap-plus"
    c.landing.title   = "importmap-rails, with **vendoring that keeps its promises**."
    c.landing.lead    = "The same Importmap:: API, the same pins, the same import map. " \
                        "Plus minified downloads, jsDelivr's bundled builds, version " \
                        "locks, update by name, and pins that remember where they came " \
                        "from. Switch by changing one line in your Gemfile."
    c.landing.install = { code: 'gem "importmap-plus"', filename: "Gemfile", lexer: :ruby }
    c.landing.ctas = [
      { label: "Get started", href: "/docs/installation", style: :primary },
      { label: "GitHub", href: "https://github.com/zoolutions/importmap-plus", style: :ghost, icon: :github }
    ]
    c.landing.features = [
      { icon: "arrow-left-right", title: "Drop-in",
        body: "Same constants, same engine, same config/importmap.rb. An app already on importmap-rails changes one Gemfile line and nothing else." },
      { icon: "minimize-2", title: "Minified downloads",
        body: "pin --minify runs a vendored file through bun, esbuild or terser before it lands in vendor/javascript, and later updates keep minifying it." },
      { icon: "package", title: "esm.run bundles",
        body: "--from esm.run vendors jsDelivr's one-file bundle, rewrites its imports to bare specifiers, and pins the dependencies it needs." },
      { icon: "lock", title: "Version locks",
        body: "pin --lock holds a package at a version. update, pristine and pin leave it there until you unlock it or pass --force." },
      { icon: "refresh-cw", title: "Update by name",
        body: "update luxon stimulus-use re-pins just those. update --all says explicitly what a bare update has always done." },
      { icon: "map-pin", title: "Provenance that sticks",
        body: "The pin comment records the CDN, minification and lock, so an unpkg download never silently moves back to jspm on the next update." }
    ]

    # The sidebar nav derives from the registry — one heading → one registry.
    # Each registry's authored pages become NavItems automatically (an unwritten
    # page is skipped, so no dead links); the page `group:` values render as the
    # collapsible sub-groups. This also feeds the AI surfaces (/llms.txt,
    # /llms-full.txt, search, MCP) with zero extra code.
    c.nav_registries = { "Docs" => Doc }
  end
end
