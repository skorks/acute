require_relative "../test_helper"
require "open3"
require "rbconfig"

# A layer marks the real gem's features loaded, so a later `require "chronic"` doesn't replace it (D46). Each case
# runs in a subprocess, so the real gem's constants don't reach the other tests.
class ShadowTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)

  def run_ruby(code, gem_name: nil)
    gem_lib = gem_name && Gem::Specification.find_by_name(gem_name).full_require_paths
    args = [RbConfig.ruby, "-I", LIB, *Array(gem_lib).flat_map { |dir| ["-I", dir] }, "-e", code]
    out, err, status = Open3.capture3(*args)
    assert_predicate status, :success?, err
    [out.strip, err]
  end

  def test_later_require_of_chronic_keeps_acutes_parse
    out, err = run_ruby(<<~RUBY, gem_name: "chronic")
      require "acute/chronic"
      p require("chronic")
      puts Chronic.method(:parse).source_location.first
      puts Chronic::VERSION
    RUBY
    assert_equal "false", out.lines.first.strip
    assert_includes out, "acute/chronic.rb"
    assert_empty err
  end

  def test_later_require_without_the_gem_is_not_an_error
    out, = run_ruby(<<~RUBY)
      require "acute/chronic"
      p require("chronic")
    RUBY
    assert_equal "false", out
  end

  def test_real_gem_first_warns_once
    _, err = run_ruby(<<~RUBY, gem_name: "chronic")
      require "chronic"
      require "acute/chronic"
      require "acute/chronic"
    RUBY
    assert_equal 1, err.lines.grep(/\Aacute:/).count
    assert_match(%r{chronic gem was loaded before acute/chronic.*require acute/chronic first, or drop}, err)
  end

  # The real gem defines Chronic::Time, which a bare Time in the layer would find before Ruby's.
  def test_real_gem_first_still_parses
    out, = run_ruby(<<~RUBY, gem_name: "chronic")
      require "chronic"
      require "acute/chronic"
      p Chronic.parse("tomorrow 3pm", now: Time.new(2026, 10, 17, 14, 0, 0, "-04:00")).class
      puts Chronic.method(:parse).source_location.first
    RUBY
    assert_equal "Time", out.lines.first.strip
    assert_includes out, "acute/chronic.rb"
  end

  # GitLab's fork loads as "gitlab-chronic", which Bundler requires for `gem "gitlab-chronic"`.
  def test_later_require_of_gitlab_chronic_is_a_no_op
    out, = run_ruby(<<~RUBY)
      require "acute/chronic"
      p require("gitlab-chronic")
    RUBY
    assert_equal "false", out
  end

  def test_chronic_duration_names_and_gitlab_fork
    %w[chronic_duration gitlab_chronic_duration].each do |name|
      out, err = run_ruby(<<~RUBY, gem_name: name)
        require "acute/chronic_duration"
        p require("chronic_duration")
        p require("gitlab_chronic_duration")
        puts ChronicDuration.method(:parse).source_location.first
      RUBY
      assert_equal %w[false false], out.lines.first(2).map(&:strip), name
      assert_includes out, "acute/chronic_duration.rb"
      assert_empty err
    end
  end

  def test_real_chronic_duration_first_warns
    _, err = run_ruby(%(require "chronic_duration"; require "acute/chronic_duration"), gem_name: "chronic_duration")
    assert_match(%r{chronic_duration gem was loaded before acute/chronic_duration}, err)
  end

  def test_numerizer
    out, err = run_ruby(<<~RUBY, gem_name: "numerizer")
      require "acute/numerizer"
      p require("numerizer")
      puts Numerizer.method(:numerize).source_location.first
    RUBY
    assert_equal "false", out.lines.first.strip
    assert_includes out, "acute/numerizer.rb"
    assert_empty err

    _, err = run_ruby(%(require "numerizer"; require "acute/numerizer"), gem_name: "numerizer")
    assert_match(%r{numerizer gem was loaded before acute/numerizer}, err)
  end
end
