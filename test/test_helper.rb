require "minitest/autorun"
require_relative "../lib/acute"

module Helpers
  NY = "America/New_York".freeze

  # Saturday 17 October 2026, 2pm in New York
  def parse(text, now: "2026-10-17T14:00", zone: NY, **opts) = Acute.parse!(text, now: now, zone: zone, **opts)

  def wall(t) = t.strftime("%F %T %:z")

  def codes(result) = result.assumptions.map(&:code)

  def alt_walls(result) = result.alternatives.map { |r| wall(r.begin) }

  # Ractor#value is Ruby 4.0's; before it, Ractor#take
  def ractor_value(ractor) = ractor.respond_to?(:value) ? ractor.value : ractor.take
end

Minitest::Test.include(Helpers)
