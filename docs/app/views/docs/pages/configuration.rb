# frozen_string_literal: true

# Rails.application.config.importmap.* and the Importmap::Packager knobs.
class Views::Docs::Pages::Configuration < DocsUI::Page
  title "Configuration"
  eyebrow "Reference"

  def lead = "The application config the engine reads, and the class-level settings bin/importmap reads."

  def content
    app_config
    packager_config
    retries
  end

  private

  def app_config
    DocsUI::Section("config.importmap", description: "Set in config/application.rb or an environment file.") do
      DocsUI::PropTable(
        [
          [ [ :code, "paths" ], "Array<Pathname>", "[]", "Import map files, drawn in order. The engine appends config/importmap.rb during initialization, so files added in application.rb or an environment file are drawn before it; engines append theirs here." ],
          [ [ :code, "sweep_cache" ], "Boolean", "true in development and test", "Watch the JavaScript directories and clear the rendered map when a file changes. Only takes effect when classes are reloadable." ],
          [ [ :code, "cache_sweepers" ], "Array<Pathname>", "[] — app/javascript and vendor/javascript are added when the watcher is installed", "The directories the watcher covers, read once when sweep_cache is on and classes are reloadable. Engines append their JavaScript directories before importmap.cache_sweeper runs." ],
          [ [ :code, "rescuable_asset_errors" ], "Array<Class>", "the pipeline's missing-asset error", "Errors that make a pin resolve to nothing (and log a warning) instead of raising. Propshaft::MissingAssetError and Sprockets' AssetNotFound are added for you." ],
          [ [ :code, "preload_strategy" ], "Symbol", ":all", "Which preload: true pins get a modulepreload link. :all is every one of them, upstream's behaviour. :reachable is only those the entry point reaches through static imports — see Preloading. A pin naming an entry point, and preload: false, mean the same under both." ],
          [ [ :code, "early_hints" ], "Boolean", "true", "Send the modulepreload links javascript_importmap_tags is about to emit as a 103 Early Hints Link header. A no-op unless the server supports it (Puma needs early_hints true) — see Preloading." ]
        ]
      )
      DocsUI::Code(<<~RUBY, filename: "config/application.rb")
        config.importmap.sweep_cache = true
        config.importmap.cache_sweepers << Rails.root.join("lib/javascript")
      RUBY
    end
  end

  def packager_config
    DocsUI::Section("Importmap::Packager", description: "Class-level settings read by bin/importmap.") do
      md <<~'MD'
        `bin/importmap` loads `config/application.rb` but not your initializers, so
        these are set there (or in a file it requires), after
        `require "importmap/packager"`.
      MD
      DocsUI::PropTable(
        [
          [ [ :code, "minifier" ], "#call(source) → String", "the first of bun, esbuild, terser found", "What --minify runs a download through." ],
          [ [ :code, "retry_attempts" ], "Integer", "3", "How many times a CDN or registry request is tried." ],
          [ [ :code, "retry_wait" ], "Numeric", "0.5", "Seconds between tries, multiplied by the attempt number." ],
          [ [ :code, "endpoint" ], "URI", "https://api.jspm.io/generate", "The JSPM generator API." ],
          [ [ :code, "esm_run_resolver" ], "URI", "https://data.jsdelivr.com/v1/packages/npm/", "The jsDelivr data API --from esm.run resolves versions through." ]
        ]
      )
      DocsUI::Code(<<~RUBY, filename: "config/application.rb")
        require "importmap/packager"

        Importmap::Packager.minifier      = ->(source) { MyMinifier.minify(source) }
        Importmap::Packager.retry_attempts = 5
        Importmap::Packager.retry_wait     = 2
      RUBY
      md <<~'MD'
        `Importmap::Npm.base_uri` (default `https://registry.npmjs.org`) is where
        `outdated`, `update` and `audit` ask about versions and advisories; point it
        at a mirror if your network needs one.
      MD
    end
  end

  def retries
    DocsUI::Section("Retries") do
      md <<~'MD'
        CDNs reset connections and rate-limit bursts. A reset connection, a timeout
        or a 429, 500, 502, 503 or 504 from a CDN or the registry is tried
        `retry_attempts` times, pausing `retry_wait × attempt` seconds between
        tries, before `bin/importmap` gives up. A transport failure then says which
        request it was making; an HTTP error reports the status, or the message the
        service returned. A 404 is not retried: the package isn't there.
      MD
    end
  end
end
