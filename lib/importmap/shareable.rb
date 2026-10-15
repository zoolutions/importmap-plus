# frozen_string_literal: true

# Deep-freezes a value set once at boot and read by every thread after it, so
# no reader can be handed something another thread is still changing:
# Ractor.make_shareable where Ruby has Ractors (CRuby 3.0+), which also lets
# a non-main Ractor read it, and a plain freeze where it hasn't (JRuby,
# TruffleRuby). Freezes in place and returns the value.
module Importmap::Shareable
  def self.make(value)
    defined?(::Ractor) ? ::Ractor.make_shareable(value) : value.freeze
  end
end
