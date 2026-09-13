require "test_helper"
require "importmap/package_graph"
require "importmap/packager"

class Importmap::PackageGraphTest < ActiveSupport::TestCase
  ROOT = "https://ga.jspm.io/npm:pkg@1.0.0/".freeze

  test "crawls the files an entry imports and rewrites every specifier to its key" do
    graph = build_graph("dist/index.js", {
      "dist/index.js" => %(import u from"./util.js";import c from"../_/chunk.js";export{u,c}),
      "dist/util.js"  => %(export default 1),
      "_/chunk.js"    => %(import u from"../dist/util.js";export default u)
    })

    assert_equal 2, graph.size
    assert_equal %w[ _/chunk.js dist/util.js ], graph.files.keys.sort
    assert_equal %(import u from"pkg/dist/util";import c from"pkg/_/chunk";export{u,c}), graph.entry_source
    assert_equal %(import u from"pkg/dist/util";export default u), graph.files["_/chunk.js"]
    assert_equal "pkg", graph.under
  end

  test "resolves each specifier against the file that imports it" do
    graph = build_graph("a/one.js", {
      "a/one.js"   => %(import x from"./two.js";import y from"../b/two.js";export{x,y}),
      "a/two.js"   => %(export default "a"),
      "b/two.js"   => %(export default "b")
    })

    assert_equal %(import x from"pkg/a/two";import y from"pkg/b/two";export{x,y}), graph.entry_source
  end

  test "fetches a file imported from two places once" do
    fetched = []
    graph = build_graph("index.js", {
      "index.js"  => %(import a from"./a.js";import b from"./b.js";export{a,b}),
      "a.js"      => %(export{default}from"./shared.js"),
      "b.js"      => %(export{default}from"./shared.js"),
      "shared.js" => %(export default 1)
    }, on_fetch: ->(url) { fetched << url })

    assert_equal 3, graph.size
    assert_equal 1, fetched.count { |url| url.end_with?("shared.js") }
  end

  test "saves an .mjs sibling as .js and keys it without the extension" do
    graph = build_graph("index.js", {
      "index.js"    => %(export{default}from"./sibling.mjs"),
      "sibling.mjs" => %(export default 1)
    })

    assert_equal [ "sibling.js" ], graph.files.keys
    assert_equal %(export{default}from"pkg/sibling"), graph.entry_source
  end

  test "keeps the whole package remote when a relative path escapes the package root" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("dist/index.js", {
        "dist/index.js" => %(export{default}from"../../other@2.0.0/index.js")
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when the CDN doesn't have a file the entry imports" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", { "index.js" => %(export{default}from"./gone.js") })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when a sibling isn't JavaScript" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", {
        "index.js"  => %(import data from"./data.json";export default data),
        "data.json" => %({})
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when two files would collapse to one key" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", {
        "index.js"  => %(import a from"./dup.js";import b from"./dup.mjs";export{a,b}),
        "dup.js"    => %(export default 1),
        "dup.mjs"   => %(export default 2)
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when a sibling would take the entry's own key" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("dist/index.js", {
        "dist/index.js" => %(export{default}from"../index.js"),
        "index.js"      => %(export default 1)
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when a sibling would take a key another pin already has" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("dist/index.js", {
        "dist/index.js" => %(export{default}from"./extra.js"),
        "dist/extra.js" => %(export default 1)
      }, forbidden: [ "pkg/dist/extra" ])
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when a sibling needs more than the import map can give it" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", {
        "index.js"  => %(export{default}from"./worker-host.js"),
        "worker-host.js" => %(export default new Worker("./w.js"))
      })
    end

    assert_equal [ "workers" ], error.reasons
  end

  test "reports only the reasons the graph can't answer for when the entry needs more too" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", {
        "index.js" => %(import u from"./util.js";export default new Worker("./w.js")),
        "util.js"  => %(export default 1)
      })
    end

    assert_equal [ "workers" ], error.reasons
  end

  test "rewrites a file another pin already vendored to that pin's key instead of copying it" do
    graph = build_graph("dist/lightbox.js", {
      "dist/lightbox.js" => %(export{default}from"./core.js"),
      "dist/core.js"     => %(export default 1)
    }, known: { "#{ROOT}dist/core.js" => "pkg" })

    assert_empty graph.files
    assert_equal %(export{default}from"pkg"), graph.entry_source
  end

  test "leaves a relative specifier that only appears in a comment alone" do
    graph = build_graph("index.js", {
      "index.js" => %(/** @typedef {import('./types.js').T} T */\nexport{default}from"./util.js"),
      "util.js"  => %(export default 1)
    })

    assert_equal [ "util.js" ], graph.files.keys
    assert_includes graph.entry_source, %(import('./types.js'))
    assert_includes graph.entry_source, %(from"pkg/util")
  end

  test "is nothing to build for an entry with no relative imports" do
    assert_nil build_graph("index.js", { "index.js" => %(import x from"other";export default x) })
  end

  test "is nothing to build for a CDN whose files it can't address" do
    assert_nil Importmap::PackageGraph.build("https://esm.sh/pkg@1.0.0/index.js",
      %(export{default}from"./util.js"), package: "pkg") { |_url| nil }
  end

  test "is nothing to build for a download that isn't an ES module" do
    assert_nil build_graph("index.js", { "index.js" => %(var x=require("./util.js");module.exports=x) })
  end

  test "reads a scoped package's name and a subpath entry out of the URL" do
    graph = Importmap::PackageGraph.build("https://cdn.jsdelivr.net/npm/@scope/pkg@1.0.0/dist/index.js",
      %(export{default}from"./util.js"), package: "@scope/pkg/dist") do |url|
        %(export default 1) if url == "https://cdn.jsdelivr.net/npm/@scope/pkg@1.0.0/dist/util.js"
      end

    assert_equal "@scope/pkg", graph.under
    assert_equal %(export{default}from"@scope/pkg/dist/util"), graph.entry_source
  end

  test "crawls an unpkg entry" do
    graph = Importmap::PackageGraph.build("https://unpkg.com/pkg@1.0.0/index.js",
      %(export{default}from"./util.js"), package: "pkg") do |url|
        %(export default 1) if url == "https://unpkg.com/pkg@1.0.0/util.js"
      end

    assert_equal [ "util.js" ], graph.files.keys
  end

  test "keeps the whole package remote when a specifier it crawled comes back unrewritten" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("mid.js", {
        "mid.js"  => %(export default await import(/* webpackChunkName: "leaf" */ "./leaf.js")),
        "leaf.js" => %(export default 1)
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when a relative path leaves the package root sideways" do
    [ "..//tmp/evil.js", ".//a.js", "./sub//a.js" ].each do |specifier|
      error = assert_raises Importmap::PackageGraph::Unownable, "expected #{specifier} to be refused" do
        build_graph("dist/index.js", { "dist/index.js" => %(export{default}from"#{specifier}") })
      end

      assert_equal [ "relative imports" ], error.reasons
    end
  end

  test "keeps the whole package remote when a sibling hides in a dot directory" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", {
        "index.js"           => %(export{default}from"./.internal/x.js"),
        ".internal/x.js"     => %(export default 1)
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "keeps the whole package remote when two files differ only in case" do
    error = assert_raises Importmap::PackageGraph::Unownable do
      build_graph("index.js", {
        "index.js"  => %(import a from"./Locale.js";import b from"./locale.js";export{a,b}),
        "Locale.js" => %(export default 1),
        "locale.js" => %(export default 2)
      })
    end

    assert_equal [ "relative imports" ], error.reasons
  end

  test "crawls a dynamic import and an export star" do
    graph = build_graph("index.js", {
      "index.js"   => %(export*from"./star.js";export const load=()=>import("./lazy.js")),
      "star.js"    => %(export default 1),
      "lazy.js"    => %(export default 2)
    })

    assert_equal %w[ lazy.js star.js ], graph.files.keys.sort
    assert_equal %(export*from"pkg/star";export const load=()=>import("pkg/lazy")), graph.entry_source
  end

  test "crawls an import statement split over several lines" do
    graph = build_graph("index.js", {
      "index.js" => %(import {\n  a\n} from\n  "./util.js";\nexport default a),
      "util.js"  => %(export default 1)
    })

    assert_equal [ "util.js" ], graph.files.keys
    assert_includes graph.entry_source, %("pkg/util")
  end

  test "keeps the whole package remote when a specifier carries a query or no extension" do
    [ "./h.js?v=1", "./h.js#frag", "./sub/i", "./j.jsm" ].each do |specifier|
      assert_raises Importmap::PackageGraph::Unownable, "expected #{specifier} to be refused" do
        build_graph("index.js", { "index.js" => %(export{default}from"#{specifier}") })
      end
    end
  end

  test "reads the package out of a jsDelivr bundle URL and a prerelease version" do
    assert_equal "md5", Importmap::PackageGraph.package_for("https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
    assert_equal "pkg", Importmap::PackageGraph.package_for("https://unpkg.com/pkg@1.0.0-beta.1+build.5/dist/a.js")
    assert_nil Importmap::PackageGraph.package_for("https://unpkg.com/pkg/dist/a.js")
    assert_nil Importmap::PackageGraph.package_for("http://unpkg.com/pkg@1.0.0/dist/a.js")
    assert_nil Importmap::PackageGraph.package_for("https://GA.JSPM.IO/npm:pkg@1.0.0/index.js")
  end

  test "the keys it writes are the keys pin_all_from gives the directory it writes" do
    graph = build_graph("dist/index.js", {
      "dist/index.js"   => %(import a from"./nested/index.js";import b from"./util.mjs";export{a,b}),
      "dist/nested/index.js" => %(export default 1),
      "dist/util.mjs"   => %(export default 2)
    })

    assert_equal [ "pkg/dist/nested", "pkg/dist/util" ], map_keys_for(graph).sort
    assert_equal %(import a from"pkg/dist/nested";import b from"pkg/dist/util";export{a,b}), graph.entry_source
  end

  private
    # Draws the pin_all_from line the Packager writes for +graph+ over a real
    # directory of its files, so the keys the crawl rewrote specifiers to are
    # checked against the keys Importmap::Map actually expands, not against a
    # second copy of its rules.
    def map_keys_for(graph)
      Dir.mktmpdir do |dir|
        graph.files.each do |path, source|
          FileUtils.mkdir_p(File.join(dir, File.dirname(path)))
          File.write(File.join(dir, path), source)
        end

        map = Importmap::Map.new
        map.pin_all_from(dir, under: graph.under, to: "graph")
        JSON.parse(map.to_json(resolver: PassthroughResolver.new))["imports"].keys
      end
    end

    class PassthroughResolver
      def path_to_asset(path) = "/assets/#{path}"
    end

    def build_graph(entry, files, known: {}, forbidden: [], on_fetch: nil)
      Importmap::PackageGraph.build("#{ROOT}#{entry}", files.fetch(entry), package: "pkg",
                                    known: known, forbidden: forbidden) do |url|
        on_fetch&.call(url)
        files[url.delete_prefix(ROOT)]
      end
    end
end
