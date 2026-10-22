# Stability

acute follows [semantic versioning](https://semver.org) from 1.0.0. `gem "acute", "~> 1.0"` takes every release this page lets through.

## What SemVer covers

- The public Ruby API, as [docs/usage.md lists it](usage.md#the-public-api).
- Failure codes.
- The tool names, and the tool and MCP input and output schemas in [schema/](../schema).
- The CLI's flags, its `--json` output and its exit codes ([docs/cli.md](cli.md)).

Changing or removing any of these needs a major release.

## Minor releases

- New failure codes, fields, kinds or options. Outputs are tolerant: ignore a field you don't know, and treat an unknown value as none of the known ones ([JSON](usage.md#json)).
- A fixed rule that changes a phrase's answer. The CHANGELOG always notes it, with the rule id from [docs/rules.md](rules.md).
- Dropping a Ruby version past its end of life.

## Patch releases

- Zone data (tzdata) updates.
- Bug fixes that change no documented answer.

## Outside SemVer

These may change in any release:

- the wording of messages and hints;
- the CLI's human-readable output;
- performance;
- everything marked `# @api private` in the source.

## Schema `$id`s

Each schema's `$id` names the release tag, `https://raw.githubusercontent.com/skorks/acute/v<VERSION>/schema/<name>.json`, so it moves with every release.
