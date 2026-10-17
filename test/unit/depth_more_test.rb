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

  def test_d44_starting_x_is_open_from_its_start
    assert_equal ["2027-01-07 00:00:00 -05:00", nil], span("starting January 7th")
    assert_equal ["2027-01-07 00:00:00 -05:00", nil], span("beginning on January 7th")
    assert_equal ["2026-10-18 00:00:00 -04:00", nil], span("starting from next week")
    assert_equal "2027-01-01 00:00:00 -05:00", wall(parse("beginning of January").begin)
  end

  def test_d44_a_count_of_units_starting_x_runs_that_long_from_its_start
    assert_equal ["2026-10-19 00:00:00 -04:00", "2026-10-22 00:00:00 -04:00"], span("3 days starting from next Monday")
    assert_equal ["2027-02-04 00:00:00 -05:00", "2027-02-11 00:00:00 -05:00"], span("the week commencing february 4")
  end

  def test_d44_two_digits_after_a_numeric_day_and_month_are_its_year
    r = parse("08/12,15")
    assert_equal ["2015-08-12 00:00:00 -04:00", :day], [wall(r.begin), r.grain]
    assert_equal "2027-08-12 15:00:00 -04:00", wall(parse("08/12 15:00").begin)
  end

  def test_d38_an_ambiguous_zone_gives_each_of_its_offsets_in_order
    r = parse("Jul 15, 2027 3:45pm IST")
    assert_equal "2027-07-15 06:15:00 -04:00", wall(r.begin)
    assert_equal ["2027-07-15 10:45:00 -04:00", "2027-07-15 09:45:00 -04:00"], alt_walls(r)
    assert_includes r.assumptions.map(&:code), :ambiguous_zone
    assert_equal ["2027-07-15 05:45:00 -04:00"], alt_walls(parse("Jul 15, 2027 3:45pm BST"))
  end

  def test_d38_bst_in_gb_is_british_summer_time_alone
    r = parse("Jul 15, 2027 3:45pm BST", zone: "Europe/London")
    assert_equal ["2027-07-15 15:45:00 +01:00", []], [wall(r.begin), alt_walls(r)]
    refute_includes r.assumptions.map(&:code), :ambiguous_zone
  end

  def test_d44_a_zone_in_brackets_is_the_zone_and_a_second_zone_labels_the_first
    assert_equal "2014-08-17 20:00:00 -04:00", wall(parse("08/17/14 17:00 (PDT)").begin)
    assert_equal "2016-09-22 22:34:51 -04:00", wall(parse("Fri Sep 23 2016 10:34:51 GMT+0800 (CST)").begin)
    assert_equal "2026-11-23 15:45:30 -05:00", wall(parse("Mon Nov 23 2026 15:45:30 GMT-0500 (Eastern Standard Time)").begin)
    assert_equal "2010-05-12 14:04:34 -04:00", wall(parse("12 May 2010 2:04:34 PM Eastern Daylight Time").begin)
    assert_raises(Acute::ParseError) { parse("9 am (tomorrow)") }
    assert_raises(Acute::ParseError) { parse("9 am (bst") }
  end
end
