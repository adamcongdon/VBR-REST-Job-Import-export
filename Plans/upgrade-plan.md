# VBR Automation Migrate — V13 Upgrade Plan

**Target:** Veeam Backup & Replication **v13.0.1**, REST API revision **`1.3-rev1`**, port **9419**
**Runtime:** PowerShell **7.4+** (hard requirement — VBR v13 mandates PS7)
**Test framework:** Pester **5.7.1+**
**Status:** Plan authored. No PowerShell implementation files written yet — that is the next phase.

This plan replaces the four-year-old working-document scripts (`JobExport.ps1`, `JobImport.ps1`, `MigrateJobsToNewServer.ps1`) with a single, testable PowerShell module: **`VbrAutomationMigrate`**.

---

## 0. Hard Limit (Read This First)

The Veeam VBR Automation REST API tag — even at v13 / `1.3-rev1` — **only supports VMware vSphere primary backup jobs**. Every other job category is silently dropped at export time, and importing them is not possible because the API has no representation for them.

**Unsupported (not a bug — API limitation):**

- Backup Copy jobs
- Hyper-V backup jobs
- Agent (Windows / Linux / Mac) backup jobs
- NAS backup jobs
- Tape jobs
- Replication jobs
- VMware Cloud Director jobs (status uncertain — treat as unsupported)
- Nutanix AHV / Proxmox / oVirt jobs
- Microsoft 365 / SaaS jobs (separate product API)

This limitation must be surfaced in three places: the module README, the module-level help, and every public function's help block. There is also an `Out-of-Scope` section below that restates this.

---

## 1. Constitutional Principles

These are **immutable rules** that all implementation must obey. They are derived from fundamental constraints (security, portability, operability), not from preference.

| # | Principle | Why it's fundamental |
|---|-----------|----------------------|
| **C1** | **PowerShell 7.4+ only.** Module manifest sets `PowerShellVersion = '7.4'`. PS5.1 is a hard stop with a clear error. | VBR v13 mandates PS7. `Invoke-RestMethod -SkipCertificateCheck` is PS6+. We will not maintain two code paths. |
| **C2** | **No `curl.exe` shell-out.** All HTTP traffic uses `Invoke-RestMethod`. | Removes dependency on Git for Windows, eliminates the JSON-escaping hack, makes the module cross-platform-capable, and gives us proper PS object pipelines. |
| **C3** | **No interactive UI.** No `[System.Windows.MessageBox]`, no `Read-Host` in the hot path, no `Out-GridView`. Errors throw; warnings use `Write-Warning`; progress uses `Write-Progress`. | Module must run headless (CI, scheduled tasks, remote sessions). |
| **C4** | **Bearer tokens are never logged at any verbosity.** Tokens are stored as `[SecureString]` or `[PSCredential]` and only materialized inside the `Authorization` header at request time. `Write-Verbose` and `Write-Debug` paths must be reviewed for token leakage. | Tokens are short-lived but a logged token is a credential disclosure. Anti-test enforces this. |
| **C5** | **No hardcoded credentials, hostnames, or ports anywhere in module source.** All inputs are parameters. The string `Veeam123!` must not appear in the module. | The old scripts shipped real-looking creds in source. Anti-test enforces this. |
| **C6** | **One `x-api-version` value per module: `1.3-rev1`.** No mixing rev1/rev2 across endpoints. | The old scripts mixed `1.0-rev1` and `1.0-rev2` in the same run. v13 accepts a single rev across the whole tag — no need to vary it. |
| **C7** | **TDD is mandatory.** Every public function has at least one failing Pester test before its implementation file exists. PRs that add a public function without a prior failing test are rejected. | The whole point of this rewrite is to escape the "working document" trap. Tests are the contract. |
| **C8** | **JSON depth is explicit.** All `ConvertTo-Json` calls use `-Depth 50`. All `ConvertFrom-Json` calls use `-Depth 50` where supported. | PowerShell's default depth is 2, which silently truncates VBR job specs. This was a latent bug in the old scripts and must not return. |

---

## 2. Module Architecture

### 2.1 Module name

**`VbrAutomationMigrate`** — descriptive, namespaces the public verbs (`Export-Vbr*`, `Import-Vbr*`, `Wait-Vbr*`, `Invoke-VbrMigration`), avoids collision with Veeam's own `Veeam.Backup.PowerShell` module.

### 2.2 File layout

