require "test_helper"
require "importmap/module_inspector"

class Importmap::ModuleInspectorTest < ActiveSupport::TestCase
  test "a package whose imports are all bare specifiers can be vendored" do
    inspector = inspect_source(%(import r from"crypt";import t from"charenc";export default r))

    assert inspector.vendorable?
    assert_empty inspector.reasons
    assert_nil inspector.reason
  end

  test "an export or import from a relative path is a relative import" do
    assert_reason "relative imports", %(export{top}from"./enums.js")
    assert_reason "relative imports", %(import a from '../_/f08a6ffe.js')
    assert_reason "relative imports", %(import"./modifiers/index.js")
    assert_reason "relative imports", %(const p = () => import('../photoswipe.js'))
    assert_reason "relative imports", %(export * from "./utils/detectOverflow.js")

    assert_vendorable %(import r from"crypt")
    assert_vendorable %(import a from"@scope/pkg/sub/path")
    assert_vendorable %(const from = "./not-an-import.js")
    assert_vendorable %(export default{from:"./enums.js"})
  end

  test "an import of something other than a string literal is a dynamic import" do
    assert_reason "dynamic imports", %(const load = name => import(name))
    assert_reason "dynamic imports", %(import(`${base}/chunk.js`))
    assert_reason "dynamic imports", %(import("chunks/" + name))
    assert_reason "dynamic imports", %(import( url ))

    assert_vendorable %(import("crypt"))
    assert_vendorable %(import( "crypt" ))
    assert_vendorable %(import("crypt"),import("charenc"))
    assert_vendorable %(import("crypt", { with: { type: "json" } }))
    assert_vendorable %(doimport(name))
    assert_vendorable %(mod.import(name))
  end

  test "constructing a worker is a worker" do
    assert_reason "workers", %(const w = new Worker(url))
    assert_reason "workers", %(new SharedWorker("./worker.js"))
    assert_reason "workers", %(new  Worker (u))
    assert_reason "workers", %(new window.Worker(url))
    assert_reason "workers", %(new self.Worker(url))
    assert_reason "workers", %(new globalThis . SharedWorker(url))

    assert_vendorable %(const Worker = 1)
    assert_vendorable %(new WorkerPool(url))
    assert_vendorable %(new MyWorker.Factory(url))
  end

  test "reading import.meta.url is import.meta.url" do
    assert_reason "import.meta.url", %(const base = import.meta.url)
    assert_reason "import.meta.url", %(new URL("x", import . meta . url))

    assert_vendorable %(const url = meta.url)
    assert_vendorable %(const url = ctx.import.meta.url)
  end

  test "a string naming a wasm file is wasm" do
    assert_reason "wasm", %(const binary = "./tiktoken_bg.wasm")
    assert_reason "wasm", %(fetch('shiki/onig.wasm'))
    assert_reason "wasm", %(const u = `${base}/onig.wasm`)
    assert_reason "wasm", %(fetch("onig.wasm?v=1"))
    assert_reason "wasm", %(fetch("onig.wasm#start"))

    assert_vendorable %(const note = "compiled from wasm")
    assert_vendorable %(const f = "wasmer.js")
  end

  test "a type annotation in a block comment is not an import" do
    assert_vendorable %(/** @typedef {import('../core/base.js').default} Base */)
    assert_vendorable <<~JS
      /** @typedef {import('./content.js').default} Content */
      /** @typedef {import("../photoswipe.js").Point} Point */
      export default class {}
    JS
    assert_vendorable %(/* new Worker("./w.js") — how it used to work */export default 1)

    # A comment opener inside a string is not a comment: the code after it
    # must still be read, or a real sibling import disappears from view.
    assert_reason "relative imports", <<~JS
      const open = "/*";
      import sibling from "./sibling.js";
      const close = "*/";
    JS
    assert_reason "workers", %(const s = '/* not a comment';const w = new Worker(u);const e = "*/")
    # A string is kept, not stripped, so text inside one still counts — the
    # documented caveat, and the harmless direction.
    assert_reason "relative imports", %(const marker = "/* @typedef {import('./x.js')} */";export default marker)

    # A regex literal is code, and a comment opener inside one is not a
    # comment: /[/*]/ would otherwise swallow the file to the next "*/".
    assert_reason "relative imports", %(const re = /[/*]/; import y from "./sibling.js"; const end = "*/";)
    assert_reason "workers", %(const re = /[/*]/; const w = new Worker(u); const end = "*/";)

    assert_reason "relative imports", %(if (x) /[/*]/.test(s); import y from "./sibling.js"; const e = "*/";)
    assert_reason "relative imports", %(throw /[/*]/.test(s); import y from "./sibling.js"; const e = "*/";)
    assert_reason "relative imports", %(function f(){} /[/*]/.test(s); import y from "./sibling.js"; const e = "*/";)

    # The token before the slash may be a keyword a long way back on the line.
    assert_reason "relative imports", <<~JS
      const ok = x instanceof Y
                 ? a
                 : /[/*]/.test(s);
      import y from "./sibling.js";
      const e = "*/";
    JS

    # A quote inside a regex literal can only ever leave a comment in place,
    # never hide code: a span read as a string is kept verbatim, not dropped.
    assert_reason "relative imports", <<~JS
      const re = /["']/;
      /* import "./commented.js" */
      import y from "./sibling.js";
    JS
    assert_reason "relative imports", %(const re = /["']/; /* c */ import y from "./sibling.js";)

    # Only the comment is discounted; code beside it still counts.
    assert_reason "relative imports", <<~JS
      /** @typedef {import('./types.js').Type} Type */
      export {default} from "./slide.js";
    JS
  end

  test "reasons are reported in a fixed precedence, reason being the first" do
    source = <<~JS
      import base from "./enums.js";
      const load = name => import(name);
      const w = new Worker(u);
      const here = import.meta.url;
      const binary = "./core.wasm";
    JS

    assert_equal [ "relative imports", "dynamic imports", "workers", "import.meta.url", "wasm" ],
                 inspect_source(source).reasons
    assert_equal "relative imports", inspect_source(source).reason
    assert_not inspect_source(source).vendorable?
  end

  test "a later pattern is reported on its own when the earlier ones are absent" do
    inspector = inspect_source(%(const here = import.meta.url; const b = "./core.wasm";))

    assert_equal [ "import.meta.url", "wasm" ], inspector.reasons
    assert_equal "import.meta.url", inspector.reason
  end

  test "a file with a top-level import or export statement is an ES module" do
    assert_es_module %(export default 1)
    assert_es_module %(import "./polyfill.js")
    assert_es_module %(export { a } from "b")
    assert_es_module %(import r from"crypt";import t from"charenc";var e={};export default e)
    assert_es_module %(export * from "./utils.js")
    assert_es_module %(export const VERSION = "1.0.0")
    assert_es_module %(export async function render() {})
    assert_es_module %(import{select}from"d3-selection";export{select})
    assert_es_module %(import a, { b } from "c"; export default a)
  end

  # jsDelivr serves a package's own dist file, which for plenty of packages is
  # the UMD bundle npm has always shipped. Vendoring one gives an import map
  # entry that resolves to a file exporting nothing.
  test "a CommonJS or UMD bundle is not an ES module" do
    assert_not_es_module %(module.exports = md5)
    assert_not_es_module %(const crypt = require("crypt"); module.exports = crypt)
    assert_not_es_module %((function(f){if(typeof exports==="object"&&typeof module!=="undefined"){module.exports=f()}})(function(){}))
    assert_not_es_module %(var a = require("./util"))
  end

  # lodash never writes `module.exports` in code — it reaches its exports
  # through `freeModule.exports` and spells the name out only in a comment,
  # which is stripped before any of this is read. The UMD sniff it opens with
  # is what gives it away.
  test "a UMD bundle that only sniffs for its loader is not an ES module" do
    assert_not_es_module %(var freeExports = typeof exports == 'object' && exports && !exports.nodeType && exports)
    assert_not_es_module %(if (typeof define == 'function' && define.amd) { define(function() { return _ }) })
    assert_not_es_module %(/** Detect `module.exports`. */ var moduleExports = freeModule && freeModule.exports === freeExports)
  end

  # Nothing says CommonJS and nothing says ESM: a side-effect-only module looks
  # exactly like this, and it is what every CDN in the chain would answer with.
  test "a file that claims neither is taken for an ES module" do
    assert_es_module %(console.log("hello"))
    assert_es_module %()
  end

  test "an identifier or method that merely ends in import or export is not a statement" do
    assert_not_es_module %(module.exports = { reimport: 1, myexport: 2, loader.import: 3 })
    assert_not_es_module %(module.exports = obj.import("x"))
    assert_not_es_module %(const exports2 = require("x"); module.exports = exports2)
  end

  # The two clauses read different text on purpose, each in the direction that
  # keeps a non-module out: an import statement is only believed outside a
  # string literal, a module.exports is believed wherever it appears.
  # lodash builds a template compiler out of variables called importsKeys and
  # importsValues; without a space between the keyword and the name, `imports,`
  # reads as an import of `s`.
  test "an identifier starting with import is not an import statement" do
    assert_not_es_module %(var importsKeys = keys(imports), importsValues = values(imports); module.exports = importsKeys)
    assert_not_es_module %(module.exports = function(imports, importsKeys) {})
  end

  test "an import statement quoted inside a CommonJS bundle is not an export" do
    assert_not_es_module %(const usage = "import md5 from 'md5'"; module.exports = usage)
    assert_not_es_module %(module.exports = { snippet: `export default 1` })
  end

  # A line comment is dropped before import statements are read, and only
  # there: for the vendorability patterns a `//` inside a regex literal is
  # dangerous to read as a comment, but here the worst it can do is send a
  # package on to the next CDN.
  test "an import or export written in a line comment is not a statement" do
    assert_not_es_module %(// export default 1\nvar a = require("x"))
    assert_not_es_module %(// usage: import md5 from "md5"\nmodule.exports = md5)
    assert_es_module %(// the real thing follows\nexport default 1)
  end

  test "an exports property assignment or an AMD define is not an ES module" do
    assert_not_es_module %(exports.md5 = function() {})
    assert_not_es_module %(exports.__esModule = true; exports.default = md5)
    assert_not_es_module %(exports["default"] = md5)
    assert_not_es_module %(exports['md5'] = md5)
    assert_not_es_module %(define(["require", "exports"], function(require, exports) {}))
    assert_not_es_module %(define(function() { return md5 }))
  end

  test "a module.exports written about in a comment still counts against the file" do
    assert_not_es_module %(/** sets module.exports */ var a = require("x"))
  end

  private
    def inspect_source(source)
      Importmap::ModuleInspector.new(source)
    end

    def assert_reason(reason, source)
      inspector = inspect_source(source)

      assert_not inspector.vendorable?, "expected #{source.inspect} to be unvendorable"
      assert_equal reason, inspector.reason
    end

    def assert_vendorable(source)
      inspector = inspect_source(source)

      assert inspector.vendorable?, "expected #{source.inspect} to be vendorable, got #{inspector.reasons.inspect}"
    end

    def assert_es_module(source)
      assert inspect_source(source).es_module?, "expected #{source.inspect} to be an ES module"
    end

    def assert_not_es_module(source)
      assert_not inspect_source(source).es_module?, "expected #{source.inspect} not to be an ES module"
    end
end
