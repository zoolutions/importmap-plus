require "strscan"

# Decides whether a downloaded ESM file can stand alone as the single file an
# import map entry points at. A vendored package is exactly one file served
# under a digested asset path, so anything the file expects to find beside
# itself — a sibling module, a worker script, a wasm binary, its own directory
# via import.meta.url — resolves to a 404 in the browser.
#
# Like Packager::ESM_RUN_IMPORT_REGEXP this reads the source with regexes
# rather than parsing JavaScript, so the same text inside a string still counts.
# It is deliberately the cautious direction: a false positive keeps a working
# remote pin, and `pin --vendor` is the escape hatch. Every judgement call here
# leans that way, because the two mistakes are not equal — a package wrongly
# kept remote still works, a package wrongly vendored 404s in production.
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

  # A string literal, consumed whole so nothing inside it is ever read as
  # code. Unterminated, it simply doesn't match and the quote is stepped over.
  STRING_REGEXP = /"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`/m.freeze # :nodoc:
  # A regex literal, consumed whole for the same reason: `/[/*]/` otherwise
  # hands the block-comment matcher an opener and loses the file to the next
  # `*/`. The body allows an escape or a character class, since both can hold
  # the delimiter.
  REGEXP_LITERAL_REGEXP = %r{/(?![*/])(?:[^/\\\n\[]|\\.|\[(?:[^\]\\\n]|\\.)*\])+/[dgimsuvy]*}.freeze # :nodoc:
  # Whether a `/` opens a regex literal or divides depends on the token before
  # it. Getting it wrong can only keep text that should have been dropped —
  # never drop text that should have been kept — so the cautious reading is
  # the safe one here too. Only the tail of what has been kept is looked at:
  # matching the whole buffer at every slash is quadratic, and pdf.js is a
  # megabyte of minified source with a slash in every other line.
  # `)` and `}` are in the set even though they also end an expression that a
  # `/` would divide: reading `(a + b) / 2` as a regex keeps the text either
  # way, while leaving them out lets `if (x) /[/*]/` open a false comment.
  # Verified against 31 published packages — no verdict changes.
  BEFORE_REGEXP_LITERAL_REGEXP =
    /(?:[(,=:\[!&|?{};+\-*%~^<>)\}]|\b(?:return|throw|typeof|case|in|of|do|else|yield|await|delete|void|instanceof|new))\s*\z/.freeze # :nodoc:
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
      @code ||= without_block_comments
    end

    # Block comments are discounted before anything is matched. A published
    # bundle is full of `/** @typedef {import('./slide.js').Slide} Slide */` —
    # type annotations naming files the package never loads, which would
    # otherwise keep a self-contained package remote; photoswipe alone carries
    # 76 of them.
    #
    # The scan walks the source instead of running a `/\*.*?\*/` over it,
    # because that regex reads a `"/*"` inside a string as a comment opener and
    # swallows the code up to the next `*/` — and an `import "./sibling.js"`
    # swallowed there is precisely the 404 this class exists to catch. Strings
    # are matched first and kept whole, so a comment opener inside one is never
    # reached.
    #
    # Line comments are left alone. Stripping them would mean reading `//` as
    # an opener inside a regex literal such as `[//]`, which is the same trap
    # in the same dangerous direction, and nothing is known to hide behind one.
    def without_block_comments
      scanner = StringScanner.new(source)
      kept    = +""

      until scanner.eos?
        if scanner.skip(BLOCK_COMMENT_REGEXP)
          next
        elsif (literal = scanner.scan(STRING_REGEXP)) ||
              (regexp_literal_next?(kept, scanner) && (literal = scanner.scan(REGEXP_LITERAL_REGEXP)))
          kept << literal
        else
          kept << scanner.getch
        end
      end

      kept
    end

    # Wide enough for the longest keyword above plus the indentation a
    # pretty-printed file can put between it and the slash; a keyword the
    # window cuts in half simply reads as division, which keeps less.
    REGEXP_LOOKBEHIND_LIMIT = 32 # :nodoc:

    def regexp_literal_next?(kept, scanner)
      scanner.match?(%r{/}) &&
        (kept[-REGEXP_LOOKBEHIND_LIMIT..] || kept).match?(BEFORE_REGEXP_LITERAL_REGEXP)
    end
end
