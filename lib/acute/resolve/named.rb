module Acute
  module Resolve
    # Named periods: parts of the day, weekends, seasons and holidays, each inside the period that holds one
    module Named
      DAY = Period::DAY
      PART_POINT = Assumption.for(:part_of_day_point)
      WEEKEND_FRIDAY = Assumption.for(:weekend_friday_evening)
      SEASON = Assumption.for(:meteorological_season)

      # D1, D35: start and end in seconds from the day's start, and the point
      PARTS = Ractor.make_shareable({
        morning: [6 * 3600, 12 * 3600, 9 * 3600], afternoon: [12 * 3600, 17 * 3600, 15 * 3600],
        evening: [17 * 3600, 21 * 3600, 19 * 3600], night: [21 * 3600, 28 * 3600, 22 * 3600],
        tonight: [17 * 3600, 28 * 3600, 22 * 3600], lunch: [12 * 3600, 14 * 3600, 12 * 3600 + 1800],
        early_hours: [0, 4 * 3600, 2 * 3600] # D42
      })
      # D3: meteorological, by the month each starts in; the south is six months on
      SEASONS = { spring: 3, summer: 6, autumn: 9, winter: 12 }.freeze
      # D15, D28: each built-in holiday as a formula. [month, day] is a fixed date; [month, day, wday] the first
      # wday on or after it (the third Monday of January is the first from the 15th); [holiday, days] an offset
      # from Easter or another holiday
      HOLIDAYS = Ractor.make_shareable({
        new_years_day: [1, 1], groundhog_day: [2, 2], valentines: [2, 14], st_patricks: [3, 17], april_fools: [4, 1],
        earth_day: [4, 22], flag_day: [6, 14], juneteenth: [6, 19], independence_day: [7, 4], patriot_day: [9, 11],
        bosses_day: [10, 16], halloween: [10, 31], veterans_day: [11, 11], christmas_eve: [12, 24],
        christmas: [12, 25], boxing_day: [12, 26], new_years_eve: [12, 31],
        mlk_day: [1, 15, 1], presidents_day: [2, 15, 1], mothers_day: [5, 8, 0], memorial_day: [5, 25, 1],
        fathers_day: [6, 15, 0], labor_day: [9, 1, 1], columbus_day: [10, 8, 1], thanksgiving: [11, 22, 4],
        us_thanksgiving: [11, 22, 4], black_friday: [:us_thanksgiving, 1], cyber_monday: [:us_thanksgiving, 4],
        easter: [:easter, 0], good_friday: [:easter, -2], easter_monday: [:easter, 1], palm_sunday: [:easter, -7],
        maundy_thursday: [:easter, -3], ash_wednesday: [:easter, -46], mardi_gras: [:easter, -47],
        pentecost: [:easter, 49], whit_monday: [:easter, 50], trinity_sunday: [:easter, 56],
        # D40, D48: the Tuesday after the first Monday; the Wednesday of April's last full week
        election_day: [11, 2, 2], admin_day: [4, 21, 3], grandparents_day: [:labor_day, 6],
        military_spouse_day: [:mothers_day, -2], lincolns_birthday: [2, 12], law_day: [5, 1], loyalty_day: [5, 1],
        may_day: [5, 1], workers_day: [5, 1], siblings_day: [4, 10], world_vegan_day: [11, 1], kwanzaa: [12, 26],
        ides_of_march: [3, 15]
      })
      # D48: a holiday of several days names its first, then all of them
      LASTS = { kwanzaa: 7 }.freeze
      # D15, D27: the holidays a country has its own way, or alone
      GB_IE = { mothers_day: [:easter, -21], mothering_sunday: [:easter, -21], may_day: [5, 1, 1] }.freeze
      LOCAL = Ractor.make_shareable({
        "CA" => { thanksgiving: [10, 8, 1], canada_day: [7, 1], victoria_day: [5, 18, 1], vimy_ridge_day: [4, 9] },
        "AU" => { australia_day: [1, 26], anzac_day: [4, 25], melbourne_cup: [11, 1, 2] },
        "NZ" => { anzac_day: [4, 25] }, "GB" => { **GB_IE, guy_fawkes: [11, 5] }, "IE" => GB_IE,
        "ZA" => { reconciliation_day: [12, 16], kruger_day: [10, 10] }, "PH" => { rizal_day: [12, 30] },
        "TT" => { indian_arrival_day: [5, 30] }, "BZ" => { garifuna_day: [11, 19] }
      })

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

      # D48: "labor day weekend": the weekend nearest the holiday, the one before from Monday to Wednesday, and the
      # holiday with it when it is a Monday or Friday
      def self.long_weekend(h, ctx)
        d = h.b / DAY
        wd = (d + 4) % 7
        sat = (d + (wd == 0 ? -1 : wd <= 3 ? -1 - wd : 6 - wd)) * DAY
        e = [sat + 2 * DAY, h.e].max
        return [Span.new(h.b, e, :weekend, nil)] if h.b < sat
        ctx.note(WEEKEND_FRIDAY)
        [Span.new(sat, e, :weekend, nil), Span.new(sat - 6 * 3600, e, :weekend, nil)]
      end

      # D3, D33: a season belongs to the year it starts in
      def self.season(name, year, ctx)
        m = SEASONS.fetch(name)
        m = (m + 5) % 12 + 1 if ctx.south
        ctx.note(SEASON)
        b = Period.civil(year, m, 1)
        Span.new(b, Period.add(b, 3, :month), :season, nil)
      end

      # D15, D28: the holiday in the year, or nil when the locale has none of that name. D47: a holidays: given
      # is asked first
      def self.holiday(name, year, ctx)
        if (given = ctx.holidays) && (date = given.named(name, year))
          d = date.jd - 2_440_588
          return Span.new(d * DAY, d * DAY + DAY, :day, nil)
        end
        f = (own = LOCAL[ctx.locale.country]) && own[name] || HOLIDAYS[name]
        return unless f
        d = day_of(f, year)
        Span.new(d * DAY, d * DAY + DAY, :day, nil)
      end

      def self.day_of(f, year)
        a, b, wday = f
        if Integer === a
          wday ? nth_weekday(Calendar.days_from_civil(year, a, b), wday, 1) : Calendar.days_from_civil(year, a, b)
        elsif a == :easter then Calendar.easter(year) + b
        else day_of(HOLIDAYS.fetch(a), year) + b
        end
      end

      # The day number of the nth wday on or after the day first
      def self.nth_weekday(first, wday, n) = first + (wday - (first + 4) % 7) % 7 + 7 * (n - 1) # (first + 4) % 7: its weekday
    end
  end
end
