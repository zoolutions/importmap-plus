# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

begin
  require "conformance_kit/minitest"
rescue LoadError
  # The Appraisal gemfiles CI tests with leave conformance-kit out (it needs
  # Ruby 3.2+); the kit's check below skips there, the rest runs.
end

# Once a production app has booted nothing draws its map again, so the engine
# finalizes it: frozen, with every pin deeply frozen, still rendering.
class FinalizeTest < ActiveSupport::TestCase
  include ConformanceKit::Minitest if defined?(ConformanceKit::Minitest)

  class Resolver
    def path_to_asset(path) = "/assets/#{path}"
  end

  test "finalize! freezes the map and deep-freezes what its readers return" do
    map = drawn_map.finalize!

    assert_predicate map, :frozen?
    assert_predicate map.packages["alpha"].path, :frozen?
    assert_predicate map.directories["app/javascript/controllers"].under, :frozen?
    if defined?(Ractor)
      assert Ractor.shareable?(map.packages), "packages is not Ractor-shareable"
      assert Ractor.shareable?(map.directories), "directories is not Ractor-shareable"
    end
  end

  test "a finalized map is a boot-finalized configuration" do
    skip "conformance-kit is not in this bundle (the Appraisal gemfiles leave it out)" unless defined?(ConformanceKit::Minitest)
    map = drawn_map

    assert_boot_finalized(readers: [ map.method(:packages), map.method(:directories) ], finalize: -> { map.finalize! })
  end

  test "a finalized map still renders, and caches what it rendered" do
    map = drawn_map.finalize!
    json = map.to_json(resolver: Resolver.new)

    assert_equal "/assets/alpha.js", JSON.parse(json)["imports"]["alpha"]
    assert_same json, map.to_json(resolver: Resolver.new)
    assert_equal [ "/assets/alpha.js" ], map.preloaded_module_paths(resolver: Resolver.new).grep(/alpha/)
  end

  test "a finalized map refuses every change, and says why" do
    map = drawn_map.finalize!

    [
      -> { map.pin "bravo" },
      -> { map.pin_all_from "app/javascript/helpers" },
      -> { map.enable_integrity! },
      -> { map.draw { pin "bravo" } },
      -> { map.send(:clear_cache) }
    ].each do |change|
      error = assert_raises(FrozenError) { change.call }
      assert_match(/finalized/, error.message)
    end
    assert_equal %w[ alpha ], map.packages.keys
  end

  test "finalize! twice is harmless" do
    map = drawn_map.finalize!

    assert_same map, map.finalize!
  end

  test "the app's map is left drawable in test, where the suite pins into it" do
    assert_equal false, Rails.application.config.importmap.finalize
    assert_not_predicate Rails.application.importmap, :frozen?
  end

  test "the app's map is finalized after boot in production" do
    assert_equal "true\n", boot_dummy("production", "print Rails.application.importmap.frozen?")
  end

  test "config.importmap.finalize = false keeps a production app's map drawable" do
    assert_equal "false\n", boot_dummy("production", "print Rails.application.importmap.frozen?", finalize: false)
  end

  private
    def drawn_map
      Importmap::Map.new.draw do
        pin "alpha"
        pin_all_from "app/javascript/controllers", under: "controllers"
      end
    end

    # Boots test/dummy in another process. Its app/ can't be eager-loaded
    # (ApplicationCable without Action Cable), so that one setting is undone.
    def boot_dummy(env, script, finalize: nil)
      boot = <<~RUBY
        require #{File.expand_path("dummy/config/application", __dir__).inspect}
        Rails.application.initializer("finalize_test", after: :load_environment_config) do |app|
          app.config.eager_load = false
          #{"app.config.importmap.finalize = #{finalize}" unless finalize.nil?}
        end
        Rails.application.initialize!
        #{script}
        puts
      RUBY
      out, err, status = Open3.capture3({ "RAILS_ENV" => env, "SECRET_KEY_BASE" => "finalize-test" }, RbConfig.ruby, "-e", boot)
      assert status.success?, "booting test/dummy in #{env} failed:\n#{err}"
      out
    end
end
