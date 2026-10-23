require_relative "../test_helper"

# Never copy another library's code into acute (AGENTS.md, "Compatibility layers"). A file under lib/, data/ or schema/
# that carries another project's copyright or licence notice, or says it was ported, copied or adapted from somewhere,
# fails here.
class NoForeignCodeTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DIRS = %w[lib data schema].freeze
  OWN = /Alan Skorkin/
  NOTICES = [
    /Copyright\s*(\(c\)|©)/i,
    /Permission is hereby granted/i,
    /Licensed under/i,
    /SPDX-License-Identifier/i,
    /\b(ported|copied|adapted) from\b/i
  ].freeze

  ALLOWED = {}.freeze

  def offences
    DIRS.flat_map { |dir| Dir[File.join(ROOT, dir, "**/*")] }.select { |path| File.file?(path) }.flat_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      File.foreach(path, encoding: "UTF-8").each_with_index.filter_map do |line, i|
        next if line.match?(OWN) || NOTICES.none? { |re| line.match?(re) }

        [rel, i + 1, line.strip[0, 80]]
      end
    end
  end

  def test_no_file_holds_another_projects_notice_or_a_ported_from_line
    found = offences.reject { |rel, _, _| ALLOWED.key?(rel) }.map { |rel, n, text| "#{rel}:#{n}: #{text}" }
    assert_empty found, "foreign copyright or 'ported from' lines; acute writes its own code (AGENTS.md)"
  end

  def test_every_allowed_file_still_has_an_offence
    assert_empty ALLOWED.keys - offences.map(&:first), "stale ALLOWED entries"
  end
end
