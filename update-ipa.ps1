param(
    [string]$Repo = "vineetshah11/recon-bolt-revived",
    [string]$OutputDir = "d:\Hobbies\AI\Antigravity Projects\Recon Bolt\build-output"
)

$gh = "C:\Program Files\GitHub CLI\gh.exe"
$env:GH_TOKEN = "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"

Write-Host "Checking latest CI run on $Repo..."
$runJson = & $gh run list --repo $Repo --limit 1 --json databaseId,status,conclusion,headSha,updatedAt | ConvertFrom-Json

if (-not $runJson) {
    Write-Error "No CI runs found."
    exit 1
}

$run = $runJson[0]
Write-Host "Latest run ID: $($run.databaseId) (Commit: $($run.headSha.Substring(0,7))) - Status: $($run.status), Conclusion: $($run.conclusion)"

while ($run.status -ne "completed") {
    Write-Host "CI is still in progress ($($run.status)). Waiting 15 seconds..."
    Start-Sleep -Seconds 15
    $run = (& $gh run list --repo $Repo --limit 1 --json databaseId,status,conclusion,headSha,updatedAt | ConvertFrom-Json)[0]
}

if ($run.conclusion -ne "success") {
    Write-Error "CI build finished with failure: $($run.conclusion)"
    exit 1
}

Write-Host "Build succeeded! Downloading fresh ReconBolt.ipa..."
$targetIpa = Join-Path $OutputDir "ReconBolt-ipa\ReconBolt.ipa"
if (Test-Path $targetIpa) {
    Remove-Item -Force $targetIpa -ErrorAction SilentlyContinue
}

& $gh run download $run.databaseId --repo $Repo --dir $OutputDir

if (Test-Path $targetIpa) {
    $item = Get-Item $targetIpa
    Write-Host "`n==============================================="
    Write-Host "SUCCESS: Fresh IPA is ready!"
    Write-Host "Path: $($item.FullName)"
    Write-Host "Size: $([math]::Round($item.Length / 1MB, 2)) MB"
    Write-Host "Timestamp: $($item.LastWriteTime)"
    Write-Host "===============================================`n"
} else {
    Write-Error "IPA file was not found after download."
}
