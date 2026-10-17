# Proleptic Gregorian dates as day numbers (days since 1970-01-01), after Howard Hinnant's algorithms.
module Acute
  module Calendar
    MONTH_DAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

    def self.days_from_civil(y, m, d)
      y -= 1 if m <= 2
      era = y.div(400)
      yoe = y - era * 400
      doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
      doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
      era * 146_097 + doe - 719_468
    end

    # Packed as y * 10000 + m * 100 + d, so the hot path allocates no Array
    def self.civil_from_days(z)
      z += 719_468
      era = z.div(146_097)
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
  end
end
