# Records numerizer 0.2.0's answers to the inputs in test/numerizer/fixture.jsonl, by running the real gem in a
# separate process. Not part of bin/check: run it by hand with numerizer 0.2.0 installed (and 0.1.1, to compare):
#   ruby test/numerizer/record.rb
require "json"
require "open3"

ROOT = File.expand_path("../..", __dir__)
FIXTURE = File.join(ROOT, "test/numerizer/fixture.jsonl")
ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen
          seventeen eighteen nineteen].freeze
TENS = %w[_ _ twenty thirty forty fifty sixty seventy eighty ninety].freeze
FEW = %w[one two five].freeze
ORDINALS = { "one" => "first", "two" => "second", "three" => "third", "five" => "fifth", "eight" => "eighth",
             "nine" => "ninth", "twelve" => "twelfth" }.freeze

def spell(n, hyphen: "-", join: " and ")
  return ONES[n] if n < 20
  return TENS[n / 10] + (n % 10 > 0 ? hyphen + ONES[n % 10] : "") if n < 100
  if n < 1000
    return "#{ONES[n / 100]} hundred#{join + spell(n % 100, hyphen:, join:) if n % 100 > 0}"
  end
  big, name = [[10**9, "billion"], [10**6, "million"], [1000, "thousand"]].find { |v, _| n >= v }
  rest = n % big
  "#{spell(n / big, hyphen:, join:)} #{name}#{(rest < 100 ? join : " ") + spell(rest, hyphen:, join:) if rest > 0}"
end

def ordinal(word)
  return ORDINALS[word] if ORDINALS.key?(word)
  return word.sub(/y\z/, "ieth") if word.end_with?("y")
  "#{word}th"
end

def inputs
  rng = Random.new(20_261_023)
  list = []
  gem_tests = File.read(Dir[File.expand_path("~/.rbenv/versions/*/lib/ruby/gems/*/gems/numerizer-0.2.0/test/test_numerizer.rb")].first)
  list.concat(gem_tests.scan(/(?<=['"])[^'"\n]+(?=['"])/))
  Dir[File.join(ROOT, "test/cases/*.jsonl")].each do |f|
    File.foreach(f) { |l| (t = JSON.parse(l)["text"]) && list << t unless l.strip.empty? }
  end
  # every number to 120, then a sample: past that the words repeat
  [*0..120, *(121..999).step(9), 999, 1000].each do |n|
    list << spell(n) << spell(n, hyphen: " ", join: " ") << spell(n).upcase
  end
  list.push("0", "7", "42", "100", "1000", "2026")
  numbers = Array.new(80) { rng.rand(1000..1_000_000) } + [10**6, 10**9, 10**12, 2 * 10**9 + 7]
  numbers.each do |n|
    list << spell(n) << spell(n, hyphen: " ", join: " ") << spell(n, hyphen: "-", join: " ").capitalize
  end
  (1..99).each do |n|
    w = spell(n)
    ord = w.split(/(-)/).then do |p|
      p[-1] = ordinal(p[-1])
      p.join
    end
    list << ord << "the #{ord} of may" << "#{w} and a half"
    list << "a #{w}th" if n < 10 || n % 11 == 0
  end
  %w[half third fourth quarter fifth sixth seventh eighth nineth].each do |f|
    FEW.each do |n|
      list << "#{n} #{f}" << "#{n} #{f}s" << "a #{f}" << "#{n} and a #{f}" << "#{n} and #{ONES[2]} #{f}s" << "#{n}-#{f}"
      list << "#{n} 1/2 #{f}" << "3 and #{n} #{f}s hours"
    end
  end
  list.push("A hundred", "ONE HUNDRED AND FIVE", "  two   hundred ", "one\ttwo", "one\nhundred", "twenty  one",
            "thirty-one", "pre-war", "one-", "-one", "a", "a a", "", " ", "twentyone", "1 and 2", "100 and 5",
            "3 1/2", "3 and 1/2", "3-1/2", "2 hundred 3", "two hundred three thousand", "hundred", "and",
            "one two three", "five 5", "5 five", "forty-two-hundred", "ninteen", "fourty", "1st", "tenth 5",
            "a.m.", "ça va un", "one é two", "one million two", "10 thousand and 5 hundred")
  list.map { _1.dup.force_encoding("UTF-8") }.uniq
end

def run_gem(version, input_path)
  code = <<~RUBY
    gem "numerizer", #{version.inspect}
    require "numerizer"
    require "json"
    JSON.parse(File.read(#{input_path.inspect})).each { |s| puts JSON.generate(Numerizer.numerize(s)) }
  RUBY
  out, err, status = Open3.capture3(RbConfig.ruby, "-e", code)
  abort "numerizer #{version}: #{err}" unless status.success?
  out.lines.map { JSON.parse(_1) }
end

require "tmpdir"
Dir.mktmpdir do |dir|
  list = inputs
  path = File.join(dir, "in.json")
  File.write(path, JSON.generate(list))
  new = run_gem("0.2.0", path)
  File.write(FIXTURE, "#{list.zip(new).map { |i, o| JSON.generate([i, o]) }.join("\n")}\n")
  puts "#{list.size} inputs recorded"
  old = run_gem("0.1.1", path)
  diffs = list.zip(old, new).reject { |_, a, b| a == b }
  puts "0.1.1 differs from 0.2.0 on #{diffs.size}"
  diffs.first(10).each { |i, a, b| puts "  #{i.inspect}: 0.1.1 #{a.inspect}, 0.2.0 #{b.inspect}" }
end
