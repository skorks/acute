module Acute
  module Resolve
    # Named periods: parts of the day, weekends, seasons and holidays, each inside the period that holds one
    module Named
      DAY = Period::DAY
      PART_POINT = Assumption.for(:part_of_day_point)
      WEEKEND_FRIDAY = Assumption.for(:weekend_friday_evening)
      SEASON = Assumption.for(:meteorological_season)

      # D1, D35: start and end in seconds from the day's start, and the point
      PARTS = {
        morning: [6 * 3600, 12 * 3600, 9 * 3600], afternoon: [12 * 3600, 17 * 3600, 15 * 3600],
        evening: [17 * 3600, 21 * 3600, 19 * 3600], night: [21 * 3600, 28 * 3600, 22 * 3600],
        tonight: [17 * 3600, 28 * 3600, 22 * 3600], lunch: [12 * 3600, 14 * 3600, 12 * 3600 + 1800],
        early_hours: [0, 4 * 3600, 2 * 3600] # D42
      }.freeze
      # D3: meteorological, by the month each starts in; the south is six months on
      SEASONS = { spring: 3, summer: 6, autumn: 9, winter: 12 }.freeze
      FIXED_HOLIDAYS = { christmas: 1225, christmas_eve: 1224, new_years_eve: 1231, new_years_day: 101,
                         halloween: 1031 }.freeze

      def self.part(name, day, ctx)
        b, e, point = PARTS.fetch(name)
        ctx.note(PART_POINT)
        Span.new(day * DAY + b, day * DAY + e, :hour, day * DAY + point)
      end

      # D8: Saturday 00:00 to Monday 00:00, then from Friday 18:00
      def self.weekends(week, ctx)
        sat = week.b + ((6 - ctx.week_start) % 7) * DAY
        ctx.note(WEEKEND_FRIDAY)
        [Span.new(sat, sat + 2 * DAY, :weekend, nil), Span.new(sat - 6 * 3600, sat + 2 * DAY, :weekend, nil)]
      end

      # D3, D33: a season belongs to the year it starts in
      def self.season(name, year, ctx)
        m = SEASONS.fetch(name)
        m = (m + 5) % 12 + 1 if ctx.south
        ctx.note(SEASON)
        b = Period.civil(year, m, 1)
        Span.new(b, Period.add(b, 3, :month), :season, nil)
      end

      # D15, D28: formula holidays for the locale
      def self.holiday(name, year, ctx)
        d = if (md = FIXED_HOLIDAYS[name])
              Calendar.days_from_civil(year, md / 100, md % 100)
            elsif ctx.locale.country == "CA" # name == :thanksgiving
              nth_weekday(Calendar.days_from_civil(year, 10, 1), 1, 2)
            else
              nth_weekday(Calendar.days_from_civil(year, 11, 1), 4, 4)
            end
        Span.new(d * DAY, d * DAY + DAY, :day, nil)
      end

      # The day number of the nth wday on or after the day first
      def self.nth_weekday(first, wday, n) = first + (wday - Calendar.weekday(first)) % 7 + 7 * (n - 1)
    end
  end
end
