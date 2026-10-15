# frozen_string_literal: true

require "test_helper"
require "importmap/packager"
require "importmap/npm"

# The class-level settings an app writes once at boot (an initializer pointing
# the CLI at a mirror) and every thread reads after: stored deeply frozen, so
# no reader can be handed a value another thread is still changing.
class BootSettingsTest < ActiveSupport::TestCase
  setup { skip "#{RUBY_ENGINE} has no Ractor, so nothing here can be checked for shareability" unless defined?(Ractor) }

  test "EsmRun.resolver is shareable by default and after a write, through either class" do
    original = Importmap::EsmRun.resolver
    assert_shareable original

    Importmap::EsmRun.resolver = URI("https://mirror.example.com/v1/packages/npm/")
    assert_shareable Importmap::EsmRun.resolver

    Importmap::Packager.esm_run_resolver = URI("https://other.example.com/v1/packages/npm/")
    assert_shareable Importmap::EsmRun.resolver
    assert_equal URI("https://other.example.com/v1/packages/npm/"), Importmap::EsmRun.resolver
  ensure
    Importmap::EsmRun.resolver = original
  end

  test "Npm.base_uri is shareable by default and after a write" do
    original = Importmap::Npm.base_uri
    assert_shareable original

    Importmap::Npm.base_uri = URI("https://registry.example.com")
    assert_shareable Importmap::Npm.base_uri
  ensure
    Importmap::Npm.base_uri = original
  end

  test "Packager.endpoint is shareable by default and after a write" do
    original = Importmap::Packager.endpoint
    assert_shareable original

    Importmap::Packager.endpoint = URI("https://generator.example.com/generate")
    assert_shareable Importmap::Packager.endpoint
  ensure
    Importmap::Packager.endpoint = original
  end

  test "a frozen URI setting still builds the request URIs derived from it" do
    original = Importmap::Npm.base_uri
    Importmap::Npm.base_uri = URI("https://registry.example.com")
    npm = Importmap::Npm.new(file_fixture("outdated_import_map.rb"))
    requested = nil

    npm.stub(:get_json, ->(uri) { requested = uri.to_s; "{}" }) { npm.send(:get_package, "md5") }

    assert_equal "https://registry.example.com/md5", requested
  ensure
    Importmap::Npm.base_uri = original
  end

  test "the default minifier is shareable and is the first tool found" do
    assert_shareable Importmap::Packager.minifier
    assert_equal Importmap::Minifier.detect, Importmap::Packager.minifier.tool
  end

  test "a minifier an app sets is used as given, shareable or not" do
    original = Importmap::Packager.minifier
    minifier = ->(source) { source.upcase }

    Importmap::Packager.minifier = minifier
    assert_same minifier, Importmap::Packager.minifier
  ensure
    Importmap::Packager.minifier = original
  end

  test "assigning nil puts the default minifier back" do
    original = Importmap::Packager.minifier
    Importmap::Packager.minifier = ->(source) { source }

    Importmap::Packager.minifier = nil

    assert_kind_of Importmap::Minifier, Importmap::Packager.minifier
    assert_equal Importmap::Minifier.detect, Importmap::Packager.minifier.tool
    assert_shareable Importmap::Packager.minifier
  ensure
    Importmap::Packager.minifier = original
  end

  test "the minifiers' argv builders are shareable" do
    assert_shareable Importmap::Minifier::TOOLS
    assert_equal [ "in.js", "--minify", "--format=esm", "--outfile=out.js" ], Importmap::Minifier::TOOLS.fetch("esbuild").call("in.js", "out.js")
  end

  private
    def assert_shareable(value)
      assert Ractor.shareable?(value), "#{value.inspect} (#{value.class}) is not Ractor-shareable"
    end
end
