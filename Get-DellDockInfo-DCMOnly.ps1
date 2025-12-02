<#
.SYNOPSIS
    Detects Dell docking stations using ONLY Dell Command | Monitor (v3.0 - DCM Only).

.DESCRIPTION
    This script requires Dell Command | Monitor to be installed and uses ONLY the
    DCIM WMI namespace for dock detection. No fallback methods are used.

    This ensures consistent, accurate serial numbers from Dell's official management tool.

    If Dell Command | Monitor is not installed, the script will fail with instructions.

.PARAMETER OutputFormat
    Specifies the output format: Object, JSON, or Text. Default is Object.

.PARAMETER IncludeAllDocks
    When specified, includes all detected Dell docks, not just WD/UD series models.

.EXAMPLE
    .\Get-DellDockInfo-DCMOnly.ps1
    Returns a custom object with dock information from Dell Command | Monitor.

.EXAMPLE
    .\Get-DellDockInfo-DCMOnly.ps1 -OutputFormat JSON
    Returns dock information in JSON format.

.NOTES
    Author: Intune Automation
    Version: 3.0
    Prerequisites:
    - Dell Command | Monitor (REQUIRED - no alternatives)
    - Dell system (Latitude, Precision, OptiPlex, etc.)
    - Windows 10/11

    To install Dell Command | Monitor:
    - Download from: https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=904df
    - Or use Dell SupportAssist
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Object', 'JSON', 'Text')]
    [string]$OutputFormat = 'Object',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAllDocks
)

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages with timestamp for debugging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error'   { Write-Error $logMessage }
        'Warning' { Write-Warning $logMessage }
        'Debug'   { Write-Debug $logMessage }
        default   { Write-Verbose $logMessage }
    }
}

function Test-DellCommandMonitor {
    <#
    .SYNOPSIS
        Checks if Dell Command | Monitor is installed and accessible.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        Write-Log "Checking for Dell Command | Monitor installation" -Level Debug

        # Check for DCIM namespace (Dell Command | Monitor WMI namespace)
        $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue

        if ($namespace) {
            Write-Log "Dell Command | Monitor DCIM namespace detected" -Level Debug
            return $true
        }

        Write-Log "Dell Command | Monitor DCIM namespace not found" -Level Debug
        return $false
    }
    catch {
        Write-Log "Error checking for Dell Command | Monitor: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Get-DockFromDCIM {
    <#
    .SYNOPSIS
        Retrieves dock information using Dell Command | Monitor WMI classes.
    .DESCRIPTION
        Queries multiple DCIM classes to get comprehensive dock information including
        WD series and UD series docks with accurate serial numbers and firmware versions.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        Write-Log "Querying DCIM WMI classes for docking devices" -Level Debug

        $results = @()

        # Try DCIM_DockingDevice class
        try {
            $dockDevices = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction Stop

            if ($dockDevices) {
                foreach ($dock in $dockDevices) {
                    Write-Log "Found dock via DCIM_DockingDevice: $($dock.Model)" -Level Debug

                    # Filter based on IncludeAllDocks parameter
                    if (-not $IncludeAllDocks) {
                        # Only include WD and UD series docks
                        if ($dock.Model -notmatch '(WD|UD)[-\s]?\d+') {
                            Write-Log "Skipping non-WD/UD series dock: $($dock.Model)" -Level Debug
                            continue
                        }
                    }

                    $dockInfo = [PSCustomObject]@{
                        DetectionMethod = 'DCIM_DockingDevice'
                        Model           = $dock.Model
                        SerialNumber    = $dock.SerialNumber
                        FirmwareVersion = $dock.FirmwareVersion
                        Status          = $dock.Status
                        Connected       = $true
                        DeviceID        = $dock.DeviceID
                        Manufacturer    = 'Dell Inc.'
                        AssetTag        = $dock.AssetTag
                    }

                    $results += $dockInfo
                }
            }
        }
        catch {
            Write-Log "DCIM_DockingDevice class not available or query failed: $($_.Exception.Message)" -Level Debug
        }

        # Try additional DCIM classes that might contain dock info
        try {
            $peripherals = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_Peripheral' -ErrorAction SilentlyContinue

            if ($peripherals) {
                foreach ($peripheral in $peripherals) {
                    # Check if it's a dock
                    if ($peripheral.Description -match 'Dock' -or $peripheral.Name -match '(WD|UD)[-\s]?\d+') {
                        Write-Log "Found dock via DCIM_Peripheral: $($peripheral.Name)" -Level Debug

                        if (-not $IncludeAllDocks) {
                            if ($peripheral.Name -notmatch '(WD|UD)[-\s]?\d+') {
                                continue
                            }
                        }

                        $dockInfo = [PSCustomObject]@{
                            DetectionMethod = 'DCIM_Peripheral'
                            Model           = $peripheral.Name
                            SerialNumber    = $peripheral.SerialNumber
                            FirmwareVersion = $peripheral.Version
                            Status          = $peripheral.Status
                            Connected       = $true
                            DeviceID        = $peripheral.InstanceID
                            Manufacturer    = 'Dell Inc.'
                            AssetTag        = $null
                        }

                        $results += $dockInfo
                    }
                }
            }
        }
        catch {
            Write-Log "DCIM_Peripheral class not available or query failed: $($_.Exception.Message)" -Level Debug
        }

        if ($results.Count -eq 0) {
            Write-Log "No docking devices found in DCIM namespace" -Level Debug
            return $null
        }

        return $results
    }
    catch {
        Write-Log "Error querying DCIM namespace: $($_.Exception.Message)" -Level Error
        return $null
    }
}

