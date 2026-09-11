# frozen_string_literal: true

# The pin comment: what it records, who reads it, and the grammar.
class Views::Docs::Pages::Provenance < DocsUI::Page
  title "Provenance"
  eyebrow "Vendoring"

  def lead = "The version comment on a pin also says where the package came from, whether it is minified, and whether it is locked."

  def content
    the_comment
    who_reads_it
    grammar
  end

  private

  def the_comment
    DocsUI::Section("The pin comment") do
      md <<~'MD'
        importmap-rails writes `# @3.7.2` after a vendored pin so `outdated` and
        `update` know the version. importmap-plus extends that comment with a
        parenthesised list of what the file was built with:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "react" # @19.1.0
        pin "luxon" # @3.7.2 (esm.run)
        pin "choices.js" # @11.2.4 (minified)
        pin "stimulus-use" # @0.53.1 (esm.run, minified, locked)
        pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js" # @2.2.0 (locked)
      RUBY
      md <<~'MD'
        The CDN is named when it isn't jspm. `minified` says the file went through a
        minifier. `locked` says the version is held — see
        [Locking versions](/docs/locking). A remote pin has no comment unless it is
        locked; then the version from its URL is written out so the lock has
        something to hold.
      MD
    end
  end

  def who_reads_it
    DocsUI::Section("Who reads it") do
      md <<~'MD'
        `update`, `pristine` and a plain `pin` read the comment back, so a package
        keeps its CDN and stays minified without you repeating the flags. This
        closes a gap in importmap-rails, where an unpkg download would silently move
        back to jspm on the next `update`.

        The flags override the comment for that one command: `--from` moves a
        package to another CDN (and rewrites the comment), `--no-minify` stops
        minifying it, `--no-lock` drops its lock. `pristine --from esm.run` moves
        everything vendored to esm.run and records it on each pin.
      MD
    end
  end

  def grammar
    DocsUI::Section("Grammar", description: "In case you write or edit the comment by hand.") do
      DocsUI::Code(<<~TEXT, lexer: :plaintext)
        pin "<name>"[, options] # @<version>[ (<detail>[, <detail>...])]

        detail := <provider> | minified | locked | locked: <range>
      TEXT
      md <<~'MD'
        Details come in that order: provider, `minified`, `locked`. `locked: <range>`
        is reserved for range locks in a later release; today's parser already reads
        it as a lock. The version is whatever the CDN URL carried, so prerelease tags
        such as `@2.0.0-beta.19` are fine. Anything after `pin` on the same line is
        the pin; there is no multi-line form.
      MD
    end
  end
end
