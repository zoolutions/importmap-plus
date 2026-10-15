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
    assert_not_predicate value, :frozen?
    assert_not_predicate path, :frozen?
    assert_not_predicate value["logger"], :frozen?
  end

  # A Method can't be copied either, so the copy raises TypeError as it does
  # for a Proc, but make_shareable gives up on it only after freezing what
  # came before it.
  test "a hash holding something that can't be copied, nor shared, is left as it was" do
    path = +"alpha.js"
    value = { "alpha" => path, "upcase" => "alpha".method(:upcase) }

    assert_same value, Importmap::Shareable.make(value)
    assert_not_predicate value, :frozen?
    assert_not_predicate path, :frozen?
  end

  test "a value that holds itself is made shareable, not recursed into for good" do
    value = [ +"alpha.js" ]
    value << value

    assert_same value, Importmap::Shareable.make(value)
    assert Ractor.shareable?(value)
  end

  test "a struct around a lambda over the app's state is frozen around it" do
    seen = []
    callable = ->(source) { seen << source }
    value = Struct.new(:name, :path).new(+"lazy", callable)

    assert_same value, Importmap::Shareable.make(value)
    assert_predicate value.name, :frozen?
    assert_not_predicate callable, :frozen?
  end
end

# JRuby and TruffleRuby have no Ractor: there the value's hashes, arrays,
# structs and strings are frozen all the way down.
class ShareableWithoutRactorsTest < ActiveSupport::TestCase
  Pin = Struct.new(:name, :preload)

  # The logger keeps Ractor.make_shareable off the whole value, so what is
  # frozen here was frozen by the fallback.
  test "without Ractors, the hashes, arrays, structs and strings inside a value are frozen, and nothing else" do
    pin = Pin.new(+"alpha", [ +"application" ])
    logger = Logger.new(StringIO.new)
    value = { +"alpha" => pin, "logger" => logger }

    Importmap::Shareable.stub(:ractors?, false) do
      assert_same value, Importmap::Shareable.make(value)
    end

    assert_predicate value, :frozen?
    assert_predicate pin, :frozen?
    assert_predicate pin.name, :frozen?
    assert_predicate pin.preload, :frozen?
    assert_predicate pin.preload.first, :frozen?
    assert_not_predicate logger, :frozen?
  end

  test "without Ractors, what is inside a value that is already frozen is frozen too" do
    path = +"alpha.js"
    value = { "alpha" => [ path ] }.freeze

    Importmap::Shareable.stub(:ractors?, false) { Importmap::Shareable.make(value) }

    assert_predicate path, :frozen?
  end

  test "without Ractors, a value that holds itself is frozen once" do
    value = { "alpha" => [ +"alpha.js" ] }
    value["self"] = value

    Importmap::Shareable.stub(:ractors?, false) { Importmap::Shareable.make(value) }

    assert_predicate value, :frozen?
    assert_predicate value["alpha"].first, :frozen?
  end
end
