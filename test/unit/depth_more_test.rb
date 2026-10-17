require_relative "../test_helper"

# More of the details settled in the depth pass (D44)
class DepthMoreTest < Minitest::Test
  def span(text, **opts)
    r = parse(text, **opts)
    [wall(r.begin), r.end && wall(r.end)]
  end

  def test_d44_two_dotted_numbers_after_at_are_a_clock
    assert_equal "2026-10-18 12:30:00 -04:00", wall(parse("at 12.30").begin)
    assert_equal "2026-12-30 00:00:00 -05:00", wall(parse("12.30").begin)
    assert_raises(Acute::ParseError) { parse("at 650.650.6500") }
  end

  def test_d44_a_clock_joined_to_a_numeric_date_by_a_dash_is_its_time
    assert_equal "2024-05-31 14:15:00 -04:00", wall(parse("05/31/2024-14:15").begin)
    assert_equal ["2024-05-31 00:00:00 -04:00", "2024-05-31 14:15:00 -04:00"], span("05/31/2024 - 14:15")
  end

  def test_d44_an_overnight_clock_range_begun_yesterday_is_under_way
    assert_equal ["2026-10-16 23:00:00 -04:00", "2026-10-17 15:00:00 -04:00"], span("from 23 to 3pm")
    assert_equal ["2026-10-17 23:00:00 -04:00", "2026-10-18 03:00:00 -04:00"], span("11pm to 3am")
  end

  def test_d44_looking_back_a_passed_this_month_is_the_one_passed
    assert_equal ["2026-08-01 00:00:00 -04:00", "2026-10-17 14:00:00 -04:00"], span("since this August")
  end
end