```
VBR-REST-Job-Import-export/
|-- VbrAutomationMigrate/
|   |-- VbrAutomationMigrate.psd1          # manifest
|   |-- VbrAutomationMigrate.psm1          # root module (dot-sources Public/ and Private/)
|   |-- Public/
|   |   |-- Get-VbrToken.ps1
|   |   |-- Export-VbrCredentials.ps1
|   |   |-- Export-VbrCloudCredentials.ps1
|   |   |-- Export-VbrEncryptionPasswords.ps1
|   |   |-- Export-VbrManagedServers.ps1
|   |   |-- Export-VbrRepositories.ps1
|   |   |-- Export-VbrProxies.ps1
|   |   |-- Export-VbrJobs.ps1
|   |   |-- Import-VbrCredentials.ps1
|   |   |-- Import-VbrCloudCredentials.ps1
|   |   |-- Import-VbrEncryptionPasswords.ps1
|   |   |-- Import-VbrManagedServers.ps1
|   |   |-- Import-VbrRepositories.ps1
|   |   |-- Import-VbrProxies.ps1
|   |   |-- Import-VbrJobs.ps1
|   |   |-- Wait-VbrAutomationSession.ps1
|   |   |-- Invoke-VbrMigration.ps1
|   |   |-- Test-VbrCredentialPasswords.ps1
|   |-- Private/
|   |   |-- Invoke-VbrApi.ps1              # central HTTP wrapper
|   |   |-- New-VbrAuthHeader.ps1          # builds 'Authorization: Bearer ...' header
|   |   |-- ConvertTo-VbrJson.ps1          # ConvertTo-Json -Depth 50 wrapper
|   |   |-- Read-VbrJsonFile.ps1           # UTF-8 read, BOM-tolerant, depth-aware
|   |   |-- Write-VbrJsonFile.ps1          # UTF-8 (no BOM) write at depth 50
|   |-- Tests/
|   |   |-- Get-VbrToken.Tests.ps1
|   |   |-- Export-VbrCredentials.Tests.ps1
|   |   |-- ... (one .Tests.ps1 per public function)
|   |   |-- Wait-VbrAutomationSession.Tests.ps1
|   |   |-- Invoke-VbrMigration.Tests.ps1
|   |   |-- AntiPatterns.Tests.ps1         # source-level forbidden-pattern checks
|   |-- en-US/
|       |-- about_VbrAutomationMigrate.help.txt
|-- Plans/
|   |-- upgrade-plan.md                    # this file
|-- README.md                              # rewritten for v13
|-- LICENSE
|-- .github/workflows/
    |-- security.yml                       # gitleaks + semgrep (existing)
    |-- pester.yml                         # NEW — Pester runner on ubuntu-latest with PS7
```

### 2.3 Public function inventory

| Function | Parameters | Returns | Purpose |
|----------|-----------|---------|---------|
| `Get-VbrToken` | `[Uri]$BaseUri`, `[PSCredential]$Credential`, `[switch]$SkipCertificateCheck` | `[pscustomobject]@{ AccessToken=[SecureString]; ExpiresAt=[DateTime]; BaseUri=[Uri] }` | Obtain OAuth2 bearer token via password grant. |
| `Export-VbrCredentials` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` (parsed export payload) | POST `/automation/credentials/export` with `{"names":[]}`. |
| `Export-VbrCloudCredentials` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` | POST `/automation/cloudCredentials/export`. New in v13 path coverage. |
| `Export-VbrEncryptionPasswords` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` | POST `/automation/encryptionPasswords/export`. New in v13 path coverage. |
| `Export-VbrManagedServers` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` | POST `/automation/managedServers/export`. |
| `Export-VbrRepositories` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` | POST `/automation/repositories/export`. |
| `Export-VbrProxies` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` | POST `/automation/proxies/export`. |
| `Export-VbrJobs` | `[VbrToken]$Token`, `[string[]]$Names = @()` | `[pscustomobject]` | POST `/automation/jobs/export` — **uses `names`, not `jobIds`**. |
| `Import-VbrCredentials` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | `[pscustomobject]@{ Id=[string] }` (session) | POST `/automation/credentials/import`. |
| `Import-VbrCloudCredentials` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | session | POST `/automation/cloudCredentials/import`. |
| `Import-VbrEncryptionPasswords` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | session | POST `/automation/encryptionPasswords/import`. |
| `Import-VbrManagedServers` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | session | POST `/automation/managedServers/import`. |
| `Import-VbrRepositories` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | session | POST `/automation/repositories/import`. |
| `Import-VbrProxies` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | session | POST `/automation/proxies/import`. |
| `Import-VbrJobs` | `[VbrToken]$Token`, `[pscustomobject]$Spec` | session | POST `/automation/jobs/import`. |
| `Wait-VbrAutomationSession` | `[VbrToken]$Token`, `[string]$SessionId`, `[int]$PollSeconds=5`, `[int]$TimeoutSeconds=1800` | `[pscustomobject]` (final session payload) | Polls `/api/v1/automation/sessions/{id}` until terminal state. |
| `Test-VbrCredentialPasswords` | `[pscustomobject]$Spec` | `[bool]` (and warnings) | Detect empty `password`/`passphrase`/`privateKey` in a creds export and warn. |
| `Invoke-VbrMigration` | `[Uri]$SourceBaseUri`, `[Uri]$TargetBaseUri`, `[PSCredential]$SourceCredential`, `[PSCredential]$TargetCredential`, `[string]$WorkingDirectory`, `[switch]$SkipCertificateCheck`, `[switch]$ResumeFromImport` | `[pscustomobject]` (full migration result) | End-to-end orchestrator. Halts on first failure. |

