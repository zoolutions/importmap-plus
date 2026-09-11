# frozen_string_literal: true

# Adding import map files from engines and elsewhere.
class Views::Docs::Pages::Composing < DocsUI::Page
  title "Composing import maps"
  eyebrow "Serving"

  def lead = "Combine several import map files — an engine's pins with the application's — through config.importmap.paths."

  def content
    paths
    engines
  end

  private

  def paths
    DocsUI::Section("config.importmap.paths") do
      md <<~'MD'
        By default Rails loads the import map definition from the application's
        `config/importmap.rb` into the `Importmap::Map` at
        `Rails.application.importmap`. Any additional file appended to
        `Rails.application.config.importmap.paths` is drawn into the same map, in
        order, so a later file can override an earlier pin.
      MD
    end
  end

  def engines
    DocsUI::Section("Pinning from an engine") do
      md <<~'MD'
        An engine appends its own `config/importmap.rb` before the `importmap`
        initializer runs, and pins its JavaScript from its own asset directory:
      MD
      DocsUI::Code(<<~RUBY, filename: "my_engine/lib/my_engine/engine.rb")
        module MyEngine
          class Engine < ::Rails::Engine
            # ...
            initializer "my-engine.importmap", before: "importmap" do |app|
              app.config.importmap.paths << Engine.root.join("config/importmap.rb")
              # ...
            end
          end
        end
      RUBY
      DocsUI::Code(<<~RUBY, filename: "my_engine/config/importmap.rb")
        pin_all_from File.expand_path("../app/assets/javascripts", __dir__)
      RUBY
      md <<~'MD'
        An engine that wants its import map reloaded in development also appends
        its JavaScript directory to `config.importmap.cache_sweepers` — see
        [Caching & ETags](/docs/caching).
      MD
    end
  end
end
