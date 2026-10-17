require_relative "tables/assumptions"

module Acute
  Assumption = Struct.new(:code, :rule, :message)

  class Assumption
    ALL = Tables::ASSUMPTIONS.to_h { |code, (rule, message)| [code, new(code, rule, message).freeze] }.freeze

    def self.for(code) = ALL.fetch(code)
  end
end
