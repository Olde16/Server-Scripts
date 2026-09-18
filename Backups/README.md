# Backups

Generic SSH/rsync snapshot backups for Linux servers.

## Requirements

- Bash
- rsync
- OpenSSH client
- flock
- GNU date

## Install

```bash
cp backup.conf.example backup.conf
nano backup.conf
chmod +x backup.sh
DRY_RUN=true ./backup.sh
./backup.sh
```

Use cron or a systemd timer for scheduled runs.

## How it works

The first successful run creates a full snapshot. Later runs use rsync with `--link-dest`, so unchanged files are hard-linked from the previous snapshot. Every snapshot remains directly browsable while using much less storage than independent copies.

A new checksum-based full snapshot is created after `FULL_EVERY_DAYS`.

The script also prevents concurrent runs, updates `latest` only after success, removes incomplete snapshots after failures, applies retention, and writes logs.

## Restore

Every timestamped directory is a usable snapshot:

```bash
rsync -a /srv/backups/example/2026-09-19_03-00-00/ /srv/restore/
```

Always perform real test restores. A backup that has never been restored should not be considered verified.

## Security

Use a dedicated, least-privileged SSH account where possible. Prefer SSH keys, restrict key and filesystem permissions, and keep backup storage separate from the source server.

The script does not encrypt backups.

## Disclaimer

This project is licensed under the GNU GPL v3 or later; see the repository `LICENSE`.

The script is provided without warranty and may delete data when misconfigured. Test before production use and maintain independent recovery options. No author or contributor assumes responsibility for data loss, downtime, security incidents, misconfiguration, or other damage, to the extent permitted by applicable law.

Parts of this project may be created or modified with generative AI assistance. AI assistance does not replace human review, testing, security review, or deployment responsibility.
