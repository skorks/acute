module Acute
  class Tool
    # The model pays for every char of a result on every call, so a tool gives the library's JSON without what
    # repeats: the input's echo, a begin equal to time, a mention's kind and text again in its value, the expected
    # reading of a verdict that holds, now's offset, which the now string ends with, a rule's ical when it holds
    # only its dtstart and rrule, a rule's exdates, which ical's EXDATE line holds, whichever of cron and cron_reason
    # is null, and empty lists. An assumption's message is its short form, the gist in about half the chars. The
    # schema rules make the same cuts in the output schemas, so the two can't drift.
    # @api private
    module Compact
      def self.call(out)
        case out["kind"]
        when "time" then result(out)
        when "extraction"
          out.delete("text")
          out["mentions"].each do |m|
            m.delete("kind")
            case m["value"]["kind"]
            when "time" then result(m["value"])
            when "rule" then rule(m["value"])
            end
          end
        when "verdict"
          out.delete("text")
          if out["ok"] then out.delete("expected")
          elsif out["expected"] then result(out["expected"])
          end
        when "rule" then rule(out)
        when "now" then out.delete("offset")
        end
        out.delete("unread") if out["unread"] == []
        out
      end

      def self.result(r)
        r.delete("text")
        if r["assumptions"].empty? then r.delete("assumptions")
        else r["assumptions"].each { _1["message"] = Assumption.for(_1["code"].to_sym).short }
        end
        r.delete("alternatives") if r["alternatives"].empty?
        [r, *r["alternatives"]].each { _1.delete("begin") if _1["begin"] == _1["time"] }
      end
      private_class_method :result

      def self.rule(r)
        r.delete("text")
        r.delete("exdates")
        r.delete("ical") unless r["ical"].include?("\nEXDATE")
        r.delete(r["cron"] ? "cron_reason" : "cron")
      end
      private_class_method :rule

      # defs: the schemas tool's output schema holds, by file name, before they are inlined. The recurrence tool
      # adds a rule's first occurrences, and extract a count of the mentions past its cap.
      def self.schema(defs, tool)
        trim(defs["result"], drop: %w[text], optional: %w[begin assumptions alternatives])
        trim(defs.dig("result", "properties", "alternatives", "items"), optional: %w[begin])
        trim(defs["extraction"], drop: %w[text])
        trim(defs.dig("extraction", "properties", "mentions", "items"), drop: %w[kind])
        defs["extraction"]["properties"]["more"] = { "type" => "integer" } if defs["extraction"]
        trim(defs["verdict"], drop: %w[text], optional: %w[expected unread])
        if (rule = defs["rule"])
          trim(rule, drop: %w[text exdates], optional: %w[ical cron cron_reason])
          rule["properties"] = rule["properties"].merge("cron" => { "type" => "string" }, "cron_reason" => { "type" => "string" })
        end
        if tool == "recurrence"
          rule["properties"]["next"] = { "type" => "array", "items" => { "type" => "string" }, "maxItems" => OCCURRENCES }
          rule["required"] += ["next"]
        end
        trim(defs["now"], drop: %w[offset])
        trim(defs["failure"], drop: %w[text]) # T5: a tool never echoes its input
        defs
      end

      def self.trim(node, drop: [], optional: [])
        return unless node
        node["properties"] = node["properties"].except(*drop)
        node["required"] -= drop + optional
      end
      private_class_method :trim
    end
  end
end
