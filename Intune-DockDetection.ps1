<#
.SYNOPSIS
    Intune detection script for Dell WD-19S/WD-19DC docking stations.

.DESCRIPTION
    This script is designed for Microsoft Intune Proactive Remediations or
    Detection scripts. It checks if a Dell WD-19S or WD-19DC dock is connected
    and reports the finding.

    Exit Codes:
    - Exit 0: Dock detected (compliant)
    - Exit 1: No dock detected (non-compliant)

.NOTES
    Author: Intune Automation
    Version: 1.0
    Usage: Deploy as Intune Detection Script or Proactive Remediation Detection

    Script will output JSON to stdout for inventory purposes before exiting.
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

# Suppress progress bars for better performance
$ProgressPreference = 'SilentlyContinue'

function Test-DellCommandMonitor {
    try {
        $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue
        return ($null -ne $namespace)
    }
    catch {
        return $false
    }
}

function Get-DockFromDCIM {
    try {
        $dockDevices = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction Stop

        if (-not $dockDevices) {
            return $null
        }

        $results = @()
        foreach ($dock in $dockDevices) {
            if ($dock.Model -match 'WD-19(S|DC)') {
                $results += [PSCustomObject]@{
                    Model        = $dock.Model
                    SerialNumber = $dock.SerialNumber
                    Method       = 'DCIM'
                }
            }
        }

        return $results
    }
    catch {
        return $null
    }
}

function Get-DockFromUSB {
    try {
        $dellVID = '413C'
        $wd19PIDs = @('B06E', 'B06F', 'B0A0', 'B0A1')

        $usbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%USB%VID_$dellVID%'" -ErrorAction Stop

        $results = @()
        foreach ($device in $usbDevices) {
            if ($device.DeviceID -match "VID_$dellVID&PID_([0-9A-F]{4})") {
                $pid = $matches[1]

                if ($pid -in $wd19PIDs) {
                    $model = if ($pid -in @('B06E', 'B06F')) { 'Dell WD-19S' } else { 'Dell WD-19DC' }

                    $serialNumber = 'Unknown'
                    if ($device.DeviceID -match '\\([A-Z0-9]{7,})$') {
                        $serialNumber = $matches[1]
                    }

                    $results += [PSCustomObject]@{
                        Model        = $model
                        SerialNumber = $serialNumber
                        Method       = 'USB'
                    }
                }
            }
        }

        return $results
    }
    catch {
        return $null
    }
}

# Main detection logic
try {
    $docks = @()

    # Try Dell Command | Monitor first
    if (Test-DellCommandMonitor) {
        $docks = Get-DockFromDCIM
    }

    # Fallback to USB enumeration
    if ($null -eq $docks -or $docks.Count -eq 0) {
        $docks = Get-DockFromUSB
    }

    # Prepare output
    $result = @{
        ComputerName  = $env:COMPUTERNAME
        DetectionDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        DockDetected  = ($null -ne $docks -and $docks.Count -gt 0)
        DockCount     = if ($docks) { $docks.Count } else { 0 }
        Docks         = $docks
    }

    # Output JSON for logging/inventory
    Write-Output ($result | ConvertTo-Json -Compress)

    # Exit with appropriate code for Intune
    if ($result.DockDetected) {
        # Dock detected - compliant
        exit 0
    }
    else {
        # No dock detected - non-compliant
        exit 1
    }
}
catch {
    # Error occurred - treat as non-compliant
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}
