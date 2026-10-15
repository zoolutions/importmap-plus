# frozen_string_literal: true

require "test_helper"

begin
  require "conformance_kit/minitest"
rescue LoadError
  # The Appraisal gemfiles CI tests with leave conformance-kit out (it needs
  # Ruby 3.2+); the kit's checks below skip there, the handshake tests run.
end

# Map#to_json and #preloaded_module_packages memoize what they render. These
# tests hold a render inside the app's resolver, with a Queue handshake, while
# the map changes or another render races it.
class CacheAsContentionTest < ActiveSupport::TestCase
  include ConformanceKit::Minitest if defined?(ConformanceKit::Minitest)

  class Resolver
    def path_to_asset(path) = "/assets/#{path}"
  end

  # Stops in its first path_to_asset until the test lets it go: by then the
  # render has read the map it is rendering.
  class HeldResolver < Resolver
    def initialize(entered, release)
      @entered, @release = entered, release
    end

    def path_to_asset(path)
      if @entered
        @entered << true
        @release.pop
        @entered = nil
      end
      super
    end
  end

  # Gives up the GVL (and, under an Async reactor, the fiber) on every path,
  # so concurrent renders interleave inside the resolver.
  class YieldingResolver < Resolver
    def path_to_asset(path)
      Thread.pass
      Async::Task.current?&.yield if defined?(Async::Task)
      super
    end
  end

  test "a render that started before a pin never caches over the map with that pin" do
    map = Importmap::Map.new.draw { pin "alpha" }
    entered, release = Queue.new, Queue.new
    render = Thread.new { map.to_json(resolver: HeldResolver.new(entered, release)) }
    entered.pop

    map.pin "bravo"
    release << true
    render.join

    assert_equal %w[ alpha bravo ], imports_of(map).keys
  end

  test "a render held across a reload returns the map it started from, whole" do
    map = Importmap::Map.new.draw { pin "alpha", integrity: "sha384-abc" }
    entered, release = Queue.new, Queue.new
    render = Thread.new { map.to_json(resolver: HeldResolver.new(entered, release)) }
    entered.pop

    map.draw do
      enable_integrity!
      pin "bravo"
    end
    release << true

    assert_equal({ "imports" => { "alpha" => "/assets/alpha.js" } }, JSON.parse(render.value))
  end

  test "renders that miss the cache together all return the one render it kept" do
    map = Importmap::Map.new.draw { pin "alpha" }
    entered, release = Queue.new, Queue.new
    renders = Array.new(2) { Thread.new { map.to_json(resolver: HeldResolver.new(entered, release)) } }
    2.times { entered.pop }
    2.times { release << true }

    first, second = renders.map(&:value)
    assert_same first, second
    assert_same first, map.to_json(resolver: Resolver.new)
  end

  test "to_json is thread-safe under contention" do
    skip CONFORMANCE_KIT_MISSING unless defined?(ConformanceKit::Minitest)
    map = Importmap::Map.new.draw { pin "alpha"; pin "bravo" }

    assert_thread_safe(threads: 8, iterations: 50, consistent: :identical) { map.to_json(resolver: YieldingResolver.new) }
  end

  test "to_json is fiber-safe under an Async reactor" do
    skip CONFORMANCE_KIT_MISSING unless defined?(ConformanceKit::Minitest)
    map = Importmap::Map.new.draw { pin "alpha"; pin "bravo" }

    assert_fiber_safe(fibers: 8, iterations: 50, consistent: :identical) { map.to_json(resolver: YieldingResolver.new) }
  end

  private
    CONFORMANCE_KIT_MISSING = "conformance-kit is not in this bundle (the Appraisal gemfiles leave it out); " \
                              "run it with the root Gemfile on Ruby 3.2+"

    def imports_of(map)
      JSON.parse(map.to_json(resolver: Resolver.new))["imports"]
    end
end
