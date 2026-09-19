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
    reachable
    early_hints
  end

  private

  def default
    DocsUI::Section("modulepreload by default") do
      md <<~'MD'
        Without preloading, the browser loads one file, parses it, finds its imports,
        loads those, and so on down to the deepest nested import — a waterfall.
        importmap-rails avoids it with
        [modulepreload links](https://developers.google.com/web/updates/2017/12/modulepreload):
        `javascript_importmap_tags` emits the import map, then one modulepreload
        link for every pin marked `preload: true` (the default) that applies to the
        entry point being rendered, then the entry point import — so every
        preloaded file starts downloading at once.
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

        <%# emits, after the import map, a link for hotkey but none for md5: %>
        <link rel="modulepreload" href="/assets/@github--hotkey.js">
      ERB
      md <<~'MD'
        `bin/importmap` keeps `preload:` when it rewrites a pin, so a `preload: false`
        survives `update`.

        A package [vendored with its file graph](/docs/multi-file-packages) gets a
        `pin_all_from` line carrying whatever the entry's pin says, so a
        `preload: false` entry doesn't preload its chunks and a preloaded one does.
        That is one link per file — 48 of them for `@popperjs/core`, which imports
        every one of its files statically. A package that reaches some of its files
        through a lazy `import("./chunk.js")` preloads those too, since the line
        maps the whole directory; pin it `preload: false` if that matters more than
        the waterfall.
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

        <%# emits, after the import map, a link for md5 but none for hotkey: %>
        <link rel="modulepreload" href="/assets/md5.js">
      ERB
      md <<~'MD'
        A pin with `preload: true` is preloaded for every entry point; one with a
        name is preloaded only when that entry point is rendered.
      MD
    end
  end

  def reachable
    DocsUI::Section("Preloading what the page reaches", description: "importmap-plus only.") do
      md <<~'MD'
        `preload: false` is bookkeeping. An app on this gem carried this line:

        ```ruby
        # imported only by apexcharts.js, which is itself lazy. Without it,
        # 1.1 MB was preloaded on every page.
        pin "apexcharts/core", preload: false
        ```

        Nothing in the import map knew that. `apexcharts` was pinned
        `preload: false` because the app loads it with `import()`, but every
        package *it* imports still said `preload: true`, so the browser fetched
        the whole chart library on every page to render a page with no chart on
        it. Each of those dependencies needs its own `preload: false`, and the
        list changes whenever the package does — or whenever a package is
        [vendored with its file graph](/docs/multi-file-packages) and contributes a whole
        directory of pins to the same question.

        The import graph already answers it. `app/javascript`,
        `vendor/javascript` and every `pin_all_from` directory are files on
        disk, and their `import` statements name pin keys. Turn on
        `preload_strategy`:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/application.rb")
        config.importmap.preload_strategy = :reachable
      RUBY
      md <<~'MD'
        and `javascript_importmap_tags "application"` emits a modulepreload link
        only for the pins `application` actually reaches.

        ### What counts as reachable

        A static `import` — `import "x"`, `import a from "x"`,
        `export * from "x"` — is an edge; the browser fetches `x` while linking
        the module, which is exactly what a modulepreload link is for. A dynamic
        `import("x")` is not: it is the app saying "later", and preloading its
        target would undo the deferral. So the set is the entry point, plus
        everything reachable from it through static imports, however deep.

        Relative imports are resolved against the importing pin's own path and
        matched back to the pin holding that path. A pin whose file isn't on the
        asset paths, and a pin pointing at a CDN URL, are leaves: they are
        preloaded if something reaches them, and nothing is read from them.
      MD
      DocsUI::PropTable(
        [
          [ [ :code, "preload: true" ], "the default", "Preloaded only when the entry point reaches it." ],
          [ [ :code, %(preload: "admin") ], "a name", "Preloaded whenever that entry point is rendered, reachable or not — the app overruling the graph." ],
          [ [ :code, "preload: false" ], "off", "Never preloaded, under either strategy." ]
        ]
      )
      md <<~'MD'
        That last row is the escape hatch: a module your app reaches in a way a
        regex can't see — a specifier built at runtime, an import inside a
        string — gets a pin naming the entry point, and it is preloaded again.

        ### Cost

        The files are read once per import map cache generation and cached with
        the rendered map, so a production render costs nothing beyond the first
        one after boot. In development the cache sweeper drops it on every `.js`
        change under `app/javascript` or `vendor/javascript`, and the next
        render reads each reachable file once — around a millisecond for a
        13-file graph. The default `:all` never opens a file.
      MD
      DocsUI::Callout(:note) do
        md <<~'MD'
          `:all` — upstream importmap-rails' behaviour, one link per
          `preload: true` pin — stays the default. `:reachable` changes what
          your pages preload, so it is opt-in: turn it on, then check the
          Network panel of a page you know is lazy.
        MD
      end
    end
  end

  def early_hints
    DocsUI::Section("103 Early Hints", description: "importmap-plus only.") do
      md <<~'MD'
        A modulepreload link is still markup: the browser acts on it once it has
        parsed that far into the HTML, so every module waits for the response to
        start streaming. The same list can go out before the response as a
        [103 Early Hints](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/103)
        `Link` header, and the fetches begin while your app is still rendering.

        `javascript_importmap_tags` sends one, for exactly the modules it is
        about to preload:
      MD
      DocsUI::Code(<<~HTTP, lexer: :http)
        HTTP/1.1 103 Early Hints
        Link: </assets/application-abc.js>; rel=modulepreload, </assets/@hotwired--stimulus-def.js>; rel=modulepreload
      HTTP
      md <<~'MD'
        This is what Rails' own `javascript_include_tag` and `stylesheet_link_tag`
        already do for their assets, and it needs the same thing they do: a server
        that puts `rack.early_hints` in the Rack env. Puma does when you ask it to:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/puma.rb")
        early_hints true
      RUBY
      md <<~'MD'
        On a server that doesn't, `send_early_hints` is a no-op — nothing is sent
        and nothing breaks. Turn it off entirely with:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/application.rb")
        config.importmap.early_hints = false
      RUBY
      md <<~'MD'
        The hinted set is the tags' set, so it narrows with them: `preload: false`,
        an entry point's own list, and `preload_strategy = :reachable` all decide
        what gets hinted. The header carries no `integrity` parameter — browsers
        don't honour one there — and the modulepreload tag in the body still does,
        which is where the hash has to match.

        A hint is only sent while the response hasn't started. Under
        `render stream: true` the layout renders after the 200 is already going
        out, so nothing is hinted for that page — a 103 written then would land
        in the middle of the body. Rails guards its own early hints the same way.
      MD
    end
  end
end
