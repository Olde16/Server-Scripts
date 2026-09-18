# Server Scripts

A collection of small, practical scripts for Linux/Unix-like server environments.

The goal: useful server helpers that are configurable, documented, and reasonably conservative.

## Repository structure

- `Backups/` — SSH/rsync snapshot backups
- `API-Endpoints/` — API/endpoint related helpers

Each directory should contain its own README with requirements, configuration, usage, and limitations.

## General disclaimer

These scripts are provided as-is and without warranty. Depending on their purpose and configuration, they may perform privileged or destructive operations.

**Read the documentation and the script before running anything on a production system. Test first, keep independent recovery options, and verify restores/recovery procedures.**

No author or contributor assumes responsibility for data loss, downtime, security incidents, misconfiguration, or other damage resulting from use or modification, to the extent permitted by applicable law.

Some files may be created or modified with assistance from generative AI. AI assistance does not replace human review, testing, security review, or operational responsibility.

## License

Unless a file or directory explicitly states otherwise, this repository is released under the **GNU General Public License v3 or later**. See [LICENSE](LICENSE).

Individual scripts may contain their own GPL notice as recommended by the license.

## Contributing

Useful improvements, bug fixes, portability fixes, documentation, and new small server utilities are welcome.

Please keep scripts:

- configurable instead of hard-coded
- documented
- conservative with destructive operations
- explicit about requirements and privileges
- tested on a real target environment before being called production-ready