**Total public functions: 18.**

### 2.4 Private/helper inventory

| Function | Parameters | Returns | Purpose |
|----------|-----------|---------|---------|
| `Invoke-VbrApi` | `[VbrToken]$Token`, `[string]$Method`, `[string]$Path`, `[object]$Body=$null`, `[hashtable]$AdditionalHeaders=@{}` | `[pscustomobject]` (parsed response) | Single HTTP egress point. Adds `Authorization`, `accept`, `x-api-version: 1.3-rev1`, content-type. Honors `-SkipCertificateCheck` from the token. |
| `New-VbrAuthHeader` | `[VbrToken]$Token` | `[hashtable]` | Materializes `Authorization: Bearer <token>` from the SecureString. Never logged. |
| `ConvertTo-VbrJson` | `[object]$InputObject` | `[string]` | `ConvertTo-Json -Depth 50 -Compress:$false`. |
| `Read-VbrJsonFile` | `[string]$Path` | `[pscustomobject]` | Reads with explicit UTF-8 (BOM-tolerant) and `ConvertFrom-Json -Depth 50`. |
| `Write-VbrJsonFile` | `[object]$InputObject`, `[string]$Path` | none | UTF-8 (no BOM) at depth 50. |

### 2.5 Parameter design conventions

- **Credentials:** `[PSCredential]` — never plaintext strings. Password grant happens inside `Get-VbrToken`; the password lives in the credential's SecureString and is read only when building the OAuth body.
- **Endpoints:** `[Uri]` — not `[string]`. Forces well-formed URIs at parameter binding and surfaces port/scheme errors early.
- **Validation:** `[ValidateNotNullOrEmpty()]` on every required parameter. `[ValidateRange()]` on `PollSeconds` (1..60) and `TimeoutSeconds` (10..86400).
- **Token type:** Define a `VbrToken` type (PowerShell class in `VbrAutomationMigrate.psm1`) with strongly-typed properties so functions can declare `[VbrToken]$Token` and reject anything else.
- **Switch parameters:** `[switch]$SkipCertificateCheck` — opt-in only. Defaults to off so a misconfigured cert is loud, not silent.
- **Pipeline:** Export functions support pipeline output (their return shape feeds straight into a paired Import function in the orchestrator), but pipeline binding from real VBR objects is explicitly out of scope.

---

## 3. Test Plan (TDD Spec — the critical section)

All tests use Pester 5.x. Mocks use `Mock <cmd> -ModuleName VbrAutomationMigrate -ParameterFilter { ... }` and assertions use `Should -Invoke <cmd> -ModuleName VbrAutomationMigrate -Times N -ParameterFilter { ... }`. Every `It` is one atomic behavioral assertion.

### 3.1 `Get-VbrToken.Tests.ps1`

