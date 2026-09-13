How `Importmap::ModuleInspector` reads a download without parsing JavaScript, and how `Importmap::Minifier` picks its tool.

### `COMPUTED_IMPORT_REGEXP` treats an `import()` as computed unless its whole argument is one string literal
- **Holds because:** `import("chunks/" + name)` resolves to a path nobody can know at vendoring time, so the file cannot stand alone — but the lookahead would be satisfied by the leading `"chunks/"` alone. It therefore requires the closing quote to be followed by `)` or `,`. The whitespace lives *inside* the lookahead (`import\s*\((?!\s*["']…)`), which is what makes `import( "crypt" )` read correctly as static. Written the other way — `import\s*\(\s*` followed by the lookahead — `\s*` backtracks to zero, the lookahead reads the space instead of the quote, and that same spaced call is misread as computed.
- **Where:** `lib/importmap/module_inspector.rb#COMPUTED_IMPORT_REGEXP`
- **Safe direction:** reading a static import as computed is the harmless mistake — the package stays on its CDN and still works; reading a computed import as static vendors a file whose chunks 404 in production.
- **Proven by:** `test/module_inspector_test.rb:"an import of something other than a string literal is a dynamic import"`
- **Origin:** PR #22

### Block comments are discounted only after string literals have been consumed whole
- **Holds because:** running `/\*.*?\*/`m over the source reads a `"/*"` *inside a string* as a comment opener and swallows everything up to the next `*/` — and an `import "./sibling.js"` swallowed there is exactly the 404 this class exists to catch. The scan walks the source with `StringScanner`, matching `STRING_REGEXP` before anything else, so a comment opener inside a string is never reached. Comments are discounted at all because a published bundle is full of `/** @typedef {import('./slide.js').Slide} */` annotations naming files the package never loads.
- **Where:** `lib/importmap/module_inspector.rb#without_block_comments` (with `STRING_REGEXP`, `BLOCK_COMMENT_REGEXP`)
- **Safe direction:** keeping text that was really a comment only risks a false "can't be vendored", which leaves a working remote pin; dropping code that was really code hides the reason a package must stay remote.
- **Proven by:** `test/module_inspector_test.rb:"a type annotation in a block comment is not an import"`
- **Origin:** cubic learning d0c9956a; PR #22

### A `/` opens a regex literal after `throw`, after a control statement's `)`, or after `}`, with whitespace allowed in between
- **Holds because:** `if (x) /[/*]/` would otherwise be read as division, the `/*` inside the character class would be taken for a comment opener, and the file up to the next `*/` would be dropped. `BEFORE_REGEXP_LITERAL_REGEXP` therefore includes `)`, `}` and `throw` (alongside the other operators and keywords) and ends in `\s*\z` so indentation between the token and the slash does not break the match. Only the last 32 characters of what has been kept are examined — matching the whole buffer at every slash is quadratic, and pdf.js is a megabyte of minified source.
- **Where:** `lib/importmap/module_inspector.rb#BEFORE_REGEXP_LITERAL_REGEXP`, `#regexp_literal_next?`, `REGEXP_LOOKBEHIND_LIMIT`
- **Safe direction:** reading `(a + b) / 2` as a regex start keeps the text either way; not reading a real regex start loses code to a false comment. Over-inclusion is the safe error.
- **Proven by:** no test names this directly; exercised indirectly by `test/module_inspector_test.rb:"a type annotation in a block comment is not an import"` and the live `--minify`/vendoring cases in `test/commands_test.rb`
- **Origin:** cubic learning 0568e881

### In the default scan, the only branch that deletes text is the block comment; a string or regex literal is always kept
- **Holds because:** the loop has exactly three outcomes — skip a block comment, scan a literal and append it whole, or step one character forward. A literal is never dropped, so nothing the inspector needs to see can disappear behind a mis-read quote or slash. The `statements_only: true` mode used by `es_module?` is the deliberate exception: it also skips line comments and empties each literal to its bare delimiters (`literal[0, 1] * 2`), because there the worst outcome is sending a package on to the next CDN.
- **Where:** `lib/importmap/module_inspector.rb#without_block_comments`
- **Safe direction:** keeping a span is always safe; deleting one can erase the evidence that a package needs sibling files.
- **Proven by:** `test/module_inspector_test.rb:"an import statement quoted inside a CommonJS bundle is not an export"`, `:"an import or export written in a line comment is not a statement"`
- **Origin:** PR #22

### `WORKER_REGEXP` matches a dot-qualified constructor but not a name that merely ends in `Worker`
- **Holds because:** `new window.Worker(…)` and `new self.Worker(…)` fetch a top-level script that never goes through the import map, so the package cannot be vendored as one file — but `new WorkerPool(…)` and `new MyWorker.Factory(…)` are ordinary constructors. The qualifier group `(?:[\w$]+\s*\.\s*)*` requires the dot, and `(?:Shared)?Worker` must be the final segment before `(`.
- **Where:** `lib/importmap/module_inspector.rb#WORKER_REGEXP`
- **Proven by:** `test/module_inspector_test.rb:"constructing a worker is a worker"`
- **Origin:** cubic learning fea4fc2e

