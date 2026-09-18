require "importmap/module_inspector"

# Every module specifier a JavaScript file names, in source order, with whether
# the browser resolves it while linking the module or later at runtime. What an
# import map has to define, read back out of the files the map serves.
#
# Like Importmap::ModuleInspector and Importmap::PackageGraph::IMPORT_REGEXP
# this reads the source with regexes rather than parsing JavaScript, so an
# import statement spelled out inside a string literal is reported too, and a
# form the regexp can't read — a magic comment between the keyword and the
# specifier, a specifier built at runtime — isn't reported at all. Both
# mistakes are the cautious direction for the one caller: a specifier reported
# that the browser never asks for costs a pin, and a specifier missed leaves
# the app exactly as broken as it was before anyone ran the check.
#
# Block comments are discounted first, through ModuleInspector#code, because a
# published bundle is full of `/** @typedef {import('./slide.js').Slide} */` —
# type annotations naming files the package never loads.
class Importmap::ImportScanner
  Import = Struct.new(:specifier, :kind, keyword_init: true) # :nodoc:

  # `import("x")` of a string literal, then every static spelling: the bare
  # `import "x"` and the `from "x"` that ends `import a from "x"`,
  # `import {a} from "x"`, `import * as a from "x"`, `export {a} from "x"` and
  # `export * from "x"`. The lookbehind keeps `loader.import(` and identifiers
  # ending in `import` or `from` out, and the dynamic branch comes first so an
  # `import(` is never read as the bare form.
  #
  # The closing `[),]` on the dynamic branch is what makes a computed
  # specifier — `import(name)`, `import(`./${lang}.js`)` — match nothing
  # rather than match half of something; it is the same test
  # Importmap::ModuleInspector::COMPUTED_IMPORT_REGEXP makes from the other
  # side, and the two must agree about which files hold one.
  IMPORT_REGEXP = /
    (?<![\w.$])
    (?:
      import\s*\(\s*(["'])([^"'\n]*)\1\s*[),] |
      (?:from|import)\s*(["'])([^"'\n]*)\3
    )
  /x.freeze # :nodoc:

  attr_reader :source

  def initialize(source)
    @source = source.to_s
  end

  def imports
    @imports ||= Importmap::ModuleInspector.new(source).code.scan(IMPORT_REGEXP).map do |_, dynamic, _, static|
      dynamic ? Import.new(specifier: dynamic, kind: :dynamic) : Import.new(specifier: static, kind: :static)
    end
  end
end