#endregion

#region Main Script Logic

Write-Log "Starting Dell dock detection (Dell Command | Monitor ONLY)" -Level Info

# Check if Dell Command | Monitor is installed
if (-not (Test-DellCommandMonitor)) {
    $errorMessage = @"
Dell Command | Monitor is NOT installed on this system.

This script requires Dell Command | Monitor to provide accurate dock information.

To install Dell Command | Monitor:
1. Download from: https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=904df
2. Or use Dell SupportAssist to install it
3. Reboot after installation if required

After installation, run this script again.
"@

    Write-Log $errorMessage -Level Error

    $result = [PSCustomObject]@{
        DockDetected         = $false
        Message              = 'Dell Command | Monitor not installed'
        RequiresInstallation = $true
        InstallURL           = 'https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=904df'
        DetectionDate        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ComputerName         = $env:COMPUTERNAME
        Docks                = @()
    }

    switch ($OutputFormat) {
        'JSON' {
            return $result | ConvertTo-Json -Depth 5 -Compress
        }
        'Text' {
            return $errorMessage
        }
        default {
            return $result
        }
    }
}

Write-Log "Dell Command | Monitor is installed and available" -Level Info

# Query docks from DCIM namespace
$allDocks = Get-DockFromDCIM

# Handle no docks found
if (-not $allDocks -or $allDocks.Count -eq 0) {
    Write-Log "No Dell docks detected via Dell Command | Monitor" -Level Warning

    $result = [PSCustomObject]@{
        DockDetected    = $false
        Message         = 'No Dell docking stations detected'
        DetectionDate   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ComputerName    = $env:COMPUTERNAME
        Docks           = @()
    }

    switch ($OutputFormat) {
        'JSON' {
            return $result | ConvertTo-Json -Depth 5 -Compress
        }
        'Text' {
            return "No Dell docking stations detected on $($env:COMPUTERNAME)"
        }
        default {
            return $result
        }
    }
}

# Prepare final output
$output = [PSCustomObject]@{
    DockDetected    = $true
    DockCount       = $allDocks.Count
    DetectionDate   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ComputerName    = $env:COMPUTERNAME
    Docks           = $allDocks
}

Write-Log "Successfully detected $($allDocks.Count) dock(s) via Dell Command | Monitor" -Level Info

# Return results in requested format
switch ($OutputFormat) {
    'JSON' {
        return $output | ConvertTo-Json -Depth 5 -Compress
    }
    'Text' {
        $textOutput = "Dell Dock Detection Results (Dell Command | Monitor)`n"
        $textOutput += "=" * 60 + "`n"
        $textOutput += "Computer: $($env:COMPUTERNAME)`n"
        $textOutput += "Detection Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        $textOutput += "Docks Found: $($allDocks.Count)`n`n"

        foreach ($dock in $allDocks) {
            $textOutput += "Dock Information:`n"
            $textOutput += "  Model: $($dock.Model)`n"
            $textOutput += "  Serial Number: $($dock.SerialNumber)`n"
            $textOutput += "  Firmware Version: $($dock.FirmwareVersion)`n"
            $textOutput += "  Detection Method: $($dock.DetectionMethod)`n"
            $textOutput += "  Connected: $($dock.Connected)`n"
            $textOutput += "  Status: $($dock.Status)`n"
            if ($dock.AssetTag) {
                $textOutput += "  Asset Tag: $($dock.AssetTag)`n"
            }
            $textOutput += "`n"
        }

        return $textOutput
    }
    default {
        return $output
    }
}

#endregion
