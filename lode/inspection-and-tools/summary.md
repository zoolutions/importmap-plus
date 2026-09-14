# Inspection and tools: ModuleInspector, Minifier, HttpRetries

Fork-only collaborators: `lib/importmap/module_inspector.rb`, `lib/importmap/minifier.rb`, `lib/importmap/http_retries.rb`, and (for retry behaviour only — resolution is the packager lode's subject) `lib/importmap/provider_chain.rb`. They live in their own files, not inside `packager.rb`, so upstream-owned files stay diff-minimal for the next `git merge upstream/main` (`CLAUDE.md`, `.claude/rules/coding-style.md`) — a new file never conflicts, a hundred new lines inside an upstream file does. The gemspec depends on nothing but railties, activesupport and actionpack (`CLAUDE.md`), so there is no JavaScript parser: `ModuleInspector` decides everything with regexes and `StringScanner` (`require "strscan"`, `module_inspector.rb:1`), and the two CDN clients retry with plain `Net::HTTP` rather than a retry gem.

## ModuleInspector (`lib/importmap/module_inspector.rb`)

**Purpose.** A vendored package is one file on a digested asset path. `ModuleInspector` decides whether a downloaded file can stand alone (`vendorable?`/`reasons`/`reason`) and whether it's an ES module at all (`es_module?`) (class comment, lines 3-14; called from `Importmap::Packager#ensure_servable`, `packager.rb:562-568`), reading the source two memoized ways: `code` (block comments stripped) and `statements` (block *and* line comments stripped, every literal emptied to its delimiters) (lines 141-147).

### Regex constants

| Constant | Source | Matches | Deliberately does not match |
|---|---|---|---|
| `RELATIVE_IMPORT_REGEXP` | `/(?<![\w.$])(?:from\|import)\s*\(?\s*["']\.{1,2}\//` | `from "./x"`, `import "./x"`, `import('../x')` | `obj.import(`, an identifier ending in `import` |
| `COMPUTED_IMPORT_REGEXP` | `/(?<![\w.$])import\s*\((?!\s*["'][^"']*["']\s*[),])/` | `import(name)`, `` import(`${base}/x.js`) ``, `import("a"+b)` | `import("crypt")`, `import( "crypt" )` — a lone string-literal argument |
| `WORKER_REGEXP` | `/(?<![\w.$])new\s+(?:[\w$]+\s*\.\s*)*(?:Shared)?Worker\s*\(/` | `new Worker(url)`, `new window.Worker(url)`, `new globalThis . SharedWorker(url)` | `new WorkerPool(url)`, `new MyWorker.Factory(url)` — a dot must precede `Worker` |
| `IMPORT_META_URL_REGEXP` | `/(?<![\w.$])import\s*\.\s*meta\s*\.\s*url\b/` | `import.meta.url`, spaced | `meta.url`, `ctx.import.meta.url` |
| `WASM_REGEXP` | ``/(["'`])[^"'`\n]*\.wasm(?:[?#][^"'`\n]*)?\1/`` | `"./x.wasm"`, `` `${base}/onig.wasm` ``, `"onig.wasm?v=1"`, `"onig.wasm#start"` | `"compiled from wasm"`, `"wasmer.js"` — extension must end the literal |

`PATTERNS` (lines 44-50) maps reason string to regexp in the precedence `reasons` checks (`filter_map`, line 114, declaration order): `"relative imports"`, `"dynamic imports"`, `"workers"`, `"import.meta.url"`, `"wasm"` — relative imports first because they're "both the commonest cause and the one an app developer can act on" (lines 41-43). `reason` is `reasons.first`; `vendorable?` is `reasons.empty?` (lines 117-123).

### Scan order: string, then block comment, then regex

`without_block_comments` (lines 170-186) is one `StringScanner` pass that at each position tries, in order: skip a block comment (and, in `statements_only` mode, a line comment); else scan a string literal; else scan a regex literal if context says one opens here; else consume one character:

```ruby
if scanner.skip(BLOCK_COMMENT_REGEXP) || (statements_only && scanner.skip(LINE_COMMENT_REGEXP))
  next
elsif (literal = scanner.scan(STRING_REGEXP)) ||
      (regexp_literal_next?(kept, scanner) && (literal = scanner.scan(REGEXP_LITERAL_REGEXP)))
  kept << (statements_only ? literal[0, 1] * 2 : literal)
else
  kept << scanner.getch
end
```

Why: a `"/*"` can sit *inside* a string. A naive `/\/\*.*?\*\//m` over the whole buffer would read that embedded opener as a comment start and swallow everything to the next literal `*/`, including a real `import "./sibling.js"` in between. Because `STRING_REGEXP` (line 54: `"..."` / `'...'` / `` `...` `` with escapes) is tried before the scanner advances past the opening quote, the whole string is consumed as one token, comment-opener bytes included. Unterminated, it "simply doesn't match and the quote is stepped over" (line 53).

### Regex-literal handling

`REGEXP_LITERAL_REGEXP` (line 59) consumes a `/.../flags` literal whole for the same reason as strings: an unguarded `/[/*]/` would hand the block-comment matcher an opener at its embedded `/*` and lose the file to the next `*/` (lines 56-58; `module_inspector_test.rb:95-100`). A bare `/` is ambiguous between regex-open and division, so `regexp_literal_next?` (lines 193-196) tries the regex path only when the last `REGEXP_LOOKBEHIND_LIMIT = 32` characters (line 191, "wide enough for the longest keyword above... matching the whole buffer at every slash is quadratic, and pdf.js is a megabyte of minified source with a slash in every other line") of what's kept end with `BEFORE_REGEXP_LITERAL_REGEXP` (lines 66-71) — punctuation `( , = : [ ! & | ? { } ; + - * % ~ ^ < > ) }` or a keyword (`return throw typeof case in of do else yield await delete void instanceof new`). `)`/`}` are included even though they can also close a dividing expression, because "reading `(a + b) / 2` as a regex keeps the text either way, while leaving them out lets `if (x) /[/*]/` open a false comment" (lines 66-68) — "verified against 31 published packages — no verdict changes" (line 69), but no automated test covers this ambiguity (see grammar table).

### Safe failure direction

Class comment: "a false positive keeps a working remote pin... a package wrongly kept remote still works, a package wrongly vendored 404s in production" (lines 11-14). The scanner embodies this: text is deleted on exactly one branch (`scanner.skip(...)` on a matched comment); everything else — a string (line 179), a regex literal, a plain character (line 181) — is kept whole, so in the default scan a span the scanner can't be sure about is never dropped (the `statements_only` mode empties every literal to its delimiters and also skips line comments, by design; `review/inspection-and-tools.md` scopes the invariant).

### `es_module?`

```ruby
def es_module?
  statements.match?(ESM_STATEMENT_REGEXP) || !code.match?(COMMONJS_REGEXP)
end
```

(lines 136-138). `ESM_STATEMENT_REGEXP` (lines 80-86) matches every import/export spelling a published bundle uses, read against `statements` — every literal emptied to `literal[0, 1] * 2` (line 179) — so a quoted or commented-out import never counts, but `import "x"` still reads because its delimiters survive. `COMMONJS_REGEXP` (lines 98-101) matches `module.exports`, `exports.foo =` / `exports["foo"] =`, `.exports =`, `require(`, `define(`, or a `typeof exports/module/define ==`/`!=` sniff — read against `code` (strings and regex literals intact), "because a UMD wrapper hidden in a string is a UMD wrapper" (lines 131-135). A file with neither signal is taken for an ES module (`es_module?`, lines 136-138).

## Minifier (`lib/importmap/minifier.rb`)

**Discovery.** `TOOLS` (lines 11-15) lists `bun`, `esbuild`, `terser` — the order `detect` tries them (line 19). `executable_for` (lines 26-37) checks `node_modules/.bin` before every `PATH` directory (line 27; `minifier_test.rb:17-29`). `command_extensions` (lines 41-45) is `[""]` except on Windows, where npm installs these as shims, so it also tries every `PATHEXT` extension (default `.COM;.EXE;.BAT;.CMD`; `minifier_test.rb:31-47`).

**Argv per tool** (lines 12-14):

```ruby
"bun"     => ->(input, output) { [ "build", "--no-bundle", "--minify", "--format=esm", "--target=browser", input, "--outfile=#{output}" ] },
"esbuild" => ->(input, output) { [ input, "--minify", "--format=esm", "--outfile=#{output}" ] },
"terser"  => ->(input, output) { [ input, "--module", "--compress", "--mangle", "--output", output ] }
```

`call` (lines 55-75) writes `source` into a `Dir.mktmpdir`, runs `Open3.capture3(executable, *TOOLS.fetch(tool).call(input, output))` (line 67, an argv array — no shell string), raising `Error` if the process failed or the output file is missing. `--no-bundle` plus `--format=esm`/`--module` keep every tool transform-only: per `CLAUDE.md`, "bare specifiers stay exactly as the CDN resolved them and the import map keeps resolving them" — a bundler would rewrite those very specifiers. `minifier_test.rb:49-69` proves specifiers survive, but `skip`s unless a minifier is installed.

**Custom minifier hook.** Lives on `Importmap::Packager.minifier=` (`packager.rb:113-117`, `self.minifier ||= Importmap::Minifier.new`), used at `download_package_file` (`packager.rb:550`). Per the docs (`docs/app/views/docs/pages/minifying.rb:70-82`), the assignment must sit in `config/application.rb`, not an initializer: `bin/importmap` loads `config/application.rb` but not the app's initializers, so an assignment placed there wouldn't run before the CLI needs it.

**Errors.** `Error = Class.new(StandardError)` (line 9) — raised when no tool is found (line 59) or the chosen tool's process fails (line 70).

## HttpRetries (`lib/importmap/http_retries.rb`)

A module `include`d by `Importmap::Packager` (`packager.rb:9`) and `Importmap::Npm` (`npm.rb:7`), so both share one `with_retries` and one set of class-level accessors. `attempts` defaults to `3`, `wait` to `0.5` seconds (`singleton_class.attr_accessor :attempts, :wait`, lines 12-14). `Packager.retry_attempts=`/`retry_wait=` (`packager.rb:99-107`) delegate onto the same module attributes, so setting either through `Packager` changes it for `Npm` too.

```ruby
RETRYABLE_ERRORS = [ SocketError, SystemCallError, Timeout::Error, EOFError, OpenSSL::SSL::SSLError, Net::ProtocolError ].freeze
```

Retried codes (line 10): `%w[ 429 500 502 503 504 ]`. `with_retries` (lines 17-34) loops up to `attempts` times, sleeping `wait * attempt` between tries, returning early once attempts are exhausted or the code isn't retryable. Once a rescued transport error exhausts attempts it raises `self.class::HTTPError` — the *including* class's own error, so it's `Importmap::Packager::HTTPError` or `Importmap::Npm::HTTPError` — as `"Unexpected transport error #{description} (#{error.class}: #{error.message})"` (line 28). A still-retryable status code after the last attempt is returned as-is, left for the caller (e.g. `Packager#handle_failure_response`) to turn into its own error.

Tests zero the wait: `packager_test.rb:928-934`'s `without_retry_wait` sets `Importmap::Packager.retry_wait = 0` and restores it in `ensure`; `npm_test.rb:225-242` sets `Importmap::HttpRetries.wait = 0` directly (same module attribute) and restores it the same way.

**ProviderChain and retries.** `ProviderChain` (resolution mechanics are the packager lode's subject) does not retry itself — each CDN call is one `packager.import(*specs, env:, from: provider)` (`provider_chain.rb:63`), and `Packager#import`'s HTTP call is already wrapped in `with_retries`. A single provider is retried up to `HttpRetries.attempts` times before `ProviderChain` treats it as having said "no" and moves to the next — CDN fallback stacks on top of transport retries, not instead of them.

## Invariants and contracts

- A comment opener inside a string or regex literal is never read as a comment start, and in the default scan deletion happens on exactly one branch (a matched block comment; `statements_only` also empties literals and skips line comments, by design) — every other span, even one the scanner isn't sure about, is kept — `module_inspector_test.rb:72-125` (esp. lines 111-118).
- `reasons` precedence is fixed (relative imports, dynamic imports, workers, import.meta.url, wasm) — `module_inspector_test.rb:127-140`.
- A file with neither an ESM statement nor a CommonJS signal is an ES module — `module_inspector_test.rb:183-186`.
- An identifier merely ending in `import`/`export` is never a statement — `module_inspector_test.rb:188-192, 200-203`.
- The minifier never changes an import specifier — `minifier_test.rb:49-69` (skipped when no tool is installed); `node_modules/.bin` is checked before `PATH` — `:17-29`; Windows resolves only via a `PATHEXT` shim — `:31-47`.
- A transport error retries up to `HttpRetries.attempts` times then raises the including class's `HTTPError`, and a 429/5xx response retries the same way — `packager_test.rb:488-521, 527-541`; `npm_test.rb:225-249`.
- `Packager.retry_wait=` and `HttpRetries.wait=` mutate the one shared attribute — `packager_test.rb:928-934`, `npm_test.rb:225-242`.

## Grammar table (ModuleInspector)

| Form | Example | Result | Tested |
|---|---|---|---|
| Double-quoted relative import | `import"./modifiers/index.js"` | relative imports | yes — `:16` |
| Single-quoted relative import | `import a from '../_/f08a6ffe.js'` | relative imports | yes — `:15` |
| Relative export | `export{top}from"./enums.js"` | relative imports | yes — `:14` |
| Dynamic relative import | `import('../photoswipe.js')` | relative imports | yes — `:17` |
| Bare-specifier import | `import r from"crypt"` | vendorable | yes — `:20` |
| Scoped bare specifier | `import a from"@scope/pkg/sub/path"` | vendorable | yes — `:21` |
| `from` as plain identifier | `const from = "./not-an-import.js"` | vendorable | yes — `:22` |
| Computed dynamic import (identifier) | `import(name)` | dynamic imports | yes — `:27` |
| Computed dynamic import (template literal) | `` import(`${base}/chunk.js`) `` | dynamic imports | yes — `:28` |
| Computed dynamic import (concatenation) | `import("chunks/" + name)` | dynamic imports | yes — `:29` |
| Dynamic import, spaced identifier | `import( url )` | dynamic imports | yes — `:30` |
| Dynamic import, single string literal | `import("crypt")` / `import( "crypt" )` | vendorable | yes — `:32-33` |
| Dynamic import, string + attributes object | `import("crypt", { with: { type: "json" } })` | vendorable | yes — `:35` |
| Identifier merely containing "import" | `doimport(name)`, `mod.import(name)` | vendorable | yes — `:36-37` |
| Bare `new Worker(...)` | `new Worker(url)` | workers | yes — `:41` |
| `new SharedWorker(...)` | `new SharedWorker("./worker.js")` | workers | yes — `:42` |
| Qualified worker via global object | `new window.Worker(url)`, `new self.Worker(url)` | workers | yes — `:44-45` |
| Qualified worker, spaced dots | `new globalThis . SharedWorker(url)` | workers | yes — `:46` |
| Non-worker `*Worker*` constructor | `new WorkerPool(url)`, `new MyWorker.Factory(url)` | vendorable | yes — `:49-50` |
| `import.meta.url`, spaced | `import . meta . url` | import.meta.url | yes — `:55` |
| Lookalike, wrong preceding token | `ctx.import.meta.url` | vendorable | yes — `:58` |
| Wasm path, template literal | `` `${base}/onig.wasm` `` | wasm | yes — `:64` |
| Wasm path with query string | `"onig.wasm?v=1"` | wasm | yes — `:65` |
| Wasm path with fragment | `"onig.wasm#start"` | wasm | yes — `:66` |
| String merely mentioning "wasm" | `"compiled from wasm"`, `"wasmer.js"` | vendorable | yes — `:68-69` |
| Block-comment type annotation | `/** @typedef {import('./x.js').Foo} */` | discounted entirely | yes — `:72-78` |
| Comment-opener bytes inside a string | `"/*"` then `import sibling from "./sibling.js"` | string kept whole; import after it still read | yes — `:83-87` |
| Comment-opener bytes inside a regex literal | `/[/*]/` then `import y from "./sibling.js"` | regex kept whole; import after it still read | yes — `:95, 98-100` |
| Regex after a keyword far back on the line | `x instanceof Y ? a : /[/*]/.test(s)` then an import | recognized via 32-char lookbehind window | yes — `:103-109` |
| Quote characters inside a regex literal | `` /["']/ `` then a real block comment then an import | regex kept whole, not read as a string; real comment still stripped | yes — `:113-118` |
| Regex after `)`/`}` (division ambiguity) | `(a + b) / 2` | intentionally over-reads as regex | **no** — cited as manually verified against 31 packages, not automated |
| CommonJS assignment | `module.exports = md5` | not an ES module | yes — `:165` |
| CommonJS with `require` | `require("crypt"); module.exports = crypt` | not an ES module | yes — `:166` |
| UMD IIFE sniffing `typeof exports`/`module` | `(function(f){if(typeof exports==="object"...)})(...)` | not an ES module | yes — `:167` |
| `exports.foo = ...` property assignment | `exports.md5 = function() {}` | not an ES module | yes — `:221` |
| Computed `exports[...] =` | `exports["default"] = md5`, `exports['md5'] = md5` | not an ES module | yes — `:223-224` |
| AMD `define([...], fn)` | `define(["require", "exports"], function(require, exports) {})` | not an ES module | yes — `:225` |
| AMD `define(fn)` | `define(function() { return md5 })` | not an ES module | yes — `:226` |
| Loader sniff, `typeof exports`, no assignment | `typeof exports == 'object' && exports && ...` | not an ES module | yes — `:176` |
| Loader sniff, `typeof define ... define.amd` | `typeof define == 'function' && define.amd` | not an ES module | yes — `:177` |
| `module.exports` named only in a comment | `/** sets module.exports */ var a = require("x")` | not an ES module | yes — `:229-231` |
| Identifier starting with import/export | `importsKeys`, `importsValues`, `reimport`, `myexport` | not a statement or reason | yes — `:188-192, 200-203` |
| Import statement quoted inside a string | `"import md5 from 'md5'"` in a CommonJS file | not an ESM statement | yes — `:206-207` |
| Import/export written in a line comment | `// export default 1` then `require(...)` | not an ESM statement | yes — `:214-217` |
| Every ESM statement spelling | `import{a}from"b"`, `export * from`, `export default`, `export const/async function` | ES module | yes — `:149-159` |
| Multiple reasons on one file | relative import + dynamic import + worker + import.meta.url + wasm all present | all five reported in order; `reason` is the first | yes — `:127-140` |

## `Importmap::PackageGraph` — the file-graph crawl (fork-only)

`lib/importmap/package_graph.rb`. Given an entry URL, its source and the pin key,
`PackageGraph.build` returns the sibling files the entry needs, each rewritten so
the import map can serve it — or nil when this download is one file, and
`Unownable` when the graph can't be taken over whole. It is built through
`PackageGraph.for_download(packager, …)`, which assembles the crawl's inputs
from the packager, turns `Unownable` into `Unvendorable` carrying the hash of
the bytes the CDN served, and treats a sibling the CDN gives up on — a 500
after the retries, a body in an encoding this gem can't decode — as the same
answer as a 404.

- **When it engages** — the entry's `ModuleInspector` reasons are exactly
  `["relative imports"]`, it is an ES module, and the URL matches one of
  `ROOT_REGEXPS` (`ga.jspm.io/npm:`, `cdn.jsdelivr.net/npm/`, `unpkg.com`), whose
  capture is the package the keys are written under. esm.sh and skypack name no
  package directory in their paths, so a download from them stays remote. Reasons
  *besides* relative imports raise `Unownable` with only those, so a pin kept
  remote records the reason the graph can't answer for.
- **What it crawls** — breadth-first over `ModuleInspector#code` (block comments
  discounted, which is why a JSDoc `@typedef {import('./x.js')}` naming a file the
  package never ships doesn't 404 the pin), each specifier resolved against the
  file that imports it, each file fetched once.
- **Keys** — `<package>/<path without the extension>`, with a trailing `index`
  dropped, matching `Importmap::Map#module_name_from` exactly; `.mjs` is saved as
  `.js` because Map's glob is `**/*.js{,m}`.
- **What it refuses** (all as `Unownable("relative imports")`, because a remote pin
  works and a graph with a hole doesn't): a path that leaves the package root, one
  the CDN answers 404 for, one that isn't `.js`/`.mjs`, one whose segments aren't
  plain names (`..`, `a//b`, a leading `/`, a dot-directory), two files that would
  collapse to one key or differ only in case, a key the entry pin or another pin
  already owns, and — the backstop — any file whose rewritten source still carries
  a relative import, which is how a form the rewrite can't read (a magic comment
  between the keyword and the specifier) is caught rather than shipped.
- **Accepted limit** — like `ESM_RUN_IMPORT_REGEXP`, `IMPORT_REGEXP` doesn't parse
  JavaScript, so a data string spelling out an import statement is rewritten inside
  the string too.

## `Importmap::VendoredGraph` — the directory and its line (fork-only)

`lib/importmap/vendored_graph.rb`. The graph directory is
`vendor/javascript/<entry filename without .js>/` — named for the *pin*, so two
pins of one package each own their own — while the keys go under the package the
*CDN URL* names, so a module they share resolves to one key and is evaluated once
(jspm resolves Node's `buffer` and `crypto` into `@jspm/core`). `to:` on the line
is what makes the asset path match the directory.

Ownership is the line: `mapped?` requires both the directory path and the
`(graph of …)` comment, so a `pin_all_from` an app wrote itself is never rewritten
and its directory is never deleted. `write` builds a pid-suffixed partial beside
the target and `commit` renames the old directory aside, moves the new one in and
removes the old — restoring it if the move fails.

## Related

- [../packager/summary.md](../packager/summary.md) — pin-line rewriting, provenance, provider resolution; how `Unvendorable`/`NotAnEsModule` (raised from `ensure_servable`) feed a pin's `remote: <reason>` detail.
- [../review/inspection-and-tools.md](../review/inspection-and-tools.md)
- [../lode-map.md](../lode-map.md)
