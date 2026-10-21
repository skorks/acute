require_relative "tables/assumptions"

module Acute
  Assumption = Struct.new(:code, :rule, :message, :short)

  class Assumption
    ALL = Tables::ASSUMPTIONS.to_h { |code, (rule, message, short)| [code, new(code, rule, message, short).freeze] }.freeze

    def self.for(code) = ALL.fetch(code)
  end
end
