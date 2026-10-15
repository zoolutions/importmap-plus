# frozen_string_literal: true

# Deep-freezes a value set once at boot and read by every thread after it, so
# no reader can be handed something another thread is still changing:
# Ractor.make_shareable where Ruby has Ractors (CRuby 3.0+), which also lets
# a non-main Ractor read it, and a plain freeze where it hasn't (JRuby,
# TruffleRuby). Freezes in place and returns the value.
#
# Never raises. A value no Ractor can share (a lambda that closes over the
# app's state, a logger, anything holding a Mutex or an IO) is returned as it
# is, and keeps working on the main Ractor only.
module Importmap::Shareable
  def self.make(value)
    return value.freeze unless defined?(::Ractor)
    return value if ::Ractor.shareable?(value)
    return value unless dry_run(value)

    ::Ractor.make_shareable(value)
  rescue ::Ractor::Error
    value
  end

  # Whether to freeze +value+ in place. Ractor.make_shareable freezes as it
  # goes, so a value it gives up on half-way would be left half-frozen (a
  # logger, frozen around the Monitor it can't share): it runs on a copy
  # first, which raises Ractor::Error without touching +value+. A Proc can't
  # be copied (TypeError), but make_shareable checks a Proc before freezing
  # it, so a Proc, or a Hash, Array or Struct holding one, is tried for real.
  # Any other object holding a Proc is left as it is.
  def self.dry_run(value)
    ::Ractor.make_shareable(value, copy: true)
    true
  rescue TypeError
    value.is_a?(Proc) || value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(Struct)
  end
  private_class_method :dry_run
end
