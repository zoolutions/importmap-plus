# frozen_string_literal: true

# pin --minify and pristine --minify, which minifier runs, and how to bring
# your own.
class Views::Docs::Pages::Minifying < DocsUI::Page
  title "Minifying"
  eyebrow "Vendoring"

  def lead = "Run a download through bun, esbuild or terser before it lands in vendor/javascript."

  def content
    why
    how
    everything
    custom_minifier
  end

  private

  def why
    DocsUI::Section("Why") do
      md <<~'MD'
        Plenty of packages publish unminified ESM (pdfjs-dist, choices.js, luxon), and a
        CDN that serves package files hands them out as published. Lighthouse's
        unminified-JavaScript audit will tell you which of your vendored packages
        those are.
      MD
    end
  end

  def how
    DocsUI::Section("pin --minify") do
      DocsUI::Code(<<~SHELL, lexer: :console)
        $ ./bin/importmap pin luxon --minify
        Pinning "luxon" to vendor/javascript/luxon.js via download from https://ga.jspm.io/npm:luxon@3.7.2/build/es6/luxon.mjs (minified)
      SHELL
      md <<~'MD'
        The first of [bun](https://bun.sh), [esbuild](https://esbuild.github.io) or
        [terser](https://terser.org) found in `node_modules/.bin` or on your `PATH`
        (Windows `.cmd` shims included) is used, always in transform-only mode so bare
        import specifiers are left exactly as the CDN resolved them and the import
        map keeps resolving them.

        The pin records it, and so does the header of the vendored file:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "luxon" # @3.7.2 (minified)
        pin "stimulus-use" # @0.53.1 (esm.run, minified)
      RUBY
      md <<~'MD'
        From then on `update`, `pristine` and a plain `pin` keep minifying that
        package; `--no-minify` turns it off again. Dependencies pinned alongside a
        `--minify` download are minified too.
      MD
    end
  end

  def everything
    DocsUI::Section("Everything already vendored") do
      md <<~'MD'
        `pristine` redownloads every vendored package; with `--minify` it minifies
        them all in one go and records it on each pin:
      MD
      DocsUI::Code(<<~SHELL, lexer: :shell)
        ./bin/importmap pristine --minify
      SHELL
    end
  end

  def custom_minifier
    DocsUI::Section("Bringing your own minifier") do
      md <<~'MD'
        Assign anything that responds to `call(source)` and returns the minified
        source. `bin/importmap` loads `config/application.rb` but not your
        initializers, so the assignment has to happen there (or in a file it
        requires):
      MD
      DocsUI::Code(<<~RUBY, filename: "config/application.rb")
        require "importmap/packager"

        Importmap::Packager.minifier = ->(source) { MyMinifier.minify(source) }
      RUBY
    end
  end
end
