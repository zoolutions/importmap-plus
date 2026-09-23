require "net/http"
require "uri"
require "json"
require "importmap/http_retries"

class Importmap::Npm
  include Importmap::HttpRetries

  PIN_REGEX = /#{Importmap::Map::PIN_REGEX}.*/.freeze # :nodoc:
  VERSION_FROM_URL_REGEX = /^pin .*(?<=npm:|npm\/|skypack\.dev\/|unpkg\.com\/|esm\.sh\/|esm\.sh\/\*)([^@\/]+)@(\d+\.\d+\.\d+(?:[^\/\s"']*))/.freeze # :nodoc:
  VERSION_FROM_COMMENT_REGEX = /#{PIN_REGEX} #.*@(\d+\.\d+\.\d+(?:[^\s]*)).*$/.freeze # :nodoc:

  Error     = Class.new(StandardError)
  HTTPError = Class.new(Error)

  singleton_class.attr_accessor :base_uri
  self.base_uri = URI("https://registry.npmjs.org")

  def initialize(importmap_path = "config/importmap.rb", vendor_path: "vendor/javascript")
    @importmap_path = Pathname.new(importmap_path)
    @vendor_path    = Pathname.new(vendor_path)
  end

  # With +only:+, just those packages are looked up; names may carry a
  # subpath (apexcharts/core), which the registry doesn't know about.
  def outdated_packages(only: nil)
    wanted = only&.map { |name| extract_base_package_name(name) }
    candidates = wanted ? packages_with_versions.select { |package, _| wanted.include?(package) } : packages_with_versions

    candidates.each_with_object([]) do |(package, current_version), outdated_packages|
      outdated_package = OutdatedPackage.new(name: package, current_version: current_version)

      if !(response = get_package(package))
        outdated_package.error = 'Response error'
      elsif (error = response['error'])
        outdated_package.error = error
      else
        latest_version = find_latest_version(response)
        next unless outdated?(current_version, latest_version)

        outdated_package.latest_version = latest_version
      end

      outdated_packages << outdated_package
    end.sort_by(&:name)
  end

  # The version the registry calls latest, or nil when it couldn't be asked.
  # The registry is authoritative about what a package's latest version is,
  # where a CDN answers with the latest it happens to have built.
  def latest_version(package)
    response = get_package(package)

    find_latest_version(response)&.to_s unless response.nil? || response["error"]
  end

  def vulnerable_packages
    get_audit.flat_map do |package, vulnerabilities|
      vulnerabilities.map do |vulnerability|
        VulnerablePackage.new(
          name: package,
          severity: vulnerability['severity'],
          vulnerable_versions: vulnerability['vulnerable_versions'],
          vulnerability: vulnerability['title']
        )
      end
    end.sort_by { |p| [p.name, p.severity] }
  end

  # Memoized: a command that asks twice would otherwise report the
  # unversioned packages twice.
  def packages_with_versions
    @packages_with_versions ||= begin
      # We cannot use the name after "pin" because some dependencies are loaded from inside packages
      # Eg. pin "buffer", to: "https://ga.jspm.io/npm:@jspm/core@2.0.0-beta.19/nodelibs/browser/buffer.js"
      with_versions = importmap.scan(VERSION_FROM_URL_REGEX) |
        importmap.scan(VERSION_FROM_COMMENT_REGEX)

      with_versions.map! do |package, version|
        [extract_base_package_name(package), version]
      end.uniq!

      vendored_packages_without_version(with_versions).each do |package, path|
        $stdout.puts "Ignoring #{package} (#{path}) since no version is specified in the importmap"
      end

      with_versions
    end
  end

  private
    OutdatedPackage   = Struct.new(:name, :current_version, :latest_version, :error, keyword_init: true)
    VulnerablePackage = Struct.new(:name, :severity, :vulnerable_versions, :vulnerability, keyword_init: true)

    def importmap
      @importmap ||= File.read(@importmap_path)
    end

    def get_package(package)
      uri = self.class.base_uri.dup
      uri.path = "/" + package
      response = get_json(uri)

      JSON.parse(response)
    rescue JSON::ParserError
      nil
    rescue HTTPError => error
      # One package the registry won't answer for shouldn't end the run: the
      # caller records it as unchecked, so the rest are still reported on.
      # with_retries has already spent its attempts by the time we get here.
      { "error" => error.message }
    end

    def get_json(uri)
      request = Net::HTTP::Get.new(uri)
      request["Content-Type"] = "application/json"

      response = begin
        with_retries("fetching #{uri}") do
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http|
            http.request(request)
          }
        end
      rescue HTTPError
        raise
      rescue => error
        raise HTTPError, "Unexpected transport error (#{error.class}: #{error.message})"
      end

      unless response.code.to_i < 300
        raise HTTPError, "Unexpected error response #{response.code}: #{response.body}"
      end

      response.body
    end

    def find_latest_version(response)
      latest_version = response.is_a?(String) ? response : response.dig('dist-tags', 'latest')
      return latest_version if latest_version

      return unless response['versions']

      response['versions'].keys.map { |v| Gem::Version.new(v) rescue nil }.compact.sort.last
    end

    def outdated?(current_version, latest_version)
      Gem::Version.new(current_version) < Gem::Version.new(latest_version)
    rescue ArgumentError
      current_version.to_s < latest_version.to_s
    end

    def get_audit
      uri = self.class.base_uri.dup
      uri.path = "/-/npm/v1/security/advisories/bulk"

      body = packages_with_versions.each.with_object({}) { |(package, version), data|
        data[package] ||= []
        data[package] << version
      }
      return {} if body.empty?

      response = post_json(uri, body)

      unless response.code.to_i < 300
        raise HTTPError, "Unexpected error response #{response.code}: #{response.body}"
      end

      JSON.parse(response.body)
    end

    def post_json(uri, body)
      with_retries("posting to #{uri}") do
        Net::HTTP.post(uri, body.to_json, "Content-Type" => "application/json")
      end
    rescue HTTPError
      raise
    rescue => error
      raise HTTPError, "Unexpected transport error (#{error.class}: #{error.message})"
    end

    def extract_base_package_name(package)
      if package.start_with?("@")
        # Scoped packages can have nested paths, e.g. @scope/package/subpath
        parts = package.split("/", 3)
        parts.size > 2 ? parts.first(2).join("/") : package
      else
        # Non-scoped packages - just take the first part
        package.split("/").first
      end
    end

    def vendored_packages_without_version(packages_with_versions)
      versioned_packages = packages_with_versions.map(&:first).to_set

      importmap
        .lines
        .filter_map { |line| find_unversioned_vendored_package(line, versioned_packages) }
    end

    def find_unversioned_vendored_package(line, versioned_packages)
      regexp = line.include?("to:")? /#{PIN_REGEX}to: ["']([^"']*)["'].*/ : PIN_REGEX
      match = line.match(regexp)

      return unless match

      package, filename = match.captures
      filename ||= "#{package}.js"

      return if versioned_packages.include?(package)
      return if versioned_line?(line)

      path = File.join(@vendor_path, filename)
      [package, path] if File.exist?(path)
    end

    # A pin is versioned by its own line, not by another pin of the same
    # package. The audit checks a package once at the version its pins name,
    # so "@tiptap/pm/tables" with its own comment is covered by "@tiptap/pm";
    # a vendored subpath with no comment is a file of unknown version even when
    # its base package is pinned at one, and the warning exists for that file.
    def versioned_line?(line)
      line.match?(VERSION_FROM_URL_REGEX) || line.match?(VERSION_FROM_COMMENT_REGEX)
    end
end
