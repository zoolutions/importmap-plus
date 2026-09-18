require "net/http"
require "uri"
require "pathname"
require "active_support/core_ext/array/conversions"
require "active_support/core_ext/string/inflections"
require "importmap/http_retries"
require "importmap/import_scanner"
require "importmap/integrity"
require "importmap/module_inspector"
require "importmap/packager"
require "importmap/package_graph"
require "importmap/vendored_graph"

# Everything that can be wrong with an app's import map without anything
# saying so until a page fails in the browser: a pin whose file isn't there, a
# vendored file importing a bare specifier nobody pinned, a vendored file that
# still needs the siblings it was downloaded beside, a CommonJS bundle a CDN
# handed back, two pins serving one file, a file left in vendor/javascript that
# nothing maps.
#
# It reports; it never fixes. `pin`, `unpin` and `pin --vendor` are what fix
# things, and a doctor that edited config/importmap.rb would be a doctor nobody
# could run in CI.
#
# Offline by default: every check but the last reads the map, the asset paths
# and the files on disk. +online+ adds the one check that can't be made without
# the network — that a remote pin is still served, and still serves the bytes
# its integrity hash was computed from.
class Importmap::Doctor
  include Importmap::HttpRetries

  Error     = Class.new(StandardError)
  HTTPError = Class.new(Error)

  # Wide enough for "warning" plus the space that separates every level from
  # its message, so the messages line up under each other.
  LEVEL_WIDTH = 8 # :nodoc:

  Finding = Struct.new(:level, :message) do # :nodoc:
    def to_s
      "#{level.to_s.ljust(LEVEL_WIDTH)} #{message}"
    end
  end

  # +path+ is the logical asset path or the URL the key maps to, +file+ the
  # file on disk that serves it, or nil when no asset path holds one.
  Entry = Struct.new(:name, :path, :integrity, :file, keyword_init: true) # :nodoc:

  # Where `pin --vendor` and a vendored graph write, and so the only directory
  # whose contents this gem is entitled to have an opinion about.
  VENDOR_PATH = "vendor/javascript".freeze # :nodoc:

  # Importmap::Map's directory glob is `**/*.js{,m}` — .js and .jsm, not .mjs.
  # This one takes .mjs too, on purpose: a .mjs under a pin_all_from directory
  # is precisely the file the map can never see, and saying so is the point.
  VENDORED_GLOB = "**/*.{js,jsm,mjs}".freeze # :nodoc:

  # A specifier the import map has to define. Anything the browser resolves
  # against the importing file's own URL, or fetches outright, is not one.
  SCHEME_REGEXP = %r{\A[a-zA-Z][a-zA-Z0-9+\-.]*:}.freeze # :nodoc:

  def initialize(importmap:, resolver:, root:, asset_paths: [], online: false)
    @importmap   = importmap
    @resolver    = resolver
    @root        = Pathname.new(root)
    @asset_paths = Array(asset_paths).map { |path| Pathname.new(path) }
    @online      = online
  end

  # Every finding, errors before warnings within each check and the checks in
  # the order they are defined below.
  def diagnose
    @diagnose ||= [
      *unresolvable_pins,
      *unpinned_specifiers,
      *stray_relative_imports,
      *non_modules,
      *unserved_vendored_files,
      *keys_sharing_a_path,
      *packages_vendored_twice,
      *(@online ? unreachable_remote_pins : [])
    ]
  end

  def errors?
    diagnose.any? { |finding| finding.level == :error }
  end

  def summary
    errors, warnings = diagnose.partition { |finding| finding.level == :error }

    "#{errors.size} #{"error".pluralize(errors.size)}, #{warnings.size} #{"warning".pluralize(warnings.size)}"
  end

  private
    def unresolvable_pins
      entries.reject { |entry| remote?(entry.path) }.filter_map do |entry|
        error(%(pin "#{entry.name}" → #{entry.path}: no such asset)) unless resolves?(entry.path)
      end
    end

    def unpinned_specifiers
      scannable.flat_map do |entry|
        imports_in(entry.file).filter_map do |import|
          next unless bare?(import.specifier)
          next if pinned?(import.specifier)

          error(%(#{relative(entry.file)} imports "#{import.specifier}", which isn't pinned))
        end
      end
    end

    # A vendored file's relative imports were rewritten to the keys of the
    # files vendored beside it, so one left over points at a file that isn't
    # there: the download predates the fork learning to vendor a file graph, or
    # the graph directory has since been removed.
    def stray_relative_imports
      vendored.flat_map do |entry|
        imports_in(entry.file).filter_map do |import|
          next unless relative?(import.specifier)
          next if sibling_of(entry.file, import.specifier)&.file?

          error(%(#{relative(entry.file)} imports "#{import.specifier}" by relative path — ) +
                %(run bin/importmap pin #{vendored_package_of(entry.file) || entry.name} to vendor its files))
        end
      end
    end

    def non_modules
      vendored.filter_map do |entry|
        next if Importmap::ModuleInspector.new(source_of(entry.file)).es_module?

        error("#{relative(entry.file)} isn't an ES module")
      end
    end

    def unserved_vendored_files
      (vendored_files - entries.filter_map(&:file)).map do |file|
        warning("#{relative(file)} isn't pinned by anything")
      end
    end

    # Two keys on one file are two modules in the browser, each with its own
    # state, and whichever one a package imports is the one the other half of
    # the app isn't using.
    def keys_sharing_a_path
      entries.group_by(&:path).filter_map do |path, sharing|
        next unless sharing.size > 1

        names = sharing.map { |entry| %("#{entry.name}") }
        warning("#{names.to_sentence} #{all_or_both(names)} resolve to #{path}")
      end
    end

    def packages_vendored_twice
      vendored_versions.group_by { |_file, package, _version| package }.filter_map do |package, group|
        files, versions = group.map { |file, _, _| relative(file) }, group.map { |_, _, version| version }
        next if versions.uniq.size < 2

        warning("#{files.to_sentence} #{all_or_both(files)} vendor #{package}, at #{versions.to_sentence}")
      end
    end

    def unreachable_remote_pins
      entries.select { |entry| remote?(entry.path) }.filter_map { |entry| remote_finding_for(entry) }
    end

    def remote_finding_for(entry)
      response = with_retries("fetching #{entry.path}") { Net::HTTP.get_response(URI(entry.path)) }

      if response.code != "200"
        error(%(pin "#{entry.name}" → #{entry.path}: the CDN answered #{response.code}))
      elsif Importmap::Integrity.hash?(entry.integrity) && entry.integrity != Importmap::Integrity.for(response.body)
        error(%(pin "#{entry.name}" → #{entry.path}: integrity doesn't match what the CDN served))
      end
    rescue HTTPError => e
      # The reason with_retries gives already names the URL, so the finding
      # doesn't name it a second time.
      error(%(pin "#{entry.name}": #{e.message}))
    end

    def entries
      @entries ||= @importmap.each_expanded_package.map do |name, mapping|
        Entry.new(name: name, path: mapping.path, integrity: mapping.integrity, file: file_for(mapping.path))
      end
    end

    # The files this gem may read: the app's own, not a file an engine serves
    # out of its gem, which no `bin/importmap` command can do anything about.
    # One file serving two keys is scanned once.
    def scannable
      @scannable ||= entries.select { |entry| entry.file && under?(entry.file, @root) }.uniq(&:file)
    end

    def vendored
      @vendored ||= scannable.select { |entry| under?(entry.file, @root.join(VENDOR_PATH)) }
    end

    def vendored_files
      @vendored_files ||= Pathname.glob(@root.join(VENDOR_PATH, VENDORED_GLOB)).select(&:file?).sort
    end

    # The package and version every vendored file's header names, read out of
    # the CDN URL it was downloaded from — the npm identity, which is what says
    # two pins hold one package, rather than the key, which is whatever the app
    # typed. A file with no header, or from a CDN whose URLs don't spell the
    # package out, simply isn't in the answer.
    def vendored_versions
      @vendored_versions ||= vendored_files.filter_map do |file|
        url = header_url_of(file)
        package, version = Importmap::PackageGraph.package_and_version_for(url) if url

        [ file, package, version ] if package && version
      end
    end

    # The files a graph vendored carry no header of their own — the entry they
    # were downloaded beside does, and Importmap::Packager names their
    # directory after that entry's file. So a sibling asks the entry what
    # package it belongs to, and the hint names something `bin/importmap pin`
    # can act on rather than the key of the one file that went missing.
    def vendored_package_of(file)
      vendored_packages[file] || vendored_packages[graph_entry_for(file)]
    end

    def vendored_packages
      @vendored_packages ||= vendored_versions.to_h { |file, package, _version| [ file, package ] }
    end

    def graph_entry_for(file)
      segments = file.relative_path_from(@root.join(VENDOR_PATH)).each_filename.to_a
      return if segments.size < 2

      @root.join(VENDOR_PATH, "#{segments.first}.js")
    end

    def header_url_of(file)
      File.open(file, "rb") { |io| io.gets.to_s }[Importmap::VendoredGraph::DOWNLOADED_FROM_REGEXP, 1]
    end

    def file_for(path)
      return if remote?(path)

      @asset_paths.lazy.map { |root| root.join(path) }.find(&:file?)
    end

    def resolves?(path)
      @resolver.path_to_asset(path)
      true
    rescue => error
      raise error unless rescuable_asset_error?(error)

      false
    end

    # The same list Importmap::Map rescues on the request path, so a pin the
    # map would quietly skip is the pin this reports.
    def rescuable_asset_error?(error)
      Rails.application.config.importmap.rescuable_asset_errors.any? { |klass| error.is_a?(klass) }
    end

    def imports_in(file)
      Importmap::ImportScanner.new(source_of(file)).imports
    end

    # Read as bytes and scrubbed: a vendored file this gem didn't write, or
    # wrote before it learned to ask CDNs for a body it can read, can hold a
    # sequence no UTF-8 regexp will match without raising, and one such file
    # must not stop every other check.
    def source_of(file)
      @sources ||= {}
      @sources[file] ||= File.binread(file).force_encoding(Encoding::UTF_8).scrub
    end

    # A specifier the map resolves: a key it defines outright, a key ending in
    # "/" that covers everything under it, or — leniently — a key the specifier
    # is a subpath of. That last one is not what a browser does, which needs
    # the trailing-slash key. It is here because the alternative is an error on
    # every subpath of every package vendored with its file graph, whose keys
    # this gem writes one by one, and a check that cries wolf is a check nobody
    # runs. A missed subpath still fails in the browser exactly as loudly as it
    # did before anyone ran the doctor.
    def pinned?(specifier)
      keys.any? do |key|
        key == specifier || (key.end_with?("/") ? specifier.start_with?(key) : specifier.start_with?("#{key}/"))
      end
    end

    def keys
      @keys ||= entries.map(&:name)
    end

    def bare?(specifier)
      !specifier.empty? && !relative?(specifier) && !specifier.start_with?("/") && !specifier.match?(SCHEME_REGEXP)
    end

    def relative?(specifier)
      specifier.start_with?("./", "../")
    end

    def remote?(path)
      path.match?(Importmap::Packager::REMOTE_URL_REGEXP)
    end

    def sibling_of(file, specifier)
      file.dirname.join(specifier.sub(/[?#].*\z/, ""))
    rescue ArgumentError
      nil
    end

    def under?(file, directory)
      file.to_s.start_with?("#{directory}/")
    end

    def relative(file)
      file.relative_path_from(@root)
    end

    def all_or_both(items)
      items.size > 2 ? "all" : "both"
    end

    def error(message)
      Finding.new(:error, message)
    end

    def warning(message)
      Finding.new(:warning, message)
    end
end
