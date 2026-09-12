# frozen_string_literal: true

# The mental model: bare specifiers, the substitution the browser does, and how
# the app's own modules get pinned.
class Views::Docs::Pages::HowImportMapsWork < DocsUI::Page
  title "How import maps work"
  eyebrow "Getting started"

  def lead = "An import map is a string substitution for bare module specifiers, done by the browser."

  def content
    why
    bare_specifiers
    usage
    local_modules
  end

  private

  def why
    DocsUI::Section("Why import maps") do
      md <<~'MD'
        [Import maps](https://github.com/WICG/import-maps) let you import JavaScript
        modules using logical names that map to versioned, digested files — directly
        from the browser. You can build modern JavaScript applications with libraries
        made for ES modules (ESM) without transpiling or bundling, which frees you
        from Webpack, Yarn, npm and the rest of the JavaScript toolchain. All you
        need is the asset pipeline already included in Rails.

        You ship many small JavaScript files instead of one big one. With HTTP/2 that
        no longer carries a material performance penalty during the initial
        transport, and it caches better over time: a change to one file invalidates
        that file, not a whole bundle.

        [Import maps are supported natively in all major, modern browsers](https://caniuse.com/?search=importmap).
        For legacy browsers without native support there is
        [es-module-shims](https://github.com/guybedford/es-module-shims).
      MD
    end
  end

  def bare_specifiers
    DocsUI::Section("Bare module specifiers") do
      md <<~'MD'
        A "bare module specifier" looks like `import React from "react"`. The ES
        module loader doesn't accept it: a specifier has to be an absolute path, a
        relative path, or an HTTP URL.
      MD
      DocsUI::Code(<<~JS, lexer: :javascript)
        import React from "/Users/DHH/projects/basecamp/node_modules/react"   // absolute path
        import React from "./node_modules/react"                              // relative path
        import React from "https://ga.jspm.io/npm:react@17.0.1/index.js"     // HTTP URL
      JS
      md <<~'MD'
        The import map is a clean API for mapping a bare specifier like `"react"` to
        one of those three. A pin in `config/importmap.rb`:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin "react", to: "https://ga.jspm.io/npm:react@17.0.2/index.js"
      RUBY
      md <<~'MD'
        means "every time you see `import React from "react"`, change it to
        `import React from "https://ga.jspm.io/npm:react@17.0.2/index.js"`".
      MD
    end
  end

  def usage
    DocsUI::Section("Usage") do
      md <<~'MD'
        The import map is set up through `Rails.application.importmap` from
        `config/importmap.rb`. The file is reloaded in development when it changes;
        restart the server if you remove pins and need them gone from the rendered
        map or the list of preloads.

        The map is inlined in the `<head>` of your layout by
        `<%= javascript_importmap_tags %>`, as a `<script type="importmap">` with
        the JSON configuration. The entrypoint is then imported with
        `<script type="module">import "application"</script>`; the logical name
        `application` maps to `app/javascript/application.js`.

        In `app/javascript/application.js` you set up your application by importing
        any of the modules the import map defines, with the full ESM feature set:
        named exports, default exports, `import *`.

        Use logical names that match the npm package names, so that if you later
        move to transpiling or bundling, no module import has to change.
      MD
    end
  end

  def local_modules
    DocsUI::Section("Local modules") do
      md <<~'MD'
        Local modules in `app/javascript/src` or other sub-folders of
        `app/javascript` (such as `channels`) must be pinned to be importable.
        `pin_all_from` pins every file in a folder, so you don't `pin` each module:
      MD
      DocsUI::Code(<<~RUBY, filename: "config/importmap.rb")
        pin_all_from "app/javascript/src", under: "src", to: "src"

        # With automatic integrity calculation
        enable_integrity!
        pin_all_from "app/javascript/controllers", under: "controllers", integrity: true
      RUBY
      md <<~'MD'
        `under:` sets the prefix of the bare specifier — what `import` statements
        say. `to:` sets the prefix of the asset path the file is served from, and
        defaults to `under:`, so in this example it is redundant: drop it and
        `under:` goes directly after the first parameter. `enable_integrity!` turns
        on integrity calculation globally and `integrity: true` computes a hash for
        every file in the directory — see [Subresource integrity](/docs/integrity).

        Which lets you write:
      MD
      DocsUI::Code(<<~JS, filename: "app/javascript/application.js")
        import { ExampleFunction } from "src/example_function"
      JS
      DocsUI::Callout(:note) do
        plain "Sprockets used to serve assets it couldn't find from app/javascript by relative path, so local files didn't need pinning. Propshaft has no such fallback: with Propshaft you pin your local modules."
      end
    end
  end
end
