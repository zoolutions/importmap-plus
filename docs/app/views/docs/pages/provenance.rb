# frozen_string_literal: true

# The pin comment: what it records, who reads it, and the grammar.
class Views::Docs::Pages::Provenance < DocsUI::Page
  title "Provenance"
  eyebrow "Vendoring"

  def lead = "The version comment on a pin also says where the package came from, whether it is minified, whether it had to stay remote, and whether it is locked."

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
        pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports)
        pin "monaco-editor", to: "monaco-editor.js" # @0.52.2 (vendored)
      RUBY
      md <<~'MD'
        The CDN is named when it isn't jspm. `minified` says the file went through a
        minifier. `locked` says the version is held — see
        [Locking versions](/docs/locking). `remote: <reason>` says the package was
        pinned to its CDN URL because the downloaded file can't stand alone, and
        `vendored` says `--vendor` overrode that check — see
        [Packages that can't be vendored alone](/docs/pinning). A bare `remote`,
        with no reason after it, means the same thing without saying why; write one
        by hand and it is kept as it is. A remote pin has no comment unless it is
        locked or was kept remote; then the version from its URL is written out so
        the detail has something to hang off.
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

        detail := <provider> | minified | vendored | remote | remote: <reason> | locked | locked: <range>
      TEXT
      md <<~'MD'
        Details come in that order: provider, `minified`, `vendored` or
        `remote: <reason>`, `locked`. `vendored` and `remote:` are the same slot — a
        pin is one or the other, never both — and the reason is one of
        `relative imports`, `dynamic imports`, `workers`, `import.meta.url` or
        `wasm`. `locked: <range>`
        is reserved for range locks in a later release; today's parser already reads
        it as a lock. The version is whatever the CDN URL carried, so prerelease tags
        such as `@2.0.0-beta.19` are fine. Anything after `pin` on the same line is
        the pin; there is no multi-line form.
      MD
    end
  end
end
