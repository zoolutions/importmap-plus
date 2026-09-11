require "net/http"
require "uri"
require "json"
require "importmap/minifier"
require "importmap/http_retries"

class Importmap::Packager
  include Importmap::HttpRetries

  PIN_REGEX = /#{Importmap::Map::PIN_REGEX}(.*)/.freeze # :nodoc:
  PRELOAD_OPTION_REGEXP = /preload:\s*(\[[^\]]+\]|true|false|["'][^"']*["'])/.freeze # :nodoc:
  TO_OPTION_REGEXP = /to:\s*["']([^"']*)["']/.freeze # :nodoc:
  REMOTE_URL_REGEXP = %r{\Ahttps?://}.freeze # :nodoc:

  PROVIDER_HOSTS = {
    "ga.jspm.io"       => "jspm.io",
    "unpkg.com"        => "unpkg",
    "cdn.jsdelivr.net" => "jsdelivr",
    "cdn.skypack.dev"  => "skypack",
    "esm.sh"           => "esm.sh"
  }.freeze # :nodoc:

  # jsDelivr's bundling endpoint (https://www.jsdelivr.com/esm): one minified
  # ESM file per package, with its dependencies referenced as /npm/dep@ver/+esm.
  ESM_RUN_PROVIDER    = "esm.run".freeze # :nodoc:
  ESM_RUN_CDN         = "https://cdn.jsdelivr.net/npm/".freeze # :nodoc:
  ESM_RUN_URL_REGEXP  = %r{\Ahttps://cdn\.jsdelivr\.net/npm/.+/\+esm\z}.freeze # :nodoc:
  # An esm.run bundle's own imports: `from"/npm/dep@1.2.3/+esm"`, `import"…"`,
  # `import("…")`, `export … from"…"`. Anchored on the keyword so an ordinary
  # string that happens to look like a bundle URL is left alone. What it does
  # not do is parse JavaScript, so the same text inside a string or a comment
  # would still be rewritten — a jsDelivr bundle is esbuild output whose only
  # surviving comment is the banner, and a root-relative /npm/ URL is
  # meaningless anywhere but in one of its own imports.
  ESM_RUN_IMPORT_REGEXP =
    %r{((?:\bfrom|\bimport)\s*\(?\s*)(["'])/npm/((?:@[^/"'@]+/)?[^/"'@]+)@([^/"']+)((?:/[^"']*?)?)/\+esm\2}.freeze # :nodoc:
  # name[@version][/subpath] — a leading "@" distinguishes a scoped name
  # (@scope/pkg) from an unscoped name with a subpath (apexcharts/core).
  PACKAGE_SPEC_REGEXP = %r{\A(@[^@/]+/[^@/]+|[^@/]+)(?:@([^/]+))?(/.+)?\z}.freeze # :nodoc:
  # The version comment on a vendored pin, plus what it was built with:
  #   pin "luxon" # @3.7.2
  #   pin "luxon" # @3.7.2 (esm.run, minified)
  PIN_PROVENANCE_REGEXP = /#\s*@([^\s(]+)(?:\s+\(([^)]*)\))?/.freeze # :nodoc:
  DEFAULT_PROVIDER = "jspm.io".freeze # :nodoc:

  Error        = Class.new(StandardError)
  HTTPError    = Class.new(Error)
  ServiceError = Error.new(Error)

  singleton_class.attr_accessor :endpoint
  self.endpoint = URI("https://api.jspm.io/generate")

  singleton_class.attr_accessor :esm_run_resolver
  self.esm_run_resolver = URI("https://data.jsdelivr.com/v1/packages/npm/")

  # CDNs reset connections and rate-limit bursts. Each request is tried this
  # many times, pausing retry_wait × attempt between tries, before it fails.
  # Shared with Importmap::Npm, which talks to the registry the same way.
  class << self
    def retry_attempts = Importmap::HttpRetries.attempts
    def retry_attempts=(value)
      Importmap::HttpRetries.attempts = value
    end

    def retry_wait = Importmap::HttpRetries.wait
    def retry_wait=(value)
      Importmap::HttpRetries.wait = value
    end
  end

  # Anything responding to #call(source) => String. Defaults to the first of
  # bun, esbuild or terser found on the machine.
  singleton_class.attr_writer :minifier

  def self.minifier
    @minifier ||= Importmap::Minifier.new
  end

  attr_reader :vendor_path

  def initialize(importmap_path = "config/importmap.rb", vendor_path: "vendor/javascript")
    @importmap_path = Pathname.new(importmap_path)
    @vendor_path    = Pathname.new(vendor_path)
  end

  def import(*packages, env: "production", from: "jspm")
    return import_from_esm_run(packages) if esm_run?(from)

    response = post_json({
      "install"      => Array(packages),
      "flattenScope" => true,
      "env"          => [ "browser", "module", env ],
      "provider"     => normalize_provider(from),
    })

    case response.code
    when "200"
      extract_parsed_response(response)
    when "404", "401"
      nil
    else
      handle_failure_response(response)
    end
  end

  def pin_for(package, url = nil, preloads: nil)
    to = url ? %(, to: "#{url}") : ""
    preload_param = preload(preloads)

     %(pin "#{package}") + to + preload_param
  end

  # The pin line for a vendored download. The version comment also records
  # the CDN when it isn't jspm and whether the file was minified, so a later
  # update or pristine can do the same again:
  #
  #   pin "luxon" # @3.7.2
  #   pin "luxon" # @3.7.2 (esm.run, minified)
  #
  def vendored_pin_for(package, url, preloads = nil, minify: false)
    filename = package_filename(package)
    version  = extract_package_version_from(url)
    to = "#{package}.js" != filename ? filename : nil

    provenance = []
    provenance << provider_for_url(url) if provider_for_url(url) && provider_for_url(url) != DEFAULT_PROVIDER
    provenance << "minified" if minify

    pin_for(package, to, preloads: preloads) + %( # #{version}) + (provenance.any? ? %( (#{provenance.join(", ")})) : "")
  end

  # What the pin's version comment says a vendored package was built with:
  # { version:, provider:, minified: }, or nil for a pin without one.
  def pin_provenance(package)
    return unless @importmap_path.exist?

    line = importmap.lines.find { |candidate| candidate.match?(Importmap::Map.pin_line_regexp_for(package)) }
    match = line&.match(PIN_PROVENANCE_REGEXP)
    return unless match

    details = match[2].to_s.split(",").map(&:strip)
    minified = details.delete("minified") ? true : false

    { version: match[1], provider: details.first, minified: minified }
  end

  def packaged?(package)
    importmap.match(Importmap::Map.pin_line_regexp_for(package))
  end

  # Downloads +url+ into vendor/javascript. With +minify: true+ the source is
  # run through .minifier first and the file header records it, so later
  # updates keep minifying. Returns the dependencies an esm.run bundle imports
  # as [package, url] pairs (empty for every other provider), with the bundle's
  # absolute /npm/... imports rewritten to bare specifiers on the way in.
  def download(package, url, minify: false)
    ensure_vendor_directory_exists
    remove_existing_package_file(package)
    download_package_file(package, url, minify: minify)
  end

  def remove(package)
    remove_existing_package_file(package)
    remove_package_from_importmap(package)
  end

  def extract_existing_pin_options(packages)
    return {} unless @importmap_path.exist?

    packages = Array(packages)

    all_package_options = build_package_options_lookup(importmap.lines)

    packages.to_h do |package|
      [package, all_package_options[package] || {}]
    end
  end

  # Drops the cached import map so a read after a write sees the new file:
  # pinning an esm.run bundle appends pins and then asks the map what its
  # dependencies still need.
  def reload!
    @importmap = nil
    self
  end

  # The provenance a pin would record for +url+, shaped like #pin_provenance
  # returns, so a caller can tell whether the existing pin already says this.
  def provenance_for(url, minify: false)
    provider = provider_for_url(url)

    { provider: provider == DEFAULT_PROVIDER ? nil : provider, minified: minify ? true : false }
  end

  def remote_pin?(package)
    options = extract_existing_pin_options(package)[package] || {}
    options[:to].to_s.match?(REMOTE_URL_REGEXP)
  end

  def provider_for_url(url)
    return ESM_RUN_PROVIDER if url.to_s.match?(ESM_RUN_URL_REGEXP)

    PROVIDER_HOSTS[URI(url.to_s).host]
  rescue URI::InvalidURIError
    nil
  end

  def esm_run?(provider)
    provider.to_s == ESM_RUN_PROVIDER
  end

  def remove_existing_package_file(package)
    FileUtils.rm_rf vendored_package_path(package)
  end

  def extract_package_version_from(url)
    url.match(/@\d+\.\d+\.\d+[^\/\s"']*/)&.to_a&.first
  end

  private
    def build_package_options_lookup(lines)
      lines.each_with_object({}) do |line, package_options|
        match = line.strip.match(PIN_REGEX)

        if match
          package_name = match[1]
          options_part = match[2]

          options = {}

          if (preload_match = options_part.match(PRELOAD_OPTION_REGEXP))
            options[:preload] = preload_from_string(preload_match[1])
          end

          if (to_match = options_part.match(TO_OPTION_REGEXP))
            options[:to] = to_match[1]
          end

          package_options[package_name] = options if options.any?
        end
      end
    end

    def preload_from_string(value)
      case value
      when "true"
        true
      when "false"
        false
      when /^\[.*\]$/
        JSON.parse(value)
      else
        value.gsub(/["']/, "")
      end
    end

    def preload(preloads)
      case Array(preloads)
      in []
        ""
      in ["true"] | [true]
        %(, preload: true)
      in ["false"] | [false]
        %(, preload: false)
      in [string]
        %(, preload: "#{string}")
      else
        %(, preload: #{preloads})
      end
    end

    def post_json(body)
      with_retries("posting to #{self.class.endpoint}") do
        Net::HTTP.post(self.class.endpoint, body.to_json, "Content-Type" => "application/json")
      end
    rescue HTTPError
      raise
    rescue => error
      raise HTTPError, "Unexpected transport error (#{error.class}: #{error.message})"
    end

    def normalize_provider(name)
      name.to_s == "jspm" ? "jspm.io" : name.to_s
    end

    def extract_parsed_response(response)
      parsed = JSON.parse(response.body)
      imports = parsed.dig("map", "imports")

      {
        imports: imports,
      }
    end

    def handle_failure_response(response)
      if error_message = parse_service_error(response)
        raise ServiceError, error_message
      else
        raise HTTPError, "Unexpected response code (#{response.code})"
      end
    end

    def parse_service_error(response)
      JSON.parse(response.body.to_s)["error"]
    rescue JSON::ParserError
      nil
    end

    def importmap
      @importmap ||= File.read(@importmap_path)
    end


    def ensure_vendor_directory_exists
      FileUtils.mkdir_p @vendor_path
    end

    def remove_package_from_importmap(package)
      all_lines = File.readlines(@importmap_path)
      with_lines_removed = all_lines.grep_v(Importmap::Map.pin_line_regexp_for(package))

      File.open(@importmap_path, "w") do |file|
        with_lines_removed.each { |line| file.write(line) }
      end
    end

    def download_package_file(package, url, minify: false)
      response = with_retries("downloading #{url}") { Net::HTTP.get_response(URI(url)) }

      if response.code == "200"
        source = response.body.dup.force_encoding("UTF-8")
        source, dependencies = rewrite_esm_run_imports(source) if url.match?(ESM_RUN_URL_REGEXP)
        source = self.class.minifier.call(source) if minify

        save_vendored_package(package, url, source, minified: minify)

        dependencies || []
      else
        handle_failure_response(response)
      end
    end

    def save_vendored_package(package, url, source, minified: false)
      File.open(vendored_package_path(package), "w+") do |vendored_package|
        vendored_package.write "// #{package}#{extract_package_version_from(url)} downloaded from #{url}#{" (minified)" if minified}\n\n"

        vendored_package.write remove_sourcemap_comment_from(source).force_encoding("UTF-8")
      end
    end

    # Turns import "/npm/dep@1.2.3/+esm" into import "dep" so the bundle
    # resolves through the import map, and lists what it needs pinned.
    def rewrite_esm_run_imports(source)
      dependencies = {}

      rewritten = source.gsub(ESM_RUN_IMPORT_REGEXP) do
        keyword, quote, name, version, subpath = $1, $2, $3, $4, $5.to_s
        dependencies["#{name}#{subpath}"] ||= "#{ESM_RUN_CDN}#{name}@#{version}#{subpath}/+esm"
        "#{keyword}#{quote}#{name}#{subpath}#{quote}"
      end

      [rewritten, dependencies.to_a]
    end

    def import_from_esm_run(packages)
      imports = packages.to_h do |spec|
        name, requested, subpath = spec.match(PACKAGE_SPEC_REGEXP)&.captures
        raise Error, "Can't parse package spec #{spec.inspect}" unless name

        version = resolve_esm_run_version(name, requested)
        return nil unless version

        ["#{name}#{subpath}", "#{ESM_RUN_CDN}#{name}@#{version}#{subpath}/+esm"]
      end

      { imports: imports }
    end

    def resolve_esm_run_version(name, requested)
      uri = self.class.esm_run_resolver.dup
      uri.path += "#{name}/resolved"
      uri.query = "specifier=#{URI.encode_www_form_component(requested)}" if requested

      response = with_retries("resolving #{uri}") { Net::HTTP.get_response(uri) }

      case response.code
      when "200"
        JSON.parse(response.body)["version"]
      when "404"
        nil
      else
        handle_failure_response(response)
      end
    rescue JSON::ParserError
      raise HTTPError, "Unexpected response from #{uri}"
    end

    def remove_sourcemap_comment_from(source)
      source.gsub(/^\/\/# sourceMappingURL=.*/, "")
    end

    def vendored_package_path(package)
      @vendor_path.join(package_filename(package))
    end

    def package_filename(package)
      package.gsub("/", "--") + ".js"
    end
end
