require "test_helper"
require "importmap/packager"

class Importmap::PackagerIntegrationTest < ActiveSupport::TestCase
  setup { @packager = Importmap::Packager.new(Rails.root.join("config/importmap.rb")) }

  test "successful import against live service" do
    result = @packager.import("react@17.0.2")
    assert_equal "https://ga.jspm.io/npm:react@17.0.2/index.js", result[:imports]["react"]
  end

  test "missing import against live service" do
    assert_nil @packager.import("react-is-not-this-package@17.0.2")
  end

  test "failed request against live bad domain" do
    original_endpoint = Importmap::Packager.endpoint
    Importmap::Packager.endpoint = URI("https://invalid./error")

    assert_raises(Importmap::Packager::HTTPError) do
      @packager.import("missing-package-that-doesnt-exist@17.0.2")
    end
  ensure
    Importmap::Packager.endpoint = original_endpoint
  end

  test "successful downloads from live service" do
    Dir.mktmpdir do |vendor_dir|
      @packager = Importmap::Packager.new \
        Rails.root.join("config/importmap.rb"),
        vendor_path: Pathname.new(vendor_dir)

      package_url = "https://ga.jspm.io/npm:@github/webauthn-json@0.5.7/dist/main/webauthn-json.js"
      @packager.download("@github/webauthn-json", package_url)
      vendored_package_file = Pathname.new(vendor_dir).join("@github--webauthn-json.js")
      assert File.exist?(vendored_package_file)
      assert_equal "// @github/webauthn-json@0.5.7 downloaded from #{package_url}", File.readlines(vendored_package_file).first.strip

      package_url = "https://ga.jspm.io/npm:react@17.0.2/index.js"
      vendored_package_file = Pathname.new(vendor_dir).join("react.js")
      # This react imports a sibling file, so it is one of the packages a plain
      # download refuses; forced, because what is under test here is the
      # download, the file header and remove.
      @packager.download("react", package_url, force: true)
      assert File.exist?(vendored_package_file)
      assert_equal "// react@17.0.2 downloaded from #{package_url}", File.readlines(vendored_package_file).first.strip
      @packager.remove("react")
      assert_not File.exist?(Pathname.new(vendor_dir).join("react.js"))
    end
  end

  test "download vendors a live package's file graph beside its entry" do
    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new \
        Rails.root.join("config/importmap.rb"),
        vendor_path: Pathname.new(vendor_dir)

      packager.download("react", "https://ga.jspm.io/npm:react@17.0.2/index.js")

      assert_equal 1, packager.last_graph.size
      entry = File.read(Pathname.new(vendor_dir).join("react.js"))
      assert_includes entry, %(from"react/cjs/react.production.min")
      assert_no_match %r{(?:from|import)\s*\(?\s*["']\.}, entry
      assert File.exist?(Pathname.new(vendor_dir).join("react/cjs/react.production.min.js"))
    end
  end

  test "download refuses a live package that needs more than its file graph" do
    Dir.mktmpdir do |vendor_dir|
      packager = Importmap::Packager.new \
        Rails.root.join("config/importmap.rb"),
        vendor_path: Pathname.new(vendor_dir)

      error = assert_raises(Importmap::Packager::Unvendorable) do
        packager.download("fflate", "https://ga.jspm.io/npm:fflate@0.8.2/esm/browser.js")
      end

      assert_equal [ "workers" ], error.reasons
      assert_not File.exist?(Pathname.new(vendor_dir).join("fflate.js"))
    end
  end
end
