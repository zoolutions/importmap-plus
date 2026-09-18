require "pathname"
require "set"
require "importmap/import_scanner"

# Which pins an entry point actually reaches, read out of the files the map
# already lists. An import map says what every key resolves to; it says nothing
# about which keys a given page loads, and so `preload: true` preloads
# everything on every page. The graph is the missing half: `application.js`
# imports some of the map, those files import more of it, and the rest is only
# ever reached through `import()` — or not at all.
#
# Static imports only. A dynamic `import()` is the app saying "later", and
# preloading its target undoes the deferral the app asked for. That makes this
# a walk of what the browser fetches while linking the entry point, which is
# exactly what a modulepreload link is for.
#
# Nothing here reaches the network. The files are the ones the asset pipeline
# already serves, read once per Map cache generation and dropped with the rest
# of the cache when the sweeper sees a .js change.
class Importmap::Graph
  # A path the browser fetches itself rather than one the asset pipeline
  # serves — `https://…`, and the protocol-relative `//…` a hand-written pin
  # can hold. Importmap::Packager::REMOTE_URL_REGEXP says the same thing, but
  # requiring the CLI onto the request path to borrow it would be a poor trade.
  REMOTE_PATH_REGEXP = %r{\A(?:[a-zA-Z][a-zA-Z0-9+\-.]*:)?//}.freeze # :nodoc:

  def initialize(map, roots: [])
    @map   = map
    @roots = Array(roots).map { |root| Pathname.new(root) }
  end

  # The keys reachable from +entry_points+ through static imports, the entry
  # points themselves included. An entry point the map doesn't define, a pin
  # whose file isn't on any asset path and a remote pin are all leaves: they
  # contribute themselves and nothing further.
  def reachable_from(entry_points)
    queue   = Array(entry_points).select { |key| entries.key?(key) }
    reached = Set.new(queue)

    while (key = queue.shift)
      edges_from(key).each { |target| queue << target if reached.add?(target) }
    end

    reached
  end

  private
    def entries
      @entries ||= @map.each_expanded_package.to_h
    end

    # The key a path belongs to, for resolving a relative import back into the
    # map. Two keys can name one file; the first one drawn wins, and since both
    # resolve to the same asset path the preload set can't tell them apart
    # anyway.
    def keys_by_path
      @keys_by_path ||= entries.each_with_object({}) { |(key, mapping), keys| keys[mapping.path] ||= key }
    end

    def edges_from(key)
      @edges ||= {}
      @edges[key] ||= compute_edges(entries[key])
    end

    def compute_edges(mapping)
      file = file_for(mapping.path)
      return [] unless file

      Importmap::ImportScanner.new(source_of(file)).imports.filter_map { |import|
        key_for(import.specifier, mapping.path) if import.kind == :static
      }.uniq
    end

    def file_for(path)
      return if path.match?(REMOTE_PATH_REGEXP)

      @roots.lazy.map { |root| root.join(path) }.find(&:file?)
    end

    # Read as bytes and scrubbed, like Importmap::Doctor: a vendored file this
    # gem didn't write can hold a sequence no UTF-8 regexp will match without
    # raising, and one such file must not take a page's preloads with it.
    def source_of(file)
      File.binread(file).force_encoding(Encoding::UTF_8).scrub
    end

    # A relative specifier is resolved against the importing key's own path and
    # matched back to the key holding that path — the browser resolves it
    # against the importing module's URL, and the map's paths are what those
    # URLs are built from. Anything else names a key outright, a path a key
    # maps to, or a subpath of a package pinned as one file.
    def key_for(specifier, importer_path)
      return if specifier.empty?

      if relative?(specifier)
        keys_by_path[resolved_path(specifier, importer_path)]
      else
        exact_key(specifier) || enclosing_key(specifier)
      end
    end

    def relative?(specifier)
      specifier.start_with?("./", "../")
    end

    def resolved_path(specifier, importer_path)
      Pathname.new(importer_path).dirname.join(specifier.sub(/[?#].*\z/, "")).cleanpath.to_s
    rescue ArgumentError
      nil
    end

    def exact_key(specifier)
      entries.key?(specifier) ? specifier : keys_by_path[specifier]
    end

    # `pin "foo/", to: "foo/"` covers everything under it, and a subpath of a
    # package pinned as one file — which the browser can't resolve, and
    # Importmap::Doctor reports — is counted as reaching that package, because
    # preloading one file too many costs a request and preloading one too few
    # costs the waterfall this whole mechanism exists to avoid.
    def enclosing_key(specifier)
      entries.keys.select { |key|
        key.end_with?("/") ? specifier.start_with?(key) : specifier.start_with?("#{key}/")
      }.max_by(&:length)
    end
end
