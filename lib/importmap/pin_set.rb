# frozen_string_literal: true

# One generation of an Importmap::Map: its pins, its pin_all_from directories
# and whether integrity is on, frozen together, plus the cache of what was
# rendered from them.
#
# The map never changes a generation in place. A draw, a pin or a cache sweep
# writes into a Draft of the current one and the map swaps the finished
# generation in whole, so a request rendering mid-reload renders the
# generation before it rather than a half-drawn map. What a render caches
# lands in the generation it read: a swap leaves the old cache behind, where
# clearing one shared cache would let a render that started before the change
# write the old map back into it.
class Importmap::PinSet
  # A generation being drawn: the same three things, writable, for the one
  # writer holding the map's lock.
  Draft = Struct.new(:packages, :directories, :integrity) do
    def to_pin_set = Importmap::PinSet.new(packages: packages, directories: directories, integrity: integrity)
  end

  attr_reader :packages, :directories, :integrity

  def initialize(packages: {}, directories: {}, integrity: false)
    @packages    = packages.freeze
    @directories = directories.freeze
    @integrity   = integrity
    @lock        = Mutex.new
    @cache       = {}
    freeze
  end

  def draft
    Draft.new(packages.dup, directories.dup, integrity)
  end

  # The same pins with an empty cache: what a sweep publishes when a watched
  # .js file changes and every render has to be redone.
  def recached
    self.class.new(packages: packages, directories: directories, integrity: integrity)
  end

  # The value cached under +key+, else the block's. The block runs outside the
  # lock, because it calls the app's asset resolver, which may take locks of
  # its own; when two renders miss at once the first one stored is kept and
  # both return it.
  def fetch(key)
    cached = @lock.synchronize { @cache[key] }
    return cached if cached

    rendered = yield
    @lock.synchronize { @cache[key] ||= rendered }
  end
end
