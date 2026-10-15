# frozen_string_literal: true

# Deep-freezes a value set once at boot and read by every thread after it, so
# no reader can be handed something another thread is still changing:
# Ractor.make_shareable where Ruby has Ractors (CRuby 3.0+), which also lets
# a non-main Ractor read it. Where it hasn't (JRuby, TruffleRuby) the value
# and the hashes, arrays, structs and strings inside it are frozen. Freezes in
# place and returns the value.
#
# Never raises. A value no Ractor can share (a lambda that closes over the
# app's state, a logger, anything holding a Mutex or an IO) is returned as it
# is, and keeps working on the main Ractor only. A Hash, Array or Struct
# around a Proc that can't be shared is frozen around it; the Proc is not.
module Importmap::Shareable
  def self.make(value)
    return freeze_all(value) unless ractors?
    return value if ::Ractor.shareable?(value)
    return value unless freezable?(value)

    ::Ractor.make_shareable(value)
  rescue ::Ractor::Error
    value
  end

  def self.ractors? = defined?(::Ractor) ? true : false

  # Whether Ractor.make_shareable can run on +value+ in place without giving
  # up half-way, which would leave it half-frozen (a logger, frozen around the
  # Monitor it can't share). Everything but a Proc is tried on a copy first,
  # which raises without touching the original. A Proc can't be copied, but
  # make_shareable checks a Proc before it freezes it, so it needs no dry run;
  # one inside any other object is never tried.
  def self.freezable?(value)
    case value
    when Hash then value.all? { |key, item| freezable?(key) && freezable?(item) }
    when Array, Struct then value.all? { |item| freezable?(item) }
    when Proc then true
    else
      ::Ractor.make_shareable(value, copy: true) unless ::Ractor.shareable?(value)
      true
    end
  rescue ::Ractor::Error, TypeError
    false
  end

  # Without Ractors: the value itself, and the hashes, arrays, structs and
  # strings inside it. Any other object inside it is left as it is.
  def self.freeze_all(value)
    case value
    when Hash then value.each { |key, item| freeze_nested(key); freeze_nested(item) }
    when Array, Struct then value.each { |item| freeze_nested(item) }
    end
    value.freeze
  end

  def self.freeze_nested(value)
    freeze_all(value) if value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(Struct) || value.is_a?(String)
  end
  private_class_method :ractors?, :freezable?, :freeze_all, :freeze_nested
end
