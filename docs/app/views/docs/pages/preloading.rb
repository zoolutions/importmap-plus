# frozen_string_literal: true

# modulepreload links, preload: false, and preloading per entry point.
class Views::Docs::Pages::Preloading < DocsUI::Page
  title "Preloading"
  eyebrow "Serving"

  def lead = "Every pin is preloaded with a modulepreload link by default, so the browser doesn't discover imports one file at a time."

  def content
    default
    opting_out
    entry_points
  end

  private

  def default
    DocsUI::Section("modulepreload by default") do
      md <<~'MD'
        Without preloading, the browser loads one file, parses it, finds its imports,
        loads those, and so on down to the deepest nested import — a waterfall.
        importmap-rails avoids it with
        [modulepreload links](https://developers.google.com/web/updates/2017/12/modulepreload):
        `javascript_importmap_tags` emits one for every pin before the import map,
        so every file starts downloading at once.
      MD
    end
  end

  def opting_out
    DocsUI::Section("preload: false") do
      md <<~'MD'
        A dependency you want to load on demand — a chart library used on one page,
        say — gets `preload: false` on its pin:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "@github/hotkey", to: "@github--hotkey.js" # file lives in vendor/javascript/@github--hotkey.js
        pin "md5", preload: false # file lives in vendor/javascript/md5.js
      RUBY
      DocsUI::Code(<<~ERB, filename: "app/views/layouts/application.html.erb")
        <%= javascript_importmap_tags %>

        <%# includes the following link before the import map is set up: %>
        <link rel="modulepreload" href="/assets/javascript/@github--hotkey.js">
      ERB
      md <<~'MD'
        `bin/importmap` keeps `preload:` when it rewrites a pin, so a `preload: false`
        survives `update`.
      MD
    end
  end

  def entry_points
    DocsUI::Section("Preloading per entry point") do
      md <<~'MD'
        `preload:` also takes a string or an array of strings naming the entry
        points a dependency should be preloaded for. `javascript_importmap_tags`
        takes the entry point as its argument (`"application"` by default):
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "@github/hotkey", to: "@github--hotkey.js", preload: "application"
        pin "md5", preload: ["application", "alternate"]
      RUBY
      DocsUI::Code(<<~ERB, filename: "app/views/layouts/alternate.html.erb")
        <%= javascript_importmap_tags "alternate" %>

        <%# includes the following link before the import map is set up: %>
        <link rel="modulepreload" href="/assets/javascript/md5.js">
      ERB
      md <<~'MD'
        A pin with `preload: true` is preloaded for every entry point; one with a
        name is preloaded only when that entry point is rendered.
      MD
    end
  end
end
