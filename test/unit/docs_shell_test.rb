require_relative "../test_helper"
require "shellwords"
require "stringio"
require_relative "../../lib/acute/cli"

# Runs every "$ acute ..." line in the README's and docs/' plain ``` blocks, and checks that what it prints
# (stdout, then stderr) is the lines below it, up to a blank line or the next "$". A line with no output
# below it, or one that reads a file, shows usage only. A block after a "<!-- no-doc-test -->" line is skipped.
class DocsShellTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PAGES = [File.join(ROOT, "README.md"), *Dir[File.join(ROOT, "docs/*.md")]].freeze
  BLOCK = /^(<!-- no-doc-test -->\n)?```(\w*)\n(.*?)^```$/m # every block, so a closing fence never opens one
  COMMAND = /\A\$ acute (.*)$/

  PAGES.each do |page|
    define_method("test_#{File.basename(page, ".md")}") { check_page(page) }
  end

  private

  def check_page(page)
    text = File.read(page)
    failures = text.to_enum(:scan, BLOCK).flat_map do
      match = Regexp.last_match
      next [] if match[1] || !match[2].empty?
      check(match[3], "#{File.basename(page)}:#{text[0, match.begin(3)].count("\n") + 1}")
    end
    assert_empty failures
  end

  def check(code, where)
    lines = code.lines(chomp: true)
    lines.each_with_index.filter_map do |line, i|
      command = line[COMMAND, 1] or next
      shown = lines[(i + 1)..].take_while { !_1.strip.empty? && !_1.start_with?("$ ") }
      next if shown.empty? || command.include?("<")
      self.assertions += 1
      printed = acute(Shellwords.split(command))
      "#{where}: $ acute #{command}\nshows\n#{shown.join("\n")}\nprints\n#{printed}" unless printed == shown.join("\n")
    end
  end

  def acute(argv)
    out, err = StringIO.new, StringIO.new
    Acute::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err)
    (out.string + err.string).chomp
  end
end
