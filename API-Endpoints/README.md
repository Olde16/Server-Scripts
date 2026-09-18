# API Endpoints

Small API/server examples and templates.

The folders here are intentionally allowed to contain **real, working examples** rather than artificially generic frameworks. If a script is useful as-is, it should stay useful as-is.

## Available examples

### API-Go-Template

A complete Go REST API example using `net/http` and MySQL.

This is a concrete example application, not a drop-in generic framework. It is kept close to the version actually used by the repository author.

[Open API-Go-Template](./API-Go-Template/)

## General rule for examples

Examples in this directory should be runnable with as little configuration as reasonably possible.

That does **not** mean removing application-specific code just to make an example look generic. If an example depends on a specific database schema, API, data model, or service setup, the README should explain that dependency instead.

## Requirements

Every example should document:

- required runtime/toolchain
- external services such as databases
- required configuration
- how to run it locally
- how to build/deploy
- important security considerations

## Disclaimer

These examples are provided as-is and without warranty. Read and understand the code before deploying it to a production server.

No author or contributor assumes responsibility for data loss, downtime, security incidents, misconfiguration, or other damage resulting from use or modification, to the extent permitted by applicable law.

AI tools may be used during development of this repository, including for code and documentation. Before anything is published, I personally review and test the code. Particular attention is given to code quality, security, and reliable operation.

The repository is licensed under the GNU GPL v3 or later unless a file states otherwise.