### `WASM_REGEXP` matches a `.wasm` path in any quote style, with an optional query or fragment after the extension
- **Holds because:** a `.wasm` binary is fetched at runtime by a path the package computes and is never part of the JavaScript file naming it, so the file cannot stand alone. The path is usually built in a template literal, hence the backtick in the delimiter class, and a cache-busting `?v=…` or `#…` after `.wasm` must not defeat the match.
- **Where:** `lib/importmap/module_inspector.rb#WASM_REGEXP`
- **Proven by:** `test/module_inspector_test.rb:"a string naming a wasm file is wasm"`
- **Origin:** cubic learning 71ab71fc

### Of the five vendorability patterns, only `WASM_REGEXP` can match a plain string; the other four are keyword-anchored
- **Holds because:** `RELATIVE_IMPORT_REGEXP`, `COMPUTED_IMPORT_REGEXP`, `WORKER_REGEXP` and `IMPORT_META_URL_REGEXP` all require `from`/`import`/`new`/`import.meta` before the text, so `const p = "./x.js"` matches none of them even though strings are deliberately kept whole by the scan. That is what makes keeping strings affordable: a bare path in a data string does not by itself keep a package remote.
- **Where:** `lib/importmap/module_inspector.rb#PATTERNS` and the four keyword-anchored regexps
- **Proven by:** `test/module_inspector_test.rb:"a package whose imports are all bare specifiers can be vendored"`, `:"an identifier or method that merely ends in import or export is not a statement"`
- **Origin:** PR #22

### `es_module?` reads import/export statements with line comments masked, and treats `exports.x =`, `exports["default"] =`, `module.exports`, `require(` and AMD `define(` as non-ESM markers
- **Holds because:** a bundle that ships a usage example in a comment or a string is still CommonJS, so the statement half reads `statements` (line comments dropped, literals emptied); the CommonJS half reads `code`, because a UMD wrapper hidden in a string is still a UMD wrapper. The loader sniff (`typeof exports|module|define`) is in the set because the assignment often is not — lodash reaches its exports through `freeModule.exports` and spells `module.exports` out only in a comment. A file that declares no exports of its own and carries any of these markers is not vendored: loaded through an import map it runs and exports nothing, and `import x from "pkg"` then fails to link in the browser, taking the importing module down with it.
- **Where:** `lib/importmap/module_inspector.rb#es_module?`, `ESM_STATEMENT_REGEXP`, `COMMONJS_REGEXP`, `LINE_COMMENT_REGEXP`; raised as `Importmap::Packager::NotAnEsModule` in `packager.rb#ensure_servable`
- **Safe direction:** calling a real ES module CommonJS only sends the package on to the next CDN or keeps it remote; calling a UMD bundle an ES module vendors a file that breaks every page importing it, in the browser only.
- **Proven by:** `test/module_inspector_test.rb:"a CommonJS or UMD bundle is not an ES module"`, `:"a UMD bundle that only sniffs for its loader is not an ES module"`, `:"an exports property assignment or an AMD define is not an ES module"`, `:"an import or export written in a line comment is not a statement"`, `:"a module.exports written about in a comment still counts against the file"`
- **Origin:** PR #24

### `Importmap::Minifier` normalizes any tool that isn't `:auto` with `to_s` before looking it up
- **Holds because:** `TOOLS` is keyed by strings, so `Minifier.new(:terser)` would miss every key and `TOOLS.fetch(tool)` would raise `KeyError` instead of running terser. `@tool = tool == :auto ? self.class.detect : tool&.to_s` makes a symbol, a string and nil all behave.
- **Where:** `lib/importmap/minifier.rb#initialize` (with `TOOLS`, `#call`)
- **Proven by:** `test/minifier_test.rb:"accepts a tool name as a symbol"`
- **Origin:** cubic learning 4c9f52bf

### Not a bug: a relative specifier in a *line* comment is fetched, and 404s the whole package
- **Holds because:** `ModuleInspector#code` discounts block comments only — line comments are kept on purpose, because stripping them means reading `//` as an opener inside a regex literal such as `[//]` and dropping code that decides whether a package can be vendored. `PackageGraph` reads the same text, so `// import legacy from "./legacy.js"` is crawled, the CDN answers 404 and the package stays remote. That is the same verdict the same source gets without the crawl — the inspector reports `relative imports` for it either way — so nothing regressed, and the direction is the safe one.
- **Where:** `lib/importmap/module_inspector.rb#without_block_comments`; `lib/importmap/package_graph.rb#discover`
- **Origin:** gate round 1 (parser), PR #30

### Accepted limit: a data string that spells out an import statement is rewritten inside the string
- **Holds because:** `PackageGraph::IMPORT_REGEXP` is anchored on the keyword and doesn't parse JavaScript, exactly like `Packager::ESM_RUN_IMPORT_REGEXP`, so `export const doc = 'import x from "./util.js"'` comes out as `'import x from "pkg/util"'`. The gem takes no JavaScript parser as a dependency; a published bundle carrying such a string has not been seen, and the alternative — a scanner that tracks literals through a `gsub` — is the parser this class exists to avoid. Recorded so the next reviewer doesn't raise it as new.
- **Where:** `lib/importmap/package_graph.rb#IMPORT_REGEXP`, `#rewrite_specifiers`
- **Origin:** gate round 1 (parser), PR #30
