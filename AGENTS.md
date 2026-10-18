# acute

A natural-language date and time parser for Ruby, the successor to chronic.

## How a phrase is parsed

```
text ──lex──▶ tokens ──grammar──▶ tree ──resolve(ctx)──▶ readings ──▶ Result
```

| Stage | File | Knows | Doesn't know |
|---|---|---|---|
| lex | `lib/acute/lexer.rb` | bytes, the word table | meaning, now |
| grammar | `lib/acute/grammar.rb`, `grammar/*.rb` | what was said: atoms (Clock, Date, Weekday, Unit, Holiday…) nested by size into Within, Range, Open, Shift… | now, the zone, D-rules |
| resolve | `lib/acute/resolve/*.rb` | every D-rule, now, the zone | text |
| result | `lib/acute/result.rb` | the public output | grammar |

- Failures are values (`Acute::Failure`), not exceptions. Only `parse!` turns them into a `ParseError`, through `lib/acute/explain.rb`.
- `context.rb` holds now, the zone chain and direction. It also collects the assumptions a parse makes.
- `zone.rb` holds offset tables built once from tzinfo. `calendar.rb` holds integer day maths.
- `lib/acute/tables/*.rb` are **generated**. Edit `data/*.yml`, then run `bin/generate`.

## The one command

`bin/check` runs:
- tables up to date;
- unit tests;
- the corpus against the ratchet in `test/corpus/passing.txt`;
- fuzz;
- speed, on the interpreter and under YJIT (set `YJIT_RUBY` to a Ruby built with YJIT if the default one lacks it).

Options: `--only STAGE`, `--grep TEXT` / `--file NAME` (corpus only), `--rule D20` (the cases and unit tests about one rule, plus the rules no case covers), `--record`.

## Adding a phrase

1. Find its case in `test/cases/*.jsonl`, or add one. The format is in `test/cases/FORMAT.md`. `bin/case "phrase" --now ... --zone ...` appends acute's current answer to `test/cases/new.jsonl` as a starting point; correct it from the rules.
2. Run `bin/try "phrase" --now 2026-10-17T14:00 --zone America/New_York --trace`. It prints the tokens, the tree, the readings and the rules applied.
3. Fix it in the right place:
   - wrong tree → `grammar.rb`, or a word in `data/words.yml`;
   - right tree, wrong time → `resolve/`.
4. Tag each convention with its rule (`# D4`), and record an assumption from `data/assumptions.yml`. The rules are in `docs/rules.md`.
5. Run `bin/check`. A case that used to pass and now fails is a regression: fix it, or explain why the case is wrong.
6. Run `bin/check --record` to add the new passing ids to the ratchet.
