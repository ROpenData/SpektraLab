# Sync the development fork (ROpenData/SpektraLab) into this repository.
#
# Usage (PowerShell, from the repository root):
#   powershell -File tools\sync-fork.ps1 [-ForkMain <ref>]
#
# What it does and why:
# 1. Fetches the fork.
# 2. Merges with --no-ff ALWAYS: a fast-forward would bypass the merge
#    drivers (.gitattributes' merge=ours for the two READMEs) and take the
#    fork's README wholesale — it did once (2026-11-17). --no-ff runs the
#    drivers, so this repository's Spektra XD READMEs survive every merge.
# 3. Verifies the READMEs still carry the fork's name, and fails loudly if
#    not (the readme-guard workflow checks this again on GitHub).
#
# The merge.ours driver must exist on this machine (one-time, per clone):
#   git config merge.ours.driver true

[CmdletBinding()]
param([string]$ForkMain = 'fork/main')

$ErrorActionPreference = 'Stop'

git fetch fork main
if ($LASTEXITCODE -ne 0) { throw 'git fetch fork main failed (the github.com channel drops out intermittently; retry or switch networks).' }

git merge --no-ff $ForkMain -m 'Merge the development fork into Spektra XD'
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Merge stopped on conflicts. Resolve them (READMEs: keep THIS repository'"'"'s version), `git add`, `git commit`, then re-run the checks below.'
    exit 1
}

$readme = Get-Content README.md -Raw
$readmeZh = Get-Content README.zh-CN.md -Raw
if ($readme -notmatch 'Spektra XD' -or $readmeZh -notmatch 'Spektra XD' -or
    $readme -match 'darkroom for the Mac' -or $readmeZh -match 'Mac 上的胶片暗房') {
    throw 'The READMEs lost the Spektra XD identity in the merge. Restore them (git checkout HEAD^ -- README.md README.zh-CN.md, commit) before pushing.'
}
Write-Output 'Merge done; the READMEs still carry the Spektra XD identity.'
Write-Output 'Next: full-clean rebuild of build\qt\engine and build\windows\engine (the stale-object lesson), ctest both, then push.'