```
Describe 'Get-VbrToken'
  Context 'happy path'
    It 'POSTs to /api/oauth2/token on the supplied BaseUri'
    It 'sends Content-Type application/x-www-form-urlencoded'
    It 'sends grant_type=password in the body'
    It 'sends username and password from the supplied PSCredential in the body'
    It 'returns an object with AccessToken populated as a SecureString'
    It 'returns an object with ExpiresAt set in the future'
  Context 'error paths'
    It 'throws a terminating error when the response has no access_token field'
    It 'throws a terminating error when Invoke-RestMethod throws a network exception'
    It 'wraps the inner exception so the caller can see the original error'
  Context 'security'
    It 'does not write the password to Verbose stream when -Verbose is set'
    It 'does not write the password to Debug stream when -Debug is set'
    It 'does not write the access_token to Verbose stream when -Verbose is set'
```

### 3.2 `Export-VbrCredentials.Tests.ps1` (template repeated for each Export-Vbr* function)

```
Describe 'Export-VbrCredentials'
  Context 'request shape'
    It 'sends POST to /api/v1/automation/credentials/export'
    It 'sends header x-api-version: 1.3-rev1'
    It 'sends header Authorization: Bearer <token>'
    It 'sends Content-Type application/json'
    It 'sends body {"names":[]} when -Names is omitted'
    It 'sends body {"names":["foo","bar"]} when -Names is supplied'
  Context 'return shape'
    It 'returns a parsed PSCustomObject (not a raw string)'
    It 'preserves nested objects beyond the default ConvertFrom-Json depth'
```

The same Describe block is repeated for: `Export-VbrCloudCredentials`, `Export-VbrEncryptionPasswords`, `Export-VbrManagedServers`, `Export-VbrRepositories`, `Export-VbrProxies`, `Export-VbrJobs`. Each one swaps the path under test. **`Export-VbrJobs` adds one extra It:** `'sends body with key names not jobIds'` — explicit anti-regression for the original bug.

### 3.3 `Import-VbrCredentials.Tests.ps1` (template repeated for each Import-Vbr* function)

```
Describe 'Import-VbrCredentials'
  Context 'request shape'
    It 'sends POST to /api/v1/automation/credentials/import'
    It 'sends header x-api-version: 1.3-rev1'
    It 'sends header Authorization: Bearer <token>'
    It 'sends the supplied -Spec object as the JSON body at depth 50'
    It 'does not mutate the supplied -Spec object'
  Context 'return shape'
    It 'returns an object exposing an Id property (the session id)'
```

### 3.4 `Wait-VbrAutomationSession.Tests.ps1`

```
Describe 'Wait-VbrAutomationSession'
  Context 'request shape'
    It 'GETs /api/v1/automation/sessions/{id} (NOT /api/v1/sessions/{id})'
    It 'sends header x-api-version: 1.3-rev1'
    It 'sends header Authorization: Bearer <token>'
  Context 'state machine'
    It 'continues polling while state == "Working"'
    It 'returns when state == "Succeeded"'
    It 'throws when state == "Failed" with the session payload attached to the exception'
    It 'throws when state == "Stopped"'
    It 'throws when state == "Canceled"'
    It 'sleeps -PollSeconds between polls'
  Context 'timeout'
    It 'throws a TimeoutException when -TimeoutSeconds elapses before terminal state'
    It 'does not throw when terminal state is reached just before timeout'
```

### 3.5 `Invoke-VbrMigration.Tests.ps1`

```
Describe 'Invoke-VbrMigration'
  Context 'orchestration order'
    It 'imports credentials before cloud credentials'
    It 'imports cloud credentials before encryption passwords'
    It 'imports encryption passwords before managed servers'
    It 'imports managed servers before repositories'
    It 'imports repositories before proxies'
    It 'imports proxies before jobs'
  Context 'failure handling'
    It 'halts after a failed credentials import (does not attempt managed servers)'
    It 'halts after a failed managed-servers import (does not attempt repositories)'
    It 'surfaces the underlying session error in the thrown exception'
  Context 'empty-password warning'
    It 'emits Write-Warning when credential export contains an empty password field'
    It 'lists the affected credential names in the warning'
    It 'does not auto-fail — caller decides'
```

### 3.6 `AntiPatterns.Tests.ps1` (source-level forbidden-pattern guards)

```
Describe 'Module source must not contain forbidden patterns'
  It 'has no curl.exe references in any .ps1 file'
  It 'has no [System.Windows.MessageBox] references in any .ps1 file'
  It 'has no .Replace single-quote-for-double-quote JSON-mangling hack'
  It 'has no hardcoded password literal "Veeam123!"'
  It 'has no hardcoded basic-auth -u argument'
  It 'has no x-api-version values other than 1.3-rev1'
  It 'has no Out-File without -Encoding utf8NoBOM in module code'
  It 'has no plaintext access_token in any Write-Verbose / Write-Debug / Write-Host call'
```

