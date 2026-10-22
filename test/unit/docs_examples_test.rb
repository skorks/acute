require_relative "../test_helper"
require "stringio"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__)) # the docs require "acute", as a user would

# Runs the ```ruby blocks of the README and docs/ in order, one scope per page, and checks what each shows:
# "# => value" against the value's inspect, "puts x" against the "# " lines below it, and
# "# Some::Error: message" (with "#   e.code => ..." lines) against what the code above it raises.
# A block after a "<!-- no-doc-test -->" line is skipped.
class DocsExamplesTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PAGES = [File.join(ROOT, "README.md"), *Dir[File.join(ROOT, "docs/*.md")]].freeze
  BLOCK = /^(<!-- no-doc-test -->\n)?```ruby\n(.*?)^```/m
  SHOWN = /\A\s*# => (.+)$/
  INLINE = /\A(.*\S)\s+# => (.+)$/
  RAISED = /\A# ((?:\w+::)*\w+Error): (.+)$/
  FIELD = /e\.(\w+) => (.+?)(?=, e\.|$)/
  PUTS = /\Aputs\b/
  COMMENT = /\A# (?!=>)(.*)$/

  PAGES.each do |page|
    define_method("test_#{File.basename(page, ".md")}") { check_page(page) }
  end

  private

  def check_page(page)
    text = File.read(page)
    scope = Object.new.instance_eval { binding }
    failures = text.to_enum(:scan, BLOCK).flat_map do
      match = Regexp.last_match
      next [] if match[1]
      check(scope, match[2], "#{File.basename(page)}:#{text[0, match.begin(2)].count("\n") + 1}")
    end
    assert_empty failures
  end

  def check(scope, code, where)
    failures = []
    lines = code.lines
    pending = +""
    i = 0
    run = ->(src) { scope.eval(src, where) }
    expect = lambda do |shown, value|
      self.assertions += 1
      failures << "#{where}: shows #{shown.strip}, is #{value.inspect}" unless shown.strip == value.inspect
    end
    while i < lines.size
      line = lines[i]
      if (shown = line[SHOWN, 1])
        expect.(shown, run.(pending))
        pending = +""
      elsif (expr, shown = line.match(INLINE)&.captures) && !line.start_with?("#")
        expect.(shown, run.(pending + expr))
        pending = +""
      elsif (error, message = line.match(RAISED)&.captures)
        begin
          self.assertions += 1
          run.(pending)
          failures << "#{where}: shows #{error}, raised nothing"
        rescue StandardError => e
          failures << "#{where}: shows #{error}: #{message}, raised #{e.class}: #{e.message}" unless [e.class.name, e.message] == [error, message]
          while lines[i + 1]&.match?(/\A#\s+e\./)
            i += 1
            lines[i].scan(FIELD) { |field, value| expect.(value, e.public_send(field)) }
          end
        end
        pending = +""
      elsif line.match?(PUTS) && lines[i + 1]&.match?(COMMENT)
        printed = []
        printed << lines[i += 1][COMMENT, 1] while lines[i + 1]&.match?(COMMENT)
        self.assertions += 1
        out = capture { run.(pending + line) }
        failures << "#{where}: shows\n#{printed.join("\n")}\nprints\n#{out}" unless out.chomp == printed.join("\n")
        pending = +""
      else
        pending << line
      end
      i += 1
    end
    capture { run.(pending) } unless pending.strip.empty?
    failures
  rescue StandardError => e
    failures << "#{where}: #{e.class}: #{e.message}"
  end

  def capture
    $stdout, saved = StringIO.new, $stdout
    yield
    $stdout.string
  ensure
    $stdout = saved
  end
end
