require_relative "tables/zones"

module Acute
  # The regional conventions one locale sets (D27): numeric date order, week start, hemisphere and which
  # country's formula holidays apply. A hand table of the countries the corpus uses; D39 wants it
  # generated from CLDR.
  Locale = Struct.new(:country, :day_first, :week_start, :south)

  class Locale
    SUNDAY_WEEKS = Ractor.make_shareable(%w[US CA JP IN PK BR NP ZA PH MX IL KR TW HK]) # D19, D39
    MONTH_FIRST = Ractor.make_shareable(%w[US CA JP CN PH NP])                          # D10, D37
    SOUTH = Ractor.make_shareable(%w[AU NZ ZA BR AR CL UY PY BO PE])                    # D3

    def self.build(country) = new(country, !MONTH_FIRST.include?(country), SUNDAY_WEEKS.include?(country) ? 0 : 1,
                                  SOUTH.include?(country)).freeze

    # Built once at load, frozen and shareable, so any Ractor can read them
    ALL = Ractor.make_shareable(Tables::COUNTRIES.to_h { [_1, build(_1)] })
    US = ALL.fetch("US")

    TAG = /\A[a-z]{2,3}(?:[-_][a-z0-9]{2,8})*\z/i

    def self.for(code)
      unless (Symbol === code || (String === code && code.valid_encoding?)) && TAG.match?(code)
        raise OptionError.new("locale: must be a tag like en-US, en-GB or fr", option: :locale, value: code)
      end
      country = code.to_s.split(/[-_]/).last.upcase
      ALL[country] || build(country)
    end

    # tzdata lists a zone under every country that uses it (America/Toronto under BS and CA), and lists none
    # for a zone tzdata made a link (Europe/Oslo to Europe/Berlin); these are the zone's own country, from zone.tab
    SHARED = {
      "Africa/Abidjan" => "CI", "Africa/Johannesburg" => "ZA", "Africa/Lagos" => "NG", "Africa/Maputo" => "MZ",
      "Africa/Nairobi" => "KE", "America/Panama" => "PA", "America/Phoenix" => "US", "America/Puerto_Rico" => "PR",
      "America/Toronto" => "CA", "Asia/Bangkok" => "TH", "Asia/Dubai" => "AE", "Asia/Kuching" => "MY",
      "Asia/Qatar" => "QA", "Asia/Riyadh" => "SA", "Asia/Singapore" => "SG", "Asia/Tokyo" => "JP",
      "Asia/Yangon" => "MM", "Europe/Belgrade" => "RS", "Europe/Berlin" => "DE", "Europe/Brussels" => "BE",
      "Europe/Helsinki" => "FI", "Europe/Amsterdam" => "NL", "Europe/Copenhagen" => "DK", "Europe/Luxembourg" => "LU",
      "Europe/Monaco" => "MC", "Europe/Oslo" => "NO", "Europe/Stockholm" => "SE", "Europe/London" => "GB", "Europe/Paris" => "FR", "Europe/Prague" => "CZ",
      "Europe/Rome" => "IT", "Europe/Simferopol" => "UA", "Europe/Zurich" => "CH", "Indian/Maldives" => "MV",
      "Pacific/Auckland" => "NZ", "Pacific/Guadalcanal" => "SB", "Pacific/Guam" => "GU",
      "Pacific/Port_Moresby" => "PG", "Pacific/Tarawa" => "KI", "Pacific/Pago_Pago" => "AS"
    }.freeze

    # Zone name => its country's code
    ZONE_COUNTRIES = Ractor.make_shareable(Tables::ZONE_COUNTRIES.merge(SHARED))

    # D27: from the zone's country; UTC and zones with no country fall back to en-US
    def self.for_zone(name) = ALL[ZONE_COUNTRIES[name]] || US
  end
end
