# Shared test setup. Sourced from BeforeAll in every *.Tests.ps1 file.
#
# Defines $script:ModuleName and $script:ModuleRoot so individual tests
# never reference a literal module name (R5 mitigation in the plan).

$script:ModuleName = 'VbrAutomationMigrate'
$script:ModuleRoot = Split-Path -Parent $PSScriptRoot
$script:ModulePath = Join-Path $script:ModuleRoot "$script:ModuleName.psd1"

# Force a clean import so tests see latest source (Pester 5 BeforeAll quirk).
Get-Module -Name $script:ModuleName -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module $script:ModulePath -Force -DisableNameChecking
