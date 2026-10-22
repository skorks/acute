require_relative "../test_helper"
require "stringio"
require "tmpdir"
require_relative "../../lib/acute/cli"
require_relative "../../lib/acute/chronic_duration"
require_relative "../../lib/acute/tool"
require_relative "../../lib/acute/mcp"

# Controls the security probes found working, pinned so they stay that way
class HardeningTest < Minitest::Test
  cover "Acute::Zone*" # hostile zone names
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

  def test_t33_every_option_message_quotes_a_huge_value_only_in_part
    huge = "x" * 1_000_000
    [{ now: huge }, { now: "2026-10-22T12:00:00.#{"9" * 1_000_000}x" }, { holidays: huge }, { holidays: [huge] * 3 }].each do |opts|
      e = assert_raises(Acute::OptionError) { Acute.parse("in 2 business days", **opts) }
      assert_operator e.message.bytesize, :<, 200, opts.keys.first
    end
  end

  # T31: a host whose /etc/localtime names a zone acute doesn't ship made every parse without zone: raise
  def test_t31_the_system_zone_is_always_one_acute_ships
    skip "symlinks need privileges on Windows" if Gem.win_platform?
    Dir.mktmpdir do |dir|
      links = 0
      link = lambda do |target|
        path = File.join(dir, "localtime#{links += 1}")
        File.symlink(target, path)
        path
      end
      { "/usr/share/zoneinfo/Asia/Tokyo" => "Asia/Tokyo", "/usr/share/zoneinfo/posix/Europe/Berlin" => "Europe/Berlin",
        "/usr/share/zoneinfo/right/UTC" => "UTC", "/usr/share/zoneinfo/US/Pacific-New" => "UTC",
        "/etc/zoneinfo/localtime" => "UTC", "../usr/share/zoneinfo/../../../etc/passwd" => "UTC",
        "/var/db/timezone/zoneinfo/Europe/Kyiv" => "Europe/Kyiv" }.each do |target, zone|
        assert_equal zone, Acute::Context.system_zone(nil, link.(target)), target
      end
      tokyo = link.("/usr/share/zoneinfo/Asia/Tokyo")
      assert_equal "America/New_York", Acute::Context.system_zone(":America/New_York", tokyo)
      assert_equal "Asia/Tokyo", Acute::Context.system_zone("Mars/Olympus", tokyo)
      plain = File.join(dir, "copied")
      File.write(plain, "TZif")
      assert_equal "UTC", Acute::Context.system_zone(nil, plain)
    end
  end

  # T32: an ISO 8601 now with an offset past ±23:59 moved now by days, silently
  def test_t32_now_offsets_are_held_to_a_day
    %w[+99:99 -24:00 +23:60 +2400].each do |offset|
      assert_raises(Acute::OptionError, offset) { Acute.parse("tomorrow", now: "2026-10-22T12:00#{offset}", zone: "UTC") }
    end
    assert_equal Time.utc(2026, 10, 22, 12, 1), Acute.parse("now", now: "2026-10-23T12:00+23:59", zone: "UTC").time
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

  # Linear means 4x the text costs about 4x the time; quadratic would cost 16x. Absolute limits fail on a slow runner,
  # and a collection mid-run pushed a linear 4x past 8x on macOS CI, so each run starts collected and the limit is 11x.
  def best_of_three(&)
    Array.new(3).map do
      GC.start
      seconds(&)
    end.min
  end

  # T23: each lone frequency word asked whether a determiner came before it by matching all the text before
  # it, so 100 KB of "daily weekly monthly" took 30 s
  def test_t23_lone_frequency_words_keep_extract_linear
    now = Time.new(2026, 10, 22, 12, 0, 0, "-04:00")
    ["daily weekly monthly ", "daily "].each do |unit|
      small = unit * (25_000 / unit.size)
      large = unit * (100_000 / unit.size)
      t1 = best_of_three { Acute.extract(small, now: now) }
      t4 = best_of_three { Acute.extract(large, now: now) }
      assert_operator t4 / t1, :<, 11, "#{unit}: 4x the text took #{(t4 / t1).round(1)}x as long (#{t1}s, #{t4}s)"
      assert_operator seconds { Acute.extract(large[0, 4096], now: now) }, :<, 0.5, unit
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

  # T29: each byte of a word multiplied its key, a bignum by then, so one unbroken 64 KB word took 0.6 s to
  # lex and a megabyte of base64 in extract's text minutes. Text over 512 bytes reaches the lexer only from
  # extract, which blanks such a run's middle.
  def test_t29_a_long_unbroken_word_lexes_in_linear_time
    shapes = {
      "letters" => ->(n) { "a" * n },
      "noon" => ->(n) { "noon" * (n / 4) },
      "cjk" => ->(n) { "会議" * (n / 2) },
      "dotted url" => ->(n) { "https://#{"www.example." * (n / 12)}com/a" }
    }
    shapes.each do |name, shape|
      small = shape.call(30_000)
      large = shape.call(120_000)
      t1 = best_of_three { Acute.extract(small) }
      t4 = best_of_three { Acute.extract(large) }
      assert_operator t1, :>=, 0.001, "#{name}: too quick to time"
      assert_operator t4 / t1, :<, 11, "#{name}: 4x the text took #{(t4 / t1).round(1)}x as long (#{t1}s, #{t4}s)"
    end
    assert_operator best_of_three { Acute.parse("a" * Acute::MAX_LENGTH) }, :<, 0.05
    assert_equal ["tomorrow"], Acute.extract("#{"x" * 100_000} tomorrow").mentions.map(&:text)
  end

  def test_t29_a_blanked_run_keeps_every_offset_and_splits_as_before
    text = "会議は日本 #{"é" * 40}#{"日本" * 40}’s 5pm, at noon #{"a." * 50}b tomorrow ½#{"x" * 70}½ 3pm"
    found = Acute.extract(text).mentions
    assert_equal %w[5pm noon tomorrow 3pm], found.map(&:text)
    found.each { |m| assert_equal m.text, text[m.offset] }
    assert_equal [], Acute.extract("twenty #{"q" * 80} four").mentions.map(&:text)
    assert_equal ["friday"], Acute.extract("next #{"q" * 80} friday").mentions.map(&:text)
  end

  # extract looks at a few bytes before or after a word, and those can start or end inside a character
  def test_t25_a_byte_window_inside_a_character_never_raises
    assert_equal ["3rd"], Acute.extract("3rd’ü.bü").mentions.map(&:text)
    assert_equal ["3 days"], Acute.extract("éé 3 days").mentions.map(&:text)
  end

  def test_extract_of_binary_text_with_high_bytes_gives_json
    out = Acute.extract("tomorrow \xff".b)
    assert_equal ["tomorrow"], out.mentions.map(&:text)
    assert_equal "tomorrow \uFFFD", JSON.parse(out.to_json)["text"]
  end

  # T3: the rewrites never see text longer than acute reads
  def test_t3_chronic_duration_turns_down_text_over_the_limit_before_rewriting_it
    long = "1 hour #{"and " * Acute::MAX_LENGTH}"
    assert_nil ChronicDuration.parse(long)
    ChronicDuration.raise_exceptions = true
    assert_raises(ChronicDuration::DurationParseError) { ChronicDuration.parse(long) }
  ensure
    ChronicDuration.raise_exceptions = false
  end

  RAW = /[\x00-\x1f\x7f\u0085  \p{Cf}]/
  HOSTILE = ["tomorow\e]0;pwned\a\e[31m", "x\nFORGED: ok\r", "‮noon", " \u0085\x00", "\xff\xfe".b.force_encoding("UTF-8")].join(" ")

  def refute_raw(where, text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    assert_predicate text, :valid_encoding?, "#{where} is not valid UTF-8: #{text.inspect}"
    refute_match RAW, text, "#{where}: #{text.inspect}"
  end

  def raised
    yield
    flunk("no error")
  rescue Acute::Error => e
    e.message
  end

  # Every place acute quotes its input: the message escapes control and format characters (T30), invalid
  # UTF-8 and newlines, so a quoted word can't forge or reorder a line
  def test_every_echo_of_the_input_escapes_it
    now = { now: "2026-10-22T12:00", zone: "America/New_York" }
    { "parse!" => -> { Acute.parse!(HOSTILE, **now) }, "duration!" => -> { Acute.duration!(HOSTILE) },
      "recurrence!" => -> { Acute.recurrence!("every #{HOSTILE}", **now) }, "from_cron!" => -> { Acute::Rule.from_cron!(HOSTILE) },
      "zone" => -> { Acute.parse("3pm", zone: HOSTILE) }, "now" => -> { Acute.parse("3pm", now: HOSTILE) },
      "locale" => -> { Acute.parse("3pm", locale: HOSTILE) }, "week_start" => -> { Acute.parse("3pm", week_start: HOSTILE) },
      "verify value" => -> { Acute.verify("tomorrow", "2026-10-23#{HOSTILE}", **now) } }.each do |where, call|
      refute_raw(where, raised(&call))
    end
    verdict = Acute.verify(HOSTILE, Time.now, **now)
    refute_raw("verify message", verdict.message)
    refute_raw("verify inspect", verdict.inspect)
    assert_equal "unparsed", JSON.parse(verdict.to_json)["status"] # its text field is the input as data, scrubbed
    refute_raw("rule to_s", Acute.recurrence("every day #{HOSTILE}", **now, strict: false)&.to_s)
  end

  # T5: no prose a tool returns holds the input; the words it couldn't read come back only in unread
  def test_t5_tool_results_and_mcp_errors_never_echo_the_input
    tool = Acute::Tool.new(now: "2026-10-22T12:00", zone: "America/New_York")
    hostile = HOSTILE.scrub
    { "parse" => { "text" => hostile }, "duration" => { "text" => hostile }, "recurrence" => { "text" => hostile },
      "extract" => { "text" => hostile }, "verify" => { "text" => hostile, "value" => "2026-10-23" },
      "describe" => { "value" => hostile[0, 64] }, hostile => {} }.each do |name, args|
      result = tool.call(name, args)
      result.except("unread", "remainder").each_value { refute_match(/pwned|FORGED|noon/, _1.to_json, name) }
    end
    lines = [{ name: "parse", arguments: { text: "3pm", zone: hostile } }, { name: hostile, arguments: {} }].map do |params|
      JSON.generate({ jsonrpc: "2.0", id: 1, method: "tools/call", params: params })
    end
    out = StringIO.new
    Acute::MCP.new.serve(StringIO.new("#{lines.join("\n")}\n#{JSON.generate({ jsonrpc: "2.0", id: 2, method: hostile })}\n"), out)
    out.string.lines.map { JSON.parse(_1) }.each do |reply|
      reply.dig("result", "structuredContent")&.delete("unread")
      reply.dig("result", "content")&.each { |c| c["text"] = JSON.parse(c["text"]).except("unread").to_json }
      refute_match(/pwned|FORGED/, reply.to_json)
    end
  end

  def test_the_cli_quotes_invalid_utf8_on_stdin_rather_than_raising
    out, err = cli(["--json"], "\xff\xfe tomorow\n3pm\n".b)
    assert_equal(%w[failure time], out.lines.map { JSON.parse(_1)["kind"] })
    assert_equal "�� tomorow", JSON.parse(out.lines[0])["text"]
    assert_empty err
  end

  def test_the_cli_escapes_terminal_escapes_in_its_errors
    hostile = "\e[31mtomorrow\e]0;pwned\a"
    [cli([hostile]), cli([], "#{hostile}\n"), cli(["--json"], "#{hostile}\n"), cli([hostile, "--next", "2"]),
     cli(["--next", "2"], "every \e[31mday\n")].each do |out, err|
      refute_match(/[\e\a]/, out)
      refute_match(/[\e\a]/, err)
      assert_match(/pwned|e\[31m|\\e/, out + err)
    end
    [cli(["--next", "2", "--json"], "every \e[31mday\n"), cli(["--zone", hostile, "3pm"]), cli(["--locale", hostile, "3pm"]),
     cli(["--next", hostile, "x"]), cli(["--bogus#{hostile}"]), cli(["mcp", "--zone", hostile]),
     cli(["#{hostile}‮ "])].each do |out, err|
      refute_match(/[\e\a‮ ]/, out + err)
      assert_operator err.count("\n"), :<=, 1, err
    end
  end
end
