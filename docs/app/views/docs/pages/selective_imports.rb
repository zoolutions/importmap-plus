# frozen_string_literal: true

# Importing a module on one page only, with javascript_import_module_tag.
class Views::Docs::Pages::SelectiveImports < DocsUI::Page
  title "Selective imports"
  eyebrow "Serving"

  def lead = "Pin a module without preloading it, then import it only on the pages that need it."

  def content
    the_module
    the_page
  end

  private

  def the_module
    DocsUI::Section("A page-specific module") do
      md <<~'MD'
        Write the module under `app/javascript` and pin it with `preload: false`, so
        it isn't fetched on every page:
      MD
      DocsUI::Code(<<~JS, filename: "app/javascript/checkout.js")
        // some checkout specific js
      JS
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        # ... other pins ...
        pin "checkout", preload: false
      RUBY
    end
  end

  def the_page
    DocsUI::Section("Importing it on one page") do
      md <<~'MD'
        Import the module on the specific page with `javascript_import_module_tag`.
        You'll likely want a `content_for` block on the page or partial, yielded in
        the layout:
      MD
      DocsUI::Code(<<~ERB, filename: "app/views/checkouts/show.html.erb")
        <% content_for :head do %>
          <%= javascript_import_module_tag "checkout" %>
        <% end %>
      ERB
      DocsUI::Code(<<~ERB, filename: "app/views/layouts/application.html.erb")
        <%= javascript_importmap_tags %>
        <%= yield(:head) %>
      ERB
      DocsUI::Callout(:warning) do
        plain "javascript_import_module_tag must come after javascript_importmap_tags: the import map has to be in the document before any module that relies on it."
      end
    end
  end
end
