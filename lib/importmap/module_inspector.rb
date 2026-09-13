# Decides whether a downloaded ESM file can stand alone as the single file an
# import map entry points at. A vendored package is exactly one file served
# under a digested asset path, so anything the file expects to find beside
# itself — a sibling module, a worker script, a wasm binary, its own directory
# via import.meta.url — resolves to a 404 in the browser.
#
# Like Packager::ESM_RUN_IMPORT_REGEXP this reads the source with regexes
# rather than parsing JavaScript, so the same text inside a string still counts.
# It is deliberately the cautious direction: a false positive keeps a working
# remote pin, and `pin --vendor` is the escape hatch.
class Importmap::ModuleInspector
  # `from "./x"`, `from '../x'`, a bare `import "./x"` and a dynamic
  # `import("./x")`. Anchored on the keyword, and the lookbehind keeps
  # `obj.import(` and identifiers ending in `import` out.
  RELATIVE_IMPORT_REGEXP = /(?<![\w.$])(?:from|import)\s*\(?\s*["']\.{1,2}\//.freeze # :nodoc:
  # import() of anything but a string literal: the specifier is computed at
  # runtime, so what it resolves to can't be known here, let alone vendored.
  # The whitespace lives inside the lookahead on purpose: as `import\s*\(\s*`
  # followed by a negative lookahead, `\s*` backtracks to zero and the lookahead
  # then reads the space rather than the quote, so `import( "crypt" )` reads as
  # computed.
  COMPUTED_IMPORT_REGEXP = /(?<![\w.$])import\s*\((?!\s*["'][^"']*["']\s*[),])/.freeze # :nodoc:
  # A worker is fetched as its own top-level script and never goes through the
  # import map, so its URL has to exist on its own.
  # The qualifier group catches `new window.Worker(…)` and `new self.Worker(…)`;
  # it needs the dot, so `new WorkerPool(…)` is still left alone.
  WORKER_REGEXP = /(?<![\w.$])new\s+(?:[\w$]+\s*\.\s*)*(?:Shared)?Worker\s*\(/.freeze # :nodoc:
  # import.meta.url is the file's own digested asset path, which is not the
  # directory the package's other files were published to.
  IMPORT_META_URL_REGEXP = /(?<![\w.$])import\s*\.\s*meta\s*\.\s*url\b/.freeze # :nodoc:
  # A .wasm binary is fetched at runtime by a path the package computes; it is
  # never part of the JavaScript file that names it. Template literals count —
  # the path is usually built from a base — and so does a cache-busting query
  # or a fragment after the extension.
  WASM_REGEXP = /(["'`])[^"'`\n]*\.wasm(?:[?#][^"'`\n]*)?\1/.freeze # :nodoc:

  # In precedence order: the first one that matches is the reason reported, and
  # relative imports come first because they are both the commonest cause and
  # the one an app developer can act on.
  PATTERNS = {
    "relative imports" => RELATIVE_IMPORT_REGEXP,
    "dynamic imports"  => COMPUTED_IMPORT_REGEXP,
    "workers"          => WORKER_REGEXP,
    "import.meta.url"  => IMPORT_META_URL_REGEXP,
    "wasm"             => WASM_REGEXP
  }.freeze # :nodoc:

  # Block comments are discounted before anything is matched. A published
  # bundle is full of `/** @typedef {import('./slide.js').Slide} Slide */` —
  # type annotations naming files the package does not load at runtime, which
  # would otherwise keep a perfectly self-contained package remote. photoswipe
  # alone carries 76 of them. Line comments are left in: `//` is too common
  # inside URLs to strip safely, and nothing is known to hide there.
  BLOCK_COMMENT_REGEXP = %r{/\*.*?\*/}m.freeze # :nodoc:

  attr_reader :source

  # The source as it would be written to vendor/javascript: after an esm.run
  # bundle's imports have been rewritten to bare specifiers, before minifying.
  def initialize(source)
    @source = source.to_s
  end

  # Every pattern the source matches, in precedence order.
  def reasons
    @reasons ||= PATTERNS.filter_map { |reason, regexp| reason if code.match?(regexp) }
  end

  def reason
    reasons.first
  end

  def vendorable?
    reasons.empty?
  end

  private
    def code
      @code ||= source.gsub(BLOCK_COMMENT_REGEXP, "")
    end
end
