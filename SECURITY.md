# Security

## Reporting a vulnerability

Please report it privately through GitHub's private vulnerability reporting:
https://github.com/skorks/acute/security/advisories/new

Please don't open a public issue for a vulnerability.

## Supported versions

Only the latest release is supported.

## What to expect

You will get an acknowledgement of your report. Once the problem is confirmed, a fix is released and a security advisory is published.

## What acute guarantees

- Parsing never reads files, runs commands or loads code because of its input. A failure is a value; only the `!` methods raise.
- Each call's cost is bounded: `parse` reads at most 512 bytes, and `next`, `between` and `each` stop at fixed budgets. `extract` reads text of any length in time linear in it, so cap what you pass it.
- Messages and the CLI escape control and format characters, and quote only the start of a long value.
- The gem has no runtime dependencies. It is published from GitHub by trusted publishing, with a build attestation, by a job that runs no development gems.
