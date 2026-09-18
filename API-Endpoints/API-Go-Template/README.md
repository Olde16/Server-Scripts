# API-Go-Template

A concrete Go REST API example used by the repository author.

This directory is intentionally **not** a generic database/API framework. The Go source files are kept as an example of a working server application and should be treated as such.

## Quick start

Requirements:

- Go
- MySQL
- a database matching the schema expected by `database.go` and the API code

From this directory:

```bash
go run .
```

To build a standalone binary:

```bash
go build -o api .
```

The exact database connection details and application behaviour are defined by the existing source code. **The source files are intentionally not modified just to make this example more generic.**

## What's included

- Go HTTP server
- JSON API endpoints
- authentication handling
- MySQL database access
- CRUD-style endpoints for the application's data model
- example data/query handlers

The files are split by responsibility so they can also serve as a reference when building a similar small Go API.

## Database

The application expects the database/schema used by the existing code.

The original database definition is documented below for convenience. It is application-specific and is **not** intended to be a universal database template.

```text
country
athletes
medals
sports
medals_athletes_sports
authorized_users
api_tokens
```

Before running the API against a real database, inspect `database.go` and the authentication code and make sure the connection and credentials are appropriate for your environment.

## Deployment

For a simple server deployment, build the binary and run it using your preferred process manager.

The author's existing setup uses systemd, but the Go application itself does not require systemd.

Example:

```bash
go build -o api .
./api
```

For production use, consider:

- running as a dedicated unprivileged user
- protecting database credentials
- putting the API behind TLS/reverse proxy infrastructure where appropriate
- restricting database permissions
- configuring a restart policy
- monitoring logs and process health

## Important

This example may contain assumptions specific to its original application and data model. It is provided primarily as a useful working example, not as a promise that it can be copied into an arbitrary server and work unchanged.

If you adapt it, review the authentication, database access, error handling, and exposed endpoints before deployment.

## License and disclaimer

This project is licensed under the GNU GPL v3 or later; see the repository `LICENSE`.

The code is provided without warranty. No author or contributor assumes responsibility for data loss, downtime, security incidents, misconfiguration, or other damage resulting from its use or modification, to the extent permitted by applicable law.

AI tools may be used during development of this repository, including for code and documentation. Before anything is published, I personally review and test the code. Particular attention is given to code quality, security, and reliable operation.
