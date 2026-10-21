require "date"

module Acute
  # The holidays: option (D47): an object that answers holiday?(date) and named(name, year), or a region of the
  # holidays gem, which is loaded only then
  module Holidays
    def self.for(given)
      case given
      when Symbol, String, Array then Region.new(Array(given).map(&:to_sym))
      else
        unless given.respond_to?(:holiday?) && given.respond_to?(:named)
          raise OptionError.new("holidays: must be a holidays-gem region, or answer holiday?(date) and named(name, year)",
                                option: :holidays, value: given)
        end
        given
      end
    end

    class Region
      def initialize(regions)
        begin
          require "holidays" unless defined?(::Holidays)
        rescue LoadError
          raise OptionError.new("holidays: #{regions.join(", ")} is a region of the holidays gem, " \
                                "which is not installed", option: :holidays, value: regions)
        end
        @regions = regions
      end

      def holiday?(date) = !::Holidays.on(date, *@regions).empty?

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

    # Monday to Friday, less the holidays
    class Workdays
      def initialize(holidays)
        @holidays = holidays
      end

      def business_day?(date) = !date.saturday? && !date.sunday? && !@holidays.holiday?(date)
    end
  end
end
