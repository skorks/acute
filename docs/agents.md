# acute for agents

Use this page to let an LLM hand date phrases to acute instead of working out dates itself. acute offers itself as seven tools. `Acute::Tool` gives them to an app that calls a model through an SDK; `acute mcp` serves the same tools to any MCP client. Both take their names, descriptions and argument schemas from [schema/tools/](../schema/tools).

Said on Saturday 17 October 2026 at 14:00 in New York:

```ruby
require "acute/tool"
tool = Acute::Tool.new(now: "2026-10-17T14:00", zone: "America/New_York")
tool.call("verify", { "text" => "next friday at noon", "value" => "2026-10-24T12:00" })
# => {"kind" => "verdict", "status" => "mismatch", "ok" => false, "message" => "The text is Fri 23 Oct, 12pm, not Sat 24 Oct, 12pm.", "expected" => {"kind" => "time", "time" => "2026-10-23T12:00:00-04:00", "end" => "2026-10-23T12:01:00-04:00", "grain" => "minute", "zone" => "America/New_York"}}
```

## The tools

| Tool | Arguments ([schema/tools/](../schema/tools)) | Returns |
|---|---|---|
| `parse` | `text`, `context` | [result.json](../schema/result.json) |
| `duration` | `text` | [duration.json](../schema/duration.json) |
| `recurrence` | `text` | [rule.json](../schema/rule.json), plus `next`: its first three occurrences |
| `extract` | `text`, `context` | [extraction.json](../schema/extraction.json) |
| `verify` | `text`, `value`, `context` | [verdict.json](../schema/verdict.json) |
| `describe` | `value`, `style` | [description.json](../schema/description.json) |
| `now` | none | [now.json](../schema/now.json) |

Any of them may instead return a [failure](../schema/failure.json).

`recurrence`'s `next` is the rule's first three occurrences, from `dtstart` on, as ISO 8601 times, or dates for a rule of whole days. A rule that ends sooner lists fewer. `cron`, when the rule has one, runs in the wall time of `zone` (`CRON_TZ`).

## Compact results

The tools return the hashes described in [schema/](../schema), with what repeats left out, since the model pays for every char of a result on every call. A result leaves out the input's `text` (on a parse, extract or verify result, a mention's value and a verdict's `expected`); a `begin` equal to `time`; a mention's `kind`, which its value's `kind` repeats; a verdict's `expected` when `ok` is true; `now`'s `offset`, which the `now` string ends with; a rule's `ical` unless it has an EXDATE, since `dtstart` and `rrule` hold the rest, and whichever of `cron` and `cron_reason` is null; and `assumptions`, `alternatives` and `unread` when they're empty, a failure's `unread` included. An assumption's `message` is its short form, `short` in [data/assumptions.yml](../data/assumptions.yml): the gist in about 50 chars rather than 80. The library's own JSON keeps them all, and the long messages.

## Failures and `unread`

A tool never raises on what the model sends. Wrong arguments, or text acute can't read, come back as `{kind: "failure", code, error, unread}`. `error` is acute's own words and never quotes the input: text from the arguments could carry instructions, so the words a failure points at go in `unread`, which every tool's description marks as user data. This holds for every `error`, `message` and `description` acute writes, including the MCP server's JSON-RPC errors.

## In an app: `Acute::Tool`

<!-- no-doc-test -->
```ruby
require "acute/tool"
tool = Acute::Tool.new(zone: user.zone, locale: user.locale)
tool.definitions(:anthropic)          # or :openai
tool.call(name, arguments)            # arguments as the SDK hands them: a Hash or OpenAI's JSON string
```

The app fixes every option at construction, with the same keywords as `Acute.with`. The input schemas leave them out, so the model can set neither the zone nor the time: an argument named `zone` or `now` is an `unknown_argument` failure. `prefix:` namespaces the tool names, such as `prefix: "dates_"`.

### RubyLLM

`require "acute/tool/ruby_llm"` adds `tool.ruby_llm`, one `RubyLLM::Tool` per tool. ruby_llm isn't a dependency of acute: add `gem "ruby_llm"` to your Gemfile. Without it the require fails with

