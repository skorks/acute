require_relative "../test_helper"
require "prism"

# No path from parsed text to code loading, the filesystem or a shell: lib/ makes none of these calls outside the
# allow-list, each entry with its reason. A new use fails here until it is listed; a listed use that has gone fails too.
class DangerousCallsTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)
  EVALS = %i[eval instance_eval class_eval module_eval class_exec instance_exec module_exec binding].freeze
  SENDS = %i[send public_send __send__].freeze
  CONSTS = %i[const_get const_set const_source_location remove_const].freeze
  KERNEL = %i[open system exec spawn fork syscall load autoload gets readline readlines select trap].freeze
  REQUIRES = %i[require require_relative].freeze
  RECEIVERS = %w[Marshal YAML Psych File IO Dir Kernel Open3 Process FileUtils Pathname URI Net ObjectSpace].freeze
  GLOBALS = %i[$stdin $stdout $stderr STDIN STDOUT STDERR ARGF].freeze

  ALLOWED = {
    "acute/cli.rb: $stdin" => "the CLI's default input, given as an argument so tests pass their own; read a line at a time",
    "acute/cli.rb: $stdout" => "the CLI's default output stream",
    "acute/cli.rb: $stderr" => "the CLI's default error stream",
    "acute/context.rb: File.readlink" => "the system zone's name from the fixed /etc/localtime link, when TZ is unset",
    "acute/mcp.rb: File.expand_path" => "the bundled schema/ directory, from __dir__",
    "acute/mcp.rb: File.join" => "a bundled schema's path: a name from OUTPUTS or a $ref inside a bundled schema",
    "acute/mcp.rb: File.read" => "reads that bundled schema; no request field reaches the path",
    "acute/tool.rb: File.expand_path" => "the bundled tool schemas' paths, from __dir__ and the fixed NAMES",
    "acute/tool.rb: File.read" => "reads those bundled tool schemas once, at load"
  }.freeze

  class Finder < Prism::Visitor
    attr_reader :found

    def initialize(path)
      @path = path
      @found = []
      super()
    end

    def visit_call_node(node)
      name = node.name
      recv = node.receiver
      args = node.arguments&.arguments || []
      const = recv && const_name(recv)
      if RECEIVERS.include?(const) && !(const == "Process" && %i[clock_gettime pid].include?(name))
        hit("#{const}.#{name}", node)
      elsif EVALS.include?(name) && (name == :binding || !args.empty?)
        hit(name.to_s, node) unless %i[class_exec instance_exec module_exec].include?(name) && node.block
      elsif SENDS.include?(name) && !literal?(args.first)
        hit("#{name} with a computed name", node)
      elsif CONSTS.include?(name)
        hit(name.to_s, node)
      elsif KERNEL.include?(name) && (recv.nil? || const == "Kernel")
        hit(name.to_s, node)
      elsif REQUIRES.include?(name) && recv.nil? && !literal?(args.first)
        hit("#{name} of a computed path", node)
      end
      super
    end

    def visit_x_string_node(node) = hit("backticks", node) || super
    def visit_interpolated_x_string_node(node) = hit("backticks", node) || super
    def visit_global_variable_read_node(node) = (GLOBALS.include?(node.name) && hit(node.name.to_s, node)) || super
    def visit_constant_read_node(node) = (GLOBALS.include?(node.name) && hit(node.name.to_s, node)) || super

    private

    def hit(what, node)
      @found << [what, node.location.start_line]
      nil
    end

    def const_name(node)
      case node
      when Prism::ConstantReadNode then node.name.to_s
      when Prism::ConstantPathNode then node.parent.nil? || const_name(node.parent) == "Object" ? node.name.to_s : nil
      end
    end

    def literal?(arg) = arg.is_a?(Prism::SymbolNode) || arg.is_a?(Prism::StringNode)
  end

  def uses
    Dir[File.join(LIB, "**/*.rb")].flat_map do |path|
      result = Prism.parse_file(path)
      assert_predicate result, :success?, "#{path} doesn't parse"
      finder = Finder.new(path)
      result.value.accept(finder)
      rel = path.delete_prefix("#{LIB}/")
      finder.found.map { |what, line| ["#{rel}: #{what}", line] }
    end
  end

  def test_lib_makes_no_dangerous_call_outside_the_allow_list
    unlisted = uses.reject { |key, _| ALLOWED.key?(key) }.map { |key, line| "#{key} (line #{line})" }
    assert_empty unlisted, "dangerous calls in lib/; remove them, or list each in ALLOWED with its reason"
  end

  def test_every_allowed_use_is_still_made
    assert_empty ALLOWED.keys - uses.map(&:first), "stale ALLOWED entries"
  end

  def test_the_finder_catches_each_kind
    src = <<~RUBY
      eval(s); x.instance_eval(s); obj.send(m); obj.public_send(:ok); Object.const_get(n); Marshal.load(b)
      YAML.load(t); ::File.read(p); IO.popen(c); Dir.glob(g); open(u); system(c); `ls`; %x(ls \#{c}); spawn(c)
      require name; require "ok"; $stdin.read; Kernel.exec(c); x.instance_exec { 1 }
    RUBY
    finder = Finder.new("t.rb")
    Prism.parse(src).value.accept(finder)
    assert_equal ["eval", "instance_eval", "send with a computed name", "const_get", "Marshal.load", "YAML.load",
                  "File.read", "IO.popen", "Dir.glob", "open", "system", "backticks", "backticks", "spawn",
                  "require of a computed path", "$stdin", "Kernel.exec"], finder.found.map(&:first)
  end
end
