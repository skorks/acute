require_relative "../test_helper"

# Every option checks its value before any text is read, and fails with an OptionError that names it
class OptionErrorsTest < Minitest::Test
  AT = { now: "2026-10-17T14:00", zone: NY }.freeze

  def bad(option, *values)
    values.each do |v|
      e = assert_raises(Acute::OptionError, "#{option}: #{v.inspect}") { Acute.parse("this is not a phrase", **AT, option => v) }
      assert_equal option, e.option
      assert_equal v.inspect, e.value.inspect
      assert_raises(Acute::OptionError) { Acute.with(**AT, option => v) }
      assert_raises(Acute::OptionError) { Acute.extract("tomorrow", **AT, option => v) }
    end
  end

  def test_locale
    bad :locale, "", "-", "x", "en-", "-US", "en US", :"", 5, [], Object.new, true
    assert Acute.parse("tomorrow", **AT, locale: "en-GB")
    assert Acute.parse("tomorrow", **AT, locale: :fr)
  end

  def test_week_start
    bad :week_start, "", 1, :tuesday, [], true, Object.new
    assert Acute.parse("tomorrow", **AT, week_start: "monday")
  end

  def test_hemisphere
    bad :hemisphere, "", 1, :east, [], true
  end

  def test_dst
    bad :dst, "", 1, :nearest, [], true
  end

  def test_strict
    bad :strict, nil, "", "x", 0, 1, :yes, []
  end

  def test_context
    bad :context, "", nil, :sideways, "future", 5
  end

  def test_fiscal_year_start
    bad :fiscal_year_start, "", "x", "1e3", "0x5", 0, 13, -1, 10**20, 1.5, :foo, [], true
    assert Acute.parse("tomorrow", **AT, fiscal_year_start: "12")
  end

  def test_year_bias
    bad :year_bias, "", "x", -1, 100, 10**20, 1.5, :foo, [], true
    assert Acute.parse("tomorrow", **AT, year_bias: 0)
    assert Acute.parse("tomorrow", **AT, year_bias: 99)
  end

  def test_now
    bad :now, "", "tomorrow", 5, :now, [], 10**20
  end

  def test_zone
    bad :zone, "", "Mars/Olympus", 5, :utc, [], Object.new
  end

  def test_business_days
    bad :business_days, Object.new, "x", 5
  end

  def test_holidays_objects_and_names
    bad :holidays, Object.new, 5, [nil], [""], ["us", 1], "", "us gb", "../x", {}
  end

  def test_holidays_regions_are_checked_when_the_context_is_built
    Object.const_set(:Holidays, Module.new do
      def self.available_regions = %i[us gb]
      def self.on(*) = []
    end)
    bad :holidays, :zz, %i[us zz], "nowhere"
    assert Acute.parse("tomorrow", **AT, holidays: %i[us gb])
  ensure
    Object.send(:remove_const, :Holidays) if Object.const_defined?(:Holidays)
  end

  def test_the_missing_gem_is_an_option_error
    skip "the holidays gem is installed" if Gem::Specification.find_all_by_name("holidays").any?
    bad :holidays, :us
  end

  def test_describe_style
    e = assert_raises(Acute::OptionError) { Acute.describe(Date.new(2026, 10, 18), style: :fancy) }
    assert_equal :style, e.option
  end
end
