require_relative "errors"
require_relative "lexer"
require_relative "calendar"
require_relative "tables/words"

module Acute
  # Turns a Failure into a ParseError with a message, character positions and a hint. Only the error
  # path comes here, so it can afford to rescan the text.
  module Explain
    def self.error(failure, text)
      return ParseError.new("the text is not valid UTF-8", code: :invalid_encoding, position: 0...0) if failure.code == :invalid_encoding
      first = chars(text, failure.start)...chars(text, failure.stop)
      slice = text.byteslice(failure.start, failure.stop - failure.start)
      case failure.code
      when :unknown_word
        words = Lexer.unknown_ranges(text).map { |r| text.byteslice(r.begin, r.size) }
        hint = suggest(words.first)
        noun = words.size == 1 ? "word" : "words"
        ParseError.new("unknown #{noun} #{words.map(&:inspect).join(", ")}", code: :unknown_word, position: first,
                       unknown: words, hint: hint && "did you mean #{hint.inspect}?")
      when :invalid_date
        ParseError.new(invalid(text, failure) || "#{slice.inspect} is not a valid time", code: :invalid_date, position: first)
      when :incomplete
        ParseError.new("the phrase is incomplete", code: :incomplete, position: first)
      when :conflict
        ParseError.new("#{slice.inspect} doesn't fit with the rest of the phrase", code: :conflict, position: first)
      when :dst_skipped_time
        ParseError.new("#{slice.inspect} names a wall time the clocks skip as they go forward", code: failure.code,
                       position: first, hint: "dst: :earlier, :later or :compatible picks an instant for it")
      when :dst_repeated_time
        ParseError.new("#{slice.inspect} names a wall time that happens twice as the clocks go back",
                       code: failure.code, position: first, hint: "dst: :earlier or :later picks one")
      else
        ParseError.new("longer than #{MAX_LENGTH} bytes", code: :too_long, position: first)
      end
    end

    def self.chars(text, byte) = text.byteslice(0, byte).length

    L = Lexer
    MONTHS = %w[_ January February March April May June July August September October November December].freeze

    # D48: what is out of range in an invalid date or time ("June has 30 days"), or nil when it can't say
    def self.invalid(text, failure)
      all = Lexer.lex(text, []).each_slice(L::STRIDE).to_a
      t = all.select { |_, _, _, st, e| st >= failure.start && e <= failure.stop }
      mer = all[all.index(t.last) + 1]&.first == L::MER if t.any?
      month = day = year = nil
      nums = []
      t.each_with_index do |(k, v, f), i|
        case k
        when L::CLOCK
          hour = v / 10_000
          return "there is no hour #{hour} on a 12-hour clock" if mer && hour > 12 && hour < 24
          return clock(hour, v / 100 % 100, v % 100)
        when L::MONTH
          month = v
          day ||= [i > 0 && t[i - 1], t[i + 1]].find { |x| x && x[0] == L::NUM && x[2] & L::DIGITS <= 2 }&.at(1)
        when L::ORD then day = v
        when L::HOLIDAY then (month, day = 2, 29) if v == :leap_day
        when L::NUM
          case f & L::DIGITS
          when 4 then year = v
          when 1, 2 then nums << v
          else return nil
          end
        end
      end
      return "there is no hour #{nums[0]} on a 12-hour clock" if mer && t.size == 1 && nums[0].to_i > 12
      month, day = numeric(nums, year && t[0][1] == year) unless month
      return unless month && day && month.between?(1, 12) && day >= 1
      return "#{year} is not a leap year" if month == 2 && day == 29 && year && !Calendar.leap?(year)
      max = year ? Calendar.days_in_month(year, month) : month == 2 ? 29 : Calendar::MONTH_DAYS[month]
      return if day <= max
      return "February has 28 days, 29 in a leap year" if month == 2 && !year
      "#{MONTHS[month]}#{" #{year}" if month == 2} has #{max} days"
    end

    def self.clock(hour, min, sec)
      return "there is no hour #{hour}" if hour > 24 || (hour == 24 && min + sec > 0)
      return "there is no minute #{min}" if min > 59
      "there is no second #{sec}" if sec > 59
    end

    # A numeric date's month and day: year first, or the one order where only one number can be the month
    def self.numeric(nums, year_first)
      return unless nums.size == 2
      return nums if year_first
      a, b = nums
      if a <= 12 && b > 12 then [a, b]
      elsif b <= 12 && a > 12 then [b, a]
      end
    end

    def self.letters(bytes) = bytes.inject(0) { |m, c| m | 1 << (c & 63) }

    HINTS = Ractor.make_shareable(Tables::HINT_WORDS.map { |w| [w, w.bytes, letters(w.bytes)] })

    # The closest known word within two edits, if it is close enough to be a likely typo
    def self.suggest(word)
      return unless word&.ascii_only?
      a = word.downcase.bytes
      mask = letters(a)
      best = nil
      best_distance = 3
      HINTS.each do |candidate, b, m|
        next if (b.size - a.size).abs >= best_distance
        # each letter one word has and the other lacks costs an edit, so this bounds the distance from below
        next if (mask & ~m).to_s(2).count("1") >= best_distance || (m & ~mask).to_s(2).count("1") >= best_distance
        d = distance(a, b, best_distance)
        if d < best_distance && d < b.size / 2
          best = candidate
          best_distance = d
        end
      end
      best
    end

    # Optimal string alignment distance: Levenshtein plus adjacent transpositions, three rows at a time.
    # Gives up with limit once a whole row is at least limit, since the distance can only grow from there.
    def self.distance(a, b, limit = Float::INFINITY)
      before = nil
      prev = (0..b.size).to_a
      a.each_with_index do |ca, i|
        row = [i + 1]
        low = i + 1
        b.each_with_index do |cb, j|
          d = prev[j + 1] + 1
          d = row[j] + 1 if row[j] + 1 < d
          s = prev[j] + (ca == cb ? 0 : 1)
          d = s if s < d
          d = before[j - 1] + 1 if i > 0 && j > 0 && ca == b[j - 1] && a[i - 1] == cb && before[j - 1] + 1 < d
          row << d
          low = d if d < low
        end
        return limit if low >= limit
        before = prev
        prev = row
      end
      prev[b.size]
    end
  end
end
