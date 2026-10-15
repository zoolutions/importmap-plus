# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

begin
  require "conformance_kit/minitest"
rescue LoadError
  # The Appraisal gemfiles CI tests with leave conformance-kit out (it needs
  # Ruby 3.2+); the kit's check below skips there, the rest runs.
end

# Once an app has booted, the engine finalizes its map: every pin is deeply
# frozen, and so is every set of pins a later draw, pin, reload or cache sweep
# publishes, so a development app keeps reloading.
class FinalizeTest < ActiveSupport::TestCase
  include ConformanceKit::Minitest if defined?(ConformanceKit::Minitest)

  class Resolver
    def path_to_asset(path) = "/assets/#{path}"
  end

  # A pin target an app might write: a path object with a lock of its own,
  # which no Ractor can share.
  class LockedPath
    attr_reader :lock

    def initialize(path)
      @path = path
      @lock = Mutex.new
    end

    def to_s = @path
  end

  test "finalize! deep-freezes what the map's readers return" do
    map = drawn_map.finalize!

    assert_predicate map, :finalized?
    assert_predicate map.packages["alpha"], :frozen?
    assert_predicate map.packages["alpha"].path, :frozen?
    assert_predicate map.directories["app/javascript/controllers"].under, :frozen?
    if defined?(Ractor)
      assert Ractor.shareable?(map.packages), "packages is not Ractor-shareable"
      assert Ractor.shareable?(map.directories), "directories is not Ractor-shareable"
    end
  end

  test "a map is not finalized until finalize! is called" do
    map = drawn_map

    assert_not_predicate map, :finalized?
    assert_not_predicate map.packages["alpha"], :frozen?
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

  test "a finalized map takes every change, and publishes each one finalized" do
    map = drawn_map.finalize!
    before = map.to_json(resolver: Resolver.new)

    map.pin "bravo"
    map.pin_all_from "app/javascript/helpers", under: "helpers"
    map.enable_integrity!
    map.draw { pin "charlie", to: "charlie.js" }

    assert_equal %w[ alpha bravo charlie ], map.packages.keys
    assert_equal %w[ app/javascript/controllers app/javascript/helpers ], map.directories.keys
    assert_predicate map, :finalized?
    assert_predicate map.packages["charlie"].path, :frozen?
    assert_predicate map.directories["app/javascript/helpers"].under, :frozen?
    if defined?(Ractor)
      assert Ractor.shareable?(map.packages), "packages is not Ractor-shareable after a pin"
      assert Ractor.shareable?(map.directories), "directories is not Ractor-shareable after a pin"
    end
    assert_not_equal before, map.to_json(resolver: Resolver.new)
  end

  test "a cache sweep on a finalized map renders again and stays finalized" do
    map = drawn_map.finalize!
    json = map.to_json(resolver: Resolver.new)

    map.send(:clear_cache)

    assert_not_same json, map.to_json(resolver: Resolver.new)
    assert_predicate map, :finalized?
    assert Ractor.shareable?(map.packages), "packages is not Ractor-shareable after a sweep" if defined?(Ractor)
  end

  test "a reload of a finalized map redraws its file into a new finalized generation" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "importmap.rb")
      File.write(path, %(pin "alpha"\n))
      map = Importmap::Map.new.draw(path).finalize!

      File.write(path, %(pin "alpha"\npin "bravo"\n))
      map.draw(path)

      assert_equal %w[ alpha bravo ], map.packages.keys
      assert_predicate map.packages["bravo"], :frozen?
      assert Ractor.shareable?(map.packages), "packages is not Ractor-shareable after a reload" if defined?(Ractor)
    end
  end

  test "finalize! twice is harmless" do
    map = drawn_map.finalize!

    assert_same map, map.finalize!
    assert_predicate map, :finalized?
  end

  test "a pin finalize! can't make shareable is left as it is, and the rest is still frozen" do
    target = LockedPath.new("lazy.js")
    map = Importmap::Map.new.draw do
      pin "alpha"
      pin "lazy", to: target
    end

    map.finalize!

    assert_predicate map.packages, :frozen?
    assert_predicate map.packages["lazy"], :frozen?
    assert_same target, map.packages["lazy"].path
    assert_not_predicate target, :frozen?
    assert_not_predicate target.lock, :frozen?
    target.lock.synchronize { }
    assert Ractor.shareable?(map.packages["alpha"]), "a pin that can be shareable was left out" if defined?(Ractor)
    assert_equal "/assets/lazy.js", JSON.parse(map.to_json(resolver: Resolver.new))["imports"]["lazy"]
  end

  test "the app's map is finalized after boot in every environment" do
    %w[ development test production ].each do |env|
      assert_equal "true true\n", boot_dummy(env, "print Rails.application.importmap.finalized?, ' ', #{shareable_packages}"), env
    end
  end

  test "a development app keeps reloading its finalized map" do
    Dir.mktmpdir do |dir|
      extra = File.join(dir, "importmap.rb")
      File.write(extra, %(pin "before_reload"\n))
      script = <<~RUBY
        File.write(#{extra.inspect}, %(pin "after_reload"\\n))
        Rails.application.reloader.reload!
        Rails.application.importmap.cache_sweeper.execute
        print Rails.application.importmap.packages.key?("after_reload"), " ", Rails.application.importmap.finalized?, " ", #{shareable_packages}
      RUBY

      assert_equal "true true true\n", boot_dummy("development", script, paths: [ extra ])
    end
  end

  test "config.importmap.finalize = false leaves the map unfinalized" do
    %w[ development test production ].each do |env|
      assert_equal "false false\n", boot_dummy(env, "print Rails.application.importmap.finalized?, ' ', Rails.application.importmap.packages.values.first.frozen?", finalize: false), env
    end
  end

  test "an app that configures values no Ractor can share still boots finalized" do
    Dir.mktmpdir do |dir|
      extra = File.join(dir, "importmap.rb")
      File.write(extra, %(pin "lazy", to: LockedPath.new("lazy.js")\n))
      setup = <<~RUBY
        class LockedPath
          def initialize(path)
            @path = path
            @lock = Mutex.new
          end

          def to_s = @path
        end
        require "importmap/packager"
        minified = []
        # The docs' example: a minifier that closes over the app's own state.
        Importmap::Packager.minifier = ->(source) { minified << source; source }
      RUBY
      script = <<~RUBY
        lazy = Rails.application.importmap.packages["lazy"].path
        Importmap::Packager.minifier.call("x")
        print Rails.application.importmap.finalized?, " ", lazy.frozen?, " ", minified.size, " ", Importmap::Packager.minifier.frozen?
      RUBY

      %w[ development production ].each do |env|
        assert_equal "true false 1 false\n", boot_dummy(env, script, setup: setup, paths: [ extra ]), env
      end
    end
  end

  private
    def drawn_map
      Importmap::Map.new.draw do
        pin "alpha"
        pin_all_from "app/javascript/controllers", under: "controllers"
      end
    end

    def shareable_packages
      defined?(Ractor) ? "Ractor.shareable?(Rails.application.importmap.packages)" : "true"
    end

    # Boots test/dummy in another process. Its app/ can't be eager-loaded
    # (ApplicationCable without Action Cable), so that one setting is undone.
    # +setup+ runs before the app boots, as config/application.rb would, and
    # +paths+ are import map files added there, drawn before config/importmap.rb.
    def boot_dummy(env, script, finalize: nil, setup: nil, paths: [])
      boot = <<~RUBY
        require #{File.expand_path("dummy/config/application", __dir__).inspect}
        #{setup}
        Rails.application.config.importmap.paths.concat(#{paths.inspect})
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
