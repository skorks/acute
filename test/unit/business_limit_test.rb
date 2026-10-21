require_relative "../test_helper"

class BusinessLimitTest < Minitest::Test
  NOW = Time.new(2026, 10, 21, 12, 0, 0, "-04:00")

  def parse_in(text, **opts) = Acute.parse(text, now: NOW, zone: NY, **opts)

  def elapsed(&) = Process.clock_gettime(Process::CLOCK_MONOTONIC).then { |t| yield; Process.clock_gettime(Process::CLOCK_MONOTONIC) - t }

  def test_ten_thousand_business_days_work
    assert parse_in("in 10000 business days")
  end

  def test_more_fails_as_a_value_and_raises_with_a_message
    assert_nil parse_in("in 10001 business days")
    e = assert_raises(Acute::ParseError) { Acute.parse!("in 10001 business days", now: NOW, zone: NY) }
    assert_equal :business_day_limit, e.code
    assert_match(/more than 10000 business days/, e.message)
  end

  def test_spelled_out_huge_counts_fail_fast
    assert_operator elapsed { assert_nil parse_in("nine hundred ninety nine million business days") }, :<, 1
    assert_operator elapsed { assert_nil parse_in("nine hundred ninety nine million business days ago") }, :<, 1
  end

  def test_a_calendar_that_never_has_a_business_day_fails_fast
    never = Object.new
    def never.business_day?(_) = false
    assert_operator elapsed { assert_nil parse_in("in 3 business days", business_days: never) }, :<, 1
  end
end
