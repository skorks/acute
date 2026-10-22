# Proleptic Gregorian dates as day numbers (days since 1970-01-01), after Howard Hinnant's algorithms.
module Acute
  # @api private
  module Calendar
    MONTH_DAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

    def self.days_from_civil(y, m, d)
      y -= 1 if m <= 2
      era = y / 400
      yoe = y - era * 400
      doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
      doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
      era * 146_097 + doe - 719_468
    end

    # The day number of January 1st of year y
    def self.year_start(y)
      y -= 1
      365 * y + y / 4 - y / 100 + y / 400 - 719_162
    end

    # The year whose January 1st is day d, or nil when d is no January 1st. The guess counts average years
    # to the year's middle, which is exact for every January 1st.
    def self.year_if_first(d)
      y = (d + 719_344) * 400 / 146_097
      y + 1 if 365 * y + y / 4 - y / 100 + y / 400 - 719_162 == d
    end

    # The year holding day d. The guess counts average years from year 1 and is the year or the one before.
    def self.year_of(d)
      y = (d + 719_162) * 400 / 146_097 + 1
      365 * y + y / 4 - y / 100 + y / 400 - 719_162 <= d ? y + 1 : y
    end

    # D17: the day n (not 0) Mondays to Fridays after day d, or before it when n is negative. A weekend counts from the
    # Friday before it going forward, and the Monday after it going back.
    def self.add_weekdays(d, n)
      m = (d + 3) % 7 # Monday 0 to Sunday 6
      if n > 0
        d -= m - 4 if m > 4
        r = n % 5
        d + n / 5 * 7 + r + ((m > 4 ? 4 : m) + r > 4 ? 2 : 0)
      else
        n = -n
        d += 7 - m if m > 4
        r = n % 5
        d - n / 5 * 7 - r - ((m > 4 ? 0 : m) < r ? 2 : 0)
      end
    end

    # Packed as y * 10000 + m * 100 + d, so the hot path allocates no Array
    def self.civil_from_days(z)
      z += 719_468
      era = z / 146_097
      doe = z - era * 146_097
      yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
      y = yoe + era * 400
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
      mp = (5 * doy + 2) / 153
      d = doy - (153 * mp + 2) / 5 + 1
      m = mp < 10 ? mp + 3 : mp - 9
      y += 1 if m <= 2
      y * 10_000 + m * 100 + d
    end

    def self.leap?(y) = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0

    def self.days_in_month(y, m) = m == 2 && leap?(y) ? 29 : MONTH_DAYS[m]

    # 0 = Sunday
    def self.weekday(days) = (days + 4) % 7

    # The Monday that starts ISO week 1 of year y: the week holding January 4th
    def self.iso_week_one(y)
      jan4 = days_from_civil(y, 1, 4)
      jan4 - (jan4 + 3) % 7
    end

    # The day number of Western Easter Sunday, by the anonymous Gregorian algorithm (Meeus, Jones, Butcher)
    def self.easter(y)
      a = y % 19
      b = y / 100
      c = y % 100
      h = (19 * a + b - b / 4 - (b - (b + 8) / 25 + 1) / 3 + 15) % 30
      l = (32 + 2 * (b % 4) + 2 * (c / 4) - h - c % 4) % 7
      m = (a + 11 * h + 22 * l) / 451
      n = h + l - 7 * m + 114
      days_from_civil(y, n / 31, n % 31 + 1)
    end
  end
end
