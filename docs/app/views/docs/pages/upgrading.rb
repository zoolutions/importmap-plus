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
          [ "A failed CDN request is a raw backtrace.", "Requests are retried three times with a growing pause; the failure then names the URL." ],
          [ "A download that imports sibling files, spawns a worker or fetches a .wasm is vendored anyway and 404s in the browser.", "It is pinned to its CDN URL instead, the pin says why, and pin --vendor overrides. See below." ],
          [ "pin asks jspm and nothing else; a package its generator can't build reports \"Couldn't find any packages\".", "jspm, then esm.run, then jsDelivr, until one answers. The CDN that did is recorded on the pin. --from turns the fallback off." ],
          [ "pin foo takes whatever version jspm has indexed.", "The npm registry decides the version, then every CDN is asked for that one." ],
          [ "A CDN that hands back a UMD bundle is vendored, and the import fails to link in the browser.", "It is pinned to its CDN URL with (remote: not an ES module). pin --vendor overrides." ]
        ]
      )
      md <<~'MD'
        The first `pin`, `update` or `pristine` you run may rewrite a pin comment —
        `pin "react" # @19.1.0 (unpkg)` where it used to say `# @19.1.0` — and
        that's a change you'll want to commit. Read
        [Provenance](/docs/provenance) for the grammar.

        ### Packages that ship more than one file

        A package whose entry imports a sibling by relative path — `@popperjs/core`,
        `date-fns`, `lodash-es` — is vendored whole: the next `pin` or `update` that
        touches it downloads the files it imports into a directory beside it and adds
        one `pin_all_from` line mapping them. A pin importmap-plus had kept remote
        for that reason is converted back to a download by the same command, on the
        CDN its URL names. See
        [Vendoring the file graph](/docs/multi-file-packages#vendoring-the-file-graph).

        ### Packages you vendored that can't stand alone

        Some packages you have in `vendor/javascript` today will be kept remote the
        next time `pin` or `update` touches them — pdf.js is the usual one: its main
        file spawns a `Worker` and its worker fetches `.wasm` decoders beside itself.
        `update` prints the reason and the pin becomes
        `pin "pdfjs-dist", to: "https://cdn.jsdelivr.net/…" # @6.3.289 (remote: dynamic imports)`.

        Nothing is rewritten until you run one of those commands: until then
        `pristine` keeps redownloading the file exactly as the pin says. Afterwards
        the pin is a remote pin like any other, so `pristine` skips it — there is no
        longer a vendored file to restore — and the vendored one is removed.

        If the vendored file worked for you — you configure the worker URL yourself,
        say — `bin/importmap pin pdfjs-dist --vendor` puts it back and marks the pin
        `(vendored)` so it stays that way. If it didn't, and a `.wasm` decoder or a
        sibling module was quietly 404ing, the remote pin is the fix arriving. See
        [Packages kept remote](/docs/multi-file-packages#packages-kept-remote).
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
        - The pin on a package vendored with its file graph: the entry keeps its flat
          file and its plain comment, and the `pin_all_from` line sits beside it.
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
