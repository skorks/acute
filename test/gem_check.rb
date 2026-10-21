# Builds the gem and checks what ships: only the library, its data, schemas, the executable and the licence,
# and every tracked file of those. Then installs it on its own, outside the bundle, and runs it.
#   ruby test/gem_check.rb
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

module GemCheck
  ROOT = File.expand_path("..", __dir__)
  SHIPPED = ["lib/**/*.rb", "data/*.yml", "schema/**/*.json", "exe/*", "LICENSE"].freeze
  GEM = File.join(RbConfig::CONFIG["bindir"], "gem")

  module_function

  def run(env, *cmd)
    out, status = Open3.capture2e(env, *cmd, chdir: ROOT)
    [out, status.success?]
  end

  def shipped?(path) = SHIPPED.any? { File.fnmatch?(_1, path, File::FNM_PATHNAME) }

  def main
    problems = []
    Dir.mktmpdir("acute-gem") do |tmp|
      file = File.join(tmp, "acute.gem")
      out, ok = run({}, GEM, "build", "acute.gemspec", "--output", file)
      abort "gem build failed\n#{out}" unless ok

      contents = Gem::Package.new(file).contents
      tracked = run({}, "git", "ls-files", "-z").first.split("\0").select { shipped?(_1) }
      problems.concat(contents.reject { shipped?(_1) }.map { "ships #{_1}, which is not part of the library" })
      problems.concat((tracked - contents).map { "does not ship #{_1}" })

      # No other gem is installed beside it: acute has no runtime dependencies
      home = File.join(tmp, "home")
      env = { "GEM_HOME" => home, "GEM_PATH" => home }
      env.merge!(%w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP].to_h { [_1, nil] })
      out, ok = run(env, GEM, "install", "--local", "--no-document", file)
      abort "gem install failed\n#{out}" unless ok

      out, ok = run(env, RbConfig.ruby, "-e", 'require "acute"; print Acute.parse("noon", now: Time.utc(2026, 10, 17)).begin.hour')
      problems << "require \"acute\" from the installed gem failed: #{out}" unless ok && out == "12"
      zoned = 'Acute.parse!("tomorrow 3pm", now: "2026-10-17T14:00", zone: "America/New_York").iso8601'
      out, ok = run(env, RbConfig.ruby, "-W:no-experimental", "-e", <<~RUBY)
        require "acute"
        r = Ractor.new { #{zoned} }
        print #{zoned}, " ", r.respond_to?(:value) ? r.value : r.take, " ", defined?(TZInfo).inspect
      RUBY
      want = "2026-10-18T15:00:00-04:00 2026-10-18T15:00:00-04:00 nil"
      problems << "the installed gem's zones failed: #{out}" unless ok && out == want
      # the tool reads its input schemas from the gem's schema/tools/
      out, ok = run(env, RbConfig.ruby, "-e", 'require "acute/tool"; print Acute::Tool.new(zone: "UTC").definitions.size')
      problems << "require \"acute/tool\" from the installed gem failed: #{out}" unless ok && out == "6"
      out, ok = run(env, RbConfig.ruby, File.join(home, "bin/acute"), "--now", "2026-10-17T14:00", "--zone", "UTC", "tomorrow at 5pm")
      problems << "the installed acute executable failed: #{out}" unless ok && out.include?("5pm")
      hello = %({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}\n)
      out, status = Open3.capture2(env, RbConfig.ruby, File.join(home, "bin/acute"), "mcp", "--zone", "UTC", stdin_data: hello, chdir: ROOT)
      unless status.success? && out.lines.size == 1 && JSON.parse(out).dig("result", "serverInfo", "name") == "acute"
        problems << "the installed acute mcp failed: #{out}"
      end

      problems.each { puts _1 }
      puts "#{Gem::Package.new(file).spec.full_name}: #{contents.size} files, " \
           "installs, requires and runs#{" with #{problems.size} problems" unless problems.empty?}"
    end
    problems.empty?
  end
end

exit(GemCheck.main)
