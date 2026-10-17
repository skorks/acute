require "tzinfo"

module Acute
  # The regional conventions one locale sets (D27): numeric date order, week start, hemisphere and which
  # country's formula holidays apply. A hand table of the countries the corpus uses; D39 wants it
  # generated from CLDR.
  Locale = Struct.new(:country, :day_first, :week_start, :south)

  class Locale
    SUNDAY_WEEKS = %w[US CA JP IN PK BR NP ZA PH MX IL KR TW HK].freeze  # D19, D39
    MONTH_FIRST = %w[US CA JP CN PH NP].freeze                             # D10, D37
    SOUTH = %w[AU NZ ZA BR AR CL UY PY BO PE].freeze                      # D3
    CACHE = {}
    ZONES = {}
    LOCK = Mutex.new

    def self.for(code)
      country = code.to_s.split(/[-_]/).last.upcase
      CACHE[country] || LOCK.synchronize do
        CACHE[country] ||= new(country, !MONTH_FIRST.include?(country), SUNDAY_WEEKS.include?(country) ? 0 : 1,
                               SOUTH.include?(country)).freeze
      end
    end

    US = self.for("US")

    # D27: from the zone's country; UTC and zones with no country fall back to en-US
    def self.for_zone(name)
      ZONES[name] || begin
        locale = (country = zone_countries[name]) ? self.for(country) : US
        LOCK.synchronize { ZONES[name] ||= locale }
      end
    end

    # tzinfo lists a zone under every country that uses it (America/Toronto under BS and CA); these are the
    # zone's own country, from zone.tab
    SHARED = {
      "Africa/Abidjan" => "CI", "Africa/Johannesburg" => "ZA", "Africa/Lagos" => "NG", "Africa/Maputo" => "MZ",
      "Africa/Nairobi" => "KE", "America/Panama" => "PA", "America/Phoenix" => "US", "America/Puerto_Rico" => "PR",
      "America/Toronto" => "CA", "Asia/Bangkok" => "TH", "Asia/Dubai" => "AE", "Asia/Kuching" => "MY",
      "Asia/Qatar" => "QA", "Asia/Riyadh" => "SA", "Asia/Singapore" => "SG", "Asia/Tokyo" => "JP",
      "Asia/Yangon" => "MM", "Europe/Belgrade" => "RS", "Europe/Berlin" => "DE", "Europe/Brussels" => "BE",
      "Europe/Helsinki" => "FI", "Europe/London" => "GB", "Europe/Paris" => "FR", "Europe/Prague" => "CZ",
      "Europe/Rome" => "IT", "Europe/Simferopol" => "UA", "Europe/Zurich" => "CH", "Indian/Maldives" => "MV",
      "Pacific/Auckland" => "NZ", "Pacific/Guadalcanal" => "SB", "Pacific/Guam" => "GU",
      "Pacific/Port_Moresby" => "PG", "Pacific/Tarawa" => "KI", "Pacific/Pago_Pago" => "AS"
    }.freeze

    def self.zone_countries
      @zone_countries || LOCK.synchronize do
        @zone_countries ||= TZInfo::Country.all.each_with_object(SHARED.dup) do |c, h|
          c.zone_identifiers.each { |z| h[z] ||= c.code }
        end.freeze
      end
    end
  end
end
