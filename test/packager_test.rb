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
    response = Class.new { def code() "404" end; def body() "" end }.new

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

  # Tempfile unlinks its file from a finalizer, so handing back only the path
  # leaves the import map alive at the mercy of the next GC: the Packager then
  # takes #extract_existing_pin_options' "no file" branch and every option
  # reads back nil. Hold the object for the length of the test instead.
  def create_temp_importmap(content)
    temp_file = Tempfile.new(['importmap', '.rb'])
    temp_file.write(content)
    temp_file.close
    (@temp_importmaps ||= []) << temp_file
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

    Net::HTTP.stub(:get_response, ->(uri, *) { requested << uri.to_s; resolved }) do
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

    Net::HTTP.stub(:get_response, ->(uri, *) { requested << uri.to_s; resolved }) do
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
    flaky = ->(_uri, *) { attempts += 1; raise Errno::ECONNRESET, "SSL_connect" if attempts < 3; response }

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
    broken = ->(_uri, *) { attempts += 1; raise Errno::ECONNRESET, "SSL_connect" }

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

      # The graph answers for the relative imports, so only the worker is why
      # this package still can't be vendored, and only that is reported.
      assert_equal [ "workers" ], error.reasons
      assert_equal "// the file that works today", File.read(existing)
    end
  end

  test "download refuses a source that isn't an ES module and leaves the vendored file it has" do
    response = Class.new do
      def code() "200" end
      def body() %(var f = typeof exports == "object"; module.exports = f) end
    end.new

    Dir.mktmpdir do |vendor_dir|
      existing = Pathname.new(vendor_dir).join("google-libphonenumber.js")
      File.write(existing, "// the file that works today")
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      Net::HTTP.stub(:get_response, response) do
        assert_raises(Importmap::Packager::NotAnEsModule) do
          packager.download("google-libphonenumber", "https://cdn.jsdelivr.net/npm/google-libphonenumber@3.2.42/dist/libphonenumber.js")
        end
      end

      assert_equal "// the file that works today", File.read(existing)
    end
  end

  # --vendor is the one answer to both checks: the app has looked and decided.
  test "download vendors a source that isn't an ES module when forced" do
    response = Class.new do
      def code() "200" end
      def body() %(module.exports = f) end
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      Net::HTTP.stub(:get_response, response) do
        packager.download("google-libphonenumber", "https://cdn.jsdelivr.net/npm/google-libphonenumber@3.2.42/dist/libphonenumber.js", force: true, graph: false)
      end

      assert_includes File.read("#{vendor_dir}/google-libphonenumber.js"), "module.exports = f"
    end
  end

  # A file that fails both checks is reported as unvendorable, because that is
  # the one an app can answer by keeping the pin remote.
  test "download reports a source that can't stand alone before it reports the module format" do
    response = Class.new do
      def code() "200" end
      def body() %(const s = require("./util.js"); module.exports = s; const w = new Worker(u)) end
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      Net::HTTP.stub(:get_response, response) do
        assert_raises(Importmap::Packager::Unvendorable) { packager.download("some-package", "https://ga.jspm.io/npm:some-package@1.0.0/index.js") }
      end
    end
  end

  test "download leaves the file an app has when the replacement can't be written" do
    response = Class.new do
      def code() "200" end
      def body() "export default 1" end
    end.new

    Dir.mktmpdir do |vendor_dir|
      existing = Pathname.new(vendor_dir).join("react.js")
      File.write(existing, "// the file that works today")
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      Net::HTTP.stub(:get_response, response) do
        File.stub(:rename, ->(*) { raise Errno::ENOSPC }) do
          assert_raises(Errno::ENOSPC) { packager.download("react", "https://ga.jspm.io/npm:react@17.0.2/index.js") }
        end
      end

      assert_equal "// the file that works today", File.read(existing)
      assert_empty Dir.glob("#{vendor_dir}/*.download"), "expected the partial download to be cleaned up"
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
        packager.download("@popperjs/core", "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js", force: true, graph: false)
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

  test "pin_for quotes a computed integrity hash and leaves the booleans bare" do
    assert_equal %(pin "md5", to: "https://cdn/md5.js", integrity: "sha384-abc"),
                 @packager.pin_for("md5", "https://cdn/md5.js", integrity: "sha384-abc")
    assert_equal %(pin "md5", to: "https://cdn/md5@2.2.0/md5.js", integrity: "sha384-abc" # @2.2.0 (locked)),
                 @packager.pin_for("md5", "https://cdn/md5@2.2.0/md5.js", integrity: "sha384-abc", locked: true)
    assert_equal %(pin "md5", to: "https://cdn/md5.js", integrity: false),
                 @packager.pin_for("md5", "https://cdn/md5.js", integrity: false)
  end

  test "fetch_remote returns the body without writing anything" do
    response = Class.new do
      def code() "200" end
      def body() "export default 1" end
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      body = Net::HTTP.stub(:get_response, ->(_uri, *) { response }) do
        packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js")
      end

      assert_equal "export default 1", body
      assert_empty Dir.children(vendor_dir)
    end
  end

  test "fetch_remote retries a reset connection and then raises" do
    attempts = 0
    broken = ->(_uri, *) { attempts += 1; raise Errno::ECONNRESET, "SSL_connect" }

    without_retry_wait do
      error = Net::HTTP.stub(:get_response, broken) do
        assert_raises(Importmap::Packager::HTTPError) { @packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js") }
      end

      assert_equal Importmap::Packager.retry_attempts, attempts
      assert_match(/Connection reset|SSL_connect/, error.message)
    end
  end

  test "fetch_remote raises on a response the CDN refused" do
    response = Class.new do
      def code() "404" end
      def body() "" end
    end.new

    error = Net::HTTP.stub(:get_response, ->(_uri, *) { response }) do
      assert_raises(Importmap::Packager::HTTPError) { @packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js") }
    end

    assert_match(/404/, error.message)
  end

  test "a download kept remote carries the hash of the bytes it fetched, so nothing fetches them twice" do
    unvendorable = Class.new do
      def code() "200" end
      def body() %(export default new Worker(u)) end
    end.new
    not_es_module = Class.new do
      def code() "200" end
      def body() %(module.exports = 1) end
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      error = Net::HTTP.stub(:get_response, unvendorable) do
        assert_raises(Importmap::Packager::Unvendorable) { packager.download("a", "https://ga.jspm.io/npm:a@1.0.0/index.js") }
      end
      assert_equal Importmap::Integrity.for(unvendorable.body), error.integrity

      error = Net::HTTP.stub(:get_response, not_es_module) do
        assert_raises(Importmap::Packager::NotAnEsModule) { packager.download("b", "https://ga.jspm.io/npm:b@1.0.0/index.js") }
      end
      assert_equal Importmap::Integrity.for(not_es_module.body), error.integrity
      assert_equal [ "not an ES module" ], error.reasons
    end
  end

  test "a kept-remote esm.run bundle is hashed as the CDN serves it, not as rewritten for vendoring" do
    response = Class.new do
      def code() "200" end
      def body() %(import"/npm/dep@1.0.0/+esm";export default new Worker(u)) end
    end.new

    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb"), vendor_path: Pathname.new(vendor_dir))

      error = Net::HTTP.stub(:get_response, response) do
        assert_raises(Importmap::Packager::Unvendorable) { packager.download("a", "https://cdn.jsdelivr.net/npm/a@1.0.0/+esm") }
      end

      assert_equal Importmap::Integrity.for(response.body), error.integrity
      assert_not_equal Importmap::Integrity.for(%(import"dep";export default new Worker(u))), error.integrity
    end
  end

  # jspm answers some files brotli-encoded however the request advertises
  # itself, and Net::HTTP decompresses gzip and deflate only — so the body
  # arrives as bytes no source file has.
  test "fetch_remote asks again for an unencoded body when the CDN encoded one Net::HTTP can't read" do
    sent = []
    encoded = Struct.new(:code, :body).new("200", "\x1b!\x06\x00\x8c\xd3".dup.force_encoding("ASCII-8BIT"))
    plain   = Struct.new(:code, :body).new("200", "export default 1")

    Net::HTTP.stub(:get_response, ->(_uri, headers = nil) { sent << headers; sent.size == 1 ? encoded : plain }) do
      assert_equal "export default 1", @packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js")
    end

    assert_equal [ nil, { "Accept-Encoding" => "identity" } ], sent
  end

  # Supplying an Accept-Encoding at all stops Net::HTTP decoding the gzip it
  # does understand, so a body it could read is never asked for twice.
  test "fetch_remote lets Net::HTTP negotiate an encoding it can read" do
    sent = []
    response = Struct.new(:code, :body).new("200", "export default 1")

    Net::HTTP.stub(:get_response, ->(_uri, headers = nil) { sent << headers; response }) do
      @packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js")
    end

    assert_equal [ nil ], sent
  end

  test "fetch_remote says so when a body stays unreadable after asking for it plain" do
    encoded = Struct.new(:code, :body).new("200", "\x1b!\x06\x00\x8c\xd3".dup.force_encoding("ASCII-8BIT"))

    error = Net::HTTP.stub(:get_response, ->(_uri, _headers = nil) { encoded }) do
      assert_raises(Importmap::Packager::HTTPError) { @packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js") }
    end

    assert_match %r{Can't read https://ga\.jspm\.io/npm:md5@2\.2\.0/md5\.js}, error.message
  end

  # A sibling the CDN hasn't got means the crawl can't own the package. A
  # sibling the CDN *fails* on says nothing about the package: raising keeps
  # the pin it has, where an Unvendorable would convert it to a remote pin and
  # delete the files that work today.
  # The entry's partial waits through the whole graph write, so Ctrl-C there is
  # the case a bare rescue misses. The entry is written first and cleans up
  # its own partial, so the interrupt has to land on a *sibling* — the second
  # file through the stub — to reach the cleanup under test.
  test "download leaves no entry partial behind when the write is interrupted" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)
      files = 0

      stub_cdn(CHUNKED_PACKAGE) do
        packager.stub(:remove_sourcemap_comment_from, ->(source) { (files += 1) == 1 ? source : raise(Interrupt) }) do
          assert_raises(Interrupt) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js") }
        end
      end

      assert_equal 2, files, "expected the interrupt to land on the first sibling"
      assert_empty Dir.glob("#{vendor_dir}/*.download")
      assert_not File.exist?("#{vendor_dir}/pkg.js")
    end
  end

  test "download raises rather than keeping a package remote when the CDN fails on a sibling" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)
      entry = "#{GRAPH_ROOT}dist/index.js"
      responder = ->(uri, _headers = nil) do
        body = CHUNKED_PACKAGE[uri.to_s]
        next Struct.new(:code, :body).new("200", body.dup.force_encoding("ASCII-8BIT")) if uri.to_s == entry

        Struct.new(:code, :body).new("503", "Service unavailable")
      end

      without_retry_wait do
        Net::HTTP.stub(:get_response, responder) do
          assert_raises(Importmap::Packager::HTTPError) { packager.download("pkg", entry) }
        end
      end

      assert_not File.exist?("#{vendor_dir}/pkg.js")
      assert_empty Dir.glob("#{vendor_dir}/*.download")
    end
  end

  test "fetch_remote wraps a failure the retry doesn't know as its own HTTPError" do
    error = Net::HTTP.stub(:get_response, ->(_uri, *) { raise Zlib::GzipFile::Error, "not in gzip format" }) do
      assert_raises(Importmap::Packager::HTTPError) { @packager.fetch_remote("https://ga.jspm.io/npm:md5@2.2.0/md5.js") }
    end

    assert_match(/Zlib::GzipFile::Error: not in gzip format/, error.message)
  end

  test "integrity_hash? is true only for a pin carrying a computed hash" do
    packager = Importmap::Packager.new(create_temp_importmap(<<~RUBY))
      pin "hashed", to: "https://cdn/hashed.js", integrity: "sha384-abc"
      pin 'quoted', to: 'https://cdn/quoted.js', integrity: 'sha384-abc'
      pin "boolean", to: "https://cdn/boolean.js", integrity: true
      pin "off", to: "https://cdn/off.js", integrity: false
      pin "plain", to: "https://cdn/plain.js"
    RUBY

    assert packager.integrity_hash?("hashed")
    assert packager.integrity_hash?("quoted")
    assert_not packager.integrity_hash?("boolean")
    assert_not packager.integrity_hash?("off")
    assert_not packager.integrity_hash?("plain")
    assert_not packager.integrity_hash?("missing")
  end

  test "download vendors the file graph a chunked package needs and rewrites its entry" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)

      stub_cdn(CHUNKED_PACKAGE) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js") }

      assert_equal %(import u from"pkg/dist/util";import c from"pkg/_/chunk";export{u,c}),
        File.read("#{vendor_dir}/pkg.js").lines.last
      assert_equal %(export default "café"), File.read("#{vendor_dir}/pkg/dist/util.js")
      assert_equal %(export default 2), File.read("#{vendor_dir}/pkg/_/chunk.js")
      assert_equal 2, packager.last_graph.size
    end
  end

  test "download replaces the whole graph directory, so a file the package dropped is gone" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir, %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0 (graph of pkg)\n))
      FileUtils.mkdir_p("#{vendor_dir}/pkg/dist")
      File.write("#{vendor_dir}/pkg/dist/gone.js", "export default 0")

      stub_cdn(CHUNKED_PACKAGE) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js") }

      assert_not File.exist?("#{vendor_dir}/pkg/dist/gone.js")
      assert File.exist?("#{vendor_dir}/pkg/dist/util.js")
    end
  end

  # A directory this gem didn't write is the app's: `pin date-fns` must not
  # rename away a vendor/javascript/date-fns the app has kept for years.
  test "download refuses to replace a directory the import map doesn't map as ours" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir, %(pin_all_from "#{vendor_dir}/pkg", under: "pkg"\n))
      FileUtils.mkdir_p("#{vendor_dir}/pkg")
      File.write("#{vendor_dir}/pkg/theirs.js", "// hand vendored, years ago")

      stub_cdn(CHUNKED_PACKAGE) do
        assert_raises(Importmap::VendoredGraph::Occupied) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js") }
      end

      assert_equal "// hand vendored, years ago", File.read("#{vendor_dir}/pkg/theirs.js")
      assert_not File.exist?("#{vendor_dir}/pkg.js")
      assert_empty Dir.glob("#{vendor_dir}/*.download")
    end
  end

  # pristine restores a pin as it stands, but an entry that still imports
  # siblings is not servable because pristine asked for it: a --from that moves
  # a graphed package to a CDN whose files can't be crawled would otherwise
  # write the entry unrewritten and delete the directory it resolves through.
  test "download checks a forced entry whose pin maps a graph the CDN didn't give" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir, %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0 (graph of pkg)\n))
      source = %(export{default}from"./util.js")

      error = stub_cdn({ "https://esm.sh/pkg@1.0.0/index.js" => source }) do
        assert_raises(Importmap::Packager::Unvendorable) do
          packager.download("pkg", "https://esm.sh/pkg@1.0.0/index.js", force: true, graph: true)
        end
      end

      assert_equal [ "relative imports" ], error.reasons
      assert_not File.exist?("#{vendor_dir}/pkg.js")
    end
  end

  test "download keeps a package remote for the reasons its graph can't answer for" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)
      source = %(import u from"./util.js";export default new Worker(u))

      error = stub_cdn({ "#{GRAPH_ROOT}dist/index.js" => source }) do
        assert_raises(Importmap::Packager::Unvendorable) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js") }
      end

      assert_equal [ "workers" ], error.reasons
      assert_equal Importmap::Integrity.for(source), error.integrity
      assert_empty Dir.glob("#{vendor_dir}/*")
    end
  end

  test "download leaves the graph an app has when the crawl refuses" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)
      FileUtils.mkdir_p("#{vendor_dir}/pkg/dist")
      File.write("#{vendor_dir}/pkg/dist/util.js", "// the file that works today")

      stub_cdn({ "#{GRAPH_ROOT}dist/index.js" => %(export{default}from"./gone.js") }) do
        assert_raises(Importmap::Packager::Unvendorable) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js") }
      end

      assert_equal "// the file that works today", File.read("#{vendor_dir}/pkg/dist/util.js")
      assert_empty Dir.glob("#{vendor_dir}/*.download")
    end
  end

  test "download without a graph vendors the entry alone and drops the directory its pin maps" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir, %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0 (graph of pkg)\n))
      FileUtils.mkdir_p("#{vendor_dir}/pkg")
      File.write("#{vendor_dir}/pkg/stale.js", "export default 0")

      stub_cdn(CHUNKED_PACKAGE) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js", force: true, graph: false) }

      assert_includes File.read("#{vendor_dir}/pkg.js"), %(from"./util.js")
      assert_nil packager.last_graph
      assert_not File.exist?("#{vendor_dir}/pkg")
    end
  end

  # An app's own vendor/javascript/<name> directory is not this gem's to
  # delete: only a directory the import map maps was written by a download.
  test "download without a graph leaves a directory the import map doesn't map" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir, %(pin_all_from "#{vendor_dir}/pkg", under: "pkg"\n))
      FileUtils.mkdir_p("#{vendor_dir}/pkg")
      File.write("#{vendor_dir}/pkg/theirs.js", "export default 0")

      stub_cdn(CHUNKED_PACKAGE) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js", force: true, graph: false) }

      assert_equal "export default 0", File.read("#{vendor_dir}/pkg/theirs.js")
    end
  end

  # force skips the single-file check, not the crawl: pristine passes it to
  # restore a pin exactly as it stands, graph directory and all.
  test "download crawls the graph of a forced download too" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)

      stub_cdn(CHUNKED_PACKAGE) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js", force: true) }

      assert_equal 2, packager.last_graph.size
      assert File.exist?("#{vendor_dir}/pkg/dist/util.js")
    end
  end

  test "download rewrites a graph file another pin already vendored to that pin's key" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir, %(pin "pkg"\n))
      File.write("#{vendor_dir}/pkg.js", "// pkg@1.0.0 downloaded from #{GRAPH_ROOT}dist/index.js\n\nexport default 1")

      stub_cdn(CHUNKED_PACKAGE.merge("#{GRAPH_ROOT}dist/lightbox.js" => %(export{default}from"./index.js"))) do
        packager.download("pkg/lightbox", "#{GRAPH_ROOT}dist/lightbox.js")
      end

      assert_equal %(export{default}from"pkg"), File.read("#{vendor_dir}/pkg--lightbox.js").lines.last
      assert_equal 0, packager.last_graph.size
      assert_not File.exist?("#{vendor_dir}/pkg--lightbox/dist/index.js")
    end
  end

  test "download minifies every file of the graph and heads only the entry" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)

      with_minifier(->(source) { "//min\n#{source}" }) do
        stub_cdn(CHUNKED_PACKAGE) { packager.download("pkg", "#{GRAPH_ROOT}dist/index.js", minify: true) }
      end

      assert_includes File.read("#{vendor_dir}/pkg/dist/util.js"), "//min"
      assert_includes File.read("#{vendor_dir}/pkg.js"), "downloaded from #{GRAPH_ROOT}dist/index.js (minified)"
      assert_not_includes File.read("#{vendor_dir}/pkg/dist/util.js"), "downloaded from"
    end
  end

  # The CDN's own version segment, not a semver-looking string elsewhere in the
  # URL: a line rendered with a blank version is one no command can find again.
  test "graph_pin_for takes the version from the package the URL names" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)

      assert_equal %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @latest (graph of pkg)),
        packager.graph_pin_for("pkg", "https://ga.jspm.io/npm:pkg@latest/index.js")
      assert_equal %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @2 (graph of pkg)),
        packager.graph_pin_for("pkg", "https://ga.jspm.io/npm:pkg@2/index.js")
      assert_equal %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0-beta.1 (graph of pkg)),
        packager.graph_pin_for("pkg", "https://ga.jspm.io/npm:pkg@1.0.0-beta.1/dist/index.js")
      # The package's own segment, not the first semver-looking thing in the
      # path: a chunk filename must not supply the version.
      assert_equal %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @2 (graph of pkg)),
        packager.graph_pin_for("pkg", "https://ga.jspm.io/npm:pkg@2/chunks/dep@9.9.9/index.js")

      # Whatever the version looks like, the line has to be findable again.
      line = packager.graph_pin_for("pkg", "https://ga.jspm.io/npm:pkg@latest/index.js")
      assert_match packager.vendored_graph("pkg").line_regexp, line
      assert_equal [ [ "#{vendor_dir}/pkg", "pkg", "latest" ] ], Importmap::VendoredGraph.mappings_in(line)
    end
  end

  test "graph_pin_for maps the directory under the package the CDN URL names" do
    Dir.mktmpdir do |vendor_dir|
      packager = graph_packager(vendor_dir)

      assert_equal %(pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0 (graph of pkg)),
        packager.graph_pin_for("pkg", "#{GRAPH_ROOT}dist/index.js")
      assert_equal %(pin_all_from "#{vendor_dir}/@popperjs--core", under: "@popperjs/core", to: "@popperjs--core" # @2.11.8 (graph of @popperjs/core)),
        packager.graph_pin_for("@popperjs/core", "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js")
      assert_equal %(pin_all_from "#{vendor_dir}/buffer", under: "@jspm/core", to: "buffer", preload: false # @2.1.0 (graph of @jspm/core)),
        packager.graph_pin_for("buffer", "https://ga.jspm.io/npm:@jspm/core@2.1.0/nodelibs/browser/buffer.js", false)
    end
  end

  test "remove_graph drops the line that maps a directory and the directory with it" do
    Dir.mktmpdir do |vendor_dir|
      importmap = create_temp_importmap(<<~RUBY)
        pin "pkg" # @1.0.0
        pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0 (graph of pkg)
        pin_all_from "#{vendor_dir}/other", under: "other" # @1.0.0 (graph of other)
      RUBY
      packager = Importmap::Packager.new(importmap, vendor_path: Pathname.new(vendor_dir))
      FileUtils.mkdir_p("#{vendor_dir}/pkg")

      assert packager.vendored_graph("pkg").mapped?
      assert_not packager.vendored_graph("nothing").mapped?

      packager.remove_graph("pkg")

      assert_not packager.vendored_graph("pkg").mapped?
      assert_not File.exist?("#{vendor_dir}/pkg")
      assert_includes File.read(importmap), %(pin_all_from "#{vendor_dir}/other")
      assert_includes File.read(importmap), %(pin "pkg" # @1.0.0)
    end
  end

  test "remove takes the graph directory and its line with the pin" do
    Dir.mktmpdir do |vendor_dir|
      importmap = create_temp_importmap(<<~RUBY)
        pin "pkg" # @1.0.0
        pin_all_from "#{vendor_dir}/pkg", under: "pkg" # @1.0.0 (graph of pkg)
      RUBY
      packager = Importmap::Packager.new(importmap, vendor_path: Pathname.new(vendor_dir))
      FileUtils.mkdir_p("#{vendor_dir}/pkg")
      File.write("#{vendor_dir}/pkg.js", "export default 1")

      packager.remove("pkg")

      assert_equal "", File.read(importmap).strip
      assert_not File.exist?("#{vendor_dir}/pkg")
      assert_not File.exist?("#{vendor_dir}/pkg.js")
      # The same instance is asked again: #importmap is memoised, and a caller
      # that removes a pin and then looks for it must not see the old file.
      assert_not packager.packaged?("pkg")
    end
  end

  test "fetch_remote answers nil for a file the CDN hasn't got only when the caller allows it" do
    missing = Class.new { def code() "404" end; def body() "" end }.new

    Net::HTTP.stub(:get_response, missing) do
      assert_nil @packager.fetch_remote("https://ga.jspm.io/npm:pkg@1.0.0/gone.js", allow_missing: true)
      assert_raises(Importmap::Packager::HTTPError) { @packager.fetch_remote("https://ga.jspm.io/npm:pkg@1.0.0/gone.js") }
    end
  end

  test "extract_existing_pin_options reads an array preload written with single quotes" do
    packager = Importmap::Packager.new(file_fixture("single_quote_array_preload_import_map.rb"))

    assert_equal({ preload: [ "admin" ] }, extract_options_for_package(packager, "md5"))
    assert_equal({ preload: [ "admin", "app" ] }, extract_options_for_package(packager, "charenc"))
    assert_equal({ preload: [] }, extract_options_for_package(packager, "crypt"))
  end

  test "extract_existing_pin_options keeps an empty array preload" do
    temp_importmap = create_temp_importmap(<<~PINS)
      pin "package1", preload: []
      pin "package2", preload: [], integrity: true
    PINS
    packager = Importmap::Packager.new(temp_importmap)

    assert_equal({ preload: [] }, extract_options_for_package(packager, "package1"))
    assert_equal({ preload: [], integrity: true }, extract_options_for_package(packager, "package2"))
  end

  test "pin_for writes an empty array preload rather than dropping it" do
    assert_equal %(pin "react", preload: []), @packager.pin_for("react", preloads: [])
    assert_equal %(pin "react", preload: [] # @17.0.2),
                 @packager.vendored_pin_for("react", "https://cdn/react@17.0.2", [])
    assert_equal %(pin "react"), @packager.pin_for("react", preloads: nil)
  end

  test "an array preload survives being read and written again" do
    temp_importmap = create_temp_importmap(<<~PINS)
      pin 'package1', preload: ['admin', 'app']
      pin 'package2', preload: []
    PINS
    packager = Importmap::Packager.new(temp_importmap)

    assert_equal %(pin "package1", preload: ["admin", "app"]),
                 packager.pin_for("package1", preloads: extract_options_for_package(packager, "package1")[:preload])
    assert_equal %(pin "package2", preload: []),
                 packager.pin_for("package2", preloads: extract_options_for_package(packager, "package2")[:preload])
  end
  private
    GRAPH_ROOT = "https://ga.jspm.io/npm:pkg@1.0.0/".freeze

    CHUNKED_PACKAGE = {
      "#{GRAPH_ROOT}dist/index.js" => %(import u from"./util.js";import c from"../_/chunk.js";export{u,c}),
      "#{GRAPH_ROOT}dist/util.js"  => %(export default "café"),
      "#{GRAPH_ROOT}_/chunk.js"    => %(export default 2)
    }.freeze

    def graph_packager(vendor_dir, importmap = "")
      Importmap::Packager.new(create_temp_importmap(importmap), vendor_path: Pathname.new(vendor_dir))
    end

    # One lambda for every URL the crawl asks for, so a file the fake package
    # doesn't have answers 404 the way a CDN does.
    def stub_cdn(files, &block)
      responder = ->(uri, *) do
        body = files[uri.to_s]
        # Net::HTTP tags a body ASCII-8BIT however the file is encoded, and a
        # published bundle has bytes above 0x7f in it.
        Struct.new(:code, :body).new(body ? "200" : "404", body.to_s.dup.force_encoding("ASCII-8BIT"))
      end

      Net::HTTP.stub(:get_response, responder, &block)
    end

    def with_minifier(minifier)
      original = Importmap::Packager.minifier
      Importmap::Packager.minifier = minifier
      yield
    ensure
      Importmap::Packager.minifier = original
    end

    def without_retry_wait
      original = Importmap::Packager.retry_wait
      Importmap::Packager.retry_wait = 0
      yield
    ensure
      Importmap::Packager.retry_wait = original
    end
end
