module Acute
  # A compatibility layer stands in for a gem. It marks the gem's features loaded, so a later `require "chronic"`
  # (ransack_chronic and chronic_between do) is a no-op, and warns when the real gem was loaded first.
  module Shadow
    LIB = File.expand_path("..", __dir__)

    # Ruby finds a loaded feature as a $LOAD_PATH entry plus the name, so the path recorded is acute's own lib
    # directory (on $LOAD_PATH whenever `require "acute/..."` worked) plus the gem's feature name.
    def self.call(layer, gem, *features)
      real = features.flat_map { |f| $LOADED_FEATURES.grep(%r{/#{Regexp.escape(f)}\.rb\z}) }
                     .reject { |path| path.start_with?("#{LIB}/") }
      unless real.empty?
        warn "acute: the #{gem} gem was loaded before #{layer}, so acute's methods override it; " \
             "require #{layer} first, or drop the #{gem} gem"
      end
      features.each do |feature|
        path = File.join(LIB, "#{feature}.rb")
        $LOADED_FEATURES << path unless $LOADED_FEATURES.include?(path)
      end
    end
  end
end
