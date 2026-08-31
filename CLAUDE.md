# CLAUDE.md

See **[AGENTS.md](AGENTS.md)** — conventions, file layout, and the failure modes
specific to this repo live there, and that is the file to keep current.

Read it before changing any `.tf` file. The two rules most easily broken:

- There is **no default AWS provider**. Every resource, data source and module
  must set `provider = aws.network` or `provider = aws.workload` explicitly.
- **Do not edit `providers.tf`** or add `required_providers` entries.
