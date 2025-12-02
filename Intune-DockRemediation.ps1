<#
.SYNOPSIS
    Intune remediation script for Dell WD-19S/WD-19DC docking station inventory.

.DESCRIPTION
    This script runs when a dock is detected (or not detected) by the detection script.
    It can be used to:
    - Log detailed dock information to a central location
    - Update a registry key with dock serial number
    - Report to a web API or Azure Log Analytics
    - Send notification about dock status

    This example writes dock information to the registry for inventory purposes.

.NOTES
    Author: Intune Automation
    Version: 1.0
    Usage: Deploy as Intune Proactive Remediation Script

    Exit Codes:
    - Exit 0: Remediation successful
    - Exit 1: Remediation failed
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

# Suppress progress bars
$ProgressPreference = 'SilentlyContinue'

# Registry path for storing dock information
$registryPath = 'HKLM:\SOFTWARE\Dell\DockInventory'

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
                    Model           = $dock.Model
                    SerialNumber    = $dock.SerialNumber
                    FirmwareVersion = $dock.FirmwareVersion
                    Status          = $dock.Status
                    Method          = 'DCIM'
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
                        Model           = $model
                        SerialNumber    = $serialNumber
                        FirmwareVersion = 'N/A'
                        Status          = $device.Status
                        Method          = 'USB'
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

function Set-DockInventoryRegistry {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Docks
    )

    try {
        # Create registry path if it doesn't exist
        if (-not (Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
        }

        # Write dock information to registry
        Set-ItemProperty -Path $registryPath -Name 'LastDetection' -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force
        Set-ItemProperty -Path $registryPath -Name 'ComputerName' -Value $env:COMPUTERNAME -Force
        Set-ItemProperty -Path $registryPath -Name 'DockCount' -Value $Docks.Count -Force

        # Write primary dock info (first dock if multiple)
        $primaryDock = $Docks[0]
        Set-ItemProperty -Path $registryPath -Name 'DockModel' -Value $primaryDock.Model -Force
        Set-ItemProperty -Path $registryPath -Name 'DockSerialNumber' -Value $primaryDock.SerialNumber -Force
        Set-ItemProperty -Path $registryPath -Name 'DockFirmware' -Value $primaryDock.FirmwareVersion -Force
        Set-ItemProperty -Path $registryPath -Name 'DetectionMethod' -Value $primaryDock.Method -Force

        # If multiple docks, store as JSON
        if ($Docks.Count -gt 1) {
            $docksJson = $Docks | ConvertTo-Json -Compress
            Set-ItemProperty -Path $registryPath -Name 'AllDocks' -Value $docksJson -Force
        }

        Write-Output "Successfully wrote dock inventory to registry"
        return $true
    }
    catch {
        Write-Output "Error writing to registry: $($_.Exception.Message)"
        return $false
    }
}

# Main remediation logic
try {
    Write-Output "Starting dock inventory remediation"

    $docks = @()

    # Try Dell Command | Monitor first
    if (Test-DellCommandMonitor) {
        Write-Output "Using Dell Command | Monitor for detection"
        $docks = Get-DockFromDCIM
    }

    # Fallback to USB enumeration
    if ($null -eq $docks -or $docks.Count -eq 0) {
        Write-Output "Using USB enumeration for detection"
        $docks = Get-DockFromUSB
    }

    if ($null -ne $docks -and $docks.Count -gt 0) {
        Write-Output "Found $($docks.Count) Dell WD-19 dock(s)"

        # Write to registry
        $success = Set-DockInventoryRegistry -Docks $docks

        if ($success) {
            Write-Output "Remediation completed successfully"
            exit 0
        }
        else {
            Write-Output "Remediation failed - could not write to registry"
            exit 1
        }
    }
    else {
        Write-Output "No Dell WD-19 docks detected"

        # Update registry to reflect no dock
        if (-not (Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
        }

        Set-ItemProperty -Path $registryPath -Name 'LastDetection' -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force
        Set-ItemProperty -Path $registryPath -Name 'DockCount' -Value 0 -Force
        Set-ItemProperty -Path $registryPath -Name 'DockModel' -Value 'None' -Force
        Set-ItemProperty -Path $registryPath -Name 'DockSerialNumber' -Value 'None' -Force

        Write-Output "Updated registry to reflect no dock connected"
        exit 0
    }
}
catch {
    Write-Output "Error during remediation: $($_.Exception.Message)"
    exit 1
}
