# VBR-REST-Job-Import-export

Cross-platform PowerShell module that migrates **VMware vSphere primary backup jobs** between Veeam Backup & Replication v13 servers via the Automation REST API tag (`x-api-version: 1.3-rev1`, port `9419`).

This repository previously held a set of curl-based working-document scripts targeting VBR v11. They have been removed -- see `Plans/upgrade-plan.md` for the rewrite rationale and section 7 (Risk R6) for the deletion decision.

The replacement is a single, fully-tested PowerShell 7 module: **`VbrAutomationMigrate`**.

---

## Hard limit (read this first)

The Veeam VBR Automation REST API tag -- even at v13 / `1.3-rev1` -- **only supports VMware vSphere primary backup jobs**. Every other job category is silently dropped at export time, and importing them is not possible because the API has no representation for them.

**Unsupported (not a bug -- API limitation):**

- Backup Copy jobs
- Hyper-V backup jobs
- Agent (Windows / Linux / Mac) backup jobs
- NAS backup jobs
- Tape jobs
- Replication jobs
- VMware Cloud Director jobs (status uncertain -- treat as unsupported)
- Nutanix AHV / Proxmox / oVirt jobs
- Microsoft 365 / SaaS jobs (separate product API)

If your migration includes any of those, this module will not help you.

---

## Prerequisites

- **PowerShell 7.4 or later.** VBR v13 mandates PS7. Windows PowerShell 5.1 will fail at module import with a clear error.
- **Pester 5.7+** (only if you intend to run tests).
- **Network reachability** from the host running the module to both source and target VBR servers on port `9419` (default).
- **Local administrator credentials** on both VBR servers, or any account that can use the OAuth2 password grant.

The module runs on Windows, Linux, and macOS. There is no `curl.exe` shell-out and no Git-for-Windows dependency.

---

## Install

This module is not (yet) on the PowerShell Gallery. Clone the repo and import directly:

```powershell
git clone <this-repo-url>
cd VBR-REST-Job-Import-export
Import-Module ./VbrAutomationMigrate -Force
Get-Command -Module VbrAutomationMigrate
```

You should see 18 exported functions covering token issue, seven exports, seven imports, session polling, the empty-password detector, and the end-to-end orchestrator.

---

## Quick start -- two-stage migration (recommended)

The recommended workflow for production migrations is **two stages with manual verification in between**. Stage 1 dumps everything from source to JSON files and stops. You inspect the files (and crucially populate empty credential passwords) yourself. Stage 2 reads those JSON files and pushes them into the target.

### Stage 1 -- export only

Run on a host that can reach the **source** VBR server:

```powershell
Import-Module ./VbrAutomationMigrate -Force

$srcCred = Get-Credential -Message 'Source VBR admin'

Invoke-VbrMigration -ExportOnly `
    -SourceBaseUri    'https://src-vbr.example.com:9419' `
    -SourceCredential $srcCred `
    -WorkingDirectory ./migration `
    -SkipCertificateCheck `
    -Verbose
```

This authenticates to source, exports the seven resources (credentials, cloud credentials, encryption passwords, managed servers, repositories, proxies, jobs), writes UTF-8 (no BOM) JSON to `./migration/`, runs the empty-password check, and **returns**. No target token is requested. No imports run.

The returned object exposes `SourceBaseUri`, `WorkingDirectory`, `Files` (the seven file paths), and a null `Sessions`.

### Manual verification (do this between stages)

1. **Inspect the seven JSON files in `-WorkingDirectory`.** Confirm the resource counts and names match what you expect to migrate. There should be one file per resource: `credentials.json`, `cloudCredentials.json`, `encryptionPasswords.json`, `managedServers.json`, `repositories.json`, `proxies.json`, `jobs.json`.
2. **Open `credentials.json` and populate every empty `password` / `passphrase` / `privateKey` field flagged by the empty-password warning.** The Automation REST API does not return secrets in exports, so every credential entry comes back blank for those fields. Stage 2 will re-emit the warning, but the import will succeed even with empty secrets -- jobs that depend on those credentials will then fail to run on target until you either edit the JSON now or repopulate via the VBR console after the import. Editing now is the cleaner path.
3. **If the target VBR server has different mount-host names**, edit `repositories.json` and retarget `mountServer.mountServerName` for any repository whose mount host changed.
4. **On the target VBR console, delete the default backup repository and any default proxies** so the imported ones do not collide on name. (See "Pre-flight on the target VBR server" below for context.)

### Stage 2 -- resume from import

Run on a host that can reach the **target** VBR server (typically the target VBR host itself, or a workstation inside its VPN):

```powershell
Import-Module ./VbrAutomationMigrate -Force

$tgtCred = Get-Credential -Message 'Target VBR admin'

Invoke-VbrMigration -ResumeFromImport `
    -TargetBaseUri    'https://tgt-vbr.example.com:9419' `
    -TargetCredential $tgtCred `
    -WorkingDirectory ./migration `
    -SkipCertificateCheck `
    -Verbose
```

This reads the seven JSON files from `./migration/`, re-runs the empty-password check (so any still-empty credentials are flagged again), authenticates to target, and imports all seven resources in mandatory dependency order: credentials -> cloudCredentials -> encryptionPasswords -> managedServers -> repositories -> proxies -> jobs. After each import it polls `/api/v1/automation/sessions/{id}` and halts on the first `Failed` / `Stopped` / `Canceled`.

If any single import session fails, the orchestrator throws. Fix the underlying issue and re-run with `-ResumeFromImport` again -- the JSON files in `-WorkingDirectory` are still the source of truth.

---

## Single-pass mode (if you trust the export contents)

