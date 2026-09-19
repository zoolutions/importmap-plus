require "test_helper"
require "importmap/batch_resolver"

class Importmap::BatchResolverTest < ActiveSupport::TestCase
  # Stands in for Importmap::Packager. Answers are keyed by the exact request
  # the resolver makes — [ provider, specs ] — because the whole point of the
  # class under test is which requests it makes, not only what comes back.
  # The two pure helpers come from the real Packager so the fake can't drift.
  class FakePackager
    attr_reader :asked, :last_import_error

    delegate :package_key_for, :extract_package_version_from, to: :@packager

    def initialize(answers)
      @answers  = answers
      @asked    = []
      @packager = Importmap::Packager.new
    end

    def import(*specs, env:, from:)
      @asked << [ from, specs ]
      @last_import_error = nil

      case (answer = @answers[[ from, specs ]])
      when Exception then raise answer
      when String then (@last_import_error = answer) && nil
      else answer
      end
    end
  end

  MD5     = "https://ga.jspm.io/npm:md5@2.2.0/md5.js".freeze
  MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@10.6.0/+esm".freeze
  BOTH    = [ "md5@2.2.0", "mermaid@10.6.0" ].freeze

  test "a batch every spec resolves in makes one request and yields every import" do
    packager = FakePackager.new([ "jspm", BOTH ] => { imports: { "md5" => MD5, "mermaid" => "https://ga.jspm.io/npm:mermaid@10.6.0/dist/mermaid.js" } })

    assert_equal [ [ "md5", MD5 ], [ "mermaid", "https://ga.jspm.io/npm:mermaid@10.6.0/dist/mermaid.js" ] ],
                 collect(packager, BOTH, fallback: true)

    assert_equal [ [ "jspm", BOTH ] ], packager.asked
    assert_empty resolver_for(packager).unresolved
  end

  test "a refused fallback batch asks for each spec on its own and only the refused one changes CDN" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                  => "Error: Unable to resolve https://ga.jspm.io/npm:mermaid@10.6.0/",
      [ "jspm", [ "md5@2.2.0" ] ]       => { imports: { "md5" => MD5 } },
      [ "jspm", [ "mermaid@10.6.0" ] ]  => "Error: Unable to resolve https://ga.jspm.io/npm:mermaid@10.6.0/",
      [ "esm.run", [ "mermaid@10.6.0" ] ] => { imports: { "mermaid" => MERMAID } })

    imports = nil
    out, _err = capture_io { imports = collect(packager, BOTH, fallback: true) }

    assert_equal [ [ "md5", MD5 ], [ "mermaid", MERMAID ] ], imports
    assert_includes out, %(jspm couldn't resolve "md5@2.2.0", "mermaid@10.6.0" (Unable to resolve https://ga.jspm.io/npm:mermaid@10.6.0/); asking for each on its own\n)

    assert_equal [ [ "jspm", BOTH ], [ "jspm", [ "md5@2.2.0" ] ],
                   [ "jspm", [ "mermaid@10.6.0" ] ], [ "esm.run", [ "mermaid@10.6.0" ] ] ], packager.asked
    assert_empty @resolver.unresolved
  end

  test "a refused named-provider batch asks each spec of that provider and no other" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                 => "Error: Unable to resolve",
      [ "jspm", [ "md5@2.2.0" ] ]      => { imports: { "md5" => MD5 } },
      [ "jspm", [ "mermaid@10.6.0" ] ] => "Error: Unable to resolve")

    imports = nil
    out, _err = capture_io { imports = collect(packager, BOTH, from: "jspm", fallback: false) }

    assert_equal [ [ "md5", MD5 ] ], imports
    assert_equal [ "mermaid@10.6.0" ], @resolver.unresolved
    assert_includes out, %(Couldn't find any packages in ["md5@2.2.0", "mermaid@10.6.0"] on jspm (Unable to resolve); asking for each on its own\n)
    assert_equal [ [ [ "mermaid@10.6.0" ], "jspm", "Error: Unable to resolve" ] ], @misses

    assert_equal %w[ jspm jspm jspm ], packager.asked.map(&:first)
  end

  test "a single-spec group makes the same requests it would have made before" do
    packager = FakePackager.new([ "jspm", [ "mermaid@10.6.0" ] ] => "Error: nope",
                                [ "esm.run", [ "mermaid@10.6.0" ] ] => { imports: { "mermaid" => MERMAID } })

    out, _err = capture_io { assert_equal [ [ "mermaid", MERMAID ] ], collect(packager, [ "mermaid@10.6.0" ], fallback: true) }

    assert_equal [ [ "jspm", [ "mermaid@10.6.0" ] ], [ "esm.run", [ "mermaid@10.6.0" ] ] ], packager.asked
    assert_not_includes out, "asking for each on its own"
  end

  test "a spec no CDN has is reported once, recorded, and doesn't stop the rest" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                    => "Error: Unable to resolve",
      [ "jspm", [ "md5@2.2.0" ] ]         => { imports: { "md5" => MD5 } },
      [ "jspm", [ "mermaid@10.6.0" ] ]    => "Error: no build",
      [ "esm.run", [ "mermaid@10.6.0" ] ] => "Error: Not Found",
      [ "jsdelivr", [ "mermaid@10.6.0" ] ] => "Error: Not Found")

    imports = nil
    out, _err = capture_io { imports = collect(packager, BOTH, fallback: true) }

    assert_equal [ [ "md5", MD5 ] ], imports
    assert_equal [ "mermaid@10.6.0" ], @resolver.unresolved
    assert_includes out, %(jspm couldn't resolve "mermaid@10.6.0" (no build); trying esm.run\n)
    assert_includes out, %(esm.run couldn't resolve "mermaid@10.6.0" (Not Found); trying jsdelivr\n)
    assert_includes out, %(jsdelivr couldn't resolve "mermaid@10.6.0" (Not Found)\n)
    assert_equal [ [ [ "mermaid@10.6.0" ], "jspm, esm.run or jsdelivr", nil ] ], @misses
  end

  # Each pin is independent of the others, the stance update already takes on a
  # package the registry couldn't answer for.
  test "a spec whose CDN can't be reached is reported and the specs after it still resolve" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                 => "Error: Unable to resolve",
      [ "jspm", [ "mermaid@10.6.0" ] ] => Importmap::Packager::HTTPError.new("Unexpected response code (502)"),
      [ "jspm", [ "md5@2.2.0" ] ]      => { imports: { "md5" => MD5 } })

    imports = nil
    out, _err = capture_io { imports = collect(packager, [ "mermaid@10.6.0", "md5@2.2.0" ], from: "jspm", fallback: false) }

    assert_equal [ [ "md5", MD5 ] ], imports
    assert_equal [ "mermaid@10.6.0" ], @resolver.unresolved
    assert_includes out, %(Couldn't resolve "mermaid@10.6.0" from jspm: Unexpected response code (502)\n)
  end

  test "a dependency two responses agree on is yielded once" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                 => "Error: Unable to resolve",
      [ "jspm", [ "md5@2.2.0" ] ]      => { imports: { "md5" => MD5, "crypt" => "https://ga.jspm.io/npm:crypt@0.0.2/index.js" } },
      [ "jspm", [ "mermaid@10.6.0" ] ] => { imports: { "mermaid" => MERMAID, "crypt" => "https://ga.jspm.io/npm:crypt@0.0.2/index.js" } })

    imports = nil
    out, _err = capture_io { imports = collect(packager, BOTH, from: "jspm", fallback: false) }

    assert_equal [ [ "md5", MD5 ], [ "crypt", "https://ga.jspm.io/npm:crypt@0.0.2/index.js" ], [ "mermaid", MERMAID ] ], imports
    assert_not_includes out, "Keeping"
  end

  test "a dependency two responses disagree on keeps the first and says so" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                 => "Error: Unable to resolve",
      [ "jspm", [ "md5@2.2.0" ] ]      => { imports: { "md5" => MD5, "crypt" => "https://ga.jspm.io/npm:crypt@0.0.2/index.js" } },
      [ "jspm", [ "mermaid@10.6.0" ] ] => { imports: { "mermaid" => MERMAID, "crypt" => "https://ga.jspm.io/npm:crypt@0.1.0/index.js" } })

    imports = nil
    out, _err = capture_io { imports = collect(packager, BOTH, from: "jspm", fallback: false) }

    assert_equal [ [ "md5", MD5 ], [ "crypt", "https://ga.jspm.io/npm:crypt@0.0.2/index.js" ], [ "mermaid", MERMAID ] ], imports
    assert_includes out, %(Keeping "crypt" at @0.0.2 ("mermaid@10.6.0" resolved it to @0.1.0)\n)
  end

  # md5 is one of the specs the user named, so its pin comes from its own
  # response — a sibling's response mentioning it is a dependency edge, not an
  # answer to what the user asked for.
  test "a spec the user named is taken from its own response, never a sibling's" do
    packager = FakePackager.new(
      [ "jspm", BOTH ]                 => "Error: Unable to resolve",
      [ "jspm", [ "md5@2.2.0" ] ]      => "Error: no build",
      [ "jspm", [ "mermaid@10.6.0" ] ] => { imports: { "mermaid" => MERMAID, "md5" => "https://ga.jspm.io/npm:md5@2.3.0/md5.js" } })

    imports = nil
    capture_io { imports = collect(packager, BOTH, from: "jspm", fallback: false) }

    assert_equal [ [ "mermaid", MERMAID ] ], imports
    assert_equal [ "md5@2.2.0" ], @resolver.unresolved
  end

  private
    def collect(packager, specs, from: nil, fallback: false)
      [].tap do |imports|
        resolver_for(packager).each_import(specs, env: "production", from: from, fallback: fallback) do |package, url|
          imports << [ package, url ]
        end
      end
    end

    def resolver_for(packager)
      @misses ||= []
      @resolver ||= Importmap::BatchResolver.new(packager, on_miss: ->(packages, source, reason:) { @misses << [ packages, source, reason ] })
    end
end
