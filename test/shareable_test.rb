# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

# Importmap::Shareable deep-freezes what the map and the class-level settings
# hold. A value no Ractor can share is handed back as the app gave it: never
# raised on, and never left half-frozen.
class ShareableTest < ActiveSupport::TestCase
  # Like Importmap::Minifier::TOOLS: its self is this class, and it captures nothing.
  BUILDER = ->(input) { [ input ] }

  setup { skip "#{RUBY_ENGINE} has no Ractor, so nothing here can be checked for shareability" unless defined?(Ractor) }

  test "a value that can be shared is deep-frozen in place" do
    value = { "alpha" => [ +"alpha.js" ] }

    assert_same value, Importmap::Shareable.make(value)
    assert Ractor.shareable?(value)
    assert_predicate value["alpha"].first, :frozen?
  end

  test "a lambda that captures nothing is made shareable" do
    assert_same BUILDER, Importmap::Shareable.make(BUILDER)
    assert Ractor.shareable?(BUILDER)
  end

  test "a lambda that closes over the app's state is returned as it was" do
    seen = []
    callable = ->(source) { seen << source }

    assert_same callable, Importmap::Shareable.make(callable)
    assert_not_predicate callable, :frozen?
    callable.call("x")
    assert_equal [ "x" ], seen
  end

  test "a logger is returned untouched, not half-frozen, and still logs" do
    io = StringIO.new
    logger = Logger.new(io)

    assert_same logger, Importmap::Shareable.make(logger)
    assert_not_predicate logger, :frozen?
    logger.level = :info
    logger.info("still logging")
    assert_match(/still logging/, io.string)
  end

  test "a hash holding a value no Ractor can share is left unshared, its other values too" do
    path = +"alpha.js"
    value = { "alpha" => path, "logger" => Logger.new(StringIO.new) }

    assert_same value, Importmap::Shareable.make(value)
    assert_not Ractor.shareable?(value)
    assert_not_predicate value["logger"], :frozen?
  end
end
