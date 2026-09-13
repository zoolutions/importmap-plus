require "test_helper"
require "importmap/provider_chain"

class Importmap::ProviderChainTest < ActiveSupport::TestCase
  # Stands in for Importmap::Packager: answers each provider in turn with the
  # next scripted answer, raising it when it is an exception, and records what
  # it was asked so the order can be checked.
  class FakePackager
    attr_reader :asked, :last_import_error

    def initialize(answers)
      @answers = answers
      @asked   = []
    end

    def import(*specs, env:, from:)
      @asked << [ specs, env, from ]
      @last_import_error = nil

      case (answer = @answers.fetch(from))
      when Exception then raise answer
      when String then (@last_import_error = answer) && nil
      else answer
      end
    end
  end

  MAP = { imports: { "mermaid" => "https://cdn.jsdelivr.net/npm/mermaid@10.6.0/+esm" } }.freeze

  test "the first CDN that answers is the one yielded" do
    packager = FakePackager.new("jspm" => MAP)

    assert_equal [ "jspm", MAP ], resolve(packager)
    assert_equal [ [ [ "mermaid@10.6.0" ], "production", "jspm" ] ], packager.asked
  end

  test "a CDN that answers nothing hands the package to the next one" do
    packager = FakePackager.new("jspm" => nil, "esm.run" => MAP)

    assert_output(%(jspm couldn't resolve "mermaid@10.6.0"; trying esm.run\n)) do
      assert_equal [ "esm.run", MAP ], resolve(packager)
    end
  end

  test "the reason a CDN gives for answering nothing is passed on" do
    packager = FakePackager.new("jspm" => "Error: No './dist/cytoscape.umd.js' exports subpath defined", "esm.run" => MAP)

    assert_output(%(jspm couldn't resolve "mermaid@10.6.0" (No './dist/cytoscape.umd.js' exports subpath defined); trying esm.run\n)) do
      assert_equal [ "esm.run", MAP ], resolve(packager)
    end
  end

  test "a CDN whose generator errors hands the package to the next one" do
    packager = FakePackager.new("jspm" => Importmap::Packager::ServiceError.new("Error: Module not found"), "esm.run" => MAP)

    assert_output(%(jspm couldn't resolve "mermaid@10.6.0" (Module not found); trying esm.run\n)) do
      assert_equal [ "esm.run", MAP ], resolve(packager)
    end
  end

  test "a CDN that can't be reached hands the package to the next one" do
    packager = FakePackager.new("jspm" => Importmap::Packager::HTTPError.new("Unexpected response code (502)"), "esm.run" => MAP)

    assert_output(%(jspm couldn't resolve "mermaid@10.6.0" (Unexpected response code (502)); trying esm.run\n)) do
      assert_equal [ "esm.run", MAP ], resolve(packager)
    end
  end

  test "every CDN is tried before the package is given up on" do
    packager = FakePackager.new("jspm" => nil, "esm.run" => nil, "jsdelivr" => MAP)

    assert_output(/trying esm\.run\n.*trying jsdelivr\n/m) do
      assert_equal [ "jsdelivr", MAP ], resolve(packager)
    end

    assert_equal %w[ jspm esm.run jsdelivr ], packager.asked.map(&:last)
  end

  test "a package no CDN has resolves to nothing, with every reason reported" do
    packager = FakePackager.new("jspm" => "Error: Not Found", "esm.run" => nil, "jsdelivr" => "Error: Not Found")

    assert_output(%(jspm couldn't resolve "mermaid@10.6.0" (Not Found); trying esm.run\n) +
                  %(esm.run couldn't resolve "mermaid@10.6.0"; trying jsdelivr\n) +
                  %(jsdelivr couldn't resolve "mermaid@10.6.0" (Not Found)\n)) do
      assert_nil resolve(packager)
    end
  end

  # A CDN that answers "no" is a fact about the package; one that can't be
  # reached at all is a fact about the run, and swallowing it would report a
  # network outage as a package that doesn't exist.
  test "the error from the last CDN is raised when it couldn't be reached" do
    packager = FakePackager.new("jspm" => nil, "esm.run" => nil,
                                "jsdelivr" => Importmap::Packager::HTTPError.new("Unexpected transport error"))

    error = assert_raises(Importmap::Packager::HTTPError) do
      capture_io { resolve(packager) }
    end

    assert_equal "Unexpected transport error", error.message
  end

  test "an earlier error is not raised once a later CDN has merely answered no" do
    packager = FakePackager.new("jspm" => Importmap::Packager::HTTPError.new("Unexpected transport error"),
                                "esm.run" => nil, "jsdelivr" => nil)

    capture_io { assert_nil resolve(packager) }
  end

  test "every spec in a batch is named in the reason" do
    packager = FakePackager.new("jspm" => nil, "esm.run" => MAP)

    assert_output(%(jspm couldn't resolve "md5@2.2.0", "luxon"; trying esm.run\n)) do
      Importmap::ProviderChain.new.resolve(packager, [ "md5@2.2.0", "luxon" ], env: "production") { |*args| args }
    end
  end

  test "the env the caller asked for reaches every CDN" do
    packager = FakePackager.new("jspm" => nil, "esm.run" => MAP)

    capture_io { Importmap::ProviderChain.new.resolve(packager, [ "md5" ], env: "development") { |*args| args } }

    assert_equal [ "development", "development" ], packager.asked.map { |_specs, env, _from| env }
  end

  test "the chain is named as one sentence when no CDN in it had the package" do
    assert_equal "jspm, esm.run or jsdelivr", Importmap::ProviderChain.to_sentence
  end

  # A pin comment records the provider as jspm.io, --from takes it as jspm.
  test "either spelling of jspm names the head of the chain" do
    assert Importmap::ProviderChain.default?("jspm")
    assert Importmap::ProviderChain.default?("jspm.io")
    assert_not Importmap::ProviderChain.default?("jsdelivr")
    assert_not Importmap::ProviderChain.default?(nil)
  end

  private
    def resolve(packager, specs = [ "mermaid@10.6.0" ], env: "production")
      Importmap::ProviderChain.new.resolve(packager, specs, env: env) { |provider, response| [ provider, response ] }
    end
end
