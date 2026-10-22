require_relative "tables/assumptions"

module Acute
  # A rule a parse applied: frozen and Ractor-shareable
  Assumption = Data.define(:code, :rule, :message, :short)

  class Assumption
    # @api private
    ALL = Tables::ASSUMPTIONS.to_h { |code, (rule, message, short)| [code, new(code, rule, message, short)] }.freeze

    def self.for(code) = ALL.fetch(code)
  end
end
