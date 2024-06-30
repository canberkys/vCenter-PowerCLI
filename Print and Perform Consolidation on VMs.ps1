# Connect to vCenter Server
Connect-VIServer -Server vcenter_server_name -User username -Password password

# Find and List All VMs That Require Consolidation
$vmList = Get-VM | Where-Object {
    $_.ExtensionData.Runtime.ConsolidationNeeded -eq $true
}

# Print and Perform Consolidation on VMs
if ($vmList.Count -eq 0) {
    Write-Host "No VMs require consolidation."
} else {
    Write-Host "VMs that require consolidation:"
    $vmList | ForEach-Object {
        Write-Host $_.Name
        $_.ExtensionData.ConsolidateVMDisks()
        Write-Host "Consolidation completed: $($_.Name)"
    }
}

# Disconnect from vCenter Server
Disconnect-VIServer -Confirm:$false
