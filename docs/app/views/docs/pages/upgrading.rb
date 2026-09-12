# frozen_string_literal: true

# What an app coming from importmap-rails sees change, and what it doesn't.
class Views::Docs::Pages::Upgrading < DocsUI::Page
  title "Upgrading from importmap-rails"
  eyebrow "Reference"

  def lead = "Swap the gem. Then read what bin/importmap will do differently the first time you run it."

  def content
    the_swap
    what_changes
    what_does_not
    going_back
  end

  private

  def the_swap
    DocsUI::Section("The swap") do
      DocsUI::Code(<<~RUBY, filename: "Gemfile")
        # gem "importmap-rails"
        gem "importmap-plus"
      RUBY
      DocsUI::Code(<<~SHELL, lexer: :shell)
        bundle install
      SHELL
      md <<~'MD'
        Nothing else. `config/importmap.rb`, `vendor/javascript`, `bin/importmap`,
        the layout helpers and every `Importmap::` constant are the same. importmap-plus
        tracks the importmap-rails release named in `Importmap::UPSTREAM_VERSION`;
        its own version is `Importmap::VERSION`.
      MD
      DocsUI::Callout(:warning, title: "Never both") do
        plain "The two gems define the same constants and the same engine. Remove importmap-rails from the Gemfile, and from any engine or gem of yours that depends on it, before adding importmap-plus."
      end
    end
  end

  def what_changes
    DocsUI::Section("What bin/importmap does differently") do
      DocsUI::Table(
        [ "In importmap-rails", "In importmap-plus" ],
        [
          [ "A remote pin (to: a CDN URL) is replaced with a download on the next pin or update of that package.", "A remote pin stays remote and is re-resolved from the CDN it points at. --from moves it." ],
          [ "A pin to a custom host is rewritten like any other.", "A pin to a host that isn't a known CDN is left untouched and reported as skipped." ],
          [ "preload: is dropped when a pin is rewritten.", "preload: and a boolean integrity: are kept. An integrity hash is dropped only when the URL changes." ],
          [ "A package vendored from unpkg moves back to jspm on update.", "The pin comment records the CDN; update and pristine go back to it." ],
          [ "update takes no arguments.", "update takes package names, --all and --force." ],
          [ "outdated exits 1 for any outdated package.", "outdated exits 1 only for an outdated package that isn't locked." ],
          [ "A failed CDN request is a raw backtrace.", "Requests are retried three times with a growing pause; the failure then names the URL." ]
        ]
      )
      md <<~'MD'
        The first `pin`, `update` or `pristine` you run may rewrite a pin comment —
        `pin "react" # @19.1.0 (unpkg)` where it used to say `# @19.1.0` — and
        that's a change you'll want to commit. Read
        [Provenance](/docs/provenance) for the grammar.
      MD
    end
  end

  def what_does_not
    DocsUI::Section("What doesn't change") do
      md <<~'MD'
        - The generated import map and the module preload links, byte for byte.
        - `pin`, `pin_all_from`, `enable_integrity!`, `preload:`, `integrity:`.
        - `config.importmap.paths`, `sweep_cache`, `cache_sweepers`, `rescuable_asset_errors`.
        - `Importmap::Map`, `Rails.application.importmap`, `stale_when_importmap_changes`.
        - `bin/importmap json`, `audit`, `packages`, `unpin`.
        - The pin comment format for a jspm download: `pin "react" # @19.1.0`.
      MD
    end
  end

  def going_back
    DocsUI::Section("Going back") do
      md <<~'MD'
        Swap the Gemfile line back. A pin comment with a parenthesised detail list is
        just a comment to importmap-rails; it reads the version and ignores the rest.
        The one thing you'd lose is the behaviour: the next `update` would treat your
        locks and CDN choices as importmap-rails always has.
      MD
    end
  end
end
