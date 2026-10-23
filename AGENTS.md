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
- `zone.rb` unpacks each zone's offsets from the generated `tables/zones.rb` the first time it is used. `calendar.rb` holds integer day maths.
- `lib/acute/tables/*.rb` are **generated**. Edit `data/*.yml`, then run `bin/generate`.

## The one command

`bin/check` runs:
- tables up to date;
- lint: RuboCop with `.rubocop.yml`, which records why each house-style cop is off;
- unit tests;
- the corpus against the ratchet in `test/corpus/passing.txt`;
- chronic's own tests, against the differences in `test/chronic/differences.yml`;
- fuzz;
- coverage of `lib/` across the unit tests and the corpus, against the floor in `test/coverage.rb`;
- the gem: built, holding only `lib/`, `data/`, `schema/`, `exe/`, LICENSE, README.md, CHANGELOG.md and `docs/*.md`, then installed on its own and run;
- speed, on the interpreter and under YJIT (set `YJIT_RUBY` to a Ruby built with YJIT if the default one lacks it). A failing pass is re-run up to three passes in all and judged on their medians; `ACUTE_SPEED=report` prints the numbers without judging them, as CI does.

Options: `--only STAGE`, `--skip STAGE,STAGE`, `--grep TEXT` / `--file NAME` (corpus only), `--rule D20` (the cases and unit tests about one rule, plus the rules no case covers), `--record`.

Before a release, `bin/mutant [SUBJECT]` runs mutation testing (too slow for bin/check): a unit test class reaches mutant only through its `cover "Acute::Zone*"` line.

## Adding a phrase

1. Find its case in `test/cases/*.jsonl`, or add one. The format is in `test/cases/FORMAT.md`. `bin/case "phrase" --now ... --zone ...` appends acute's current answer to `test/cases/new.jsonl` as a starting point; correct it from the rules.
2. Run `bin/try "phrase" --now 2026-10-17T14:00 --zone America/New_York --trace`. It prints the tokens, the tree, the readings and the rules applied.
3. Fix it in the right place:
   - wrong tree → `grammar.rb`, or a word in `data/words.yml`;
   - right tree, wrong time → `resolve/`.
4. Tag each convention with its rule (`# D4`), and record an assumption from `data/assumptions.yml`. The rules are in `docs/rules.md`.
5. Run `bin/check`. A case that used to pass and now fails is a regression: fix it, or explain why the case is wrong.
6. Run `bin/check --record` to add the new passing ids to the ratchet.

## Compatibility layers

Never copy another library's code into acute. A layer for another gem's API (`acute/chronic`, `acute/chronic_duration`) answers through acute's own lexer, grammar and resolver. The original gem is only a test oracle: record its answers, and list each place acute differs, with the reason, as `test/chronic/differences.yml` does.

## Releasing

1. In a PR, bump `lib/acute/version.rb`, add the version to `CHANGELOG.md`, and move every schema's `$id` to the new tag (`schema_test.rb` checks they name `v` + `Acute::VERSION`): `sed -i 's|/acute/v[^/]*/schema/|/acute/vX.Y.Z/schema/|' schema/*.json schema/tools/*.json`. Merge it.
2. On an up-to-date main: `git tag -s vX.Y.Z -m vX.Y.Z`, then `git push origin vX.Y.Z`.
3. Approve the `release` run in GitHub once its `check` job passes. `.github/workflows/release.yml` runs `bin/check` in a job that can't publish; the approved job, with no bundle, checks the tag is `v` + `Acute::VERSION` on main, then builds, attests and pushes the gem by trusted publishing: no API key exists.
4. Don't rename `release.yml` or the `release` environment: the RubyGems trusted publisher matches both.
