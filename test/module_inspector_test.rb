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

    assert_vendorable %(import("crypt"))
    assert_vendorable %(doimport(name))
    assert_vendorable %(mod.import(name))
  end

  test "constructing a worker is a worker" do
    assert_reason "workers", %(const w = new Worker(url))
    assert_reason "workers", %(new SharedWorker("./worker.js"))
    assert_reason "workers", %(new  Worker (u))

    assert_vendorable %(const Worker = 1)
    assert_vendorable %(new WorkerPool(url))
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

    assert_vendorable %(const note = "compiled from wasm")
    assert_vendorable %(const f = "wasmer.js")
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
end
