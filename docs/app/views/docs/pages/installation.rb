# frozen_string_literal: true

# Getting importmap-plus into a Rails app — new or already on importmap-rails.
class Views::Docs::Pages::Installation < DocsUI::Page
  title "Installation"
  eyebrow "Getting started"

  def lead = "One Gemfile line. An app already on importmap-rails needs nothing else."

  def content
    requirements
    add_gem
    fresh_app
    rails_frameworks
  end

  private

  def requirements
    DocsUI::Section("Requirements") do
      DocsUI::Table(
        [ "Requirement", "Version" ],
        [
          [ [ :code, "Ruby" ], ">= 3.1" ],
          [ [ :code, "Rails" ], ">= 6.0 (Rails 7.0+ for the ESM builds of Action Cable, Action Text and Active Storage)" ],
          [ "Asset pipeline", "Propshaft or Sprockets" ],
          [ "Minifier", [ :md, "optional — [bun](https://bun.sh), [esbuild](https://esbuild.github.io) or [terser](https://terser.org) for `--minify`" ] ]
        ]
      )
    end
  end

  def add_gem
    DocsUI::Section("Replace importmap-rails", description: "Rails 7+ ships importmap-rails for new applications; swap it.") do
      md <<~'MD'
        Replace `gem "importmap-rails"` with `gem "importmap-plus"` in your Gemfile and
        run `bundle install`:
      MD
      DocsUI::Code(<<~RUBY, filename: "Gemfile")
        gem "importmap-plus"
      RUBY
      md <<~'MD'
        That is the whole migration for an app already on importmap-rails: the pins,
        `config/importmap.rb`, the helpers and the `Importmap::` constants are
        unchanged, and the vendored files in `vendor/javascript` keep working. The
        first `bin/importmap` command you run may rewrite a pin comment to record
        where a package came from — see [Provenance](/docs/provenance).
      MD
    end
  end

  def fresh_app
    DocsUI::Section("An app without an import map", description: "Install, then run the generator.") do
      DocsUI::Code(<<~SHELL, lexer: :shell)
        ./bin/bundle add importmap-plus
        ./bin/rails importmap:install
      SHELL
      md <<~'MD'
        The installer:

        - adds `<%= javascript_importmap_tags %>` to `app/views/layouts/application.html.erb`,
        - creates `app/javascript/application.js` as the entrypoint,
        - creates `vendor/javascript` for downloaded pins,
        - links both directories in the Sprockets manifest when the app uses Sprockets,
        - copies `config/importmap.rb` and the `bin/importmap` binstub.
      MD
    end
  end

  def rails_frameworks
    DocsUI::Section("JavaScript from Rails frameworks") do
      md <<~'MD'
        To use JavaScript from Action Cable, Action Text and Active Storage you must
        be on Rails 7.0+, the first version that shipped ESM-compatible builds of
        those libraries. Pin them to the compiled versions included in Rails:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "@rails/actioncable", to: "actioncable.esm.js"
        pin "@rails/activestorage", to: "activestorage.esm.js"
        pin "@rails/actiontext", to: "actiontext.esm.js"
        pin "trix"
      RUBY
    end
  end
end
