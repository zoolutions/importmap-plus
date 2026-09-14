require "fileutils"
require "pathname"

# The directory a chunked package's sibling files are vendored into, and the
# one +pin_all_from+ line that maps them.
#
# Importmap::PackageGraph crawls and rewrites the files; this puts them on disk
# and in +config/importmap.rb+. The directory is named for the pin that owns it
# — the entry's own filename without its extension — so two pins of one package
# each rebuild their own directory without deleting the other's, while the keys
# both write go under the package the CDN URL names, so a module they share
# resolves to one key and the browser evaluates it once.
class Importmap::VendoredGraph
  # What the line's comment says the directory is:
  #
  #   pin_all_from "vendor/javascript/@popperjs--core", under: "@popperjs/core", to: "@popperjs--core" # @2.11.8 (graph of @popperjs/core)
  #
  GRAPH_DETAIL = "graph of".freeze # :nodoc:

  # Every graph line an import map carries, as [ directory, under, version ].
  MAPPING_REGEXP =
    /^[ \t]*pin_all_from\s+["']([^"']+)["'].*?under:\s*["']([^"']+)["'].*#\s*@([^\s(]+)\s+\(#{GRAPH_DETAIL} /.freeze # :nodoc:

  # Matched on the whole directory path, so a directory whose name begins with
  # another's doesn't answer for it; anchored on the statement, so a line that
  # only mentions one — a commented-out line, a second statement after a pin —
  # is left alone; and required to carry the comment this class writes, so a
  # pin_all_from an app wrote itself is never rewritten, and the directory it
  # maps is never taken for one of ours to delete.
  def self.line_regexp_for(directory)
    /^[ \t]*pin_all_from\s+["']#{Regexp.escape(directory.to_s)}["'].*#\s*@[^\s(]+\s+\(#{GRAPH_DETAIL} [^)]*\).*$/
  end

  def self.mappings_in(importmap)
    importmap.to_s.lines.filter_map { |line| line.match(MAPPING_REGEXP)&.captures }
  end

  # The package whose graph directory already maps +key+, or nil.
  # Importmap::Map expands directories over packages, so a key a directory
  # defines resolves to that file however the pin beside it is written.
  def self.mapping_for(importmap, key)
    mappings_in(importmap).find do |directory, under, _version|
      (key == under || key.start_with?("#{under}/")) &&
        file_in(directory, key.delete_prefix(under).delete_prefix("/"))
    end&.at(1)
  end

  # Another directory mapping the same package at another version, as
  # [ directory, package, version ]. Both write their files under the same
  # prefix, so for every file they share the app gets one of the two versions,
  # and which one depends on the order of the lines.
  def self.conflict_in(importmap, under:, version:, except:)
    mappings_in(importmap).find do |directory, other, other_version|
      other == under && other_version != version.to_s.delete_prefix("@") && directory != except.to_s
    end
  end

  # The file in a directory that answers for +path+, the way Importmap::Map's
  # expansion reaches it, or nil.
  def self.file_in(directory, path)
    candidates = path.empty? ? [ "index.js" ] : [ "#{path}.js", "#{path}/index.js" ]

    candidates.map { |candidate| Pathname.new(directory).join(candidate) }.find(&:file?)
  end

  # The header Importmap::Packager writes at the top of every vendored file,
  # read back to tell which CDN file a vendored file already is.
  DOWNLOADED_FROM_REGEXP = %r{\A// \S+ downloaded from (\S+)}.freeze # :nodoc:

  # The CDN URL every vendored file was downloaded from, by the pin key that
  # names it. A crawl that reaches one of these URLs has reached another pin's
  # file: it rewrites the specifier to that pin's key rather than copying the
  # file, because two copies of one module in an import map are two modules.
  #
  # Read as bytes: a vendored file the gem didn't write, or wrote before it
  # learned to ask CDNs for a body it can read, can hold a sequence no UTF-8
  # regexp will match without raising, and one such file must not stop every
  # other package from being pinned.
  def self.entry_urls(paths_by_key)
    paths_by_key.each_with_object({}) do |(key, path), urls|
      next unless path.file?

      url = File.open(path, "rb") { |file| file.gets.to_s }[DOWNLOADED_FROM_REGEXP, 1]
      urls[url] = key if url
    end
  end

  # A directory in the way that this gem didn't write. Nothing is renamed over
  # an app's own files; the download stops instead and says so.
  class Occupied < StandardError
    def initialize(directory)
      super("#{directory} exists and no pin_all_from line maps it as a graph; " \
            "move it aside — or remove it, if an interrupted run left it — and pin again")
    end
  end

  attr_reader :directory

  def initialize(directory, importmap_path:)
    @directory, @importmap_path = Pathname.new(directory), Pathname.new(importmap_path)
  end

  # +to:+ is what makes the keys resolve: the directory is named for the pin
  # that owns it, so without it Importmap::Map builds the asset path out of
  # +under:+ and every file 404s. It is omitted only when the two agree.
  def line_for(under:, version:, options: "")
    to = directory.basename.to_s == under ? "" : %(, to: "#{directory.basename}")

    %(pin_all_from "#{directory}", under: "#{under}") + to + options +
      %( # @#{version.to_s.delete_prefix("@")} (#{GRAPH_DETAIL} #{under}))
  end

  def line_regexp
    self.class.line_regexp_for(directory)
  end

  # Whether the import map maps this directory, which is also how this class
  # knows the directory is one the gem wrote rather than one the app keeps.
  def mapped?
    @importmap_path.exist? && importmap.match?(line_regexp)
  end

  # Writes every file of +graph+ into a partial directory beside the target,
  # each source through the block. Nothing the app has is touched until #commit.
  def write(graph, &transform)
    partial = Pathname.new("#{directory}.#{Process.pid}.download")
    FileUtils.rm_rf partial
    FileUtils.mkdir_p partial
    written = false

    begin
      write_files(graph, partial, &transform)
      written = true
    ensure
      # Cleaned up here rather than by the caller: a minifier that gives up on
      # the twentieth of forty-seven files raises before the partial's path has
      # been handed back, and nothing else knows the name to remove. In ensure
      # rather than rescue because Ctrl-C during a 250-file write is the likely
      # way this ends, and Interrupt is not a StandardError — the directory it
      # would leave carries a pid that is gone, so no later run cleans it.
      FileUtils.rm_rf partial unless written
    end

    partial
  end

  # Swaps a prepared directory over the one the app has: the old one is renamed
  # aside and removed only once the new one is in place, so the window in which
  # the app has neither is a rename rather than a recursive delete, and a
  # failure halfway puts the old one back.
  #
  # Nothing prepared means the download came back as one file, and the
  # directory a previous one left goes with it. Either way a directory the
  # import map doesn't map as ours is the app's, and is never touched.
  def commit(partial)
    return mapped? ? remove_directory : nil unless partial
    raise Occupied.new(directory) if directory.exist? && !mapped?

    previous = Pathname.new("#{directory}.#{Process.pid}.previous")
    FileUtils.rm_rf previous
    File.rename(directory, previous) if directory.exist?

    begin
      File.rename(partial, directory)
    ensure
      # In ensure, not rescue: between the two renames the app has neither
      # directory, and Ctrl-C there is not a StandardError. Whether the swap
      # happened is read off the disk — rename either put the directory in
      # place or it didn't — rather than off a flag set after it returned.
      if directory.exist?
        FileUtils.rm_rf previous
      elsif previous.exist?
        File.rename(previous, directory)
      end
    end
  end

  # Drops the directory and its line together, so nothing is left mapping files
  # nothing imports any more. A directory the import map doesn't name is not
  # this gem's to delete.
  def remove
    return false unless mapped?

    remove_directory

    lines = File.readlines(@importmap_path).grep_v(line_regexp)
    File.open(@importmap_path, "w") { |file| lines.each { |line| file.write(line) } }

    true
  end

  def remove_directory
    FileUtils.rm_rf directory
  end

  private
    def write_files(graph, partial, &transform)
      graph.files.each do |path, source|
        file = partial.join(path)
        # PackageGraph::PATH_REGEXP has already refused anything that could
        # leave the directory; this is the assertion of it, because the paths
        # come from a CDN and this is where they become a write.
        raise Importmap::PackageGraph::Unownable.new(Importmap::PackageGraph::REASON) unless file.to_s.start_with?("#{partial}/")

        FileUtils.mkdir_p file.dirname
        File.write(file, transform ? transform.call(source) : source)
      end
    end

    def importmap
      File.read(@importmap_path)
    end
end
