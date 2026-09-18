require "net/http"
require "uri"
require "json"
require "importmap/minifier"
require "importmap/module_inspector"
require "importmap/package_graph"
require "importmap/vendored_graph"
require "importmap/http_retries"
require "importmap/integrity"

class Importmap::Packager
  include Importmap::HttpRetries

  PIN_REGEX = /#{Importmap::Map::PIN_REGEX}(.*)/.freeze # :nodoc:
  PRELOAD_OPTION_REGEXP = /preload:\s*(\[[^\]]+\]|true|false|["'][^"']*["'])/.freeze # :nodoc:
  TO_OPTION_REGEXP = /to:\s*["']([^"']*)["']/.freeze # :nodoc:
  # Only the booleans: a hash string is tied to the file it was computed for,
  # so a rewrite that changes the URL has to drop it.
  INTEGRITY_OPTION_REGEXP = /integrity:\s*(true|false)\b/.freeze # :nodoc:
  INTEGRITY_HASH_REGEXP = /integrity:\s*["'][^"']+["']/.freeze # :nodoc:
  REMOTE_URL_REGEXP = %r{\Ahttps?://}.freeze # :nodoc:
  IDENTITY_ENCODING = { "Accept-Encoding" => "identity" }.freeze # :nodoc:

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
  # A lock is one more detail in that list, always last:
  #   pin "luxon" # @3.7.2 (esm.run, minified, locked)
  # "locked: <range>" is reserved for range locks, so it is read as a lock
  # today rather than mistaken for a provider name.
  LOCK_DETAIL        = "locked".freeze # :nodoc:
  LOCK_DETAIL_REGEXP = /\Alocked(?::\s*(.+))?\z/.freeze # :nodoc:
  # Why a package was left pinned to its CDN URL instead of vendored, and the
  # mark that says a vendored file was kept despite that check:
  #   pin "@popperjs/core", to: "https://…" # @2.11.8 (remote: relative imports)
  #   pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8 (vendored)
  # Both sit in the same slot — a pin is one or the other, never both — and
  # both have to be excluded when the provider is read, or "vendored" and
  # "remote: workers" are taken for CDN names.
  REMOTE_DETAIL        = "remote".freeze # :nodoc:
  REMOTE_DETAIL_REGEXP = /\Aremote(?::\s*(.+))?\z/.freeze # :nodoc:
  VENDORED_DETAIL      = "vendored".freeze # :nodoc:
  DEFAULT_PROVIDER = "jspm.io".freeze # :nodoc:

  Error        = Class.new(StandardError)
  HTTPError    = Class.new(Error)
  ServiceError = Class.new(Error)

  # A download that can't be served as the files an import map entry points at.
  # Raised before anything is written, so the vendored file an app already has
  # survives; #reasons lists what Importmap::ModuleInspector found, less the
  # relative imports a file graph answers for. The pin is kept remote, and
  # #integrity is the hash of the bytes as the CDN served them — before any
  # rewriting — so that pin carries it without a second fetch.
  class Unvendorable < Error
    attr_reader :reasons, :integrity

    def initialize(reasons, integrity: nil)
      @reasons   = Array(reasons)
      @integrity = integrity
      super("can't be vendored as a single file (#{@reasons.join(", ")})")
    end
  end

  # A download that isn't an ES module — a CommonJS or UMD bundle, which every
  # CDN that serves a package's own dist file will hand back for a package that
  # publishes one. Loaded through an import map it runs and exports nothing, so
  # the app's `import x from "pkg"` fails to link in the browser and takes the
  # importing module down with it. Raised before anything is written, like
  # Unvendorable, and kept remote the same way, with the same #reasons and
  # #integrity so the caller can treat the two alike.
  class NotAnEsModule < Error
    attr_reader :reasons, :integrity

    def initialize(integrity: nil)
      @reasons   = [ "not an ES module" ]
      @integrity = integrity
      super("isn't an ES module")
    end
  end

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

  # What the CDN said about the most recent #import that came back empty, or
  # nil. jspm answers 401 with its generator's reason in the body — "No
  # './dist/cytoscape.umd.js' exports subpath defined" — and #import still
  # answers nil, because one spec a CDN can't serve must not end a whole run.
  # The reason is worth repeating to whoever asked, and to the next CDN's turn.
  attr_reader :last_import_error

  # The file graph the most recent #download vendored beside its entry, or nil
  # when that download was one file. A reader rather than a second return
  # value: #download's is the esm.run dependency list callers destructure.
  attr_reader :last_graph

  def initialize(importmap_path = "config/importmap.rb", vendor_path: "vendor/javascript")
    @importmap_path = Pathname.new(importmap_path)
    @vendor_path    = Pathname.new(vendor_path)
  end

  def import(*packages, env: "production", from: "jspm")
    @last_import_error = nil

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
      @last_import_error = parse_service_error(response)
      nil
    else
      handle_failure_response(response)
    end
  end

  # A remote pin has no version comment unless it is locked or was kept remote
  # because its file can't stand alone; then the version in its URL is written
  # out so the lock and the reason have something to hang off:
  #
  #   pin "md5", to: "https://cdn.jsdelivr.net/npm/md5@2.2.0/md5.js" # @2.2.0 (locked)
  #   pin "@popperjs/core", to: "https://ga.jspm.io/…" # @2.11.8 (remote: relative imports)
  #
  def pin_for(package, url = nil, preloads: nil, integrity: nil, locked: false, remote: nil)
    to = url ? %(, to: "#{url}") : ""
    preload_param = preload(preloads)
    integrity_param = integrity.nil? ? "" : %(, integrity: #{integrity.inspect})
    version = extract_package_version_from(url.to_s) if locked || remote

    %(pin "#{package}") + to + preload_param + integrity_param +
      (version ? provenance_comment(version, remote: remote, locked: locked) : "")
  end

  # The pin line for a vendored download. The version comment also records
  # the CDN when it isn't jspm, whether the file was minified and whether the
  # version is locked, so a later update or pristine can do the same again:
  #
  #   pin "luxon" # @3.7.2
  #   pin "luxon" # @3.7.2 (esm.run, minified, locked)
  #
  def vendored_pin_for(package, url, preloads = nil, minify: false, integrity: nil, locked: false, vendored: false)
    filename = package_filename(package)
    version  = extract_package_version_from(url)
    to = "#{package}.js" != filename ? filename : nil

    pin_for(package, to, preloads: preloads, integrity: integrity) +
      provenance_comment(version, provider: provider_for_url(url), minified: minify, vendored: vendored, locked: locked)
  end

  # The directory +package+'s sibling files are vendored into and the line that
  # maps them; the paths under vendor/javascript are still built only here.
  def vendored_graph(package)
    Importmap::VendoredGraph.new(graph_path(package), importmap_path: @importmap_path)
  end

  # The pin_all_from line for +package+'s graph, carrying the entry's own
  # preload. Its keys go under the package the CDN *URL* names — jspm resolves
  # Node's "buffer" to a file in @jspm/core.
  def graph_pin_for(package, url, preloads = nil)
    name, version = Importmap::PackageGraph.package_and_version_for(url)

    vendored_graph(package).line_for(under: name, options: preload(preloads),
                                     version: version || extract_package_version_from(url))
  end

  def remove_graph(package)
    reload! if vendored_graph(package).remove
  end

  # What the pin's version comment says a package was built with:
  # { version:, provider:, minified:, vendored:, remote:, locked: }, or nil for
  # a pin without one.
  def pin_provenance(package)
    provenance_of(pin_line_for(package))
  end

  # The line that pins +package+, without its newline, or nil.
  def pin_line_for(package)
    return unless @importmap_path.exist?

    importmap.lines.find { |candidate| candidate.match?(Importmap::Map.pin_line_regexp_for(package)) }&.chomp
  end

  # The version a pin declares, in its provenance comment or in the CDN URL it
  # points at, or nil when it names none — as one of the app's own files
  # doesn't. Only a pin with a version can be told to be outdated.
  def pin_version(package)
    provenance = pin_provenance(package)
    return provenance[:version] if provenance

    to = (extract_existing_pin_options(package)[package] || {})[:to]
    extract_package_version_from(to.to_s)&.delete_prefix("@")
  end

  def locked?(package)
    pin_provenance(package)&.dig(:locked) || false
  end

  # Whether the pin carries a computed hash. #extract_existing_pin_options
  # leaves a hash string out on purpose — it belongs to one file — so this is
  # how a caller about to drop one says so.
  def integrity_hash?(package)
    pin_line_for(package).to_s.match?(INTEGRITY_HASH_REGEXP)
  end

  # The import-map keys of every pin, in file order.
  def pinned_packages
    return [] unless @importmap_path.exist?

    importmap.lines.filter_map { |line| line.strip[PIN_REGEX, 1] }
  end

  # The import-map keys of every locked pin, in file order.
  def locked_pins
    return [] unless @importmap_path.exist?

    importmap.lines.filter_map do |line|
      name = line.strip[PIN_REGEX, 1]
      name if name && provenance_of(line)&.dig(:locked)
    end
  end

  # The pin line with a lock added — to the version comment it has, or as a
  # new comment carrying the version from its URL. Nothing else on the line is
  # touched. Nil when the pin has no version to lock at, or isn't there.
  def locked_pin_line(package)
    line = pin_line_for(package)
    return unless line

    if line.match?(PIN_PROVENANCE_REGEXP)
      rewrite_provenance(line) { |details| without_lock(details) << LOCK_DETAIL }
    elsif (to = (extract_existing_pin_options(package)[package] || {})[:to].to_s).match?(REMOTE_URL_REGEXP) &&
          (version = extract_package_version_from(to))
      line + provenance_comment(version, locked: true)
    end
  end

  # The pin line with its lock removed; an empty detail list drops its parens.
  def unlocked_pin_line(package)
    line = pin_line_for(package)

    rewrite_provenance(line) { |details| without_lock(details) } if line
  end

  def packaged?(package)
    importmap.match(Importmap::Map.pin_line_regexp_for(package))
  end

  # Downloads +url+ into vendor/javascript, with the sibling files it imports
  # when it has any. With +minify: true+ the source is run through .minifier
  # first and the file header records it, so later updates keep minifying.
  # Returns the dependencies an esm.run bundle imports as [package, url] pairs
  # (empty for every other provider), its absolute /npm/... imports rewritten
  # to bare specifiers on the way in. Raises Unvendorable unless +force+ when
  # the download needs more than a file graph can give it. +graph: false+
  # brings the entry down alone and drops the directory it had (--vendor); the
  # caller decides, because only it knows whether the pin already maps one.
  def download(package, url, minify: false, force: false, graph: true)
    @last_graph = nil

    ensure_vendor_directory_exists
    download_package_file(package, url, minify: minify, force: force, graph: graph)
  end

  # The body at +url+ — the one GET this class makes, whether the file is
  # going to be vendored or only hashed for a remote pin. Writes nothing and
  # inspects nothing. Like #post_json, a failure the retry doesn't recognise
  # still comes out as this class's HTTPError rather than a backtrace.
  def fetch_remote(url, allow_missing: false)
    response = get_response(url)
    # jspm answers some files brotli whatever the request advertises, and
    # Net::HTTP decodes gzip and deflate only. Not asked up front: supplying an
    # Accept-Encoding at all stops it decoding the gzip it does understand.
    response = get_response(url, IDENTITY_ENCODING) if response.code == "200" && encoded?(response.body)

    if response.code == "200"
      # Still unreadable asked plain: say so, rather than let ModuleInspector raise.
      raise HTTPError, "Can't read #{url}: the CDN sent an encoding this gem can't decode" if encoded?(response.body)

      response.body
    elsif response.code == "404" && allow_missing
      nil
    else
      handle_failure_response(response)
    end
  rescue Error
    raise
  rescue => error
    raise HTTPError, "Unexpected transport error downloading #{url} (#{error.class}: #{error.message})"
  end

  def remove(package)
    remove_existing_package_file(package)
    remove_graph(package)
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

  # Why a pin was kept remote, as its comment records it: the reason string,
  # true for a bare "(remote)", or nil. Passed back to #pin_for on a rewrite so
  # update and pristine don't drop it.
  def remote_reason(package)
    pin_provenance(package)&.dig(:remote)
  end

  # Whether the pin says it was vendored on purpose — `pin --vendor` overriding
  # the single-file check — so a later update vendors it again instead of
  # converting it back to a remote pin.
  def vendored?(package)
    pin_provenance(package)&.dig(:vendored) || false
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

  # The import-map key a package spec pins: "apexcharts@7.1.0/core" pins
  # "apexcharts/core", "@hotwired/stimulus@3" pins "@hotwired/stimulus".
  def package_key_for(spec)
    name, _version, subpath = spec.to_s.match(PACKAGE_SPEC_REGEXP)&.captures
    name ? "#{name}#{subpath}" : spec.to_s
  end

  # The package a spec or key belongs to, as the registry knows it:
  # "photoswipe/lightbox" and "@hotwired/stimulus@3" are pins of "photoswipe"
  # and "@hotwired/stimulus".
  def package_name_for(spec)
    spec.to_s.match(PACKAGE_SPEC_REGEXP)&.captures&.first || spec.to_s
  end

  # The spec that asks a CDN for +key+ at +version+. A version belongs on the
  # package name, ahead of the subpath: "photoswipe/lightbox" at "@5.4.4" is
  # "photoswipe@5.4.4/lightbox", where "photoswipe/lightbox@5.4.4" is a path
  # no CDN has.
  def package_spec_for(key, version)
    name, _requested, subpath = key.to_s.match(PACKAGE_SPEC_REGEXP)&.captures

    name ? "#{name}#{version}#{subpath}" : "#{key}#{version}"
  end

  # Where +package+'s download is vendored: with #graph_path, the only place a
  # path under vendor/javascript is built from a package name.
  def vendored_package_path(package)
    @vendor_path.join(package_filename(package))
  end

  def remove_existing_package_file(package)
    FileUtils.rm_rf vendored_package_path(package)
  end

  def extract_package_version_from(url)
    url.match(/@\d+\.\d+\.\d+[^\/\s"']*/)&.to_a&.first
  end

  private
    def provenance_of(line)
      match = line&.match(PIN_PROVENANCE_REGEXP)
      return unless match

      details  = match[2].to_s.split(",").map(&:strip)
      minified = details.delete("minified") ? true : false
      locked   = without_lock(details).size != details.size

      { version: match[1], provider: without_named_details(details).first, minified: minified,
        vendored: details.include?(VENDORED_DETAIL), remote: remote_detail_of(details), locked: locked }
    end

    def without_lock(details)
      details.reject { |detail| detail.match?(LOCK_DETAIL_REGEXP) }
    end

    # The provider is read as the first detail left over, so every named detail
    # has to come out of the list first or it is taken for a CDN name.
    def without_named_details(details)
      without_lock(details).reject { |detail| detail == VENDORED_DETAIL || detail.match?(REMOTE_DETAIL_REGEXP) }
    end

    # "remote: relative imports" carries its reason; a bare "remote" says only
    # that the pin was kept remote, which is still worth keeping on a rewrite.
    def remote_detail_of(details)
      match = details.filter_map { |detail| detail.match(REMOTE_DETAIL_REGEXP) }.first
      return unless match

      match[1] || true
    end

    # " # @3.7.2 (esm.run, minified, locked)" — the details in their fixed
    # order, the parens only when there is something to say.
    def provenance_comment(version, provider: nil, minified: false, vendored: false, remote: nil, locked: false)
      details = []
      details << provider if provider && provider != DEFAULT_PROVIDER
      details << "minified" if minified
      details << VENDORED_DETAIL if vendored
      details << (remote == true ? REMOTE_DETAIL : "#{REMOTE_DETAIL}: #{remote}") if remote
      details << LOCK_DETAIL if locked

      %( # @#{version.to_s.delete_prefix("@")}) + (details.any? ? %( (#{details.join(", ")})) : "")
    end

    # Rewrites only the version comment of +line+, handing the block the
    # current details and writing back what it returns.
    def rewrite_provenance(line)
      line.sub(PIN_PROVENANCE_REGEXP) do
        version = $1
        details = yield($2.to_s.split(",").map(&:strip))

        "# @#{version}" + (details.any? ? " (#{details.join(", ")})" : "")
      end
    end

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

          if (integrity_match = options_part.match(INTEGRITY_OPTION_REGEXP))
            options[:integrity] = integrity_match[1] == "true"
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

    def get_response(url, headers = nil)
      with_retries("downloading #{url}") { Net::HTTP.get_response(URI(url), headers) }
    end

    # An encoding Net::HTTP couldn't undo is the one thing that reaches here as
    # bytes no JavaScript file has: every CDN serves source as UTF-8.
    def encoded?(body)
      !body.to_s.dup.force_encoding("UTF-8").valid_encoding?
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

      # Whatever asked to remove the pin may go on to ask whether it is still
      # there, and #importmap answers from a memo of the file as it was.
      reload!
    end

    # The file an app already has is replaced only once the new one is known to
    # be downloadable, minifiable and servable on its own; a refusal here, or a
    # failure above it, leaves the working file in place. The inspection runs on
    # the source as it will be written — after an esm.run bundle's imports have
    # become bare specifiers, before minifying, which rewrites nothing that
    # matters to it.
    def download_package_file(package, url, minify: false, force: false, graph: true)
      body   = fetch_remote(url)
      source = body.dup.force_encoding("UTF-8")
      source, dependencies = rewrite_esm_run_imports(source) if url.match?(ESM_RUN_URL_REGEXP)

      @last_graph = Importmap::PackageGraph.for_download(self, package, url, source, body) if graph
      source = @last_graph.entry_source if @last_graph

      # force is the app overriding the check — except when the pin says it has
      # a graph and the CDN didn't give one: --from skypack on a graphed pin
      # would write the entry unrewritten and drop the directory it resolves through.
      ensure_servable(source, body) unless force && (@last_graph || !graph)

      source = self.class.minifier.call(source) if minify

      save_vendored_package(package, url, source, minified: minify, graph: @last_graph)

      dependencies || []
    end

    # One inspection answers both questions; standing alone is asked first, as
    # the answer an app can act on by keeping the pin remote. A refusal carries
    # the hash of +body+ — the bytes as the CDN served them, not the rewritten
    # +source+ — so the pin kept remote doesn't fetch the file again for it.
    def ensure_servable(source, body)
      inspection = Importmap::ModuleInspector.new(source)
      return if inspection.vendorable? && inspection.es_module?

      integrity = Importmap::Integrity.for(body)

      raise Unvendorable.new(inspection.reasons, integrity: integrity) unless inspection.vendorable?
      raise NotAnEsModule.new(integrity: integrity)
    end

    # Prepared beside its targets and moved over them last, so a write that
    # fails partway leaves the files the app had rather than half the new ones;
    # the partials carry the pid so two shells pinning one package can't write
    # each other's. Entry and directory are one unit — each is broken beside
    # the other's old version — so both are prepared before either is moved,
    # and the entry's partial waits in an ensure (Ctrl-C through a 250-file
    # minify is not a StandardError) for the directory to be written.
    def save_vendored_package(package, url, source, minified: false, graph: nil)
      vendored      = vendored_graph(package)
      entry_partial = write_entry_partial(package, url, source, minified: minified)
      committed     = false

      begin
        graph_partial = graph && vendored.write(graph) do |file_source|
          remove_sourcemap_comment_from(minified ? self.class.minifier.call(file_source) : file_source)
        end

        vendored.commit(graph_partial)
        commit_entry(package, entry_partial)
        committed = true
      ensure
        FileUtils.rm_f entry_partial unless committed
        FileUtils.rm_rf graph_partial if graph_partial && !committed
      end
    end

    # Cleans up its own partial: a write that dies partway dies before the
    # caller has the partial's name.
    def write_entry_partial(package, url, source, minified: false)
      partial = Pathname.new("#{vendored_package_path(package)}.#{Process.pid}.download")
      written = false

      begin
        File.open(partial, "w+") do |vendored_package|
          vendored_package.write "// #{package}#{extract_package_version_from(url)} downloaded from #{url}#{" (minified)" if minified}\n\n"
          vendored_package.write remove_sourcemap_comment_from(source).force_encoding("UTF-8")
        end
        written = true
      ensure
        FileUtils.rm_f partial unless written
      end

      partial
    end

    # Rename is atomic over a file; a directory in the way is cleared first.
    def commit_entry(package, partial)
      remove_existing_package_file(package) if vendored_package_path(package).directory?
      File.rename(partial, vendored_package_path(package))
    end

    # Turns import "/npm/dep@1.2.3/+esm" into import "dep" so the bundle
    # resolves through the import map, and lists what it needs pinned.
    def rewrite_esm_run_imports(source)
      dependencies = {}
      versions = Hash.new { |hash, key| hash[key] = [] }

      rewritten = source.gsub(ESM_RUN_IMPORT_REGEXP) do
        keyword, quote, name, version, subpath = $1, $2, $3, $4, $5.to_s
        key = "#{name}#{subpath}"
        dependencies[key] ||= "#{ESM_RUN_CDN}#{name}@#{version}#{subpath}/+esm"
        versions[key] << version unless versions[key].include?(version)
        "#{keyword}#{quote}#{name}#{subpath}#{quote}"
      end

      # An import map maps a bare specifier to one file, so a bundle that
      # imports the same package at two versions can only get the first one
      # it asked for. Say so rather than pick silently.
      versions.each do |key, seen|
        next if seen.one?

        warn %(#{key} is imported at #{seen.join(", ")} by this bundle; pinning @#{seen.first}, an import map holds one version)
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

    def package_filename(package)
      package.gsub("/", "--") + ".js"
    end

    # The vendored file's own name without its extension, so the pin that wrote
    # the directory is the pin that owns it.
    def graph_path(package)
      @vendor_path.join(package_filename(package).delete_suffix(".js"))
    end
end
