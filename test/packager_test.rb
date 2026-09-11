require "test_helper"
require "importmap/packager"
require "minitest/mock"

class Importmap::PackagerTest < ActiveSupport::TestCase
  setup { @packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb")) }

  test "successful import with mock" do
    response = Class.new do
      def body
        { "map" => { "imports" => imports } }.to_json
      end

      def imports
        {
          "react" => "https://ga.jspm.io/npm:react@17.0.2/index.js",
          "object-assign" => "https://ga.jspm.io/npm:object-assign@4.1.1/index.js"
        }
      end

      def code() "200" end
    end.new

    @packager.stub(:post_json, response) do
      result = @packager.import("react@17.0.2")
      assert_equal response.imports, result[:imports]
    end
  end

  test "missing import with mock" do
    response = Class.new { def code() "404" end }.new

    @packager.stub(:post_json, response) do
      assert_nil @packager.import("missing-package-that-doesnt-exist@17.0.2")
    end
  end

  test "failed request with mock" do
    Net::HTTP.stub(:post, proc { raise "Unexpected Error" }) do
      assert_raises(Importmap::Packager::HTTPError) do
        @packager.import("missing-package-that-doesnt-exist@17.0.2")
      end
    end
  end

  test "packaged?" do
    assert @packager.packaged?("md5")
    assert_not @packager.packaged?("md5-extension")
  end

  test "pin_for" do
    assert_equal %(pin "react", to: "https://cdn/react"), @packager.pin_for("react", "https://cdn/react")
    assert_equal(
      %(pin "react", to: "https://cdn/react", preload: true),
      @packager.pin_for("react", "https://cdn/react", preloads: ["true"])
    )
    assert_equal(
      %(pin "react", to: "https://cdn/react", preload: false),
      @packager.pin_for("react", "https://cdn/react", preloads: ["false"])
    )
    assert_equal(
      %(pin "react", to: "https://cdn/react", preload: "foo"),
      @packager.pin_for("react", "https://cdn/react", preloads: ["foo"])
    )
    assert_equal(
      %(pin "react", to: "https://cdn/react", preload: ["foo", "bar"]),
      @packager.pin_for("react", "https://cdn/react", preloads: ["foo", "bar"])
    )

    assert_equal %(pin "react"), @packager.pin_for("react")
    assert_equal %(pin "react", preload: true), @packager.pin_for("react", preloads: ["true"])
  end

  test "vendored_pin_for" do
    assert_equal %(pin "react" # @17.0.2), @packager.vendored_pin_for("react", "https://cdn/react@17.0.2")
    assert_equal %(pin "javascript/react", to: "javascript--react.js" # @17.0.2), @packager.vendored_pin_for("javascript/react", "https://cdn/react@17.0.2")
    assert_equal %(pin "react", preload: true # @17.0.2), @packager.vendored_pin_for("react", "https://cdn/react@17.0.2", ["true"])
    assert_equal %(pin "react", preload: false # @17.0.2), @packager.vendored_pin_for("react", "https://cdn/react@17.0.2", ["false"])
    assert_equal %(pin "react", preload: "foo" # @17.0.2), @packager.vendored_pin_for("react", "https://cdn/react@17.0.2", ["foo"])
    assert_equal %(pin "react", preload: ["foo", "bar"] # @17.0.2), @packager.vendored_pin_for("react", "https://cdn/react@17.0.2", ["foo", "bar"])
  end

  test "extract_existing_pin_options with preload false" do
    temp_importmap = create_temp_importmap('pin "package1", preload: false')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: false }, options)
  end

  test "extract_existing_pin_options with preload true" do
    temp_importmap = create_temp_importmap('pin "package1", preload: true')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: true }, options)
  end

  test "extract_existing_pin_options with custom preload string" do
    temp_importmap = create_temp_importmap('pin "package1", preload: "custom"')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: "custom" }, options)
  end

  test "extract_existing_pin_options with custom preload array" do
    temp_importmap = create_temp_importmap('pin "package1", preload: ["custom1", "custom2"]')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: ["custom1", "custom2"] }, options)
  end

  test "extract_existing_pin_options with to option only" do
    temp_importmap = create_temp_importmap('pin "package1", to: "custom_path.js"')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ to: "custom_path.js" }, options)
  end

  test "extract_existing_pin_options with integrity option only" do
    temp_importmap = create_temp_importmap('pin "package1", integrity: "sha384-abcdef1234567890"')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({}, options)
  end

  test "extract_existing_pin_options with multiple options" do
    temp_importmap = create_temp_importmap('pin "package1", to: "path.js", preload: false, integrity: "sha384-abcdef1234567890"')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: false, to: "path.js" }, options)
  end

  test "extract_existing_pin_options with remote to option" do
    temp_importmap = create_temp_importmap('pin "package1", to: "https://ga.jspm.io/npm:package1@1.0.0/index.js", preload: false')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: false, to: "https://ga.jspm.io/npm:package1@1.0.0/index.js" }, options)
  end

  test "extract_existing_pin_options with version comment" do
    temp_importmap = create_temp_importmap('pin "package1", preload: false # @2.0.0')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({ preload: false }, options)
  end

  test "extract_existing_pin_options with no options" do
    temp_importmap = create_temp_importmap('pin "package1"')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "package1")

    assert_equal({}, options)
  end

  test "extract_existing_pin_options with nonexistent package" do
    temp_importmap = create_temp_importmap('pin "package1", preload: false')
    packager = Importmap::Packager.new(temp_importmap)

    options = extract_options_for_package(packager, "nonexistent")

    assert_equal({}, options)
  end

  test "extract_existing_pin_options with nonexistent file" do
    packager = Importmap::Packager.new("/nonexistent/path")

    options = extract_options_for_package(packager, "package1")

    assert_nil options
  end

  test "extract_existing_pin_options handles multiple packages in one call" do
    temp_importmap = create_temp_importmap(<<~PINS)
      pin "package1", preload: false
      pin "package2", preload: true
      pin "package3", preload: "custom"
      pin "package4" # no options
    PINS

    packager = Importmap::Packager.new(temp_importmap)

    result = packager.extract_existing_pin_options(["package1", "package2", "package3", "package4", "nonexistent"])

    assert_equal({
      "package1" => { preload: false },
      "package2" => { preload: true },
      "package3" => { preload: "custom" },
      "package4" => {},
      "nonexistent" => {}
    }, result)
  end

  test "remote_pin?" do
    temp_importmap = create_temp_importmap(<<~PINS)
      pin "remote", to: "https://ga.jspm.io/npm:remote@1.0.0/index.js"
      pin 'single', to: 'https://cdn.jsdelivr.net/npm/single@1.0.0/index.js'
      pin "local", to: "local.js"
      pin "bare"
    PINS
    packager = Importmap::Packager.new(temp_importmap)

    assert packager.remote_pin?("remote")
    assert packager.remote_pin?("single")
    assert_not packager.remote_pin?("local")
    assert_not packager.remote_pin?("bare")
    assert_not packager.remote_pin?("missing")
  end

  test "provider_for_url" do
    assert_equal "jspm.io", @packager.provider_for_url("https://ga.jspm.io/npm:md5@2.3.0/md5.js")
    assert_equal "unpkg", @packager.provider_for_url("https://unpkg.com/md5@2.3.0/md5.js")
    assert_equal "jsdelivr", @packager.provider_for_url("https://cdn.jsdelivr.net/npm/md5@2.3.0/md5.js")
    assert_equal "skypack", @packager.provider_for_url("https://cdn.skypack.dev/md5@2.3.0")
    assert_equal "esm.sh", @packager.provider_for_url("https://esm.sh/*md5@2.3.0/md5.js")
    assert_nil @packager.provider_for_url("https://cdn.example.com/md5.js")
    assert_nil @packager.provider_for_url("not a url")
  end

  test "extract_package_version_from" do
    assert_equal "@17.0.2", @packager.extract_package_version_from("https://cdn/react@17.0.2")
    assert_equal "@2.0.0-beta.19", @packager.extract_package_version_from("https://ga.jspm.io/npm:@jspm/core@2.0.0-beta.19/nodelibs/browser/buffer.js")
    assert_nil @packager.extract_package_version_from("https://cdn/react")
  end

  private

  def create_temp_importmap(content)
    temp_file = Tempfile.new(['importmap', '.rb'])
    temp_file.write(content)
    temp_file.close
    temp_file.path
  end

  def extract_options_for_package(packager, package_name)
    result = packager.extract_existing_pin_options(package_name)
    result[package_name]
  end

  test "provider_for_url tells esm.run bundles apart from plain jsdelivr files" do
    assert_equal "esm.run", @packager.provider_for_url("https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
    assert_equal "esm.run", @packager.provider_for_url("https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/+esm")
    assert_equal "jsdelivr", @packager.provider_for_url("https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js")
  end

  test "import from esm.run resolves versions through jsDelivr's data API" do
    requested = []
    resolved = Class.new do
      def code() "200" end
      def body() { "version" => "9.9.9" }.to_json end
    end.new

    Net::HTTP.stub(:get_response, ->(uri) { requested << uri.to_s; resolved }) do
      result = @packager.import("md5", "@hotwired/stimulus@3", "apexcharts@7.1.0/core", from: "esm.run")

      assert_equal({
        "md5"                => "https://cdn.jsdelivr.net/npm/md5@9.9.9/+esm",
        "@hotwired/stimulus" => "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@9.9.9/+esm",
        "apexcharts/core"    => "https://cdn.jsdelivr.net/npm/apexcharts@9.9.9/core/+esm"
      }, result[:imports])
    end

    assert_equal [
      "https://data.jsdelivr.com/v1/packages/npm/md5/resolved",
      "https://data.jsdelivr.com/v1/packages/npm/@hotwired/stimulus/resolved?specifier=3",
      "https://data.jsdelivr.com/v1/packages/npm/apexcharts/resolved?specifier=7.1.0"
    ], requested
  end

  test "import from esm.run returns nil for a package jsDelivr doesn't know" do
    missing = Class.new { def code() "404" end }.new

    Net::HTTP.stub(:get_response, missing) do
      assert_nil @packager.import("missing-package-that-doesnt-exist", from: "esm.run")
    end
  end

  test "download rewrites an esm.run bundle's imports to bare specifiers and reports its dependencies" do
    bundle = <<~JS
      import{a}from"/npm/charenc@0.0.2/+esm";import b from '/npm/@scope/pkg@1.0.0/sub/path/+esm';
      const c = () => import("/npm/crypt@0.0.2/+esm");
      export default a
    JS
    response = Class.new do
      define_method(:code) { "200" }
      define_method(:body) { bundle }
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      dependencies = Net::HTTP.stub(:get_response, response) do
        packager.download("md5", "https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
      end

      assert_equal [
        ["charenc", "https://cdn.jsdelivr.net/npm/charenc@0.0.2/+esm"],
        ["@scope/pkg/sub/path", "https://cdn.jsdelivr.net/npm/@scope/pkg@1.0.0/sub/path/+esm"],
        ["crypt", "https://cdn.jsdelivr.net/npm/crypt@0.0.2/+esm"]
      ], dependencies

      vendored = File.read(Pathname.new(vendor_dir).join("md5.js"))
      assert_equal "// md5@2.2.0 downloaded from https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm", vendored.lines.first.strip
      assert_includes vendored, %(from"charenc")
      assert_includes vendored, %(from '@scope/pkg/sub/path')
      assert_includes vendored, %(import("crypt"))
      assert_no_match %r{["']/npm/}, vendored
    end
  end

  test "download with minify runs the minifier and records it in the file header" do
    response = Class.new do
      def code() "200" end
      def body() "export  const   answer = 42;\n//# sourceMappingURL=index.js.map\n" end
    end.new
    original_minifier = Importmap::Packager.minifier
    Importmap::Packager.minifier = ->(source) { "MINIFIED:#{source.gsub(/\s+/, " ")}" }

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      dependencies = Net::HTTP.stub(:get_response, response) do
        packager.download("react", "https://ga.jspm.io/npm:react@17.0.2/index.js", minify: true)
      end

      assert_equal [], dependencies

      vendored = File.read(Pathname.new(vendor_dir).join("react.js"))
      assert_equal "// react@17.0.2 downloaded from https://ga.jspm.io/npm:react@17.0.2/index.js (minified)", vendored.lines.first.strip
      assert_includes vendored, "MINIFIED:export const answer = 42;"
    end
  ensure
    Importmap::Packager.minifier = original_minifier
  end

  test "vendored_pin_for records a non-default CDN and minification in the version comment" do
    assert_equal %(pin "react" # @17.0.2), @packager.vendored_pin_for("react", "https://ga.jspm.io/npm:react@17.0.2/index.js")
    assert_equal %(pin "react" # @17.0.2 (minified)),
                 @packager.vendored_pin_for("react", "https://ga.jspm.io/npm:react@17.0.2/index.js", minify: true)
    assert_equal %(pin "react" # @17.0.2 (unpkg)),
                 @packager.vendored_pin_for("react", "https://unpkg.com/react@17.0.2/index.js")
    assert_equal %(pin "luxon", preload: false # @3.7.2 (esm.run, minified)),
                 @packager.vendored_pin_for("luxon", "https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm", false, minify: true)
  end

  test "pin_provenance reads the version comment back" do
    Dir.mktmpdir do |dir|
      importmap_path = Pathname.new(dir).join("importmap.rb")
      File.write(importmap_path, <<~RUBY)
        pin "react" # @17.0.2
        pin "luxon", preload: false # @3.7.2 (esm.run, minified)
        pin "md5" # @2.2.0 (unpkg)
        pin "choices.js" # @11.2.4 (minified)
        pin "application"
      RUBY
      packager = Importmap::Packager.new(importmap_path)

      assert_equal({ version: "17.0.2", provider: nil, minified: false }, packager.pin_provenance("react"))
      assert_equal({ version: "3.7.2", provider: "esm.run", minified: true }, packager.pin_provenance("luxon"))
      assert_equal({ version: "2.2.0", provider: "unpkg", minified: false }, packager.pin_provenance("md5"))
      assert_equal({ version: "11.2.4", provider: nil, minified: true }, packager.pin_provenance("choices.js"))
      assert_nil packager.pin_provenance("application")
      assert_nil packager.pin_provenance("not-pinned")
    end
  end
end
