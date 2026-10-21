# acute for agents

acute offers itself to an LLM as six tools. `Acute::Tool` gives them to an app that calls a model through an SDK; `acute mcp` serves the same tools to any MCP client. Both take their names, descriptions and argument schemas from [schema/tools/](../schema/tools), and both return the hashes described in [schema/](../schema), with what repeats left out, since the model pays for every char of a result on every call. A result leaves out the input's `text` (on a parse, extract or verify result, a mention's value and a verdict's `expected`); a `begin` equal to `time`; a mention's `kind`, which its value's `kind` repeats; a verdict's `expected` when `ok` is true; `now`'s `offset`, which the `now` string ends with; and `assumptions`, `alternatives` and `unread` when they're empty, a failure's `unread` included. An assumption's `message` is its short form, `short` in [data/assumptions.yml](../data/assumptions.yml): the gist in about 50 chars rather than 80. The library's own JSON keeps them all, and the long messages.

## The tools

| Tool | Arguments ([schema/tools/](../schema/tools)) | Returns |
|---|---|---|
| `parse` | `text`, `context` | [result.json](../schema/result.json) |
| `duration` | `text` | [duration.json](../schema/duration.json) |
| `extract` | `text`, `context` | [extraction.json](../schema/extraction.json) |
| `verify` | `text`, `value`, `context` | [verdict.json](../schema/verdict.json) |
| `describe` | `value`, `style` | [description.json](../schema/description.json) |
| `now` | none | [now.json](../schema/now.json) |

Any of them may instead return a [failure](../schema/failure.json).

## Failures and `unread`

A tool never raises on what the model sends. Wrong arguments, or text acute can't read, come back as `{kind: "failure", code, error, unread}`. `error` is acute's own words and never quotes the input: text from the arguments could carry instructions, so the words a failure points at go in `unread`, which every tool's description marks as user data. This holds for every `error`, `message` and `description` acute writes, including the MCP server's JSON-RPC errors.

## In an app: `Acute::Tool`

```ruby
require "acute/tool"
tool = Acute::Tool.new(zone: user.zone, locale: user.locale)
tool.definitions(:anthropic)          # or :openai
tool.call(name, arguments)            # arguments as the SDK hands them: a Hash or OpenAI's JSON string
```

The app fixes every option at construction, with the same keywords as `Acute.with`. The input schemas leave them out, so the model can set neither the zone nor the time: an argument named `zone` or `now` is an `unknown_argument` failure. `prefix:` namespaces the tool names, such as `prefix: "dates_"`.

`require "acute/tool/ruby_llm"` adds `tool.ruby_llm`, one RubyLLM tool per tool: `chat.with_tools(*tool.ruby_llm)`.

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
- **Limits.** `text` is at most 512 chars and 512 bytes, or 4096 chars for `extract`; `value` is at most 64 chars. A business-day count past 10,000 is a failure. Over MCP, a line over 64 KiB and a batch are refused, an `id` must be a string or an integer, JSON nested more than 100 deep is a parse error, and an internal error is -32603 with nothing of the input.
- **Zone and now.** Through `Acute::Tool`, only the app sets them. Over MCP the model may pass `zone`, which must be an IANA name or a UTC offset of at most 64 chars; anything else is an `invalid_argument` failure that shows it only in `unread`. `now` is always the server's clock.