```
acute/tool/ruby_llm needs the ruby_llm gem; add it to your Gemfile (cannot load such file -- ruby_llm) (LoadError)
```

Build the tool per user or per request, with their zone:

<!-- no-doc-test -->
```ruby
require "acute/tool/ruby_llm"

tool = Acute::Tool.new(zone: current_user.time_zone)  # or Acute::Tool.new(Acute.with(zone: current_user.time_zone, locale: "en-GB"))
chat = RubyLLM.chat
chat.with_tools(*tool.ruby_llm)
chat.ask("Move my dentist appointment to the second monday of may at 3pm")
```

It's per user because the app, not the model, fixes the zone and now: the schemas give the model no way to set them, so every answer is in the zone the tool was built with.

An app that already has a tool called `parse` can rename acute's with `prefix:`: `Acute::Tool.new(zone: current_user.time_zone, prefix: "dates_")` gives the chat `dates_parse`, `dates_extract`, `dates_now` and so on.

Each call hands the model the compact hash [described above](#compact-results). A failure is a value too, never an exception, so ruby_llm passes it back and the model can correct its arguments and try again ([Failures and `unread`](#failures-and-unread)).

One caveat: when the model calls a tool name the chat doesn't have, ruby_llm answers, not acute, with ``Model tried to call unavailable tool `<name>`. Available tools: [...]``. That message quotes the name the model sent, and acute can't change it.

## Over MCP: `acute mcp`

```
$ claude mcp add acute -- acute mcp --zone America/New_York
```

`acute mcp` reads one JSON-RPC message per line on stdin and writes one per line on stdout, and exits when stdin closes. It speaks MCP 2026-07-28 to a client whose requests carry `_meta`, and 2025-11-25 or 2025-06-18 to one that opens with `initialize`.

| Option | Sets |
|---|---|
| `--zone ZONE` | the zone when a call names none (default: the system's) |
| `--locale LOCALE` | how numeric dates read, such as en-GB (default: from the zone) |
| `--context future\|past` | the default way a phrase that could point either way points |
| `--week-start sunday\|monday` | the first day of a week |

Zone and now differ from the library. The person at the other end of an MCP client may be anywhere, so every tool but `duration` takes an optional `zone`, and an invalid one is an `invalid_argument` failure. `now` is always the server's clock: no option or argument sets it.

Each tool's result is `structuredContent`, with a JSON copy in `content`. A failure is a result with `isError: true`. Since a failure is a structured result too, each tool's `outputSchema` is a `oneOf` of its own schema and the failure schema, self-contained so a client resolves it without fetching: a schema referred to once is written in place and one referred to more than once goes under `$defs`. It describes the result as the tool gives it, with the fields above left out or optional, and keeps the structure the result must conform to and drops the descriptions, which the model would pay for on every listing; [schema/](../schema) has them. An unknown tool, method or malformed request is a JSON-RPC error instead; a line over 64 KiB is refused and the server carries on.

## Security

- **The user's words.** No `error`, `message` or `description` quotes the arguments. The user's words come back in two fields only: a failure's `unread` (at most 5 items of 60 chars) and an extraction's `remainder`. Each tool's description tells the model they are user data, never instructions. The output schemas say so too, but a client may not show those to the model.
- **Limits.** `text` is at most 512 chars and 512 bytes, or 4096 chars for `extract`; `value` is at most 64 chars. A call counts at most 10,000 business days in all, across every count in it; past that a count fails with `business_day_limit`, and in `extract` that mention is not a time. Over MCP, a line over 64 KiB and a batch are refused, an `id` must be a string or an integer, JSON nested more than 100 deep is a parse error, and an internal error is -32603 with nothing of the input.
- **Zone and now.** Through `Acute::Tool`, only the app sets them. Over MCP the model may pass `zone`, which must be an IANA name or a UTC offset of at most 64 chars; anything else is an `invalid_argument` failure that shows it only in `unread`. `now` is always the server's clock.