If you trust the export contents and want to skip the manual verification step, you can run the whole migration in one shot. **This is NOT the recommended path for production migrations** -- it gives you no opportunity to populate empty credential passwords or retarget mount hosts before they hit the target.

```powershell
Invoke-VbrMigration `
    -SourceBaseUri    'https://src-vbr.example.com:9419' `
    -TargetBaseUri    'https://tgt-vbr.example.com:9419' `
    -SourceCredential $srcCred `
    -TargetCredential $tgtCred `
    -WorkingDirectory ./migration `
    -SkipCertificateCheck `
    -Verbose
```

`Invoke-VbrMigration` performs every step in order:

1. Authenticates to source via OAuth2 password grant.
2. Exports credentials, cloud credentials, encryption passwords, managed servers, repositories, proxies, and jobs.
3. Persists each export to UTF-8 (no BOM) JSON in `-WorkingDirectory`.
4. Calls `Test-VbrCredentialPasswords` and emits a `Write-Warning` for every credential that has no `password`/`passphrase`/`privateKey` populated. **You must populate these on the target VBR server manually after the import** -- the API does not return secrets in exports.
5. Authenticates to target.
6. Imports the seven resources in mandatory dependency order: credentials -> cloudCredentials -> encryptionPasswords -> managedServers -> repositories -> proxies -> jobs.
7. Polls each Automation session at `/api/v1/automation/sessions/{id}` and halts on the first `Failed` / `Stopped` / `Canceled`.

If any single import session fails, the orchestrator throws and downstream resources are not attempted. Re-run with `-ResumeFromImport` after fixing the underlying issue to skip the export phase.

---

## Lower-level usage

For advanced callers who want to drive specific resources only, every export, import, token, and helper is also exposed as a public function. Sketch:

```powershell
$srcToken = Get-VbrToken -BaseUri 'https://src:9419' -Credential $srcCred -SkipCertificateCheck
$creds    = Export-VbrCredentials -Token $srcToken
$jobs     = Export-VbrJobs        -Token $srcToken

$tgtToken = Get-VbrToken -BaseUri 'https://tgt:9419' -Credential $tgtCred -SkipCertificateCheck
$session  = Import-VbrJobs -Token $tgtToken -Spec $jobs
$result   = Wait-VbrAutomationSession -Token $tgtToken -SessionId $session.id
```

In addition to the 7 `Export-Vbr*` and 7 `Import-Vbr*` functions, the module exposes:

- `Get-VbrToken` -- OAuth2 password-grant authentication; returns a typed `[VbrToken]`.
- `Wait-VbrAutomationSession` -- polls `/api/v1/automation/sessions/{id}` until the session reaches a terminal state; throws on `Failed` / `Stopped` / `Canceled`.
- `Test-VbrCredentialPasswords` -- inspects a credentials export and emits one `Write-Warning` listing every credential whose `password` / `passphrase` / `privateKey` is empty. Used by `Invoke-VbrMigration` in every mode.

---

## Pre-flight on the target VBR server

Before running the import, on the target VBR console:

- Delete the **default backup repository** so the imported one does not collide on name.
- Delete any **default proxies** for the same reason.

---

## Empty passwords

`Export-VbrCredentials` returns credentials with empty `password`/`passphrase`/`privateKey` fields -- the API does not export secrets. Every flagged credential must be repopulated **before any backup job that uses it will run successfully**. The clean place to do this is in step 2 of the [Manual verification](#manual-verification-do-this-between-stages) section above, by editing `credentials.json` between Stage 1 and Stage 2. Alternatively, you can let the import run with empty secrets and repopulate them on the target VBR server afterwards (via the VBR console or PowerShell SDK).

`Test-VbrCredentialPasswords` and `Invoke-VbrMigration` (in every mode) surface this with `Write-Warning` listing the affected names. Migration does **not** auto-fail on missing secrets -- you decide.

---

## Constitutional principles

The module obeys 8 immutable rules. They are enforced both in the source code and by `Tests/AntiPatterns.Tests.ps1`:

1. PowerShell 7.4+ only.
2. No `curl.exe` shell-out -- only `Invoke-RestMethod`.
3. No interactive UI (`MessageBox`, `Read-Host`, `Out-GridView`).
4. Bearer tokens never written to verbose / debug / host streams.
5. No hardcoded credentials in module source.
6. Exactly one `x-api-version` value: `1.3-rev1`.
7. TDD -- every public function has at least one Pester test.
8. `ConvertTo-Json -Depth 50` and `ConvertFrom-Json -Depth 50` everywhere.

See `Plans/upgrade-plan.md` section 1 for the rationale.

---

## Tests

```powershell
cd VbrAutomationMigrate
Invoke-Pester -Path Tests/ -Output Detailed
```

162 tests across 18 files (Pester 5.7+).

---

## Security

- The module does not log access tokens, passwords, or any other secret material on any verbosity level. `Tests/AntiPatterns.Tests.ps1` enforces this with source-level scans.
- `*.json` runtime exports are still gitignored. Do not commit them. They contain hostnames, IPs, and infrastructure metadata even when the API does not return secrets.
- The repo runs Gitleaks and Semgrep on every push, PR, and weekly cron.

---

## Layout

```
VBR-REST-Job-Import-export/
|-- VbrAutomationMigrate/
|   |-- VbrAutomationMigrate.psd1
|   |-- VbrAutomationMigrate.psm1
|   |-- Public/                       # 18 exported functions
|   |-- Private/                      # 5 internal helpers
|   |-- Tests/                        # 18 .Tests.ps1 files (162 tests)
|   |-- en-US/about_VbrAutomationMigrate.help.txt
|-- Plans/upgrade-plan.md
|-- README.md
|-- LICENSE
|-- .github/workflows/
|   |-- security.yml
```

---

## License

See `LICENSE`.
