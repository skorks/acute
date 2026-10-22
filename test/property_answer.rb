# One answer per [kind, text, now, zone], for test/unit/properties_test.rb to compare between this process and
# children with other TZ and locale settings. As a script it reads those as JSON lines on stdin.
require "json"
require "time"
require_relative "../lib/acute"

module PropertyAnswer
  # The text comes tagged as a read from a file or stdin would tag it: US-ASCII under LC_ALL=C
  def self.of(kind, text, now, zone)
    text = text.dup.force_encoding(Encoding.default_external)
    if kind == "rule"
      rule = Acute.recurrence(text, now: now, zone: zone) or return nil
      [rule.to_ical, rule.next(5, after: Time.iso8601("#{now}Z"))&.map(&:iso8601)]
    else
      Acute.parse(text, now: now, zone: zone)&.to_h
    end
  end
end

$stdin.binmode.each_line { |line| puts JSON.generate(PropertyAnswer.of(*JSON.parse(line.force_encoding(Encoding::UTF_8)))) } if $PROGRAM_NAME == __FILE__
