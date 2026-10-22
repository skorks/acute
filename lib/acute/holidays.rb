require "date"

module Acute
  # The holidays: option (D47): an object that answers holiday?(date) and named(name, year), or a region of the
  # holidays gem, which is loaded only then
  # @api private
  module Holidays
    def self.for(given)
      case given
      when Symbol, String, Array then Region.new(Array(given).dup, given)
      else
        unless given.respond_to?(:holiday?) && given.respond_to?(:named)
          raise OptionError.new("holidays: must be a holidays-gem region, or answer holiday?(date) and named(name, year)",
                                option: :holidays, value: given)
        end
        given
      end
    end

    class Region
      NAME = /\A[a-z][a-z0-9_]*\z/i

      def initialize(regions, given)
        unless regions.any? && regions.all? { (Symbol === _1 || (String === _1 && _1.valid_encoding?)) && NAME.match?(_1) }
          raise OptionError.new("holidays: a region is a name like :us or :gb_eng", option: :holidays, value: given)
        end
        begin
          require "holidays" unless defined?(::Holidays)
        rescue LoadError
          raise OptionError.new("holidays: #{regions.join(", ")} is a region of the holidays gem, " \
                                "which is not installed", option: :holidays, value: given)
        end
        regions.map!(&:to_sym)
        if ::Holidays.respond_to?(:available_regions) && (unknown = regions - ::Holidays.available_regions).any?
          raise OptionError.new("holidays: unknown region #{unknown.join(", ")}", option: :holidays, value: given)
        end
        @regions = regions
      end

      def holiday?(date) = !::Holidays.on(date, *@regions).empty?

      # Its days in year y, as days since 1970
      def days_in(year) = ::Holidays.between(Date.new(year, 1, 1), Date.new(year, 12, 31), *@regions).map { _1[:date].jd - 2_440_588 }

      # The gem's names are English titles: "Christmas Day" is :christmas, "Thanksgiving" :thanksgiving
      def named(name, year)
        name = name.to_s
        found = ::Holidays.between(Date.new(year, 1, 1), Date.new(year, 12, 31), *@regions).find do |h|
          key = h[:name].downcase.delete("'.,").gsub(/[^a-z0-9]+/, "_")
          key == name || key == "#{name}_day"
        end
        found && found[:date]
      end
    end

    def self.workdays(holidays) = Region === holidays ? RegionDays.new(holidays) : Workdays.new(holidays)

    # Monday to Friday, less a holidays-gem region's days, counted rather than stepped through, with the region
    # asked once a year (T17). It is made for one call, so its cache is never shared.
    class RegionDays
      def initialize(region)
        @region = region
        @years = {}
      end

      # The day n business days from day d: n weekdays on, then one more for each holiday passed, until none is
      def add(d, n)
        to = Calendar.add_weekdays(d, n)
        k = n > 0 ? off(d + 1, to + 1) : off(to, d)
        while k > 0
          from = to
          to = Calendar.add_weekdays(from, n > 0 ? k : -k)
          k = n > 0 ? off(from + 1, to + 1) : off(to, from)
        end
        to
      end

      private

      # The holidays from Monday to Friday, from day lo up to but not including hi
      def off(lo, hi)
        (Calendar.year_of(lo)..Calendar.year_of(hi - 1)).sum do |y|
          (@years[y] ||= @region.days_in(y).reject { (_1 + 4) % 7 % 6 == 0 }.uniq).count { lo <= _1 && _1 < hi }
        end
      end
    end

    # Monday to Friday, less the holidays
    class Workdays
      def initialize(holidays)
        @holidays = holidays
      end

      def business_day?(date) = !date.saturday? && !date.sunday? && !@holidays.holiday?(date)
    end
  end
end
