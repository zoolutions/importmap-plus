require "uri"
require "json"

# Everything this gem knows about jsDelivr's bundling endpoint
# (https://www.jsdelivr.com/esm): one minified ESM file per package, with its
# dependencies referenced as /npm/dep@ver/+esm.
#
# It is the one provider whose URLs a CDN host can't identify — an esm.run
# bundle and a plain jsDelivr file are both served from cdn.jsdelivr.net — and
# the one whose downloads have to be rewritten before they can be vendored, so
# both facts live here rather than in Importmap::Packager, which asks this
# class the two questions it has: is this that provider, and is this one of its
# URLs.
#
# Nothing here writes a file or reads config/importmap.rb. The version lookup
# is the one request, and it goes out through the Packager so a jsDelivr that
# rate-limits or resets gets the same bounded retries as every other request
# this gem makes, and fails as the same Importmap::Packager::HTTPError.
class Importmap::EsmRun
  PROVIDER   = "esm.run".freeze # :nodoc:
  CDN        = "https://cdn.jsdelivr.net/npm/".freeze # :nodoc:
  URL_REGEXP = %r{\Ahttps://cdn\.jsdelivr\.net/npm/.+/\+esm\z}.freeze # :nodoc:
  # A bundle's own imports: `from"/npm/dep@1.2.3/+esm"`, `import"…"`,
  # `import("…")`, `export … from"…"`. Anchored on the keyword so an ordinary
  # string that happens to look like a bundle URL is left alone. What it does
  # not do is parse JavaScript, so the same text inside a string or a comment
  # would still be rewritten — a jsDelivr bundle is esbuild output whose only
  # surviving comment is the banner, and a root-relative /npm/ URL is
  # meaningless anywhere but in one of its own imports.
  IMPORT_REGEXP =
    %r{((?:\bfrom|\bimport)\s*\(?\s*)(["'])/npm/((?:@[^/"'@]+/)?[^/"'@]+)@([^/"']+)((?:/[^"']*?)?)/\+esm\2}.freeze # :nodoc:

  # The jsDelivr data API versions are resolved through. Also readable and
  # writable as Importmap::Packager.esm_run_resolver, which is where an app
  # that points this at a mirror has always set it.
  singleton_class.attr_accessor :resolver
  self.resolver = URI("https://data.jsdelivr.com/v1/packages/npm/")

  class << self
    def provider?(provider)
      provider.to_s == PROVIDER
    end

    def url?(url)
      url.to_s.match?(URL_REGEXP)
    end

    def url_for(name, version, subpath = nil)
      "#{CDN}#{name}@#{version}#{subpath}/+esm"
    end

    # Turns import "/npm/dep@1.2.3/+esm" into import "dep" so the bundle
    # resolves through the import map, and lists what it needs pinned as
    # [ [ package, url ], … ].
    def rewrite_imports(source)
      dependencies = {}
      versions = Hash.new { |hash, key| hash[key] = [] }

      rewritten = source.gsub(IMPORT_REGEXP) do
        keyword, quote, name, version, subpath = $1, $2, $3, $4, $5.to_s
        key = "#{name}#{subpath}"
        dependencies[key] ||= url_for(name, version, subpath)
        versions[key] << version unless versions[key].include?(version)
        "#{keyword}#{quote}#{name}#{subpath}#{quote}"
      end

      warn_about_conflicting_versions(versions)

      [ rewritten, dependencies.to_a ]
    end

    private
      # An import map maps a bare specifier to one file, so a bundle that
      # imports the same package at two versions can only get the first one it
      # asked for. Say so rather than pick silently.
      def warn_about_conflicting_versions(versions)
        versions.each do |key, seen|
          next if seen.one?

          warn %(#{key} is imported at #{seen.join(", ")} by this bundle; pinning @#{seen.first}, an import map holds one version)
        end
      end
  end

  def initialize(packager)
    @packager = packager
  end

  # The import map Importmap::Packager#import answers with, built from the
  # version jsDelivr resolves each spec to; nil when it hasn't got one of them,
  # because a bundle URL for a version nobody published is a 404 at download.
  def imports(specs)
    imports = Array(specs).to_h do |spec|
      name, requested, subpath = spec.to_s.match(Importmap::Packager::PACKAGE_SPEC_REGEXP)&.captures
      raise Importmap::Packager::Error, "Can't parse package spec #{spec.inspect}" unless name

      version = resolve_version(name, requested)
      return nil unless version

      [ "#{name}#{subpath}", self.class.url_for(name, version, subpath) ]
    end

    { imports: imports }
  end

  private
    def resolve_version(name, requested)
      uri = self.class.resolver.dup
      uri.path += "#{name}/resolved"
      uri.query = "specifier=#{URI.encode_www_form_component(requested)}" if requested

      body = @packager.fetch_remote(uri, allow_missing: true, description: "resolving #{uri}")

      body && JSON.parse(body)["version"]
    rescue JSON::ParserError
      raise Importmap::Packager::HTTPError, "Unexpected response from #{uri}"
    end
end
