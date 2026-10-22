require_relative "../test_helper"
require_relative "../corpus"
require_relative "../property_answer"
require "open3"
require "rbconfig"

# Properties over a seeded sample of the corpus: every span holds its time (begin <= time < end); the answer is the same twice, in a fresh
# process, and whatever the process's TZ and locale; a rule's occurrences strictly increase and between agrees with
# next. PROPERTY_SEED and PROPERTY_SAMPLE widen the search.
class PropertiesTest < Minitest::Test
  SEED = Integer(ENV.fetch("PROPERTY_SEED", 1066))
  SAMPLE = Integer(ENV.fetch("PROPERTY_SAMPLE", 1500))
  # Zones far from the corpus's, with odd offsets, and locales whose case rules or encodings differ from en_US.UTF-8
  ENVS = [{}, { "TZ" => "Pacific/Chatham" }, { "TZ" => "America/St_Johns", "LANG" => "tr_TR.UTF-8" },
          { "TZ" => "Asia/Kathmandu", "LC_ALL" => "C" }, { "TZ" => "UTC", "LANG" => "C", "LC_ALL" => "POSIX" }].freeze
  ANSWER = File.expand_path("../property_answer.rb", __dir__)

  def self.sample
    @sample ||= begin
      cases = Corpus.load.reject { _1["tz"].nil? || _1["now"].nil? }
      rules, times = cases.partition { _1["id"].start_with?("recurrence") }
      rng = Random.new(SEED)
      (times.sample(SAMPLE, random: rng).map { ["time", _1["text"], _1["now"], _1["tz"]] } +
        rules.map { ["rule", _1["text"], _1["now"], _1["tz"]] }).freeze
    end
  end

  def sample = self.class.sample

  def answers = sample.map { |args| PropertyAnswer.of(*args) }

  def test_a_span_holds_its_time
    checked = 0
    bad = sample.filter_map do |kind, text, now, zone|
      next if kind == "rule"
      result = Acute.parse(text, now: now, zone: zone) or next
      [result, *result.alternatives].filter_map do |r|
        checked += 1
        b, t, e = r.begin, r.time, r.end
        # "before X" is open to X's start, and its time is that end
        held = b ? b <= t && (e.nil? || t < e) : e && t == e
        "#{text.inspect} at #{now} #{zone}: #{b}, #{t}, #{e}" unless held
      end.first
    end
    assert_operator checked, :>, SAMPLE / 2
    assert_empty bad.first(10)
  end

  def test_the_same_answer_twice
    assert_equal answers, answers
  end

  def test_the_same_answer_in_fresh_processes_whatever_their_tz_and_locale
    input = sample.map { JSON.generate(_1) }.join("\n") << "\n"
    expected = answers.map { JSON.parse(JSON.generate(_1)) }
    ENVS.map do |env|
      Thread.new do
        out, err, status = Open3.capture3(env, RbConfig.ruby, ANSWER, stdin_data: input)
        [env, status.success? ? out.lines.map { JSON.parse(_1) } : err]
      end
    end.each do |thread|
      env, got = thread.value
      flunk "with #{env}: #{got}" if String === got
      diffs = sample.zip(expected, got).reject { _2 == _3 }.map { |args, want, have| "#{args.inspect}: #{want} vs #{have}" }
      assert_empty diffs.first(5), "with #{env}"
    end
  end

  def test_occurrences_strictly_increase_and_between_agrees_with_next
    checked = 0
    sample.each do |kind, text, now, zone|
      next unless kind == "rule"
      rule = Acute.recurrence(text, now: now, zone: zone) or next
      after = Time.iso8601("#{now}Z")
      occurrences = rule.next(12, after: after) or next
      next if occurrences.size < 2
      checked += 1
      occurrences.each_cons(2) { |a, b| assert_operator a, :<, b, text }
      # a Date as `to` stands for its whole day (R16), so a rule of days lists the last one too
      upto = Date === occurrences.last ? occurrences : occurrences[0...-1]
      assert_equal upto, rule.between(occurrences.first, occurrences.last), text
      assert_equal occurrences.first(3), rule.each(after: after).first(3), text
    end
    assert_operator checked, :>, 20
  end
end
