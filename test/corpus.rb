# Runs test/cases against Acute.parse and compares with the ratchet in test/corpus/passing.txt.
# Expected values are worked out with the system zoneinfo through TZInfo, not Acute::Zone, so the two check each other.
#   ruby test/corpus.rb [--record] [--grep TEXT] [--file NAME] [--rule D20] [--list STATUS]
require "json"
require "time"
require "date"
require "tzinfo"
require_relative "../lib/acute"

module Corpus
  ROOT = File.expand_path("..", __dir__)
  CASES = File.join(ROOT, "test/cases")
  RATCHET = File.join(ROOT, "test/corpus/passing.txt")
  WALL = /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d))?(\.\d+)?\z/
  CHRONIC_ONLY = %w[endian_precedence hours24 ambiguous_time_range].freeze
  # chronic's names for acute's options (D47)
  RENAMED = { "ambiguous_year_future_bias" => :year_bias }.freeze
  GRAINS = %w[second minute hour day week month quarter year].freeze
  STATUSES = %w[pass alt_differs wrong nil garbage raises chronic_option other_kind].freeze
  # The system's zoneinfo, whose rules run a century on where tzinfo-data's transitions stop at about 2076 (D47)
  ZONEINFO = TZInfo::DataSources::ZoneinfoDataSource.new
  TZS = Hash.new { |h, name| h[name] = ZONEINFO.get_timezone_info(name).create_timezone }

  module_function

  # D-rules a case is tagged with or names in its note
  def rules(c) = (c["tags"] || []).grep(/\AD\d+\z/) | c["note"].to_s.scan(/\bD\d+\b/)

  def all_rules = File.read(File.join(ROOT, "research/decisions.md")).scan(/^### (D\d+)\./).flatten

  def load(file: nil, grep: nil)
    Dir[File.join(CASES, "*.jsonl")].sort.flat_map do |path|
      next [] if file && !File.basename(path, ".jsonl").include?(file)
      File.foreach(path).filter_map do |line|
        next if line.strip.empty?
        c = JSON.parse(line)
        c if grep.nil? || c["text"].downcase.include?(grep.downcase)
      end
    end
  end

  # Compatible DST: a repeated wall time takes the earlier instant, a skipped one moves forward by the gap
  def epoch(str, tz)
    return Time.iso8601(str).to_r unless (m = WALL.match(str))
    y, mo, d, h, mi, s = m.captures.take(6).map(&:to_i)
    local = Time.utc(y, mo, d, h, mi, s)
    periods = tz.periods_for_local(local)
    offset = case periods.size
             when 0 then tz.period_for_utc(local - 86_400).observed_utc_offset
             else periods.map(&:observed_utc_offset).max
             end
    local.to_i - offset + (m[7] ? m[7].to_r : 0)
  end

  # Day-or-coarser grains step from the written wall fields: in a gap the instant has been shifted
  def interval(exp, tz)
    return exp["span"].map { |s| s && epoch(s, tz) } if exp["span"]
    str = exp["time"]
    b = epoch(str, tz)
    grain = exp.fetch("grain", "second")
    step = { "second" => 1, "minute" => 60, "hour" => 3600 }[grain]
    return [b, b + step] if step
    m = WALL.match(str) || WALL.match(str[0, 19])
    y, mo, d, h, mi, s = m.captures.take(6).map(&:to_i)
    day = Date.new(y, mo, d)
    nxt = case grain
          when "day" then day + 1
          when "week" then day + 7
          when "month" then day >> 1
          when "quarter" then day >> 3
          when "year" then day >> 12
          else raise "unknown grain #{grain}"
          end
    [b, epoch(format("%04d-%02d-%02dT%02d:%02d:%02d", nxt.year, nxt.month, nxt.day, h, mi, s), tz)]
  end

  def run_case(c)
    exp = c["expect"]
    return duration_case(c) if exp.key?("duration")
    return ["other_kind", nil] if exp["rrule"] || exp["extract"]
    opts = c["options"] || {}
    return ["chronic_option", nil] if opts.keys.intersect?(CHRONIC_ONLY)

    tz = TZS[c["tz"]]
    r = Acute.parse(c["text"], **context(c))
    got = r && ([r] + r.alternatives).map { |x| [x.begin&.to_r, x.end&.to_r] }
    return [r ? "garbage" : "pass", got] if exp["nil"]
    return ["nil", got] unless r

    want = (exp["alternatives"] || [exp]).map { |e| interval(e, tz) }
    return ["pass", got] if got == want
    [got[0] == want[0] ? "alt_differs" : "wrong", got]
  rescue StandardError, SystemStackError => e
    ["raises", "#{e.class}: #{e.message[0, 80]}"]
  end

  def context(c)
    kwargs = (c["options"] || {}).to_h { |k, v| [RENAMED[k] || k.to_sym, k == "context" ? v.to_sym : v] }
    { now: Time.at(epoch(c["now"], TZS[c["tz"]])), zone: c["tz"], **kwargs }
  end

  # Acute.read gives a passing case the kind it expects: a Duration for a duration, a Result for a time
  def read_kind?(c)
    return Acute::Duration === Acute.read(c["text"]) if c["expect"].key?("duration")
    Acute::Result === Acute.read(c["text"], **context(c))
  end

  # A duration is compared by its ISO 8601 form
  def duration_case(c)
    got = Acute.duration(c["text"])&.iso8601
    [got == c["expect"]["duration"] ? "pass" : got ? "wrong" : "nil", got]
  rescue StandardError, SystemStackError => e
    ["raises", "#{e.class}: #{e.message[0, 80]}"]
  end

  def show(c, got)
    return "#{c["id"]} | #{c["text"]} | #{c["expect"]["duration"]} | #{got.inspect}" if c["expect"].key?("duration")
    tz = TZS[c["tz"]]
    at = ->(t) { t ? tz.to_local(Time.at(t)).strftime("%F %T") : "open" }
    fmt = ->(pairs) { pairs.map { |b, e| b && e ? "#{at.(b)}+#{e - b}s" : "#{at.(b)}..#{at.(e)}" }.join(" ; ") }
    exp = c["expect"]
    want = exp["nil"] ? "nil" : fmt.((exp["alternatives"] || [exp]).map { |e| interval(e, tz) })
    shown = got.is_a?(Array) ? fmt.(got) : got.inspect
    "#{c["id"]} | #{c["text"]} | #{c["now"]} #{c["tz"]} | #{want} | #{shown}"
  rescue StandardError => e
    "#{c["id"]} | #{c["text"]} | (#{e.class}: #{e.message})"
  end

  def main(argv)
    record = argv.delete("--record")
    grep = (i = argv.index("--grep")) && argv.slice!(i, 2)[1]
    file = (i = argv.index("--file")) && argv.slice!(i, 2)[1]
    list = (i = argv.index("--list")) && argv.slice!(i, 2)[1]
    rule = (i = argv.index("--rule")) && argv.slice!(i, 2)[1]
    cases = load(file: file, grep: grep)
    if rule
      covered = cases.flat_map { |c| rules(c) }.uniq
      puts "rules with no cases: #{(all_rules - covered).join(", ")}"
      cases = cases.select { |c| rules(c).include?(rule) }
    end
    results = cases.map { |c| [c, *run_case(c)] }

    counts = results.map { |_, s, _| s }.tally
    puts "corpus: #{cases.size} cases | " + STATUSES.map { |s| "#{s} #{counts.fetch(s, 0)}" }.join(" | ")

    ratchet = File.exist?(RATCHET) ? File.readlines(RATCHET, chomp: true).reject(&:empty?) : []
    ids = cases.to_h { |c| [c["id"], true] }
    passing = results.select { |_, s, _| s == "pass" }.map { |c, _, _| c["id"] }.sort
    regressions = results.select { |c, s, _| s != "pass" && ratchet.include?(c["id"]) }
    gained = passing - ratchet
    regressions.each { |c, s, got| puts "REGRESSION #{s}: #{show(c, got)}" }
    misread = results.select { |c, s, _| s == "pass" && !c["expect"]["nil"] && !read_kind?(c) }
    misread.each { |c, _, _| puts "MISREAD: #{c["id"]} | #{c["text"]}" }
    puts "read: #{misread.size} passing cases of the wrong kind"
    puts "ratchet: #{ratchet.count { |id| ids[id] }} recorded, #{passing.size} passing, #{gained.size} new, #{regressions.size} regressed"
    results.select { |_, s, _| s == list }.each { |c, _, got| puts show(c, got) } if list

    if record
      abort "not recording: fix the regressions first" unless regressions.empty? && misread.empty?
      abort "not recording: --grep/--file/--rule run only part of the corpus" if grep || file || rule
      File.write(RATCHET, passing.join("\n") + "\n")
      puts "recorded #{passing.size} passing ids in test/corpus/passing.txt"
    end
    regressions.empty? && misread.empty?
  end
end

exit(Corpus.main(ARGV.dup)) if $PROGRAM_NAME == __FILE__