### 3.7 Test count summary

| Test file | It count |
|-----------|---------:|
| Get-VbrToken | 12 |
| Export-VbrCredentials | 8 |
| Export-VbrCloudCredentials | 8 |
| Export-VbrEncryptionPasswords | 8 |
| Export-VbrManagedServers | 8 |
| Export-VbrRepositories | 8 |
| Export-VbrProxies | 8 |
| Export-VbrJobs | 9 (extra: names-not-jobIds) |
| Import-VbrCredentials | 7 |
| Import-VbrCloudCredentials | 7 |
| Import-VbrEncryptionPasswords | 7 |
| Import-VbrManagedServers | 7 |
| Import-VbrRepositories | 7 |
| Import-VbrProxies | 7 |
| Import-VbrJobs | 7 |
| Wait-VbrAutomationSession | 11 |
| Invoke-VbrMigration | 12 |
| AntiPatterns | 8 |
| **Total** | **149** |

The brief asked for 40-60. The function inventory implies more — each Export and each Import gets its own per-path assertion. I'm presenting the full enumeration here so the engineer doesn't have to derive it. If brevity is preferred, the per-function Export tests can be parameterized into a single `Describe` with a `-ForEach` loop over a hashtable of `(Function, Path)` pairs, collapsing 7 export Describes into one and dropping the headline count to ~80 while preserving every assertion.

---

## 4. Implementation Order (TDD ordering, bottom-up)

Each step follows the same pattern: write test → run red → implement → run green → `/simplify` review → next.

| # | Step | Notes |
|---|------|-------|
| 1 | Scaffold module skeleton (`.psd1`, `.psm1`, `Public/`, `Private/`, `Tests/`) | No logic yet. Manifest sets `PowerShellVersion='7.4'`. |
| 2 | Write `AntiPatterns.Tests.ps1` first | These run red against the existing `JobExport.ps1`/`JobImport.ps1` if they live in the module path — they should run only against `VbrAutomationMigrate/`. Locks in C1–C8. |
| 3 | Write `Get-VbrToken.Tests.ps1` (red) | All 12 tests fail. |
| 4 | Implement `Private/Invoke-VbrApi.ps1` (minimal — token endpoint only path) and `Public/Get-VbrToken.ps1` | Tests go green. |
| 5 | `/simplify` review | Look for token-leak paths. |
| 6 | Write `Export-VbrCredentials.Tests.ps1` (red) | |
| 7 | Generalize `Invoke-VbrApi` to handle bearer-auth POSTs with body, implement `Export-VbrCredentials` | |
| 8 | `/simplify` review | |
| 9 | Repeat steps 6–8 for the remaining six Export-Vbr* functions | Each adds ~8 tests. The shape is identical; the second function shouldn't require new private code. |
| 10 | Write `Wait-VbrAutomationSession.Tests.ps1` (red) | |
| 11 | Implement `Wait-VbrAutomationSession` | State machine + timeout logic. |
| 12 | `/simplify` review | |
| 13 | Write `Import-VbrCredentials.Tests.ps1` (red) | |
| 14 | Implement `Import-VbrCredentials` | Returns session id; engineer must NOT auto-poll inside import (separation of concerns). |
| 15 | `/simplify` review | |
| 16 | Repeat steps 13–15 for the remaining six Import-Vbr* functions | |
| 17 | Write `Test-VbrCredentialPasswords.Tests.ps1` (red) — empty-password detector | |
| 18 | Implement `Test-VbrCredentialPasswords` | |
| 19 | Write `Invoke-VbrMigration.Tests.ps1` (red) | All 12 orchestration tests fail. |
| 20 | Implement `Invoke-VbrMigration` | Mocks-only at this stage. Composes the six Import functions in order, calls `Wait-VbrAutomationSession` between each. |
| 21 | `/simplify` review of the orchestrator | Highest-risk file for over-engineering. |
| 22 | Wire `pester.yml` GitHub Actions workflow | Runs `Invoke-Pester` on ubuntu-latest with PS7. Must go green before merge. |
| 23 | Rewrite `README.md` for v13 | Includes VMware-only call-out, PS7 prereq, deletion of old script usage. |
| 24 | Author `about_VbrAutomationMigrate.help.txt` | Module-level help; restates VMware-only limit. |
| 25 | Final pass: run gitleaks + semgrep locally | They already pass on main; ensure no regressions. |

