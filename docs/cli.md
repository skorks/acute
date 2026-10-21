# The acute command

```
$ acute --zone America/New_York "next friday 3pm"
Fri, Oct 23, 3pm EDT

$ acute --json < phrases.txt    # one JSON line per phrase
```

`acute PHRASE` prints the reading in describe's calendar style, with the zone's abbreviation, then any alternatives as "(also: …)". A duration prints as "1h 30m". With no phrase, it reads one phrase per line from stdin and prints exactly one line for each. A failure prints `error: <reason>`; with `--json`, a JSON line `{"kind":"error",...}`. The JSON of a reading is that of `to_json`: [schema/result.json](../schema/result.json) or [schema/duration.json](../schema/duration.json).

Exit codes: 0 when everything parsed, 1 when a phrase failed, 2 for bad options.

## Options

The options are those of [the library](usage.md#options), with dashes:

| Option | Sets |
|---|---|
| `--json` | print JSON (JSON Lines for stdin) |
| `--now TIME` | now, in ISO 8601 (default: the clock) |
| `--zone ZONE` | an IANA zone or offset (default: the system's) |
| `--locale LOCALE` | en-US, en-GB, en-AU… (default: from the zone) |
| `--context CONTEXT` | future or past |
| `--week-start DAY` | sunday or monday |
| `--hemisphere SIDE` | north or south, for seasons |
| `--fiscal-year-start MONTH` | 1–12 |
| `--lenient` | skip unknown words (`strict: false`) |
| `--dst POLICY` | compatible, earlier, later or reject |
| `--holidays REGION` | a holidays-gem region, such as us (needs the gem) |
| `--year-bias YEARS` | two-digit years: the 100 from this many years ago (default 50) |
| `-v`, `--version` | the version |
| `-h`, `--help` | the usage |

## acute mcp

`acute mcp [options]` serves acute's tools to an MCP client over stdio, one JSON-RPC message per line. It takes `--zone`, `--locale`, `--context` and `--week-start`; see [agents.md](agents.md#over-mcp-acute-mcp).
