# A fixed pure-Ruby workload that speed results are measured against, so a verdict doesn't depend on how busy
# the machine is: load (other processes, a shared core, a lower clock) slows this and a parse alike, and
# their ratio stays put. It does the same kinds of work as a parse: a byte loop, small method sends, hash
# lookups, case/===, Struct allocation and integer maths. Never change it: every recorded ratio depends on it.
module Reference
  Tok = Struct.new(:kind, :value)
  Box = Struct.new(:a, :b)
  WORDS = { 102 => :f, 116 => :t, 109 => :m, 110 => :n, 115 => :s, 119 => :w }.freeze
  TEXT = "next friday at 4:30pm, 2026-10-23 or so".b.freeze
  # One run's thread CPU time on a quiet core, by mode, to turn ratios back into µs. Measured 2026-10-18 on
  # Ruby 4.0.7: the step 5 spike, re-timed then at 3.3 µs (interp) and 1.13 µs (yjit) a phrase, is 0.655 and
  # 0.849 of a run. The 11.1 slice is 0.665 of a run on the interpreter.
  QUIET_NS = { "interp" => 5000.0, "yjit" => 1330.0 }.freeze

  module_function

  def mode = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "yjit" : "interp"

  def clock = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

  # [ratio, ns]: the block's cost relative to a run of the reference, and its absolute ns per call. The two
  # alternate in short rounds, so each pair runs on the same core under the same load, and the ratio is the
  # median of the rounds' ratios. Taking the fastest of each separately would pair a reference timed on a
  # fast core with a block timed on a slow one: this machine mixes both, and a process moves between them.
  def measure(rounds: 40, batch: 20)
    ratios = []
    best = Float::INFINITY
    rounds.times do
      t0 = clock
      i = 0
      while i < batch
        run
        i += 1
      end
      t1 = clock
      i = 0
      while i < batch
        yield
        i += 1
      end
      t2 = clock
      ratios << (t2 - t1) / (t1 - t0)
      best = t2 - t1 if t2 - t1 < best
    end
    [ratios.sort[rounds / 2], best / batch * 1e9]
  end

  # The block's cost in µs as on a quiet machine, from its ratio to the reference
  def quiet_us(ratio) = ratio * QUIET_NS.fetch(mode) / 1000

  def run
    toks = lex(TEXT)
    sum = 0
    toks.each { |t| sum += weigh(t) }
    days = 0
    k = 0
    while k < 12
      days += civil(2026, k + 1, 15) % 7
      k += 1
    end
    Box.new(sum, days)
  end

  def lex(s)
    out = []
    i = 0
    n = s.bytesize
    while i < n
      c = s.getbyte(i)
      if digit?(c)
        v = 0
        while i < n && digit?(c = s.getbyte(i))
          v = v * 10 + c - 48
          i += 1
        end
        out << Tok.new(:num, v)
      elsif (w = WORDS[c])
        out << Tok.new(:word, w)
        i += 1
      else
        i += 1
      end
    end
    out
  end

  def digit?(c) = c >= 48 && c <= 57

  def weigh(t)
    case t.value
    when Integer then t.value % 97
    when :f, :t then 3
    else 1
    end
  end

  def civil(y, m, d)
    y -= 1 if m <= 2
    era = y.div(400)
    yoe = y - era * 400
    doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
    era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
  end
end
