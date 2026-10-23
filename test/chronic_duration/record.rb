# Records chronic_duration 0.10.6's and gitlab_chronic_duration 0.12.0's answers to the cases below in
# test/chronic_duration/fixture.jsonl, by running each real gem in a separate process. Not part of bin/check: run
# it by hand with both gems installed:
#   ruby test/chronic_duration/record.rb
# Each line is [method, input, options, 0.10.6's answer, 0.12.0's answer]; an answer that raised is {"error": class}.
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("../..", __dir__)
FIXTURE = File.join(ROOT, "test/chronic_duration/fixture.jsonl")
GEMS = { "chronic_duration" => %w[0.10.6 chronic_duration 0.1.1], "gitlab_chronic_duration" => %w[0.12.0 gitlab_chronic_duration 0.2.0] }.freeze

# The unit words the gems name, by unit, each as the gems spell it
SPELLINGS = {
  "seconds" => %w[seconds second secs sec s], "minutes" => %w[minutes minute mins min m],
  "hours" => %w[hours hour hrs hr h], "days" => %w[days day dy d], "weeks" => %w[weeks week wks wk w],
  "months" => %w[months month mos mo], "years" => %w[years year yrs yr y]
}.freeze
LONG = SPELLINGS.transform_values(&:first).freeze
COUNTS = ["1", "2", "12", "2.5", "three", "twenty five"].freeze
JOINERS = [" ", ", ", " and ", ", and ", " plus ", " with "].freeze

def gem_spec_inputs
  Dir[File.expand_path("~/.rbenv/versions/*/lib/ruby/gems/*/gems/{,gitlab_}chronic_duration-*/spec/lib/chronic_duration_spec.rb")].flat_map do |f|
    text = File.read(f)
    text.scan(/^\s*'([^']+)'\s*=>/).flatten + text.scan(/parse\('([^']*)'/).flatten
  end
end

def parse_cases
  rng = Random.new(20_261_023)
  texts = gem_spec_inputs
  SPELLINGS.each_value do |words|
    words.each do |w|
      COUNTS.each { |n| texts << "#{n} #{w}" }
      texts << "1#{w}" << "2.5#{w}" << w
    end
  end
  units = SPELLINGS.keys.reverse
  units.combination(2).each do |big, small|
    [[LONG[big], LONG[small]], [SPELLINGS[big][2], SPELLINGS[small][2]], [SPELLINGS[big].last, SPELLINGS[small].last]].each do |a, b|
      JOINERS.each { |j| texts << "#{rng.rand(1..30)} #{a}#{j}#{rng.rand(1..59)} #{b}" }
      texts << "#{rng.rand(1..30)}#{a}#{rng.rand(1..59)}#{b}"
    end
  end
  units.combination(3).each { |a, b, c| texts << "#{rng.rand(1..9)} #{LONG[a]} #{rng.rand(1..9)} #{LONG[b]} #{rng.rand(1..9)} #{LONG[c]}" }
  texts.push("0:30", "1:20", "12:34", "59:59", "1:02:03", "12:34:56", "1:20.5", "1:02:03.25", "100:00", "1:2",
             "2:04:13:02", "1 : 20", "1:2:3:4:5:6:7", "2 days, 4:13:02", "4 days 3:15", "1:30 hours")
  texts.push("about 3 hours", "in 5 minutes", "3 hours ago", "for 2 days", "2 hours approx", "Duration: 2 hours",
             "total: 1h 30m", "1h30m!", "~2h", "2 hours (est.)", "1 hour 30", "2 hours and 10", "half an hour",
             "half hour", "an hour and a half", "a day", "an hour", "a couple of days", "three quarters of an hour",
             "1/2 hour", "1 fortnight", "1 decade", "3 business days", "5 mins.", "1. 5 hours", "half145h", "5", "2.5",
             "0", "", "gobblygoo", "23 gobblygoos", "1 2 hours", "two and a half hours", "1 hour and 30 minutes",
             "4 days and 11 hours", "  4 days and 11     hours", "4m11.5s", "2.5 weeks plus", "5d", "40h", "1w",
             "1 hour plus 30 minutes", "about 5", "6:01:00:00", "6:01:00:00:00", "1:00:01:00:00:00", "100:00:00:00:00",
             "1:02:03:04.5", "2023:06:36:02")
  texts.uniq!
  cases = texts.map { ["parse", _1, {}] }
  cases.push(["parse", "5", { default_unit: "minutes" }], ["parse", "5", { default_unit: "hours" }],
             ["parse", "1.5", { default_unit: "days" }], ["parse", "0", { keep_zero: true }],
             ["parse", "gobblygoo", { keep_zero: true }], ["parse", "0 hours", { keep_zero: true }])
  %w[1d 1mo 1w 1y 2.5w].product([{ hours_per_day: 8 }, { days_per_month: 20 }, { days_per_month: 20, hours_per_day: 8 }]).each do |t, o|
    cases << ["parse", t, o]
  end
  cases + texts.map { ["parse", _1, { raise_exceptions: true }] }
end

SPEC_SECONDS = [80, 80.51, 80.51928, 14_461, 8400, 15_638_400, 31_644_000, 94_759_200, 46_656_000].freeze
FORMATS = %w[micro short default long chrono].freeze

def output_cases
  seconds = [0, 1, 59, 60, 61, 3599, 3600, 3661, 86_399, 86_400, 90_061, 604_800, 2_592_000, 2_678_400, 31_557_600,
             34_128_000, 34_164_000, 395 * 86_400 + 900, 1.5, 0.25, 3600.0, 12_345_678, 99_999_999] + SPEC_SECONDS
  options = [{}, { weeks: true }, { units: 2 }, { keep_zero: true }, { limit_to_hours: true }, { joiner: ", " },
             { hours_per_day: 8, days_per_month: 20 }, { weeks: true, hours_per_day: 8, days_per_month: 20 }]
  seconds.product(FORMATS, options).map { |s, f, o| ["output", s, { format: f, **o }] }
end

def run_gem(name, cases_path)
  version, lib, numerizer = GEMS.fetch(name)
  code = <<~RUBY
    gem "numerizer", #{numerizer.inspect}
    gem #{name.inspect}, #{version.inspect}
    require #{lib.inspect}
    require "json"
    JSON.parse(File.read(#{cases_path.inspect}), symbolize_names: true).each do |method, input, opts|
      opts[:format] = opts[:format].to_sym if opts[:format]
      ChronicDuration.raise_exceptions = opts.delete(:raise_exceptions) || false
      answer = begin
        ChronicDuration.public_send(method, input, opts)
      rescue StandardError => e
        { error: e.class.name }
      end
      puts JSON.generate(answer)
    end
  RUBY
  out, err, status = Open3.capture3(RbConfig.ruby, "-e", code)
  abort "#{name}: #{err}" unless status.success?
  out.lines.map { JSON.parse(_1) }
end

Dir.mktmpdir do |dir|
  cases = parse_cases + output_cases
  path = File.join(dir, "cases.json")
  File.write(path, JSON.generate(cases))
  upstream = run_gem("chronic_duration", path)
  gitlab = run_gem("gitlab_chronic_duration", path)
  File.write(FIXTURE, "#{cases.zip(upstream, gitlab).map { |c, a, b| JSON.generate([*c, a, b]) }.join("\n")}\n")
  puts "#{cases.size} cases recorded; the gems differ on #{upstream.zip(gitlab).count { _1 != _2 }}"
end
