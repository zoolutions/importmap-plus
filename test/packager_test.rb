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

  test "extract_existing_pin_options keeps a boolean integrity" do
    temp_importmap = create_temp_importmap(<<~PINS)
      pin "package1", integrity: false
      pin "package2", to: "https://cdn/package2@1.0.0/index.js", preload: false, integrity: true
      pin 'package3', integrity: true # @1.0.0
    PINS
    packager = Importmap::Packager.new(temp_importmap)

    assert_equal({ integrity: false }, extract_options_for_package(packager, "package1"))
    assert_equal({ preload: false, to: "https://cdn/package2@1.0.0/index.js", integrity: true },
                 extract_options_for_package(packager, "package2"))
    assert_equal({ integrity: true }, extract_options_for_package(packager, "package3"))
  end

  test "pin_for and vendored_pin_for keep a boolean integrity" do
    assert_equal %(pin "react", to: "https://cdn/react", integrity: false),
                 @packager.pin_for("react", "https://cdn/react", integrity: false)
    assert_equal %(pin "react", preload: false, integrity: true),
                 @packager.pin_for("react", preloads: ["false"], integrity: true)
    assert_equal %(pin "react", integrity: false # @17.0.2),
                 @packager.vendored_pin_for("react", "https://cdn/react@17.0.2", integrity: false)
    assert_equal %(pin "react"), @packager.pin_for("react", integrity: nil)
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

  test "import from esm.run keeps an unscoped subpath out of the package name" do
    requested = []
    resolved = Class.new do
      def code() "200" end
      def body() { "version" => "7.1.0" }.to_json end
    end.new

    Net::HTTP.stub(:get_response, ->(uri) { requested << uri.to_s; resolved }) do
      result = @packager.import("apexcharts/core", "@scope/pkg/sub", from: "esm.run")

      assert_equal({
        "apexcharts/core" => "https://cdn.jsdelivr.net/npm/apexcharts@7.1.0/core/+esm",
        "@scope/pkg/sub"  => "https://cdn.jsdelivr.net/npm/@scope/pkg@7.1.0/sub/+esm"
      }, result[:imports])
    end

    assert_equal [
      "https://data.jsdelivr.com/v1/packages/npm/apexcharts/resolved",
      "https://data.jsdelivr.com/v1/packages/npm/@scope/pkg/resolved"
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

  test "package_key_for names the pin a spec resolves to" do
    assert_equal "md5", @packager.package_key_for("md5@2.2.0")
    assert_equal "apexcharts/core", @packager.package_key_for("apexcharts@7.1.0/core")
    assert_equal "apexcharts/core", @packager.package_key_for("apexcharts/core")
    assert_equal "@hotwired/stimulus", @packager.package_key_for("@hotwired/stimulus@3")
    assert_equal "@scope/pkg/sub", @packager.package_key_for("@scope/pkg@1.0.0/sub")
  end

  test "package_name_for is the package a spec or key belongs to" do
    assert_equal "photoswipe", @packager.package_name_for("photoswipe/lightbox")
    assert_equal "photoswipe", @packager.package_name_for("photoswipe@5.4.4/lightbox")
    assert_equal "@hotwired/stimulus", @packager.package_name_for("@hotwired/stimulus@3")
    assert_equal "@github/webauthn-json", @packager.package_name_for("@github/webauthn-json/browser-ponyfill")
    assert_equal "md5", @packager.package_name_for("md5")
  end

  test "download warns when a bundle imports one dependency at two versions" do
    bundle = %(import a from"/npm/charenc@0.0.1/+esm";import b from"/npm/charenc@0.0.2/+esm";export default[a,b])
    response = Class.new do
      define_method(:code) { "200" }
      define_method(:body) { bundle }
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      dependencies = nil
      _out, err = capture_io do
        dependencies = Net::HTTP.stub(:get_response, response) do
          packager.download("md5", "https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
        end
      end

      assert_equal [ [ "charenc", "https://cdn.jsdelivr.net/npm/charenc@0.0.1/+esm" ] ], dependencies
      assert_match(/charenc is imported at 0\.0\.1, 0\.0\.2/, err)
      assert_equal 2, File.read(Pathname.new(vendor_dir).join("md5.js")).scan(%(from"charenc")).size
    end
  end

  test "download only rewrites an esm.run bundle's module specifiers" do
    bundle = %(import a from"/npm/charenc@0.0.2/+esm";const u="/npm/sneaky@1.0.0/+esm";export default[a,u])
    response = Class.new do
      define_method(:code) { "200" }
      define_method(:body) { bundle }
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      dependencies = Net::HTTP.stub(:get_response, response) do
        packager.download("md5", "https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
      end

      assert_equal [ [ "charenc", "https://cdn.jsdelivr.net/npm/charenc@0.0.2/+esm" ] ], dependencies

      vendored = File.read(Pathname.new(vendor_dir).join("md5.js"))
      assert_includes vendored, %(import a from"charenc")
      assert_includes vendored, %(const u="/npm/sneaky@1.0.0/+esm")
    end
  end

  test "reload! drops the cached import map so a pin written now is seen next" do
    Dir.mktmpdir do |dir|
      importmap_path = Pathname.new(dir).join("importmap.rb")
      File.write(importmap_path, %(pin "react" # @17.0.2\n))
      packager = Importmap::Packager.new(importmap_path)

      assert packager.packaged?("react")
      assert_not packager.packaged?("md5")

      File.write(importmap_path, %(pin "react" # @17.0.2\npin "md5" # @2.2.0\n))
      assert_not packager.packaged?("md5"), "expected the import map to be memoized"

      packager.reload!
      assert packager.packaged?("md5")
    end
  end

  test "provenance_for describes what a pin for this URL would record" do
    assert_equal({ provider: nil, minified: false },
                 @packager.provenance_for("https://ga.jspm.io/npm:react@17.0.2/index.js"))
    assert_equal({ provider: nil, minified: true },
                 @packager.provenance_for("https://ga.jspm.io/npm:react@17.0.2/index.js", minify: true))
    assert_equal({ provider: "esm.run", minified: false },
                 @packager.provenance_for("https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm"))
    assert_equal({ provider: "unpkg", minified: false },
                 @packager.provenance_for("https://unpkg.com/react@17.0.2/index.js"))
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

  test "download retries a reset connection before giving up" do
    attempts = 0
    response = Class.new do
      def code() "200" end
      def body() "export default 1" end
    end.new
    flaky = ->(_uri) { attempts += 1; raise Errno::ECONNRESET, "SSL_connect" if attempts < 3; response }

    without_retry_wait do
      Dir.mktmpdir do |vendor_dir|
        packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

        Net::HTTP.stub(:get_response, flaky) { packager.download("react", "https://ga.jspm.io/npm:react@17.0.2/index.js") }

        assert_equal 3, attempts
        assert_includes File.read(Pathname.new(vendor_dir).join("react.js")), "export default 1"
      end
    end
  end

  test "download gives up on a connection that keeps resetting" do
    attempts = 0
    broken = ->(_uri) { attempts += 1; raise Errno::ECONNRESET, "SSL_connect" }

    without_retry_wait do
      Dir.mktmpdir do |vendor_dir|
        packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

        error = Net::HTTP.stub(:get_response, broken) do
          assert_raises(Importmap::Packager::HTTPError) { packager.download("react", "https://ga.jspm.io/npm:react@17.0.2/index.js") }
        end

        assert_equal Importmap::Packager.retry_attempts, attempts
        assert_match(/Connection reset|SSL_connect/, error.message)
        assert_not File.exist?(Pathname.new(vendor_dir).join("react.js"))
      end
    end
  end

  test "import retries a rate-limited response" do
    responses = [
      Class.new { def code() "429" end; def body() "" end }.new,
      Class.new { def code() "200" end; def body() { "map" => { "imports" => { "react" => "https://ga.jspm.io/npm:react@17.0.2/index.js" } } }.to_json end }.new
    ]
    attempts = 0

    without_retry_wait do
      Net::HTTP.stub(:post, ->(*) { attempts += 1; responses.shift }) do
        assert_equal "https://ga.jspm.io/npm:react@17.0.2/index.js", @packager.import("react@17.0.2")[:imports]["react"]
      end
    end

    assert_equal 2, attempts
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

      assert_equal({ version: "17.0.2", provider: nil, minified: false, vendored: false, remote: nil, locked: false }, packager.pin_provenance("react"))
      assert_equal({ version: "3.7.2", provider: "esm.run", minified: true, vendored: false, remote: nil, locked: false }, packager.pin_provenance("luxon"))
      assert_equal({ version: "2.2.0", provider: "unpkg", minified: false, vendored: false, remote: nil, locked: false }, packager.pin_provenance("md5"))
      assert_equal({ version: "11.2.4", provider: nil, minified: true, vendored: false, remote: nil, locked: false }, packager.pin_provenance("choices.js"))
      assert_nil packager.pin_provenance("application")
      assert_nil packager.pin_provenance("not-pinned")
    end
  end

  test "pin_provenance reads a lock back, including the reserved range form" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "react" # @17.0.2 (locked)
      pin "luxon", preload: false # @3.7.2 (esm.run, minified, locked)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)
      pin "chart.js" # @4.4.0 (unpkg, locked: ~4.4)
      pin "stimulus-use" # @0.53.1 (esm.run)
    RUBY

    assert_equal({ version: "17.0.2", provider: nil, minified: false, vendored: false, remote: nil, locked: true }, packager.pin_provenance("react"))
    assert_equal({ version: "3.7.2", provider: "esm.run", minified: true, vendored: false, remote: nil, locked: true }, packager.pin_provenance("luxon"))
    assert_equal({ version: "2.2.0", provider: nil, minified: false, vendored: false, remote: nil, locked: true }, packager.pin_provenance("md5"))
    assert_equal({ version: "4.4.0", provider: "unpkg", minified: false, vendored: false, remote: nil, locked: true }, packager.pin_provenance("chart.js"))
    assert_equal({ version: "0.53.1", provider: "esm.run", minified: false, vendored: false, remote: nil, locked: false }, packager.pin_provenance("stimulus-use"))
  end

  test "vendored_pin_for and pin_for record a lock in the version comment" do
    assert_equal %(pin "react" # @17.0.2 (locked)),
                 @packager.vendored_pin_for("react", "https://ga.jspm.io/npm:react@17.0.2/index.js", locked: true)
    assert_equal %(pin "luxon", preload: false # @3.7.2 (esm.run, minified, locked)),
                 @packager.vendored_pin_for("luxon", "https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm", false, minify: true, locked: true)
    assert_equal %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)),
                 @packager.pin_for("md5", "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preloads: ["false"], locked: true)
    assert_equal %(pin "md5", to: "https://cdn.example.com/md5.js"),
                 @packager.pin_for("md5", "https://cdn.example.com/md5.js", locked: true)
  end

  test "pinned_packages lists every import-map key in file order" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "react" # @17.0.2
      pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"
      pin '@hotwired/stimulus', to: "@hotwired--stimulus.js" # @3.2.2
      pin_all_from "app/javascript/controllers", under: "controllers"
    RUBY

    assert_equal %w[react photoswipe/lightbox @hotwired/stimulus], packager.pinned_packages
  end

  test "pinned_packages is empty without an importmap" do
    assert_empty Importmap::Packager.new("tmp/does-not-exist.rb").pinned_packages
  end

  test "pin_version reads the version from a comment or a CDN URL, and nowhere else" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "react" # @17.0.2 (locked)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js"
      pin "photoswipe/lightbox", to: "https://ga.jspm.io/npm:photoswipe@5.3.0/dist/photoswipe-lightbox.esm.js"
      pin "md5/helpers", to: "md5/helpers.js"
      pin "application"
    RUBY

    assert_equal "17.0.2", packager.pin_version("react")
    assert_equal "2.2.0", packager.pin_version("md5")
    assert_equal "5.3.0", packager.pin_version("photoswipe/lightbox")
    assert_nil packager.pin_version("md5/helpers")
    assert_nil packager.pin_version("application")
    assert_nil packager.pin_version("not-pinned")
  end

  test "package_spec_for puts the version ahead of the subpath" do
    packager = Importmap::Packager.new(create_temp_importmap(""))

    assert_equal "photoswipe@5.4.4/lightbox", packager.package_spec_for("photoswipe/lightbox", "@5.4.4")
    assert_equal "md5@2.3.0", packager.package_spec_for("md5", "@2.3.0")
    assert_equal "@hotwired/stimulus@3.2.2/webpack-helpers",
                 packager.package_spec_for("@hotwired/stimulus/webpack-helpers", "@3.2.2")
    assert_equal "photoswipe/lightbox", packager.package_spec_for("photoswipe/lightbox", nil)
  end

  test "locked? and locked_pins" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "react" # @17.0.2 (locked)
      pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2 (esm.run, locked)
      pin "apexcharts/core", to: "apexcharts--core.js" # @7.1.0 (locked)
      pin "luxon" # @3.7.2
      pin "application"
    RUBY

    assert packager.locked?("react")
    assert packager.locked?("@hotwired/stimulus")
    assert_not packager.locked?("luxon")
    assert_not packager.locked?("application")
    assert_not packager.locked?("not-pinned")
    assert_equal %w[react @hotwired/stimulus apexcharts/core], packager.locked_pins
  end

  test "locked_pin_line adds the marker without touching the rest of the line" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "react" # @17.0.2
      pin "luxon", preload: false # @3.7.2 (esm.run, minified)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false
      pin 'charenc', preload: true, integrity: false #@0.0.2
      pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
      pin "already" # @1.0.0 (locked)
    RUBY

    assert_equal %(pin "react" # @17.0.2 (locked)), packager.locked_pin_line("react")
    assert_equal %(pin "luxon", preload: false # @3.7.2 (esm.run, minified, locked)), packager.locked_pin_line("luxon")
    assert_equal %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)),
                 packager.locked_pin_line("md5")
    assert_equal %(pin 'charenc', preload: true, integrity: false # @0.0.2 (locked)), packager.locked_pin_line("charenc")
    assert_equal %(pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2 (locked)),
                 packager.locked_pin_line("@hotwired/stimulus")
    assert_equal %(pin "already" # @1.0.0 (locked)), packager.locked_pin_line("already")
  end

  test "locked_pin_line returns nil when there is no version to lock at" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "custom", to: "https://cdn.example.com/custom.js"
      pin "application"
      pin "local", to: "local.js", preload: false
      pin "versioned", to: "versioned@1.2.3.js"
    RUBY

    assert_nil packager.locked_pin_line("custom")
    assert_nil packager.locked_pin_line("application")
    assert_nil packager.locked_pin_line("local")
    assert_nil packager.locked_pin_line("versioned")
    assert_nil packager.locked_pin_line("not-pinned")
  end

  test "unlocked_pin_line removes the marker" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "luxon", preload: false # @3.7.2 (esm.run, minified, locked)
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js" # @2.2.0 (locked)
      pin "chart.js" # @4.4.0 (locked: ~4.4)
      pin "react" # @17.0.2
    RUBY

    assert_equal %(pin "luxon", preload: false # @3.7.2 (esm.run, minified)), packager.unlocked_pin_line("luxon")
    assert_equal %(pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js" # @2.2.0), packager.unlocked_pin_line("md5")
    assert_equal %(pin "chart.js" # @4.4.0), packager.unlocked_pin_line("chart.js")
    assert_equal %(pin "react" # @17.0.2), packager.unlocked_pin_line("react")
    assert_nil packager.unlocked_pin_line("not-pinned")
  end

  test "extract_existing_pin_options ignores the lock comment" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js", preload: false # @2.2.0 (locked)
    RUBY

    assert_equal({ preload: false, to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js" }, extract_options_for_package(packager, "md5"))
  end

  test "download refuses a source that can't stand alone and leaves the vendored file it has" do
    response = Class.new do
      def code() "200" end
      def body() %(export{top}from"./enums.js";const w=new Worker(u)) end
    end.new

    Dir.mktmpdir do |vendor_dir|
      existing = Pathname.new(vendor_dir).join("@popperjs--core.js")
      File.write(existing, "// the file that works today")
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      error = Net::HTTP.stub(:get_response, response) do
        assert_raises(Importmap::Packager::Unvendorable) do
          packager.download("@popperjs/core", "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js")
        end
      end

      assert_equal [ "relative imports", "workers" ], error.reasons
      assert_equal "// the file that works today", File.read(existing)
    end
  end

  test "download with force vendors a source that can't stand alone anyway" do
    response = Class.new do
      def code() "200" end
      def body() %(export{top}from"./enums.js") end
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      dependencies = Net::HTTP.stub(:get_response, response) do
        packager.download("@popperjs/core", "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js", force: true)
      end

      assert_equal [], dependencies
      assert_includes File.read(Pathname.new(vendor_dir).join("@popperjs--core.js")), %(from"./enums.js")
    end
  end

  test "download inspects an esm.run bundle after its imports become bare specifiers" do
    bundle = %(import{a}from"/npm/charenc@0.0.2/+esm";export default a)
    response = Class.new do
      define_method(:code) { "200" }
      define_method(:body) { bundle }
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      dependencies = Net::HTTP.stub(:get_response, response) do
        packager.download("md5", "https://cdn.jsdelivr.net/npm/md5@2.2.0/+esm")
      end

      assert_equal [ [ "charenc", "https://cdn.jsdelivr.net/npm/charenc@0.0.2/+esm" ] ], dependencies
    end
  end

  test "pin_provenance reads a remote reason back without mistaking it for a provider" do
    packager = Importmap::Packager.new(file_fixture("remote_reason_import_map.rb").to_s)

    assert_equal({ version: "2.11.8", provider: nil, minified: false, vendored: false,
                   remote: "relative imports", locked: false },
                 packager.pin_provenance("@popperjs/core"))
    assert_equal({ version: "0.52.2", provider: nil, minified: false, vendored: false,
                   remote: "workers", locked: true },
                 packager.pin_provenance("monaco-editor"))
    assert_equal({ version: "3.7.2", provider: "esm.run", minified: true, vendored: false,
                   remote: nil, locked: false },
                 packager.pin_provenance("luxon"))
  end

  test "pin_provenance reads a bare remote detail and a vendored detail" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "shiki", to: "https://ga.jspm.io/npm:shiki@1.0.0/index.js" # @1.0.0 (remote)
      pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8 (vendored)
      pin "chart.js" # @4.4.0 (unpkg, minified, vendored, locked)
    RUBY

    assert_equal true, packager.pin_provenance("shiki")[:remote]
    assert_equal true, packager.pin_provenance("@popperjs/core")[:vendored]
    assert_equal({ version: "4.4.0", provider: "unpkg", minified: true, vendored: true,
                   remote: nil, locked: true },
                 packager.pin_provenance("chart.js"))
  end

  test "remote_reason and vendored? read the pin's decision back" do
    packager = Importmap::Packager.new(file_fixture("remote_reason_import_map.rb").to_s)

    assert_equal "relative imports", packager.remote_reason("@popperjs/core")
    assert_equal "workers", packager.remote_reason("monaco-editor")
    assert_nil packager.remote_reason("luxon")
    assert_nil packager.remote_reason("not-pinned")
    assert_not packager.vendored?("luxon")
  end

  test "pin_for records why a pin was kept remote, with the lock last" do
    assert_equal %(pin "@popperjs/core", to: "https://cdn/core@2.11.8/i.js" # @2.11.8 (remote: workers)),
                 @packager.pin_for("@popperjs/core", "https://cdn/core@2.11.8/i.js", remote: "workers")
    assert_equal %(pin "@popperjs/core", to: "https://cdn/core@2.11.8/i.js", preload: false # @2.11.8 (remote: relative imports, locked)),
                 @packager.pin_for("@popperjs/core", "https://cdn/core@2.11.8/i.js", preloads: [ "false" ],
                                                     remote: "relative imports", locked: true)
    assert_equal %(pin "shiki", to: "https://cdn/shiki@1.0.0/i.js" # @1.0.0 (remote)),
                 @packager.pin_for("shiki", "https://cdn/shiki@1.0.0/i.js", remote: true)
    assert_equal %(pin "md5", to: "https://cdn.example.com/md5.js"),
                 @packager.pin_for("md5", "https://cdn.example.com/md5.js", remote: "workers")
  end

  test "vendored_pin_for records a deliberate vendor ahead of the lock" do
    assert_equal %(pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8 (vendored)),
                 @packager.vendored_pin_for("@popperjs/core", "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js", vendored: true)
    assert_equal %(pin "luxon" # @3.7.2 (esm.run, minified, vendored, locked)),
                 @packager.vendored_pin_for("luxon", "https://cdn.jsdelivr.net/npm/luxon@3.7.2/+esm", minify: true, vendored: true, locked: true)
    assert_equal %(pin "react" # @17.0.2),
                 @packager.vendored_pin_for("react", "https://ga.jspm.io/npm:react@17.0.2/index.js")
  end

  test "locked_pin_line and unlocked_pin_line keep the remote and vendored details" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports)
      pin "monaco-editor", to: "https://cdn/monaco@0.52.2/api.js" # @0.52.2 (remote: workers, locked)
      pin "chart.js" # @4.4.0 (unpkg, vendored, locked)
    RUBY

    assert_equal %(pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js" # @2.11.8 (remote: relative imports, locked)),
                 packager.locked_pin_line("@popperjs/core")
    assert_equal %(pin "monaco-editor", to: "https://cdn/monaco@0.52.2/api.js" # @0.52.2 (remote: workers)),
                 packager.unlocked_pin_line("monaco-editor")
    assert_equal %(pin "chart.js" # @4.4.0 (unpkg, vendored)), packager.unlocked_pin_line("chart.js")
  end

  private
    def without_retry_wait
      original = Importmap::Packager.retry_wait
      Importmap::Packager.retry_wait = 0
      yield
    ensure
      Importmap::Packager.retry_wait = original
    end
end
