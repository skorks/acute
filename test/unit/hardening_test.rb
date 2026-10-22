require_relative "../test_helper"
require "stringio"
require_relative "../../lib/acute/cli"
require_relative "../../lib/acute/chronic_duration"
require_relative "../../lib/acute/tool"

# Controls the security probes found working, pinned so they stay that way
class HardeningTest < Minitest::Test
  HOSTILE_ZONES = ["../../../../etc/passwd", "/etc/passwd", "America/../../../etc/passwd", "UTC\0", "a" * 100_000,
                   "posixrules", "right/UTC", "zone.tab", "+99:99", "America/New_York\0", "America/New_York/",
                   "America/New_York/../../../etc/passwd", "a" * 1_000_000, "America/New_York\xff", "\xff\xfe",
                   "America/New_York".encode("UTF-16LE"), "america/new_york", "AMERICA/NEW_YORK", "utc",
                   "tzinfo/data", "Africa/Abidjan.rb", "~/.bashrc", "America\\New_York", "zoneinfo/UTC"].freeze

  # Records the files opened, read or looked for while :acute_opened holds a list
  module Opened
    def open(*args, **kwargs) = watched(:open) { super }
    def read(*args, **kwargs) = watched(:read) { super }
    def exist?(*args, **kwargs) = watched(:exist?) { super }
    def file?(*args, **kwargs) = watched(:file?) { super }
    def directory?(*args, **kwargs) = watched(:directory?) { super }

    def watched(call)
      Thread.current[:acute_opened]&.push(call)
      yield
    end
  end
  File.singleton_class.prepend(Opened)
  IO.singleton_class.prepend(Opened)

  def test_a_huge_zone_name_is_quoted_only_in_part
    e = assert_raises(Acute::OptionError) { Acute.parse("tomorrow", zone: "A" * 1_000_000) }
    assert_equal "unknown zone \"#{"A" * 64}…\"", e.message
    assert_equal 1_000_000, e.value.size
  end

  def test_hostile_zone_names_raise_and_are_not_cached
    Acute::Zone.for("UTC")
    before = Acute::Zone.instance_variable_get(:@zones).keys
    Thread.current[:acute_opened] = []
    HOSTILE_ZONES.each do |name|
      e = assert_raises(Acute::OptionError, name[0, 40].inspect) { Acute.parse("tomorrow", zone: name) }
      assert_equal :zone, e.option
      assert_raises(Acute::OptionError) { Acute::Zone.for(name) }
    end
    assert_empty Thread.current[:acute_opened]
    assert_equal before, Acute::Zone.instance_variable_get(:@zones).keys
  ensure
    Thread.current[:acute_opened] = nil
  end

  def test_chronic_duration_stays_fast_on_pathological_text
    ["1 and 2 and " * 8000, "1#{" and" * 5000} x"].each do |text|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ChronicDuration.parse(text)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.0, "#{text[0, 20].inspect}..."
    end
  end

  def cli(argv, stdin = "")
    out = StringIO.new
    err = StringIO.new
    Acute::CLI.run(argv, stdin: StringIO.new(stdin), stdout: out, stderr: err)
    [out.string, err.string]
  end

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  # T23: each lone frequency word asked whether a determiner came before it by matching all the text before
  # it, so 100 KB of "daily weekly monthly" took 30 s
  def test_t23_lone_frequency_words_keep_extract_linear
    now = Time.new(2026, 10, 22, 12, 0, 0, "-04:00")
    ["daily weekly monthly ", "daily "].each do |unit|
      text = (unit * (100_000 / unit.size))
      assert_operator seconds { Acute.extract(text, now: now) }, :<, 3.0, unit
      assert_operator seconds { Acute.extract(text[0, 4096], now: now) }, :<, 0.5, unit
    end
    text = "#{"日本 " * 2000}the weekly sync, our daily standup, take it daily with food"
    assert_equal ["daily"], Acute.extract(text, now: now).mentions.map(&:text)
  end

  # T25: the words just before a mention were matched from 12 bytes back, which can be inside a character
  def test_t25_multibyte_text_before_a_mention_does_not_raise
    ["会議は日本 tomorrow", "会議は日本 12 tomorrow", "€€€€ 12 jan", "ああああ morning", "日本語 #{"x" * 3}$12 3pm"].each do |text|
      Acute.extract(text, now: Time.new(2026, 10, 22, 12, 0, 0, "-04:00"))
    end
    assert_equal ["tomorrow"], Acute.extract("会議は日本 tomorrow").mentions.map(&:text)
    refute Acute::Tool.new.call("extract", { "text" => "会議は日本 tomorrow" }).key?("error")
  end

  # T24: a rule that runs far out, or whose occurrences are far apart, stops at R19's budgets
  def test_t24_far_out_rules_stop_at_the_budgets
    now = Time.new(2026, 10, 22, 12, 0, 0, "-04:00")
    rule = ->(text) { Acute.recurrence!(text, now: now, zone: "America/New_York") }
    assert_operator(seconds do
      assert_nil rule.("every day 999999999 times").next(3, after: Time.new(9000))
      assert_nil rule.("every minute until 2200").between(now, Time.new(2200))
      assert_nil rule.("every 999999999 seconds").between(Time.at(-10**15), Time.at(10**15))
      assert_equal 3, rule.("every 999999999 years").next(3, after: now).size
      assert_equal 1000, rule.("every minute until december 31 9999").next(1000, after: now).size
      assert_equal [], rule.("every minute until 2200").next(3, after: Time.at(10**18))
    end, :<, 0.5)
  end

  def test_the_cli_escapes_terminal_escapes_in_its_errors
    hostile = "\e[31mtomorrow\e]0;pwned\a"
    [cli([hostile]), cli([], "#{hostile}\n"), cli(["--json"], "#{hostile}\n"), cli([hostile, "--next", "2"]),
     cli(["--next", "2"], "every \e[31mday\n")].each do |out, err|
      refute_match(/[\e\a]/, out)
      refute_match(/[\e\a]/, err)
      assert_match(/pwned|e\[31m|\\e/, out + err)
    end
  end
end
