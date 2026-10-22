require_relative "../test_helper"
require "stringio"
require_relative "../../lib/acute/cli"
require_relative "../../lib/acute/chronic_duration"

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
