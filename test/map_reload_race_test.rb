# frozen_string_literal: true

require "test_helper"

# A dev reload redraws the one map every request reads. These tests pause a
# draw halfway, with a Queue handshake inside the draw block, and render the
# map from other threads while it waits: what they see is what a request sees
# while config/importmap.rb is being re-evaluated.
class MapReloadRaceTest < ActiveSupport::TestCase
  PACKAGES = %w[ alpha bravo charlie delta ].freeze

  class Resolver
    def path_to_asset(path) = "/assets/#{path}"
  end

  test "32 threads rendering during 10 reloads each see one whole map, never a half-drawn one" do
    map = Importmap::Map.new
    draw_version(map, 0)

    1.upto(10) do |version|
      halfway, resume = Queue.new, Queue.new
      reload = Thread.new { draw_version(map, version, halfway: halfway, resume: resume) }
      halfway.pop

      renders = Array.new(32) { Thread.new { imports_of(map) } }.map(&:value)
      resume << true
      reload.join

      renders.each do |imports|
        assert_equal PACKAGES, imports.keys
        assert_equal [ "v#{version - 1}" ], versions_in(imports), "a render mid-reload mixed two versions of the map"
      end
      assert_equal [ "v#{version}" ], versions_in(imports_of(map))
    end
  end

  test "a reload adds to the map rather than replacing it, as the Reloader relies on" do
    map = Importmap::Map.new.draw { pin "md5", to: "https://cdn.skypack.dev/md5" }
    map.draw { pin "alpha" }

    assert_equal %w[ md5 alpha ], map.packages.keys
  end

  test "a draw that raises leaves the map it started from" do
    map = Importmap::Map.new
    draw_version(map, 0)

    assert_raises(RuntimeError) do
      map.draw do
        pin "alpha", to: "alpha-v1.js"
        raise "config/importmap.rb failed halfway"
      end
    end

    assert_equal [ "v0" ], versions_in(imports_of(map))
  end

  private
    def draw_version(map, version, halfway: nil, resume: nil)
      map.draw do
        PACKAGES.each_with_index do |name, index|
          if halfway && index == PACKAGES.size / 2
            halfway << true
            resume.pop
          end
          pin name, to: "#{name}-v#{version}.js"
        end
      end
    end

    def imports_of(map)
      JSON.parse(map.to_json(resolver: Resolver.new))["imports"]
    end

    def versions_in(imports)
      imports.values.map { |path| path[/-(v\d+)\.js\z/, 1] }.uniq
    end
end
