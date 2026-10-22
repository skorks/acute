require_relative "../test_helper"
require "yaml"

# T35: the job that can mint the OIDC token must never run code from the development gems
class WorkflowsTest < Minitest::Test
  RELEASE = YAML.safe_load_file(File.expand_path("../../.github/workflows/release.yml", __dir__))

  def publisher = RELEASE["jobs"].values.find { |job| job["environment"] == "release" }

  def test_workflow_level_permissions_are_empty
    assert_equal({}, RELEASE["permissions"])
  end

  def test_only_the_release_environment_job_may_mint_the_oidc_token
    assert publisher
    tokens = RELEASE["jobs"].select { |_, job| job.dig("permissions", "id-token") == "write" }
    assert_equal [publisher], tokens.values
  end

  def test_the_publishing_job_runs_no_bundle_and_no_bin_check
    commands = publisher["steps"].filter_map { |step| step["run"] }
    refute_empty commands
    commands.each { |cmd| refute_match(%r{\bbundle\b|bin/check}, cmd) }
  end

  def test_the_publishing_job_waits_for_the_check_job
    check = RELEASE["jobs"].find { |_, job| job["steps"].any? { |s| s["run"].to_s.include?("bin/check") } }&.first
    assert check
    assert_includes Array(publisher["needs"]), check
  end
end
