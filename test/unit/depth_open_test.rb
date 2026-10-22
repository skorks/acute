require_relative "../test_helper"

# Open ends and the spans that hold a date, settled in the depth pass (D44)
class DepthOpenTest < Minitest::Test
  cover "Acute::Resolve*"
  def span(text, **opts)
    r = parse(text, **opts)
    [r.begin && wall(r.begin), r.end && wall(r.end)]
  end

  def test_d44_open_comparisons
    assert_equal ["2027-01-01 00:00:00 -05:00", nil], span("later than 2026")
    assert_equal ["2027-01-01 00:00:00 -05:00", nil], span("greater than 2026")
    assert_equal [nil, "2027-01-01 00:00:00 -05:00"], span("earlier than 2027")
    assert_equal [nil, "2026-10-17 14:00:00 -04:00"], span("in advance of 2pm")
    assert_equal ["2016-01-01 00:00:00 -05:00", nil], span("on or after 1/1/2016")
    assert_equal ["2016-01-01 00:00:00 -05:00", nil], span("later than or in 2016")
    assert_equal [nil, "2016-01-02 00:00:00 -05:00"], span("on or before 1/1/2016")
    assert_equal [nil, "2018-03-01 00:00:00 -05:00"], span("before or in Feb 2018")
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-24 00:00:00 -04:00"], span("no later than friday")
  end

  def test_d44_or_later_and_or_earlier_after_a_time
    assert_equal ["2012-01-01 00:00:00 -05:00", nil], span("2012 or later")
    assert_equal ["2012-01-01 00:00:00 -05:00", nil], span("year 2012 or after")
    assert_equal ["2016-01-01 00:00:00 -05:00", nil], span("1/1/2016 and later")
    assert_equal ["2026-10-17 15:00:00 -04:00", nil], span("3 pm onwards")
    assert_equal [nil, "2026-10-24 00:00:00 -04:00"], span("friday or earlier")
    assert_raises(Acute::ParseError) { parse("2012 or after 2018") }
    x = Acute.extract("sales before 2010 or after 2018", now: "2026-10-17T14:00", zone: NY)
    assert_equal ["before 2010", "after 2018"], x.mentions.map(&:text)
  end

  def test_d44_after_one_clock_but_before_another_is_the_range_between
    assert_equal ["2026-10-22 09:30:00 -04:00", "2026-10-22 11:00:00 -04:00"], span("later than 9:30 but before 11:00 on Thursday")
    assert_equal ["2026-10-17 15:30:00 -04:00", "2026-10-17 18:00:00 -04:00"], span("after 3:30pm but before 6pm")
    assert_raises(Acute::ParseError) { parse("after monday but before friday") }
    assert_raises(Acute::ParseError) { parse("9 but before 11") }
  end

  def test_d44_an_open_span_that_would_run_backwards_is_no_time
    ["until 2014", "until yesterday", "since 2030", "since tomorrow"].each do |text|
      assert_equal :invalid_date, assert_raises(Acute::ParseError) { parse(text) }.code, text
    end
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 14:00:00 -04:00"], span("until now")
    assert_equal ["2026-10-12 00:00:00 -04:00", "2026-10-17 14:00:00 -04:00"], span("since monday")
  end

  def test_through_and_earlier
    assert_equal ["2026-10-17 14:00:00 -04:00", "2026-10-17 16:00:00 -04:00"], span("through 4pm")
    assert_equal ["2026-10-17 14:00:00 -04:00", "2028-01-01 00:00:00 -05:00"], span("thru 2027")
    assert_equal ["2027-04-09 00:00:00 -04:00", "2027-04-18 00:00:00 -04:00"], span("april ninth through seventeenth")
    assert_equal ["2026-10-22 09:30:00 -04:00", "2026-10-22 11:00:00 -04:00"], span("from 9:30 untill 11:00 on thursday")
    assert_equal "2026-10-17 13:45:00 -04:00", wall(parse("15 minutes earlier").begin)
  end

  def test_d44_the_week_of_a_date_is_the_week_that_holds_it
    assert_equal ["2027-10-03 00:00:00 -04:00", "2027-10-10 00:00:00 -04:00"], span("the week of october 6th")
    assert_equal ["2027-10-03 00:00:00 -04:00", "2027-10-10 00:00:00 -04:00"], span("week of october 9")
    assert_equal ["2026-10-18 00:00:00 -04:00", "2026-10-25 00:00:00 -04:00"], span("the week of the 18th")
    assert_equal ["2026-12-20 00:00:00 -05:00", "2026-12-27 00:00:00 -05:00"], span("the week of christmas")
    assert_equal ["2027-05-01 00:00:00 -04:00", "2027-06-01 00:00:00 -04:00"], span("the month of may")
    assert_raises(Acute::ParseError) { parse("the week of") }
  end
end
