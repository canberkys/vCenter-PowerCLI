# PowerCLI Script for Monitoring VM Events, Exporting to Color-Coded HTML, and Sending via Email

# vCenter Connection Info 
$vcServer = "your-vcenter-server"
$vcUser = 'vcenter-user'
$vcPassword = 'vcenter-user-password'

# HTML File Settings
$outputFile = "C:\Temp\vCenter_VM_Activity_Report.html"

# EMail Settings
$smtpServer = " smpt-server-IP/FQDN "
$emailFrom = " EMail sender "
$emailTo = " EMail Recepient "
$emailSubject = "$vcServer vCenter VM Activity Report - Last 24 Hours " # EMail Subject

#  Ignore certificate errors 
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Connect vCenter
Connect-VIServer -Server $vcServer -User $vcUser -Password $vcPassword

# Control Events
$startTime = (Get-Date).AddDays(-1) # Last 24 Hours
$events = Get-VIEvent -Start $startTime -MaxSamples 5000 # -MaxSamples may vary, a maximum of 5000 is recommended.

# Filter Events
$filteredEvents = $events | Where-Object {
    $_.GetType().Name -eq "VmCreatedEvent" -or
    $_.GetType().Name -eq "VmRemovedEvent" -or
    $_.GetType().Name -eq "VmDeployedEvent" -or
    $_.GetType().Name -eq "VmPoweredOnEvent" -or
    $_.GetType().Name -eq "VmPoweredOffEvent" -or
    $_.GetType().Name -eq "VmReconfiguredEvent" -or
    $_.GetType().Name -eq "VmSnapshotCreatedEvent" -or
    $_.GetType().Name -eq "VmSnapshotRemovedEvent" -or
    $_.GetType().Name -eq "TaskEvent" -and ($_.Info.DescriptionId -like "*CreateSnapshot*" -or $_.Info.DescriptionId -like "*RemoveSnapshot*")
}

