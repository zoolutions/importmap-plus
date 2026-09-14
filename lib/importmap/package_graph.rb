require "uri"
require "importmap/module_inspector"
require "importmap/integrity"
require "importmap/vendored_graph"

# The sibling files a chunked ESM download needs, fetched from the same CDN
# directory and rewritten so the import map can serve them.
#
# A published package that splits itself across files — +import"./_/f08a6ffe.js"+
# — cannot be vendored as the one file an import map entry points at: Propshaft
# and Sprockets digest file names and neither rewrites +import+ statements, so
# the browser asks for a path that no longer exists. The files are a closed set,
# though: everything an entry reaches through relative imports lives under the
# package's own version directory on the CDN. This crawls that set, turns every
# relative specifier into the bare key +<package>/<path without extension>+, and
# hands back the files for Importmap::Packager to write into a directory that
# one +pin_all_from+ line maps.
#
# Nothing is written here and nothing is written by the caller until the crawl
# has finished: a file it can't own — a path that escapes the package root, a
# sibling that isn't JavaScript, a chunk that spawns a worker — raises
# Unownable, and the whole package stays pinned to its CDN, which works.
class Importmap::PackageGraph
  # The one Importmap::ModuleInspector reason a graph answers for. Every other
  # reason is about a file the browser fetches by a path nobody can rewrite.
  REASON = "relative imports".freeze # :nodoc:

  # The CDNs whose URLs say which package and version a file belongs to, and so
  # where the package's directory ends. esm.sh and skypack serve a package from
  # paths that don't spell that out, so a download from them is left remote.
  ROOT_REGEXPS = [
    %r{\Ahttps://ga\.jspm\.io/npm:((?:@[^/@]+/)?[^/@]+)@([^/]+)/},
    %r{\Ahttps://cdn\.jsdelivr\.net/npm/((?:@[^/@]+/)?[^/@]+)@([^/]+)/},
    %r{\Ahttps://unpkg\.com/((?:@[^/@]+/)?[^/@]+)@([^/]+)/}
  ].map(&:freeze).freeze # :nodoc:

  # Importmap::ModuleInspector::RELATIVE_IMPORT_REGEXP with the specifier
  # captured, so the same forms it counts are the ones rewritten here. Like
  # that one and Packager::ESM_RUN_IMPORT_REGEXP it doesn't parse JavaScript,
  # so a data string that spells out an import statement is rewritten inside
  # the string too, and a form it can't read — a magic comment between the
  # keyword and the specifier, an unterminated literal — isn't rewritten at
  # all. #verify_rewritten is what makes the second kind safe: a file the crawl
  # reached and couldn't rewrite keeps the whole package remote.
  IMPORT_REGEXP =
    /((?<![\w.$])(?:from|import)\s*\(?\s*)(["'])(\.{1,2}\/[^"'\n]*)\2/.freeze # :nodoc:

  # A path under the package root that can become a file in vendor/javascript
  # and a key in the import map: no query, no fragment, nothing but a plain
  # relative path, and an extension Importmap::Map's directory glob picks up.
  #
  # Every segment is a plain name that doesn't begin with a dot, which rejects
  # four paths a CDN can hand back and this class must not act on: "..", which
  # climbs out of the package; an empty segment, as "a//b" has, whose key would
  # be one Importmap::Map never emits for the file it writes; a leading "/",
  # which Pathname#join turns into an absolute path outside vendor/javascript
  # altogether; and a dot-directory, which Map's `**/*.js{,m}` glob doesn't
  # descend into, so its files would be written and never mapped.
  PATH_REGEXP =
    %r{\A[A-Za-z0-9_@+\-][A-Za-z0-9._@+\-]*(?:/[A-Za-z0-9_@+\-][A-Za-z0-9._@+\-]*)*\.m?js\z}.freeze # :nodoc:

  # Importmap::Map's directory expansion drops a trailing "index" from a key,
  # so lib/index.js is reached as "<package>/lib" and index.js as "<package>".
  INDEX_REGEXP = %r{(?:/|\A)index\z}.freeze # :nodoc:

  # A file the crawl reached and can't take responsibility for. Translated into
  # Importmap::Packager::Unvendorable, which carries the hash of the bytes the
  # CDN served so the pin kept remote doesn't fetch them again.
  class Unownable < StandardError
    attr_reader :reasons

    def initialize(reasons)
      @reasons = Array(reasons)
      super("needs more than its file graph (#{@reasons.join(", ")})")
    end
  end

  # The graph +source+ needs beside it, or nil when this download is one file:
  # it imports no siblings, it isn't an ES module, or it comes from a CDN whose
  # package directory can't be addressed. +package+ is the import-map key the
  # entry itself is pinned under, +known+ maps the CDN URL of every file
  # another pin already vendored to that pin's key, and +forbidden+ lists the
  # keys the directory must not define. The block fetches a URL and answers nil
  # when the CDN hasn't got it.
  def self.build(url, source, package:, known: {}, forbidden: [], &fetcher)
    root, name = root_and_package(url).values_at(0, 1)
    return unless root

    inspection = Importmap::ModuleInspector.new(source)
    return unless inspection.reasons.include?(REASON) && inspection.es_module?

    # The graph answers for the relative imports; anything else the entry does
    # is why the package still can't be vendored, so only that is reported.
    raise Unownable.new(inspection.reasons - [ REASON ]) unless inspection.reasons == [ REASON ]

    new(root, name, url, source, package: package, known: known, forbidden: forbidden, &fetcher).crawl
  end

  # The graph a Packager download needs beside it, or nil when it is one file.
  # A file the crawl can't own keeps the whole package remote, carrying the
  # hash of the bytes the CDN served — as served, so the pin doesn't fetch them
  # a second time. Every URL another pin already vendored is passed in as one
  # the graph resolves to that pin's key rather than copies, and every key
  # another pin owns as one it may not define.
  def self.for_download(packager, package, url, source, body)
    build(url, source, package: package, known: packager.vendored_entry_urls,
                       forbidden: packager.pinned_packages - [ package ]) do |file_url|
      # Tagged the way the entry is: Net::HTTP hands back ASCII-8BIT, which
      # neither the rewrite's regexes nor the write can read as text.
      packager.fetch_remote(file_url, allow_missing: true)&.force_encoding("UTF-8")
    end
  rescue Unownable => refusal
    raise Importmap::Packager::Unvendorable.new(refusal.reasons, integrity: Importmap::Integrity.for(body))
  end

  # The package a CDN URL names, or nil for a CDN whose paths don't say which
  # package and version a file belongs to.
  def self.package_for(url)
    package_and_version_for(url).first
  end

  # That package and the version the URL pins it at — the version the graph is
  # of, and the fallback for a line's comment when the version isn't the
  # semver Packager#extract_package_version_from looks for.
  def self.package_and_version_for(url)
    root_and_package(url).values_at(1, 2)
  end

  # The package's own version directory on the CDN, the package it holds and
  # that package's version, as a MatchData ([] when the CDN is one whose paths
  # don't say).
  def self.root_and_package(url)
    ROOT_REGEXPS.filter_map { |regexp| url.to_s.match(regexp) }.first || []
  end

  # The package the CDN URL names, which is the prefix every key the directory
  # defines is written under. Not always the package the pin's key names: jspm
  # resolves Node's "buffer" to a file in @jspm/core.
  attr_reader :under

  # { "lib/enums.js" => source }, relative to the directory the caller writes,
  # with every specifier rewritten. An .mjs sibling is named .js here, because
  # Importmap::Map's directory glob doesn't look for .mjs.
  attr_reader :files

  attr_reader :entry_source

  def initialize(root, under, url, source, package:, known: {}, forbidden: [], &fetcher)
    @root, @under, @entry_url, @entry_source = root, under, url, source
    @package, @known, @forbidden, @fetcher = package, known, forbidden, fetcher
    @sources, @files, @keys = {}, {}, {}
  end

  def crawl
    discover
    assign_keys
    rewrite
    verify_rewritten

    self
  end

  def size
    files.size
  end

  private
    # Breadth-first from the entry, following the relative imports each file
    # makes in code — a specifier that only appears in a comment is not
    # fetched, because a JSDoc @typedef names files a package never ships and
    # asking the CDN for one 404s a package that vendors perfectly well.
    def discover
      @sources[@entry_url] = @entry_source
      queue = [ @entry_url ]

      until queue.empty?
        url = queue.shift

        imports_in(@sources[url], url).each do |target|
          next if @sources.key?(target) || @known.key?(target)

          @sources[target] = fetch(target)
          queue << target
        end
      end
    end

    def imports_in(source, url)
      Importmap::ModuleInspector.new(source).code.scan(IMPORT_REGEXP).filter_map do |_keyword, _quote, specifier|
        target = resolve(url, specifier)

        raise Unownable.new(REASON) unless target&.start_with?(@root) && vendorable_path?(path_of(target))

        target
      end.uniq
    end

    def fetch(url)
      source = @fetcher.call(url)

      # The CDN hasn't got the file the specifier names, so the browser
      # wouldn't either: the crawl can't own this package.
      raise Unownable.new(REASON) unless source

      # A sibling may import siblings of its own — that is what a chunk does —
      # but anything else it needs is as unreachable here as it is in the entry.
      inspection = Importmap::ModuleInspector.new(source)
      blockers   = inspection.reasons - [ REASON ]

      raise Unownable.new(blockers) if blockers.any?
      raise Unownable.new("not an ES module") unless inspection.es_module?

      source
    end

    # The entry keeps its own flat file and its own pin, so it is a key the
    # graph resolves to rather than a file it writes; so is every file another
    # pin already vendored, which must not be copied a second time — two copies
    # of one module in an import map are two modules, evaluated twice.
    def assign_keys
      @keys = @known.merge(@entry_url => @package)

      (@sources.keys - [ @entry_url ]).each do |url|
        path = path_of(url).sub(/\.mjs\z/, ".js")
        key  = key_for(path)

        # Two files under one key would give the import map one of them and
        # lose the other; a key another pin owns would have the directory
        # quietly take that pin's place, since pin_all_from wins over pin.
        raise Unownable.new(REASON) if @keys.value?(key) || @forbidden.include?(key)

        @files[path] = url
        @keys[url]   = key
      end

      # Two paths that differ only in case are one file on a case-insensitive
      # filesystem, where the second write wins and one key serves the other
      # module. Refusing is the same answer everywhere, rather than a package
      # that vendors on Linux and misbehaves on a Mac.
      raise Unownable.new(REASON) if @files.keys.map(&:downcase).uniq.size != @files.size
    end

    # Every relative import Importmap::ModuleInspector counted has to have come
    # back as a bare key, or the file about to be written asks the browser for
    # a path beside a digested asset. The rewrite reads the raw source while
    # the crawl reads the source with block comments discounted, so a form the
    # two disagree about — a magic comment between the keyword and the
    # specifier — is caught here rather than shipped.
    def verify_rewritten
      sources = files.values + [ entry_source ]

      raise Unownable.new(REASON) if sources.any? { |source| Importmap::ModuleInspector.new(source).reasons.include?(REASON) }
    end

    def key_for(path)
      suffix = path.chomp(File.extname(path)).sub(INDEX_REGEXP, "")

      suffix.empty? ? @under : "#{@under}/#{suffix}"
    end

    def rewrite
      @entry_source = rewrite_specifiers(@sources[@entry_url], @entry_url)
      @files.transform_values! { |url| rewrite_specifiers(@sources[url], url) }
    end

    # A specifier whose file the crawl owns becomes that file's key; anything
    # else is left exactly as it was, which is how a relative path inside a
    # comment survives untouched.
    def rewrite_specifiers(source, url)
      source.gsub(IMPORT_REGEXP) do
        keyword, quote, specifier = $1, $2, $3
        key = @keys[resolve(url, specifier)]

        key ? "#{keyword}#{quote}#{key}#{quote}" : $&
      end
    end

    def resolve(url, specifier)
      URI.join(url, specifier).to_s
    rescue URI::Error
      nil
    end

    def path_of(url)
      url.delete_prefix(@root)
    end

    def vendorable_path?(path)
      path.match?(PATH_REGEXP) && !path.split("/").include?("..")
    end
end
