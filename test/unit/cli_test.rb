require_relative "../test_helper"
require "open3"
require "stringio"
require_relative "../../lib/acute/cli"

class CLITest < Minitest::Test
  AT = %w[--now 2026-10-17T14:00 --zone America/New_York].freeze
  EXE = File.expand_path("../../exe/acute", __dir__)

  def acute(*argv, stdin: "")
    out = StringIO.new
    err = StringIO.new
    status = Acute::CLI.run(argv, stdin: StringIO.new(stdin), stdout: out, stderr: err)
    [out.string, err.string, status]
  end

  def test_echoes_a_phrase_in_english
    assert_equal ["Fri, Oct 23, 3pm EDT\n", "", 0], acute("next friday 3pm", *AT)
    assert_equal ["Sun, Oct 18, 3–5pm EDT\n", "", 0], acute("3pm", "to", "5pm", "tomorrow", *AT)
    assert_equal "Sat, Oct 24\n", acute("next saturday", *AT)[0]
    assert_equal "1h 30m\n", acute("90 min", *AT)[0]
  end

  def test_d45_alternatives_follow_the_echo
    assert_equal "Fri, Oct 23, 3pm EDT   (also: Fri, Oct 16, 3pm)\n", acute("this friday 3pm", *AT)[0]
    assert_equal "Thu, Mar 4   (also: Sat, Apr 3)\n", acute("3/4", *AT)[0]
  end

  def test_d45_a_time_of_day_names_its_zone
    assert_equal "Sat, Oct 17, 3pm +10:00\n", acute("3pm", "--now", "2026-10-17T14:00", "--zone", "+10:00")[0]
    assert_equal "Sun, Nov 1, 1:30am EDT\n", acute("1:30am nov 1", *AT)[0]
  end

  def test_json
    out, _, status = acute("next friday 3pm", "--json", *AT)
    assert_equal 0, status
    json = JSON.parse(out)
    assert_equal "2026-10-23T15:00:00-04:00", json["time"]
    assert_equal "minute", json["grain"]
    assert_equal 5400, JSON.parse(acute("90 min", "--json", *AT)[0])["seconds"]
  end

  def test_context_options_reach_the_parser
    assert_equal "Fri, Oct 16\n", acute("friday", "--context", "past", *AT)[0]
    assert_equal "2027-04-03", JSON.parse(acute("3/4", "--locale", "en-GB", "--json", *AT)[0])["begin"][0, 10]
    assert_equal "2026-10-19", JSON.parse(acute("next week", "--week-start", "monday", "--json", *AT)[0])["begin"][0, 10]
    assert_equal "2026-12-01", JSON.parse(acute("summer", "--hemisphere", "south", "--json", *AT)[0])["begin"][0, 10]
    assert_equal "2027-07-01", JSON.parse(acute("next fiscal year", "--fiscal-year-start", "7", "--json", *AT)[0])["begin"][0, 10]
  end

  def test_a_failing_phrase_exits_1_with_the_reason
    assert_equal ["", "acute: unknown word \"banana\"\n", 1], acute("banana", *AT)
  end

  def test_bad_options_exit_2
    assert_equal 2, acute("x", "--context", "sideways")[2]
    assert_equal ["", "acute: unknown zone \"Mars/X\"\n", 2], acute("x", "--zone", "Mars/X")
    assert_match(/invalid argument: --fiscal-year-start/, acute("x", "--fiscal-year-start", "july")[1])
  end

  def test_d45_batch_gives_one_line_per_line
    out, err, status = acute(*AT, stdin: "tomorrow 9am\nbanana\n3/4\nnext\n")
    assert_equal ["Sun, Oct 18, 9am EDT", "error: unknown word \"banana\"", "Thu, Mar 4   (also: Sat, Apr 3)",
                  "error: the phrase is incomplete"], out.lines(chomp: true)
    assert_equal "", err
    assert_equal 1, status
    assert_equal 0, acute(*AT, stdin: "tomorrow\nnoon\n")[2]
  end

  def test_d45_batch_json_lines
    out, = acute("--json", *AT, stdin: "tomorrow 9am\nbanana\n")
    first, second = out.lines.map { JSON.parse(_1) }
    assert_equal "2026-10-18T09:00:00-04:00", first["time"]
    assert_equal({ "kind" => "failure", "text" => "banana", "code" => "unknown_word", "error" => "unknown word \"banana\"" }, second)
  end

  def test_blank_lines_are_skipped
    assert_equal ["Sun, Oct 18, 9am EDT\nMon, Oct 19\n", "", 0], acute(*AT, stdin: "\ntomorrow 9am\n  \t\r\n\nmonday\n\n")
    assert_equal ["", "", 0], acute("--json", *AT, stdin: "\n \n")
  end

  def test_a_failure_prints_its_hint_naming_the_flag
    assert_equal ["", "acute: unknown word \"fridya\"\nhint: did you mean \"friday\"?\n", 1], acute("next", "fridya", *AT)
    _, err, = acute(*AT, "--dst", "reject", "2026-03-08 02:30")
    assert_equal "hint: --dst earlier, later or compatible picks an instant for it", err.lines(chomp: true)[1]
  end

  def test_d45_batch_prints_a_hint_on_the_failures_line
    out, = acute(*AT, "--dst", "reject", stdin: "next fridya\n2026-11-01 01:30\nbanana\n")
    assert_equal ["error: unknown word \"fridya\"   hint: did you mean \"friday\"?",
                  "error: \"2026-11-01 01:30\" names a wall time that happens twice as the clocks go back   hint: --dst earlier or later picks one",
                  "error: unknown word \"banana\""], out.lines(chomp: true)
  end

  # The tools' shape (schema/failure.json), with the input, a hint and where it points
  def test_json_failures
    out, err, status = acute("--json", *AT, "next", "fridya")
    assert_equal [{ "kind" => "failure", "text" => "next fridya", "code" => "unknown_word", "error" => "unknown word \"fridya\"",
                    "position" => [5, 11], "hint" => "did you mean \"friday\"?" }, "", 1], [JSON.parse(out), err, status]
    out, = acute("--json", *AT, "--dst", "reject", "2026-03-08 02:30")
    assert_equal ["dst_skipped_time", "--dst earlier, later or compatible picks an instant for it"], JSON.parse(out).values_at("code", "hint")
    refute JSON.parse(out).key?("position"), "a position over the whole phrase is left out, as the tools leave it"
    out, = acute("--json", *AT, "--dst", "reject", stdin: "2026-11-01 01:30\n")
    assert_equal ["dst_repeated_time", "--dst earlier or later picks one"], JSON.parse(out).values_at("code", "hint")
    out, = acute("--json", *AT, stdin: "caf\xC3\xA9 \xFF\n")
    assert_equal ["failure", "invalid_encoding", "caf\u00e9 \uFFFD"], JSON.parse(out).values_at("kind", "code", "text")
  end

  def test_a_rule_prints_its_words_ical_and_cron
    assert_equal ["every weekday at 9am\nDTSTART;TZID=America/New_York:20261019T090000\n" \
                  "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0\ncron: 0 9 * * 1-5 (CRON_TZ=America/New_York)\n", "", 0],
                 acute("every weekday at 9am", *AT)
    assert_equal "every other Tuesday\nDTSTART;VALUE=DATE:20261020\nRRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU\n", acute("every other tuesday", *AT)[0]
    json = JSON.parse(acute("every other tuesday", "--json", *AT)[0])
    assert_equal [nil, "cron can't express \"every other\""], json.values_at("cron", "cron_reason")
    refute json.key?("next")
  end

  def test_next_lists_a_rules_first_occurrences
    out, _, status = acute("every monday at 9", "--next", "2", *AT)
    assert_equal 0, status
    assert_equal ["Mon, Oct 19, 9am EDT", "Mon, Oct 26, 9am EDT"], out.lines(chomp: true).last(2)
    assert_equal ["Sat, Oct 17", "Sun, Oct 18", "Mon, Oct 19"], acute("every day", "--next", "3", *AT)[0].lines(chomp: true).last(3)
    assert_equal %w[2026-10-17T14:00:00-04:00 2026-10-17T15:00:00-04:00], JSON.parse(acute("every hour", "--next", "2", "--json", *AT)[0])["next"]
    assert_equal 1000, JSON.parse(acute("every minute", "--next", "1000", "--json", *AT)[0])["next"].size
  end

  def test_next_errors
    assert_equal ["", "acute: not a repeating time\n", 1], acute("tomorrow", "--next", "2", *AT)
    assert_equal ["", "acute: \"twice a week\" says how often, not when\n", 1], acute("twice a week", "--next", "2", *AT)
    assert_equal ["", "acute: invalid argument: --next 0\n", 2], acute("every day", "--next", "0", *AT)
    assert_equal ["", "acute: invalid argument: --next 1001\n", 2], acute("every day", "--next", "1001", *AT)
    assert_match(/invalid argument: --next three/, acute("every day", "--next", "three", *AT)[1])
  end

  def test_batch_rules_stay_one_line_each
    out, _, status = acute(*AT, "--next", "1", stdin: "every day\ntomorrow\n")
    assert_equal ["every day   DTSTART;VALUE=DATE:20261017   RRULE:FREQ=DAILY   cron: 0 0 * * * (CRON_TZ=America/New_York)   Sat, Oct 17",
                  "error: not a repeating time"], out.lines(chomp: true)
    assert_equal 1, status
    first, second = acute("--json", "--next", "1", *AT, stdin: "every day\ntomorrow\n")[0].lines.map { JSON.parse(_1) }
    assert_equal ["rule", ["2026-10-17"]], first.values_at("kind", "next")
    assert_equal "failure", second["kind"]
  end

  def test_help_and_version
    assert_match(/Usage: acute/, acute("--help")[0])
    assert_equal ["#{Acute::VERSION}\n", "", 0], acute("--version")
  end

  def test_the_executable
    out, err, status = Open3.capture3(RbConfig.ruby, EXE, "banana", *AT)
    assert_equal ["", "acute: unknown word \"banana\"\n", 1], [out, err, status.exitstatus]
    out, _, status = Open3.capture3(RbConfig.ruby, EXE, *AT, "--json", stdin_data: "tomorrow\nnoon\n")
    assert_predicate status, :success?
    assert_equal(%w[day minute], out.lines.map { JSON.parse(_1)["grain"] })
  end
end
