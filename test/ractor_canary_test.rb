# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "importmap/graph"
require "importmap/integrity"

begin
  require "conformance_kit/minitest"
rescue LoadError
  # The Appraisal gemfiles CI tests with leave conformance-kit out (it needs
  # Ruby 3.2+); the conformance workflow runs this file with the root bundle.
end

# What a request computes from the map, inside a non-main Ractor: the import
# map with its integrity hashes, the graph of what the entry point reaches,
# and an SRI hash of a file. Red when any of them picks up state a Ractor
# can't reach. Ruby 4.0+ (Ractor#value): the kit's assertion skips with the
# reason below that. `bundle exec conformance-kit check` runs it
# (.conformance.yml ractor.test_command).
class RactorCanaryTest < ActiveSupport::TestCase
  include ConformanceKit::Minitest if defined?(ConformanceKit::Minitest)

  # Resolves a pin the way an asset pipeline would: a path under /assets and
  # the SRI hash of the file under +root+. A constant, so a Ractor reaches it.
  class Resolver
    def initialize(root)
      @root = root
    end

    def path_to_asset(path) = "/assets/#{path}"
    def asset_integrity(path) = Importmap::Integrity.for(File.binread(File.join(@root, path)))
  end

  setup do
    @root = Dir.mktmpdir
    File.write(File.join(@root, "application.js"), %(import "chart"\nimport("admin")\n))
    File.write(File.join(@root, "chart.js"), %(import "./helpers.js"\nexport default 1\n))
    File.write(File.join(@root, "helpers.js"), %(export const two = 2\n))
    File.write(File.join(@root, "admin.js"), %(export default "admin"\n))
  end

  teardown { FileUtils.remove_entry(@root) }

  test "the import map, its graph and integrity hashes compute inside a non-main Ractor" do
    skip "conformance-kit is not in this bundle (the Appraisal gemfiles leave it out)" unless defined?(ConformanceKit::Minitest)

    assert_runs_in_ractor(inputs: [ @root ]) do |root|
      map = Importmap::Map.new.draw do
        enable_integrity!
        pin "application"
        pin "chart"
        pin "helpers"
        pin "admin", preload: false
      end

      [
        map.to_json(resolver: Resolver.new(root)),
        Importmap::Graph.new(map, roots: [ root ]).reachable_from([ "application" ]).sort,
        Importmap::Integrity.for(File.binread(File.join(root, "chart.js")))
      ]
    end
  end
end