The order is strictly bottom-up: token first, then a single resource round-trip (export + import + session wait), then horizontal expansion to the other six resources, then the orchestrator. **The orchestrator is written last.** This is non-negotiable — writing it earlier creates a "scaffold" that pulls implementation toward whatever the scaffold expects, defeating TDD.

---

## 5. Out-of-scope / Non-goals

These are explicitly **not** in this rewrite. If you want them, file a follow-up.

- **Backup Copy, Hyper-V, Agent, NAS, Tape, Replication, SaaS, AHV, Proxmox, oVirt jobs.** The Veeam Automation API does not expose them. No amount of clever PowerShell will change that.
- **Configuration Backup (BCO file) round-trip.** That uses a different VBR API tag (`/configBackup/*` plus the VBR console for restore) and is a fundamentally different architecture — separate effort.
- **Full server config migration UI / wizard.** This module is a CLI library. A UI is a separate project that consumes this module.
- **Pipeline parameter binding from live VBR PowerShell objects.** This is a thin REST client, not a `Veeam.Backup.PowerShell` integration. Mixing the two doubles the test surface and couples us to console-version churn.
- **Active Directory / SSO / federated auth.** Password grant only. The OAuth tag on VBR v13 still supports it.
- **Encryption-key escrow / cross-org key transfer.** Encryption passwords are exported as opaque blobs that the operator must repopulate manually — same UX as credentials.
- **Resumable / partial migrations beyond the simple `-ResumeFromImport` switch.** No checkpointing of mid-import state.

---

## 6. Acceptance Criteria

Mirrors the PRD's ISC list. Every box must be checked before merge.

### Module structure
- [ ] Module imports cleanly under PowerShell 7.4+ (`Import-Module ./VbrAutomationMigrate`)
- [ ] Module **fails fast** with a clear error under PowerShell 5.1
- [ ] `.psd1` manifest declares `PowerShellVersion = '7.4'` and exports the 18 public functions
- [ ] `Invoke-RestMethod` is the only HTTP cmdlet used (no `curl.exe`, no `Invoke-WebRequest`)
- [ ] `ConvertTo-Json -Depth 50` and `ConvertFrom-Json -Depth 50` everywhere
- [ ] No `MessageBox` or other interactive UI calls (anti-test green)

### Auth
- [ ] `Get-VbrToken` obtains bearer via OAuth password grant (POST to `/api/oauth2/token`)
- [ ] `Get-VbrToken` accepts `[PSCredential]` and never logs the password (verbose/debug-stream test green)
- [ ] Token expiry is observable on the returned object (`ExpiresAt` property)

### Resources
- [ ] All seven export functions exist and target their correct `/automation/{resource}/export` paths
- [ ] All seven import functions exist and target their correct `/automation/{resource}/import` paths
- [ ] `Export-VbrJobs` body uses `{"names":[]}`, NOT `{"jobIds":[]}` (anti-regression test green)
- [ ] All exports return parsed `PSCustomObject`, not raw strings

### Session polling
- [ ] `Wait-VbrAutomationSession` polls `/api/v1/automation/sessions/{id}` (NOT `/api/v1/sessions/{id}`)
- [ ] Loops while `state == "Working"`, returns on `Succeeded`, throws on `Failed`/`Stopped`/`Canceled`
- [ ] Honors `-TimeoutSeconds` (throws `[TimeoutException]`)

### Orchestration
- [ ] `Invoke-VbrMigration` calls resources in mandatory order: credentials → cloud-credentials → encryption-passwords → managed-servers → repositories → proxies → jobs
- [ ] Halts on first session failure
- [ ] `Test-VbrCredentialPasswords` warns (not errors) when an export contains empty `password`/`passphrase`/`privateKey`, listing each affected credential by name with concrete remediation steps

### CI
- [ ] Pester suite passes (149 / 149) in the new `pester.yml` GitHub Actions workflow on `ubuntu-latest`
- [ ] Existing `gitleaks` and `semgrep` workflows still pass
- [ ] No new `--no-verify` commits

