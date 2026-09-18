require "test_helper"
require "minitest/mock"
require "importmap/doctor"

class Importmap::DoctorTest < ActiveSupport::TestCase
  # The asset pipelines raise their own missing-asset class and the suite runs
  # against either, so the doctor is given one it can raise on both.
  MissingAsset = Class.new(StandardError)

  # Resolves exactly what is on disk under the asset paths, the way a digesting
  # pipeline does, and raises the rescuable error for anything else.
  class FakeResolver
    def initialize(asset_paths)
      @asset_paths = asset_paths
    end

    def path_to_asset(path)
      return path if path.start_with?("http")
      raise MissingAsset, path unless @asset_paths.any? { |root| File.file?(File.join(root, path)) }

      "/assets/#{path}"
    end
  end

  setup do
    @rescuable_asset_errors = Rails.application.config.importmap.rescuable_asset_errors
    Rails.application.config.importmap.rescuable_asset_errors = @rescuable_asset_errors + [ MissingAsset ]
  end

  teardown do
    Rails.application.config.importmap.rescuable_asset_errors = @rescuable_asset_errors
  end

  test "a clean map has no findings" do
    in_app "app/javascript/application.js" => %(export default 1) do |root|
      doctor = doctor_for(root) { pin "application" }

      assert_empty doctor.diagnose
      assert_not doctor.errors?
      assert_equal "0 errors, 0 warnings", doctor.summary
    end
  end

  test "a pin the pipeline can't resolve is an error" do
    in_app "app/javascript/application.js" => %(export default 1) do |root|
      doctor = doctor_for(root) do
        pin "application"
        pin "not_there", to: "nowhere.js"
      end

      assert_equal [ %(error    pin "not_there" → nowhere.js: no such asset) ], doctor.diagnose.map(&:to_s)
      assert doctor.errors?
      assert_equal "1 error, 0 warnings", doctor.summary
    end
  end

  test "a remote pin is not asked of the pipeline" do
    in_app({}) do |root|
      doctor = doctor_for(root) { pin "md5", to: "https://cdn.skypack.dev/md5" }

      assert_empty doctor.diagnose
    end
  end

  test "a bare specifier no key defines is an error" do
    in_app "vendor/javascript/shoelace.js" => %(import { customElement } from "lit/decorators.js";) do |root|
      doctor = doctor_for(root) { pin "shoelace" }

      assert_equal [ %(error    vendor/javascript/shoelace.js imports "lit/decorators.js", which isn't pinned) ],
        doctor.diagnose.map(&:to_s)
    end
  end

  test "a bare specifier a key defines exactly is fine" do
    in_app "vendor/javascript/shoelace.js" => %(import "lit";), "vendor/javascript/lit.js" => %(export default 1) do |root|
      doctor = doctor_for(root) do
        pin "shoelace"
        pin "lit"
      end

      assert_empty doctor.diagnose
    end
  end

  test "a subpath of a pinned package is taken as covered by it" do
    in_app "vendor/javascript/shoelace.js" => %(import "lit/decorators.js";), "vendor/javascript/lit.js" => %(export default 1) do |root|
      doctor = doctor_for(root) do
        pin "shoelace"
        pin "lit"
      end

      assert_empty doctor.diagnose
    end
  end

  test "a trailing-slash key covers everything under it" do
    in_app "app/javascript/application.js" => %(import "controllers/hello";) do |root|
      doctor = doctor_for(root) do
        pin "application"
        pin "controllers/", to: "https://cdn.example.com/controllers/"
      end

      assert_empty doctor.diagnose
    end
  end

  test "a dynamic import of a bare specifier is checked too" do
    in_app "app/javascript/application.js" => %(await import("lit");) do |root|
      doctor = doctor_for(root) { pin "application" }

      assert_equal [ %(error    app/javascript/application.js imports "lit", which isn't pinned) ],
        doctor.diagnose.map(&:to_s)
    end
  end

  test "a file the map serves from outside the app is not scanned" do
    Dir.mktmpdir do |gem_dir|
      File.write(File.join(gem_dir, "turbo.js"), %(import "somewhere/else";))

      in_app({}) do |root|
        doctor = doctor_for(root, asset_paths: [ Pathname.new(gem_dir) ]) { pin "turbo" }

        assert_empty doctor.diagnose
      end
    end
  end

  test "a vendored file whose relative import has no file beside it is an error" do
    in_app "vendor/javascript/@popperjs--core.js" =>
      %(// @popperjs/core@2.11.8 downloaded from https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js\n\nimport "./enums.js";) do |root|
      doctor = doctor_for(root) { pin "@popperjs/core", to: "@popperjs--core.js" }

      assert_equal [ %(error    vendor/javascript/@popperjs--core.js imports "./enums.js" by relative path — ) +
                     %(run bin/importmap pin @popperjs/core to vendor its files) ],
        doctor.diagnose.map(&:to_s)
    end
  end

  test "a vendored graph file importing its sibling is fine" do
    in_app "vendor/javascript/popper.js" => %(export { top } from "popper/lib/enums";),
           "vendor/javascript/popper/lib/index.js" => %(import "./enums.js";),
           "vendor/javascript/popper/lib/enums.js" => %(export const top = 1;) do |root|
      doctor = doctor_for(root) do
        pin "popper"
        pin_all_from root.join("vendor/javascript/popper").to_s, under: "popper", to: "popper"
      end

      assert_empty doctor.diagnose
    end
  end

  test "a graph sibling's stray relative import names the package its entry was downloaded as" do
    in_app "vendor/javascript/@popperjs--core.js" =>
             %(// @popperjs/core@2.11.8 downloaded from https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js\n\nexport default 1),
           "vendor/javascript/@popperjs--core/lib/utils.js" => %(import "./gone.js";) do |root|
      doctor = doctor_for(root) do
        pin "@popperjs/core", to: "@popperjs--core.js"
        pin_all_from root.join("vendor/javascript/@popperjs--core").to_s, under: "@popperjs/core", to: "@popperjs--core"
      end

      assert_equal [ %(error    vendor/javascript/@popperjs--core/lib/utils.js imports "./gone.js" by relative path — ) +
                     %(run bin/importmap pin @popperjs/core to vendor its files) ],
        doctor.diagnose.map(&:to_s)
    end
  end

  test "a vendored file that isn't an ES module is an error" do
    in_app "vendor/javascript/legacy.js" => %(module.exports = function () {};) do |root|
      doctor = doctor_for(root) { pin "legacy" }

      assert_equal [ %(error    vendor/javascript/legacy.js isn't an ES module) ], doctor.diagnose.map(&:to_s)
    end
  end

  test "a file in vendor/javascript no key serves is a warning" do
    in_app "vendor/javascript/old-lib.js" => %(export default 1) do |root|
      doctor = doctor_for(root) { }

      assert_equal [ %(warning  vendor/javascript/old-lib.js isn't pinned by anything) ], doctor.diagnose.map(&:to_s)
      assert_not doctor.errors?
      assert_equal "0 errors, 1 warning", doctor.summary
    end
  end

  test "an .mjs the map's glob never sees is a warning" do
    in_app "vendor/javascript/chunk.mjs" => %(export default 1) do |root|
      doctor = doctor_for(root) { pin_all_from root.join("vendor/javascript").to_s }

      assert_equal [ %(warning  vendor/javascript/chunk.mjs isn't pinned by anything) ], doctor.diagnose.map(&:to_s)
    end
  end

  test "two keys resolving to one file are a warning" do
    in_app "vendor/javascript/turbo.min.js" => %(export default 1) do |root|
      doctor = doctor_for(root) do
        pin "@hotwired/turbo", to: "turbo.min.js"
        pin "@hotwired/turbo-rails", to: "turbo.min.js"
      end

      assert_equal [ %(warning  "@hotwired/turbo" and "@hotwired/turbo-rails" both resolve to turbo.min.js) ],
        doctor.diagnose.map(&:to_s)
    end
  end

  test "two vendored files holding one package at two versions are a warning" do
    in_app "vendor/javascript/turbo.js" =>
             %(// turbo@7.3.0 downloaded from https://ga.jspm.io/npm:@hotwired/turbo@7.3.0/turbo.js\n\nexport default 1),
           "vendor/javascript/@hotwired--turbo.js" =>
             %(// @hotwired/turbo@8.0.0 downloaded from https://ga.jspm.io/npm:@hotwired/turbo@8.0.0/turbo.js\n\nexport default 1) do |root|
      doctor = doctor_for(root) do
        pin "turbo"
        pin "@hotwired/turbo", to: "@hotwired--turbo.js"
      end

      assert_equal [ %(warning  vendor/javascript/@hotwired--turbo.js and vendor/javascript/turbo.js ) +
                     %(both vendor @hotwired/turbo, at 8.0.0 and 7.3.0) ],
        doctor.diagnose.map(&:to_s)
    end
  end

  test "offline never fetches a remote pin" do
    in_app({}) do |root|
      doctor = doctor_for(root) { pin "md5", to: "https://cdn.example.com/md5" }

      Net::HTTP.stub(:get_response, ->(_uri) { flunk "offline fetched a remote pin" }) do
        assert_empty doctor.diagnose
      end
    end
  end

  test "online reports a remote pin the CDN hasn't got" do
    in_app({}) do |root|
      doctor = doctor_for(root, online: true) { pin "md5", to: "https://cdn.example.com/md5" }

      Net::HTTP.stub(:get_response, ->(_uri) { response("404", "") }) do
        assert_equal [ %(error    pin "md5" → https://cdn.example.com/md5: the CDN answered 404) ],
          doctor.diagnose.map(&:to_s)
      end
    end
  end

  test "online reports an integrity hash that doesn't match what the CDN served" do
    in_app({}) do |root|
      doctor = doctor_for(root, online: true) do
        enable_integrity!
        pin "md5", to: "https://cdn.example.com/md5", integrity: "sha384-wrong"
      end

      Net::HTTP.stub(:get_response, ->(_uri) { response("200", "export default 1") }) do
        assert_equal [ %(error    pin "md5" → https://cdn.example.com/md5: integrity doesn't match what the CDN served) ],
          doctor.diagnose.map(&:to_s)
      end
    end
  end

  test "online accepts an integrity hash of the bytes the CDN served" do
    in_app({}) do |root|
      doctor = doctor_for(root, online: true) do
        enable_integrity!
        pin "md5", to: "https://cdn.example.com/md5", integrity: Importmap::Integrity.for("export default 1")
      end

      Net::HTTP.stub(:get_response, ->(_uri) { response("200", "export default 1") }) do
        assert_empty doctor.diagnose
      end
    end
  end

  test "online reports a remote pin it couldn't reach at all" do
    in_app({}) do |root|
      doctor = doctor_for(root, online: true) { pin "md5", to: "https://cdn.example.com/md5" }

      without_retry_wait do
        Net::HTTP.stub(:get_response, ->(_uri) { raise SocketError, "down" }) do
          findings = doctor.diagnose

          assert_equal 1, findings.size
          assert_match %r{\Aerror    pin "md5": Unexpected transport error fetching https://cdn\.example\.com/md5 \(SocketError: down\)\z},
            findings.first.to_s
        end
      end
    end
  end

  private
    def in_app(files)
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)

        files.each do |path, content|
          root.join(path).dirname.mkpath
          File.write(root.join(path), content)
        end

        yield root
      end
    end

    def doctor_for(root, online: false, asset_paths: nil, &block)
      asset_paths ||= [ root.join("app/javascript"), root.join("vendor/javascript") ]

      Importmap::Doctor.new(
        importmap: Importmap::Map.new.draw(&block),
        resolver: FakeResolver.new(asset_paths),
        root: root,
        asset_paths: asset_paths,
        online: online
      )
    end

    def response(code, body)
      Struct.new(:code, :body).new(code, body)
    end

    def without_retry_wait
      original = Importmap::HttpRetries.wait
      Importmap::HttpRetries.wait = 0
      yield
    ensure
      Importmap::HttpRetries.wait = original
    end
end