# Generate HTML content (in HTML format)
$htmlContent = @"
<html>
<head>
    <style>
        table { border-collapse: collapse; width: 100%; font-family: Arial, sans-serif; }
        th, td { border: 1px solid black; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .created { background-color: #d4edda; }  /* Yeşil - VM Created */
        .removed { background-color: #f8d7da; }  /* Kırmızı - VM Removed */
        .deployed { background-color: #d1ecf1; } /* Açık Mavi - VM Deployed */
        .poweredon { background-color: #fff3cd; } /* Sarı - VM Powered On */
        .poweredoff { background-color: #f5c6cb; } /* Pembe - VM Powered Off */
        .reconfigured { background-color: #d6d8d9; } /* Gri - VM Reconfigured */
        .snapshotcreated { background-color: #e2e3e5; } /* Açık Gri - Snapshot Created */
        .snapshotremoved { background-color: #f8d7da; } /* Kırmızı - Snapshot Removed */
    </style>
</head>
<body>
<h2>vCenter VM Activity Report - Last 24 Hours</h2>
<table>
<tr>
    <th>VM Name</th>
    <th>Action</th>
    <th>Time</th>
    <th>User</th>
    <th>Details</th>
</tr>
"@

foreach ($event in $filteredEvents) {
    $vmName = $event.Vm.Name
    $action = $event.GetType().Name
    $time = $event.CreatedTime.ToString("yyyy-MM-dd HH:mm:ss")
    $user = $event.UserName
    $rowClass = ""
    $details = ""

    # Make the action genre more readable and add details
    switch ($action) {
        "VmCreatedEvent" { 
            $actionDescription = "VM Created" 
            $details = "New VM has been created."
            $rowClass = "created"
        }
        "VmRemovedEvent" { 
            $actionDescription = "VM Removed" 
            $details = "VM has been removed."
            $rowClass = "removed"
        }
        "VmDeployedEvent" { 
            $actionDescription = "VM Deployed from OVA" 
            $details = "VM has been deployed from an OVA file."
            $rowClass = "deployed"
        }
        "VmPoweredOnEvent" { 
            $actionDescription = "VM Powered On" 
            $details = "VM has been powered on."
            $rowClass = "poweredon"

            # To get the user information of the Power-On event
            $vmObject = Get-VM -Id $event.Vm.Vm
            $user = Get-VIEvent -Entity $vmObject -Start $startTime | Where-Object {
                $_.GetType().Name -eq "TaskEvent" -and $_.Info.DescriptionId -like "*powerOn*" } | Select-Object -First 1 | Select-Object -ExpandProperty UserName
        }
        "VmPoweredOffEvent" { 
            $actionDescription = "VM Powered Off" 
            $details = "VM has been powered off."
            $rowClass = "poweredoff"

            # To get the user information of the Power-Off event
            $vmObject = Get-VM -Id $event.Vm.Vm
            $user = Get-VIEvent -Entity $vmObject -Start $startTime | Where-Object {
                $_.GetType().Name -eq "TaskEvent" -and $_.Info.DescriptionId -like "*powerOff*" } | Select-Object -First 1 | Select-Object -ExpandProperty UserName
        }
        "VmReconfiguredEvent" { 
            $actionDescription = "VM Reconfigured" 
            $rowClass = "reconfigured"

            # Extract Reconfiguration details
            $details = "VM has been reconfigured. "

            # Check previous and new values
            $vm = Get-VM -Id $event.Vm.Vm

            if ($event.ConfigSpec.MemoryMB) {
                $oldMemory = ($vm | Get-VMResourceConfiguration).MemoryMB
                $newMemory = $event.ConfigSpec.MemoryMB
                $details += "RAM changed from " + $oldMemory + " MB to " + $newMemory + " MB. "
            }
            if ($event.ConfigSpec.NumCPUs) {
                $oldCPUs = ($vm | Get-VMResourceConfiguration).NumCpu
                $newCPUs = $event.ConfigSpec.NumCPUs
                $details += "CPU count changed from " + $oldCPUs + " to " + $newCPUs + ". "
            }
        }
        "VmSnapshotCreatedEvent" { 
            $actionDescription = "Snapshot Created" 
            $details = "Snapshot has been created for VM."
            $rowClass = "snapshotcreated"
        }
        "VmSnapshotRemovedEvent" { 
            $actionDescription = "Snapshot Removed" 
            $details = "Snapshot has been removed from VM."
            $rowClass = "snapshotremoved"
        }
        "TaskEvent" {
            if ($_.Info.DescriptionId -like "*CreateSnapshot*") {
                $actionDescription = "Snapshot Created"
                $details = "Snapshot has been created for VM by user $($_.UserName)."
                $rowClass = "snapshotcreated"
                $user = $_.UserName
            }
            elseif ($_.Info.DescriptionId -like "*RemoveSnapshot*") {
                $actionDescription = "Snapshot Removed"
                $details = "Snapshot has been removed from VM by user $($_.UserName)."
                $rowClass = "snapshotremoved"
                $user = $_.UserName
            }
        }
        default { 
            $actionDescription = $action 
            $details = "Details not available."
        }
    }

    # Insert in HTML line
    $htmlContent += @"
<tr class='$rowClass'>
    <td>$vmName</td>
    <td>$actionDescription</td>
    <td>$time</td>
    <td>$user</td>
    <td>$details</td>
</tr>
"@
}

$htmlContent += @"
</table>
</body>
</html>
"@

# Send Email
if ($filteredEvents.Count -gt 0) {
    $emailMessage = New-Object System.Net.Mail.MailMessage
    $emailMessage.From = $emailFrom
    $emailMessage.To.Add($emailTo)
    $emailMessage.Subject = $emailSubject
    $emailMessage.Body = $htmlContent
    $emailMessage.IsBodyHtml = $true

    $smtpClient = New-Object Net.Mail.SmtpClient($smtpServer)
    $smtpClient.Send($emailMessage)
}

# Close the connection
# Disconnect only if connected
if ($global:DefaultVIServers | Where-Object { $_.Name -eq $vcServer }) {
    Disconnect-VIServer -Server $vcServer -Confirm:$false
}