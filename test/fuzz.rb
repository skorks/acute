# Random bytes and mutated corpus phrases. parse may only give a Result or nil, parse! a Result or a
# ParseError, and each must finish within LIMIT of CPU time (retried once after a full GC, so a GC pause doesn't count).
#   ruby test/fuzz.rb [--seed N] [--count N]
require_relative "corpus"

module Fuzz
  LIMIT = 0.001
  NOW = Time.utc(2026, 10, 17, 18)
  ALPHABET = ("a".."z").to_a + ("0".."9").to_a + [" ", ":", ".", ",", "@", "'", "-", "/", "\t", "é", " ", "\xff"].map(&:b)
  WORDS = %w[tomorrow today yesterday at noon midnight midday now am pm a.m. p.m. 4 12 16:30 09:30 4:30:15 tmrw]

  module_function

  def clock = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

  def random_text(rng)
    case rng.rand(4)
    when 0 then Array.new(rng.rand(0..24)) { rng.rand(256).chr }.join.b
    when 1 then Array.new(rng.rand(0..24)) { ALPHABET.sample(random: rng) }.join.force_encoding("UTF-8")
    when 2 then Array.new(rng.rand(1..6)) { WORDS.sample(random: rng) }.join(rng.rand(3).zero? ? "" : " ")
    else Array.new(rng.rand(0..700)) { ALPHABET.sample(random: rng) }.join.force_encoding("UTF-8")
    end
  end

  def mutate(text, rng)
    s = text.b
    case rng.rand(6)
    when 0 then s.slice!(rng.rand(s.size)) unless s.empty?
    when 1 then s.insert(rng.rand(s.size + 1), ALPHABET.sample(random: rng))
    when 2
      i = rng.rand([s.size - 1, 1].max)
      s[i], s[i + 1] = s[i + 1], s[i] if s.size > 1
    when 3 then s = s.swapcase
    when 4 then s = s.byteslice(0, rng.rand(s.size + 1))
    else s << " " << WORDS.sample(random: rng).b
    end
    s.force_encoding("UTF-8")
  end

  def check(text)
    problems = []
    2.times do |attempt|
      t0 = clock
      out = Acute.parse(text, now: NOW, zone: "America/New_York")
      t1 = clock
      begin
        out2 = Acute.parse!(text, now: NOW, zone: "America/New_York")
      rescue Acute::ParseError => e
        out2 = e
      rescue StandardError => e
        return ["parse! raised #{e.class}: #{e.message}"]
      end
      t2 = clock
      problems << "parse gave #{out.class}" unless out.nil? || Acute::Result === out
      problems << "parse! gave #{out2.class}" unless Acute::Result === out2 || Acute::ParseError === out2
      problems << "parse and parse! disagree" if out.nil? != (Acute::ParseError === out2)
      return problems unless problems.empty?
      slow = [t1 - t0, t2 - t1].max
      return [] if slow < LIMIT
      return [format("took %.2f ms", slow * 1000)] if attempt == 1
      GC.start # a major GC that marks the loaded corpus takes milliseconds; don't let it land in the retry
    end
  rescue StandardError => e
    ["parse raised #{e.class}: #{e.message}"]
  end

  def main(argv)
    seed = (i = argv.index("--seed")) ? Integer(argv[i + 1]) : Random.new_seed % 1_000_000
    count = (i = argv.index("--count")) ? Integer(argv[i + 1]) : 3000
    rng = Random.new(seed)
    phrases = Corpus.load.map { _1["text"] }
    inputs = Array.new(count) { random_text(rng) } + Array.new(count) { mutate(phrases.sample(random: rng), rng) }
    failures = inputs.filter_map { |text| (p = check(text)).empty? ? nil : "FUZZ #{text.inspect}: #{p.join("; ")}" }
    puts failures.first(20)
    puts "fuzz: #{inputs.size} inputs, seed #{seed}, #{failures.size} failures"
    failures.empty?
  end
end

exit(Fuzz.main(ARGV.dup)) if $PROGRAM_NAME == __FILE__