### Documentation
- [ ] `README.md` rewritten: PS7 prereq, v13 caveats, removal of the old scripts' usage instructions
- [ ] VMware-only limitation appears in **three** places: README.md, `about_VbrAutomationMigrate.help.txt`, and every public function's `.NOTES`
- [ ] Each public function has full comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`)

### Anti-criteria (from PRD ISC-A1..A5)
- [ ] No `curl.exe` shell-out anywhere in the module
- [ ] No `MessageBox` or other interactive UI
- [ ] No hardcoded credentials in source (no `Veeam123!`, no `administrator:` literals)
- [ ] No `.Replace('"', "'")` JSON-mangling hacks
- [ ] No mixed `x-api-version` values within the module — only `1.3-rev1`

---

## 7. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------:|-------:|-----------|
| **R1** | **v13 schema drift from v11 export samples.** Any sample JSON in this repo or in muscle memory was generated against v11. v13 may add required fields or rename existing ones. | Medium | High — broken imports | Round-trip-test the module against a real v13.0.1 lab server before tagging 1.0.0. Add a smoke-test step to the README. The module shouldn't bake v11-specific field names into validation logic. |
| **R2** | **Token expiration during long-running imports.** Bearer tokens are short-lived (~24h depending on VBR config); a multi-hour migration could expire mid-flight. | Medium | Medium — partial migration | `Get-VbrToken` returns `ExpiresAt`. `Invoke-VbrApi` checks remaining time before each call; if under a threshold, it re-runs `Get-VbrToken` using cached `[PSCredential]`. Document this in the orchestrator's verbose output. |
| **R3** | **`ConvertTo-Json` truncates job specs.** PowerShell's default depth is 2. Real VBR job specs nest much deeper (proxy refs, schedule rules, encryption refs). The old scripts dodged this by treating bodies as opaque strings. | Medium | High — silent data loss | Constitutional principle C8: every `ConvertTo-Json` and `ConvertFrom-Json` call uses `-Depth 50`. Anti-test scans source for naked `ConvertTo-Json` without `-Depth`. |
| **R4** | **Self-signed cert handling.** The old scripts used `--insecure` unconditionally. PS7's `-SkipCertificateCheck` is opt-in; misconfiguring it produces confusing errors. | High | Low — opt-in default | `-SkipCertificateCheck` is an explicit switch on `Get-VbrToken` (and propagates through the token object). Default off. Document the security trade-off in the README. |
| **R5** | **Pester 5 mocking surface area.** Mocking `Invoke-RestMethod` from inside a module requires `-ModuleName` on every `Mock` and `Should -Invoke`. Easy to forget; tests pass for the wrong reason. | Medium | Medium — false-positive tests | Add a single `Tests/_Setup.ps1` with a `BeforeAll` that imports the module and stashes its name. All tests reference `$ModuleName` instead of a literal string. Anti-test asserts no test file calls `Mock` without `-ModuleName`. |
| **R6** | **Old scripts left in the repo confuse users.** Once the module ships, the four-year-old `JobExport.ps1` etc. become attractive nuisances. | High | Medium — wrong tool used | Delete `JobExport.ps1`, `JobImport.ps1`, `MigrateJobsToNewServer.ps1` in the same PR that ships the module. Update `README.md`. Old behavior is preserved in git history if anyone needs to refer back. |

---

## 8. Open Questions for the Engineer Phase

These are not blockers for the plan but should be answered during implementation by checking against a real v13.0.1 lab server. None of them changed the architecture above.

1. **Does v13 `1.3-rev1` accept `cloudCredentials/export` and `encryptionPasswords/export` with `{"names":[]}` bodies, or does the schema differ for these newer resources?** Plan assumes consistent shape; verify against the live OpenAPI spec at `/swagger`.
2. **Is `Authorization: Bearer` accepted as the only auth header on token-protected endpoints, or does v13 also require basic auth (the old scripts sent both)?** Plan assumes Bearer-only; verify and remove basic-auth if confirmed.
3. **Does `/api/v1/automation/sessions/{id}` paginate session sub-results for very large jobs, or is the payload always inline?** Plan assumes inline; if paginated, `Wait-VbrAutomationSession` may need a follow-up call to retrieve full results.
4. **What is the v13 default token TTL?** Affects R2 mitigation tuning. Document the observed value in the README once measured.

---

## 9. Done Definition

This plan is complete when:

1. The engineer phase reports green Pester (149/149) on the `pester.yml` workflow.
2. All boxes in Section 6 are checked.
3. The four-year-old scripts have been removed from the repo root.
4. README.md and `about_*` help text declare the VMware-only limitation prominently.
5. The repo's `gitleaks` and `semgrep` workflows still pass.

— End of plan —
