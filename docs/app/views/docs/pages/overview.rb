# frozen_string_literal: true

# What importmap-plus is, what it adds over importmap-rails, and the promise
# that everything else is unchanged.
class Views::Docs::Pages::Overview < DocsUI::Page
  title "Overview"
  eyebrow "Getting started"

  def lead = "A drop-in replacement for importmap-rails with vendoring that keeps its promises."

  def content
    what_it_is
    what_it_adds
    what_it_adds_at_request_time
    what_stays_the_same
    where_next
  end

  private

  def what_it_is
    DocsUI::Section("What it is") do
      md <<~'MD'
        [importmap-rails](https://github.com/rails/importmap-rails) lets a Rails app
        import JavaScript modules by logical name, straight from the browser, with
        no bundler. importmap-plus is that gem, forked, with the vendoring story
        finished: `bin/importmap` downloads what you ask for, remembers where it
        came from, minifies it when you say so, and leaves alone what you have
        locked.

        The `Importmap::` constants, the `pin` DSL, `config/importmap.rb`, the view
        helpers and the generated import map are unchanged. An app switches by
        replacing one line in its Gemfile. The importmap-rails release this tracks
        is in `Importmap::UPSTREAM_VERSION`.
      MD

      DocsUI::Callout(:warning, title: "One or the other") do
        plain "Install importmap-plus or importmap-rails, never both — they define the same "
        code { "Importmap::" }
        plain " constants and the same Rails engine."
      end
    end
  end

  def what_it_adds
    DocsUI::Section("What it adds", description: "Everything below is bin/importmap; the runtime is untouched.") do
      DocsUI::Table(
        [ "Feature", "What it does", "Docs" ],
        [
          [ [ :code, "pin --minify" ], "Runs a download through bun, esbuild or terser before it lands in vendor/javascript; later updates keep minifying.", [ :md, "[Minifying](/docs/minifying)" ] ],
          [ [ :code, "--from esm.run" ], "Vendors jsDelivr's one-file bundle, rewrites its imports to bare specifiers, and pins the dependencies it needs.", [ :md, "[esm.run bundles](/docs/esm-run)" ] ],
          [ [ :code, "pin --lock" ], "Holds a package at a version. update, pristine and pin leave it there until you unlock it or pass --force.", [ :md, "[Locking versions](/docs/locking)" ] ],
          [ [ :code, "update [PACKAGES] --all --force" ], "Update by name, or everything explicitly; --force moves locked packages and re-locks them.", [ :md, "[Updating & auditing](/docs/updating)" ] ],
          [ "Multi-file packages", "A package whose entry imports siblings is vendored with its whole file graph; one that needs more than files can give it stays on its CDN, with the reason on the pin.", [ :md, "[Multi-file packages](/docs/multi-file-packages)" ] ],
          [ "Registry-latest and CDN fallback", "A version is resolved on the npm registry first, then asked of jspm, esm.run and jsDelivr in turn until one of them has it.", [ :md, "[Pinning packages](/docs/pinning#choosing-a-cdn)" ] ],
          [ [ :code, "doctor" ], "Checks the import map against the files that are actually there, offline, and exits non-zero on an error, so CI can run it.", [ :md, "[Updating & auditing](/docs/updating#doctor)" ] ],
          [ "Provenance", "The pin comment records the CDN, minification and lock, so nothing silently drifts back to jspm.", [ :md, "[Provenance](/docs/provenance)" ] ],
          [ "Remote pins stay remote", "A pin with a CDN URL is re-resolved from that CDN; preload: and boolean integrity: survive every rewrite.", [ :md, "[Pinning packages](/docs/pinning)" ] ],
          [ "Remote pins hash themselves", "A pin left on a CDN carries a subresource-integrity hash of the bytes that were resolved, rewritten whenever the URL moves.", [ :md, "[Subresource integrity](/docs/integrity)" ] ],
          [ "Requests retry", "A reset connection, a timeout or a 429/5xx is tried three times with a growing pause before the command gives up.", [ :md, "[Configuration](/docs/configuration)" ] ]
        ]
      )
    end
  end

  def what_it_adds_at_request_time
    DocsUI::Section("What it adds at request time",
                    description: "Two opt-in settings; the tags are otherwise byte-for-byte upstream's.") do
      DocsUI::Table(
        [ "Setting", "What it does", "Docs" ],
        [
          [ [ :code, "preload_strategy = :reachable" ], "Preloads what the entry point actually imports instead of every preloaded pin, so a package a page never reaches costs nothing.", [ :md, "[Preloading](/docs/preloading#preloading-what-the-page-reaches)" ] ],
          [ [ :code, "early_hints" ], "Sends the modulepreload links as a 103 Early Hints response, so the browser starts fetching them before the HTML is rendered.", [ :md, "[Preloading](/docs/preloading#103-early-hints)" ] ]
        ]
      )
    end
  end

  def what_stays_the_same
    DocsUI::Section("What stays the same") do
      md <<~'MD'
        The parts of importmap-rails you build on are exactly as upstream ships them:

        - `pin`, `pin_all_from` and `enable_integrity!` in `config/importmap.rb`,
        - `javascript_importmap_tags` and `javascript_import_module_tag` in your layouts,
        - `Rails.application.importmap`, `Importmap::Map`, the cache sweeper and the reloader,
        - `Rails.application.config.importmap.*`,
        - `bin/importmap json`, `audit`, `outdated`, `packages`, `unpin` and `pristine`.

        Those pages of these docs are importmap-rails' own documentation, kept in step
        with the upstream release this gem tracks.
      MD
    end
  end

  def where_next
    DocsUI::Section("Where next") do
      md <<~'MD'
        - New app, or an app on importmap-rails today: [Installation](/docs/installation).
        - Coming from importmap-rails and wondering what changes: [Upgrading from importmap-rails](/docs/upgrading).
        - Every command and flag on one page: [CLI reference](/docs/cli).
      MD
    end
  end
end
