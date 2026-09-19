require "test_helper"
require "importmap/esm_run"
require "importmap/packager"

class Importmap::EsmRunTest < ActiveSupport::TestCase
  test "recognises the provider by the name --from and a pin comment use" do
    assert Importmap::EsmRun.provider?("esm.run")
    assert Importmap::EsmRun.provider?(:"esm.run")
    assert_not Importmap::EsmRun.provider?("jsdelivr")
    assert_not Importmap::EsmRun.provider?(nil)
  end

  test "tells a bundle URL apart from a plain jsDelivr file" do
    assert Importmap::EsmRun.url?("https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
    assert Importmap::EsmRun.url?("https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/+esm")
    assert_not Importmap::EsmRun.url?("https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js")
    assert_not Importmap::EsmRun.url?("https://ga.jspm.io/npm:md5@2.2.0/md5.js")
  end

  test "builds the bundle URL for a package, version and subpath" do
    assert_equal "https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm",
                 Importmap::EsmRun.url_for("md5", "2.2.0")
    assert_equal "https://cdn.jsdelivr.net/npm/apexcharts@7.1.0/core/+esm",
                 Importmap::EsmRun.url_for("apexcharts", "7.1.0", "/core")
    assert Importmap::EsmRun.url?(Importmap::EsmRun.url_for("@scope/pkg", "1.0.0", "/sub"))
  end

  test "rewrites a bundle's own imports to bare specifiers and lists them" do
    source = <<~JS
      import{a}from"/npm/charenc@0.0.2/+esm";import b from '/npm/@scope/pkg@1.0.0/sub/path/+esm';
      const c = () => import("/npm/crypt@0.0.2/+esm");
      export default a
    JS

    rewritten, dependencies = Importmap::EsmRun.rewrite_imports(source)

    assert_includes rewritten, %(from"charenc")
    assert_includes rewritten, %(from '@scope/pkg/sub/path')
    assert_includes rewritten, %(import("crypt"))
    assert_no_match %r{["']/npm/}, rewritten

    assert_equal [
      [ "charenc", "https://cdn.jsdelivr.net/npm/charenc@0.0.2/+esm" ],
      [ "@scope/pkg/sub/path", "https://cdn.jsdelivr.net/npm/@scope/pkg@1.0.0/sub/path/+esm" ],
      [ "crypt", "https://cdn.jsdelivr.net/npm/crypt@0.0.2/+esm" ]
    ], dependencies
  end

  test "leaves a string that only looks like a bundle URL alone" do
    source = %(import a from"/npm/charenc@0.0.2/+esm";const u="/npm/sneaky@1.0.0/+esm";export default[a,u])

    rewritten, dependencies = Importmap::EsmRun.rewrite_imports(source)

    assert_includes rewritten, %(const u="/npm/sneaky@1.0.0/+esm")
    assert_equal [ "charenc" ], dependencies.map(&:first)
  end

  test "warns when a bundle imports one dependency at two versions and pins the first" do
    source = %(import a from"/npm/charenc@0.0.1/+esm";import b from"/npm/charenc@0.0.2/+esm";export default[a,b])

    dependencies = nil
    _out, err = capture_io { _rewritten, dependencies = Importmap::EsmRun.rewrite_imports(source) }

    assert_match(/charenc is imported at 0\.0\.1, 0\.0\.2/, err)
    assert_equal [ [ "charenc", "https://cdn.jsdelivr.net/npm/charenc@0.0.1/+esm" ] ], dependencies
  end

  test "Packager.esm_run_resolver reads and writes the resolver this class holds" do
    original = Importmap::EsmRun.resolver

    assert_equal original, Importmap::Packager.esm_run_resolver

    Importmap::Packager.esm_run_resolver = URI("https://mirror.example.com/v1/packages/npm/")
    assert_equal URI("https://mirror.example.com/v1/packages/npm/"), Importmap::EsmRun.resolver
  ensure
    Importmap::EsmRun.resolver = original
  end

  test "resolves a version through the resolver and answers nil for a package it hasn't got" do
    packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"))
    requested = []
    resolved = Class.new do
      def code() "200" end
      def body() { "version" => "9.9.9" }.to_json end
    end.new

    Net::HTTP.stub(:get_response, ->(uri, *) { requested << uri.to_s; resolved }) do
      assert_equal({ imports: { "md5" => "https://cdn.jsdelivr.net/npm/md5@9.9.9/+esm" } },
                   Importmap::EsmRun.new(packager).imports([ "md5@2" ]))
    end

    assert_equal [ "https://data.jsdelivr.com/v1/packages/npm/md5/resolved?specifier=2" ], requested

    missing = Class.new { def code() "404" end }.new
    Net::HTTP.stub(:get_response, missing) do
      assert_nil Importmap::EsmRun.new(packager).imports([ "nope-not-a-package" ])
    end
  end

  test "an unparseable spec is this gem's own error, not a nil package" do
    packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"))

    assert_raises(Importmap::Packager::Error) { Importmap::EsmRun.new(packager).imports([ "@scope" ]) }
  end
end
