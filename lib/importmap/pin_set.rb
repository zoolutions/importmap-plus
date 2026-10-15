# frozen_string_literal: true

require "importmap/shareable"

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
  # A generation being drawn: the same things, writable, for the one writer
  # holding the map's lock. The generation it publishes is finalized when the
  # one it was drafted from was.
  Draft = Struct.new(:packages, :directories, :integrity, :finalized) do
    def to_pin_set = Importmap::PinSet.new(packages: packages, directories: directories, integrity: integrity, finalized: finalized)
  end

  attr_reader :packages, :directories, :integrity

  def initialize(packages: {}, directories: {}, integrity: false, finalized: false)
    @packages    = finalized ? deep_freeze(packages) : packages.freeze
    @directories = finalized ? deep_freeze(directories) : directories.freeze
    @integrity   = integrity
    @finalized   = finalized
    @lock        = Mutex.new
    @cache       = {}
    freeze
  end

  # Whether every pin and directory is deeply frozen: Ractor-shareable where
  # Ruby has Ractors, but for a value an app gave that no Ractor can share.
  def finalized? = @finalized

  def draft
    Draft.new(packages.dup, directories.dup, integrity, finalized?)
  end

  # The same pins with an empty cache: what a sweep publishes when a watched
  # .js file changes and every render has to be redone.
  def recached
    self.class.new(packages: packages, directories: directories, integrity: integrity, finalized: finalized?)
  end

  # The same pins deeply frozen, as a new generation with an empty cache.
  # Every generation drafted from it is finalized in turn.
  def finalized
    finalized? ? self : self.class.new(packages: packages, directories: directories, integrity: integrity, finalized: true)
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

  private
    # Each pin on its own, so one holding a value no Ractor can share (see
    # Importmap::Shareable) leaves only itself unshared. The pins are the
    # map's own structs: one that can't be shared is still frozen, around the
    # value the app gave it.
    def deep_freeze(entries)
      entries.each_value { |entry| Importmap::Shareable.make(entry).freeze }
      Importmap::Shareable.make(entries.freeze)
    end
end
