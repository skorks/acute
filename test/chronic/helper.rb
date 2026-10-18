require "minitest"
require_relative "../../lib/acute/chronic"

MiniTest = Minitest unless defined?(MiniTest)

# chronic's tests say `require 'helper'` and subclass TestCase. Here an assertion that fails is recorded with
# the parse calls made since the one before it, rather than ending the test, so every difference is seen.
module ChronicRun
  Call = Struct.new(:line, :text, :options, :got)
  Check = Struct.new(:test, :line, :calls, :expected, :actual, :error)

  class << self
    attr_reader :checks

    def reset = (@checks, @calls = [], [])

    def call(call)
      @calls << call
      @last = call
    end

    def check(test, expected, actual, error = nil)
      line = caller_locations.find { _1.path.start_with?(__dir__) && _1.label.include?(test) }&.lineno
      @checks << Check.new(test, line, @calls.empty? ? [@last].compact : @calls, expected, actual, error)
      @calls = []
    end
  end
  reset

  module Recorder
    def parse(text, options = {})
      got = super
      loc = caller_locations.find { _1.path.start_with?(__dir__) && _1.label.include?("#test_") }
      ChronicRun.call(ChronicRun::Call.new(loc&.lineno, text, options.except(:now), got))
      got
    end
  end
  Chronic.singleton_class.prepend(Recorder)
end

class TestCase < Minitest::Test
  def self.test(name, &block)
    define_method("test_#{name.gsub(/\W/, "_")}", &block) if block
  end

  # minitest 6 refuses assert_equal(nil, x), which chronic's tests use
  def assert_equal(expected, actual, *)
    return assert_nil(actual) if expected.nil?

    super
    ChronicRun.check(name, expected, actual)
  rescue Minitest::Assertion
    ChronicRun.check(name, expected, actual, :failed)
  end

  def assert_in_delta(expected, actual, *)
    super
    ChronicRun.check(name, expected, actual)
  rescue Minitest::Assertion
    ChronicRun.check(name, expected, actual, :failed)
  end

  def assert_nil(actual, *)
    super
    ChronicRun.check(name, nil, actual)
  rescue Minitest::Assertion
    ChronicRun.check(name, nil, actual, :failed)
  end

  def refute_equal(expected, actual, *)
    super
    ChronicRun.check(name, "not #{expected.inspect}", actual)
  rescue Minitest::Assertion
    ChronicRun.check(name, "not #{expected.inspect}", actual, :failed)
  end
end
