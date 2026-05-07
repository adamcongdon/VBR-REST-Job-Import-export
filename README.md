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

## Quick start -- end-to-end migration

```powershell
Import-Module ./VbrAutomationMigrate -Force

$srcCred = Get-Credential -Message 'Source VBR admin'
$tgtCred = Get-Credential -Message 'Target VBR admin'

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

You can also drive the individual functions directly. Sketch:

```powershell
$srcToken = Get-VbrToken -BaseUri 'https://src:9419' -Credential $srcCred -SkipCertificateCheck
$creds    = Export-VbrCredentials -Token $srcToken
$jobs     = Export-VbrJobs        -Token $srcToken

$tgtToken = Get-VbrToken -BaseUri 'https://tgt:9419' -Credential $tgtCred -SkipCertificateCheck
$session  = Import-VbrJobs -Token $tgtToken -Spec $jobs
$result   = Wait-VbrAutomationSession -Token $tgtToken -SessionId $session.id
```

---

## Pre-flight on the target VBR server

Before running the import, on the target VBR console:

- Delete the **default backup repository** so the imported one does not collide on name.
- Delete any **default proxies** for the same reason.

---

## Empty passwords

`Export-VbrCredentials` returns credentials with empty `password`/`passphrase`/`privateKey` fields -- the API does not export secrets. After import, every flagged credential must be repopulated on the target VBR server (via the VBR console or PowerShell SDK) before any backup job that uses it will run successfully.

`Test-VbrCredentialPasswords` and `Invoke-VbrMigration` both surface this with `Write-Warning` listing the affected names. Migration does **not** auto-fail on missing secrets -- you decide.

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

149 tests across 18 files (Pester 5.7+).

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
|   |-- Tests/                        # 18 .Tests.ps1 files (149 tests)
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
