require_relative "../test_helper"
require "open3"
require "tmpdir"
require_relative "../corpus"

class ToolsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def record(*args, to:)
    out, status = Open3.capture2e(RbConfig.ruby, File.join(ROOT, "bin/case"), *args, "--to", to)
    assert_predicate status, :success?, out
    JSON.parse(out)
  end

  def test_case_records_acutes_answer_as_a_passing_case
    begin
      TZInfo::DataSources::ZoneinfoDataSource.new
    rescue TZInfo::DataSources::ZoneinfoDirectoryNotFound
      skip "bin/case checks against the system zoneinfo, which this system lacks"
    end
    Dir.mktmpdir do |dir|
      to = File.join(dir, "new.jsonl")
      first = record("at 9", "--now", "2026-10-17T14:00", to: to)
      fold = record("2026-11-01 01:30 EST", to: to)
      none = record("last friday", "--context", "past", to: to)
      assert_equal(%w[new-0001 new-0002 new-0003], [first, fold, none].map { _1["id"] })
      assert_equal 2, first["expect"]["alternatives"].size
      assert_equal "2026-11-01T01:30:00-05:00", fold["expect"]["time"]
      assert_equal({ "context" => "past" }, none["options"])
      File.foreach(to) { |line| assert_equal "pass", Corpus.run_case(JSON.parse(line))[0], line }
    end
  end

  def test_rules_of_a_case_come_from_its_tags_and_note
    c = { "tags" => %w[D5 year], "note" => "a year (D5), not D20 or D2's" }
    assert_equal %w[D5 D20 D2], Corpus.rules(c)
  end
end
