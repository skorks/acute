require_relative "../test_helper"

# The docs are read on GitHub, so every relative link must reach a file in the repo, and an anchor a heading.
class DocsLinksTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PAGES = [File.join(ROOT, "README.md"), *Dir[File.join(ROOT, "docs/*.md")]].freeze

  def test_every_relative_link_resolves
    broken = PAGES.flat_map do |page|
      links(page).filter_map do |link|
        path, anchor = link.split("#", 2)
        target = path.empty? ? page : File.expand_path(path, File.dirname(page))
        next "#{rel(page)}: #{link}" unless File.exist?(target)
        next unless anchor && target.end_with?(".md")
        "#{rel(page)}: #{link}" unless anchors(target).include?(anchor)
      end
    end
    assert_empty broken
  end

  def test_the_pages_link_to_one_another
    assert_operator PAGES.size, :>=, 5
    PAGES.each { |page| refute_empty links(page), rel(page) }
  end

  private

  def rel(page) = page.delete_prefix("#{ROOT}/")

  def prose(page) = File.read(page).gsub(/^```.*?^```/m, "")

  def links(page) = prose(page).scan(/\]\(([^)\s]+)\)/).flatten.grep_v(/\A[a-z]+:/)

  # GitHub's slugs: lower case, punctuation dropped, spaces to hyphens, a repeat numbered
  def anchors(page)
    seen = Hash.new(-1)
    prose(page).scan(/^#+ (.+)$/).flatten.map do |heading|
      slug = heading.downcase.gsub(/[^\p{Word}\- ]/, "").tr(" ", "-")
      seen[slug] += 1
      seen[slug].zero? ? slug : "#{slug}-#{seen[slug]}"
    end
  end
end
