$bastionDone = $false
$privateDone = $false

while (-not ($bastionDone -and $privateDone)) {
    if (-not $bastionDone) {
        terraform apply -auto-approve "-target=oci_core_instance.bastion"
        if ($LASTEXITCODE -eq 0) { $bastionDone = $true; Write-Host "Bastion created!" -ForegroundColor Green }
    }
    if (-not $privateDone) {
        terraform apply -auto-approve "-target=oci_core_instance.private_host"
        if ($LASTEXITCODE -eq 0) { $privateDone = $true; Write-Host "Private host created!" -ForegroundColor Green }
    }
    if (-not ($bastionDone -and $privateDone)) {
        Write-Host "Still waiting on capacity, retrying in 90s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 90
    }
}
Write-Host "Both done!" -ForegroundColor Cyan