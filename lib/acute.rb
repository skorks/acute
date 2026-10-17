require_relative "acute/version"
require_relative "acute/errors"
require_relative "acute/context"
require_relative "acute/lexer"
require_relative "acute/grammar"
require_relative "acute/resolve"
require_relative "acute/result"
require_relative "acute/explain"

module Acute
  MAX_LENGTH = 512

  def self.parse(text, now: nil, zone: nil, context: :future)
    out = run(text, Context.new(now, zone, context))
    Result === out ? out : nil
  end

  def self.parse!(text, now: nil, zone: nil, context: :future)
    out = run(text, Context.new(now, zone, context))
    raise Explain.error(out, text) if Failure === out
    out
  end

  def self.run(text, ctx)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    return Failure.new(:too_long, 0, text.bytesize) if text.bytesize > MAX_LENGTH && text.length > MAX_LENGTH
    tokens = Lexer.lex(text)
    return tokens if Failure === tokens
    tree = Grammar.parse(tokens)
    return tree if Failure === tree
    readings = Resolve.call(tree, ctx)
    Result.new(text, readings, ctx.zone, ctx.assumptions(readings[0]))
  end
  private_class_method :run
end
