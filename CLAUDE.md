# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

PowerShell scripts that exercise the Veeam Backup & Replication (VBR) Configuration Management REST API (`/api/v1/automation/*`) to export a VBR server's configuration (credentials, managed servers, repositories, proxies, jobs) and import it into a different VBR server. Used as working documents for testing the export/import flow — not a production tool.

**Known limitation (per `MigrateJobsToNewServer.ps1`):** only VMware backup jobs are supported by the underlying REST API.

## Running the scripts

Scripts are written for Windows PowerShell and shell out to `curl.exe` from Git for Windows at the hardcoded path `C:\Program Files\Git\mingw64\bin\curl.exe`. They are not portable to PowerShell Core / non-Windows without changing that path.

- `JobExport.ps1` — calls `/export` endpoints on the source server (hardcoded `https://backup-v11:9419`), writes responses to `*.json` files in the repo root. Most `Out-File` calls are commented; only `JobExport.json` is currently written by default. Uncomment the others to refresh `CredExport.json`, `managedservers.json`, `repos.json`, `proxies.json`.
- `JobImport.ps1` — reads the `*.json` files, calls `/import` endpoints on the target server (hardcoded `https://devbox:9419`), and polls each returned session via `/api/v1/automation/sessions/{id}` until `state != "Working"`. Order is fixed: creds → managed servers → repos → proxies → jobs (each depends on the prior).
- `MigrateJobsToNewServer.ps1` — incomplete consolidation that parameterizes source/target servers via `Get-Credential`. Only the export region is sketched in; do not assume it runs end-to-end.

There is no build step, no test suite, and no linter configured.

## Architecture notes that aren't obvious from one file

**Auth flow.** Every request needs an OAuth2 bearer token obtained by POSTing `grant_type=password&username=...&password=...` to `/api/oauth2/token`. Token is captured once at script start (`$token = $t.access_token`) and reused via the `Authorization: Bearer <token>` header. `--insecure` is passed to curl because the test servers use self-signed certs.

**API versioning is inconsistent across endpoints.** Both `1.0-rev1` and `1.0-rev2` headers appear within the same script; the import script uses `1.0-rev1` for creds/managed-servers and `1.0-rev2` for repos/proxies/jobs. Don't normalize these without checking that the target VBR build accepts the version you pick.

**JSON body escaping in curl args.** PowerShell builds the curl argument array with literal backslash-escaped quotes — e.g. `'-d', '{\"names\":[]}'` — because the body is parsed by curl, not PowerShell. When editing requests, preserve the `\"` escaping.

**`*.json` files are exported as UTF-16 with BOM** (PowerShell `Out-File` default). The import script does `Get-Content $file; $x.Replace('"', "'")` to swap double quotes for single quotes before sending — this is the workaround for sending the JSON inline as a `-d` arg without further escaping. If you regenerate the export files with different encoding, the import flow may break.

**Manual edits required between export and import** (documented in script headers):
1. Credential passwords come back blank from `/export` and must be filled in before `/import`.
2. Repository `mountServer.mountServerName` references the source VBR host and must be retargeted if the destination server has a different name.
3. Default repositories/proxies on the target should be removed before import to avoid name collisions.

**Session polling.** Import endpoints return `{ id, ... }` for an async session. `WaitForComplete` in `JobImport.ps1` polls every 5s; on `result.result == "Failed"` it pops a `[System.Windows.MessageBox]` (WPF dependency — assumes the script runs interactively on Windows desktop, not a headless agent).

## JSON exports are runtime artifacts — never commit them

`CredExport.json`, `JobExport.json`, `managedservers.json`, `repos.json`, `proxies.json` are produced by `JobExport.ps1` from a live VBR server and contain credentials, hostnames, IPs, and cert thumbprints. They are listed in `.gitignore` and must stay there. (Earlier commits accidentally tracked these — see git history; treat any credentials from those commits as compromised.) Gitleaks runs on push via `.github/workflows/security.yml`.

## CI

`.github/workflows/security.yml` reuses two reusable workflows from `adamcongdon/.github`: `gitleaks-scan.yml` and `semgrep-scan.yml`. Triggered on push/PR to main/master/dev, weekly cron, and manual dispatch. No PowerShell-specific linting.
