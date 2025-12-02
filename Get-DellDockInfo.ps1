<#
.SYNOPSIS
    Detects Dell WD series docking stations and retrieves their serial numbers (v2.0 - SysInv Support).

.DESCRIPTION
    This script uses multiple detection methods to identify Dell WD series docks:
    1. Dell Command | Monitor WMI classes (DCIM namespace - primary method)
    2. Dell SysInv WMI namespace (root\dell\sysinv - provides real serials without DCM)
    3. USB device enumeration with VID/PID matching (fallback)
    4. Thunderbolt device detection (final fallback)

    Designed for deployment via Microsoft Intune as a detection or inventory script.

.PARAMETER OutputFormat
    Specifies the output format: Object, JSON, or Text. Default is Object.

.PARAMETER IncludeAllDocks
    When specified, includes all detected Dell docks, not just WD-19S/WD-19DC models.

.EXAMPLE
    .\Get-DellDockInfo.ps1
    Returns a custom object with dock information.

.EXAMPLE
    .\Get-DellDockInfo.ps1 -OutputFormat JSON
    Returns dock information in JSON format for easy parsing.

.NOTES
    Author: Intune Automation
    Version: 1.0
    Prerequisites:
    - Dell Command | Monitor (recommended but not required)
    - Administrative privileges for full WMI access
    - Windows 10/11 with Dell Latitude or Precision laptops

    Supported Dock Models:
    - Dell WD-19S (USB-C)
    - Dell WD-19DC (Dual USB-C)
    - Dell WD-15 (USB-C)
    - Dell WD-22TB4 (Thunderbolt 4)
    - Any Dell WD series docks

    Dell USB Vendor ID: 0x413C
    Common WD Series PIDs:
    - WD-19S: 0xB06E, 0xB06F
    - WD-19DC: 0xB0A0, 0xB0A1
    - WD-15: 0xB06C, 0xB06D
    - Other WD models detected via pattern matching
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
            Write-Log "Dell Command | Monitor detected" -Level Debug
            return $true
        }

        Write-Log "Dell Command | Monitor not found" -Level Debug
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
        Queries the DCIM_DockingDevice class which provides comprehensive
        information about Dell docking stations including model and serial number.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        Write-Log "Querying DCIM_DockingDevice WMI class" -Level Debug

        # Query DCIM namespace for docking devices
        $dockDevices = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction Stop

        if (-not $dockDevices) {
            Write-Log "No docking devices found in DCIM namespace" -Level Debug
            return $null
        }

        $results = @()

        foreach ($dock in $dockDevices) {
            Write-Log "Found dock: $($dock.Model)" -Level Debug

            # Filter for WD series docks if IncludeAllDocks is not set
            if (-not $IncludeAllDocks) {
                if ($dock.Model -notmatch 'WD[-\s]?\d+') {
                    Write-Log "Skipping non-WD series dock: $($dock.Model)" -Level Debug
                    continue
                }
            }

            $dockInfo = [PSCustomObject]@{
                DetectionMethod = 'DellCommandMonitor'
                Model           = $dock.Model
                SerialNumber    = $dock.SerialNumber
                FirmwareVersion = $dock.FirmwareVersion
                Status          = $dock.Status
                Connected       = $true
                DeviceID        = $dock.DeviceID
                Manufacturer    = 'Dell Inc.'
            }

            $results += $dockInfo
        }

        return $results
    }
    catch {
        Write-Log "Error querying DCIM namespace: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-DockFromSysInv {
    <#
    .SYNOPSIS
        Retrieves dock information from Dell SysInv WMI namespace.
    .DESCRIPTION
        Queries the dell_softwareidentity class in root\dell\sysinv namespace
        which contains dock firmware and serial information on Dell systems.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        Write-Log "Querying dell_softwareidentity WMI class" -Level Debug

        # Query SysInv namespace for dock firmware/software identities
        $dockDevices = Get-CimInstance -Namespace 'root\dell\sysinv' -ClassName 'dell_softwareidentity' -ErrorAction Stop

        if (-not $dockDevices) {
            Write-Log "No devices found in dell\sysinv namespace" -Level Debug
            return $null
        }

        $results = @()

        foreach ($device in $dockDevices) {
            # Look for WD series docks in ElementName
            if ($device.ElementName -match 'WD[-\s]?\d+') {
                Write-Log "Found dock in SysInv: $($device.ElementName)" -Level Debug

                # Extract model from ElementName (e.g., "WD22TB4 Firmware" -> "WD22TB4")
                $model = 'Dell WD Series'
                if ($device.ElementName -match '(WD[-\s]?\d+\w*)') {
                    $model = "Dell $($matches[1])"
                }

                $dockInfo = [PSCustomObject]@{
                    DetectionMethod = 'DellSysInv'
                    Model           = $model
                    SerialNumber    = $device.SerialNumber
                    FirmwareVersion = $device.VersionString
                    Status          = 'OK'
                    Connected       = $true
                    DeviceID        = $device.InstanceID
                    Manufacturer    = 'Dell Inc.'
                }

                $results += $dockInfo
            }
        }

        if ($results.Count -eq 0) {
            Write-Log "No Dell WD series docks found in SysInv namespace" -Level Debug
        }

        return $results
    }
    catch {
        Write-Log "Error querying dell\sysinv namespace: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-DockFromUSB {
    <#
    .SYNOPSIS
        Retrieves dock information by querying USB devices with Dell VID/PID.
    .DESCRIPTION
        Fallback method that queries Win32_PnPEntity for USB devices matching
        Dell's Vendor ID (0x413C) and known WD-19 series Product IDs.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        Write-Log "Querying USB devices for Dell docks" -Level Debug

        # Dell USB Vendor ID and known WD series PIDs
        $dellVID = '413C'
        $wdSeriesPIDs = @(
            'B06E',  # WD-19S
            'B06F',  # WD-19S (alternate)
            'B0A0',  # WD-19DC
            'B0A1',  # WD-19DC (alternate)
            'B06C',  # WD-15
            'B06D',  # WD-15 (alternate)
            'B0C3',  # WD-22TB4
            'B0C4'   # WD-22TB4 (alternate)
        )

        # Query all PnP devices
        $usbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='USB' OR DeviceID LIKE '%USB%'" -ErrorAction Stop

        $results = @()

        foreach ($device in $usbDevices) {
            # Parse VID/PID from DeviceID (format: USB\VID_413C&PID_B06E\...)
            if ($device.DeviceID -match "VID_$dellVID&PID_([0-9A-F]{4})") {
                $productId = $matches[1]

                # Check if it's a known WD series PID OR if device name contains "WD"
                $isWDDock = ($productId -in $wdSeriesPIDs) -or ($device.Name -match 'WD[-\s]?\d+') -or ($device.Description -match 'WD[-\s]?\d+')

                if ($isWDDock) {
                    Write-Log "Found Dell dock via USB: PID $productId" -Level Debug

                    # Determine model based on PID or device name
                    $model = switch ($productId) {
                        { $_ -in @('B06E', 'B06F') } { 'Dell WD-19S' }
                        { $_ -in @('B0A0', 'B0A1') } { 'Dell WD-19DC' }
                        { $_ -in @('B06C', 'B06D') } { 'Dell WD-15' }
                        { $_ -in @('B0C3', 'B0C4') } { 'Dell WD-22TB4' }
                        default {
                            # Try to extract model from device name
                            if ($device.Name -match '(WD[-\s]?\d+\w*)') {
                                "Dell $($matches[1])"
                            } else {
                                'Dell WD Series'
                            }
                        }
                    }

                    # Extract serial number from DeviceID if available
                    $serialNumber = 'Unknown'
                    if ($device.DeviceID -match '\\([A-Z0-9]+)$') {
                        $serialNumber = $matches[1]
                    }

                    # Try to get serial from Win32_USBHub
                    try {
                        $usbHub = Get-CimInstance -ClassName Win32_USBHub -Filter "DeviceID='$($device.DeviceID)'" -ErrorAction SilentlyContinue
                        if ($usbHub -and $usbHub.Description) {
                            # Some Dell docks report serial in description
                            if ($usbHub.Description -match '\(([A-Z0-9]{7,})\)') {
                                $serialNumber = $matches[1]
                            }
                        }
                    }
                    catch {
                        Write-Log "Could not query USBHub for serial: $($_.Exception.Message)" -Level Debug
                    }

                    $dockInfo = [PSCustomObject]@{
                        DetectionMethod = 'USBEnumeration'
                        Model           = $model
                        SerialNumber    = $serialNumber
                        FirmwareVersion = 'N/A'
                        Status          = $device.Status
                        Connected       = ($device.Status -eq 'OK')
                        DeviceID        = $device.DeviceID
                        Manufacturer    = 'Dell Inc.'
                        ProductID       = $productId
                        VendorID        = $dellVID
                    }

                    $results += $dockInfo
                }
            }
        }

        if ($results.Count -eq 0) {
            Write-Log "No Dell WD series docks found via USB enumeration" -Level Debug
        }

        return $results
    }
    catch {
        Write-Log "Error querying USB devices: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-DockFromThunderbolt {
    <#
    .SYNOPSIS
        Retrieves dock information from Thunderbolt device enumeration.
    .DESCRIPTION
        Secondary fallback that queries Win32_PnPEntity for Thunderbolt devices
        matching Dell dock identifiers.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        Write-Log "Querying Thunderbolt devices for Dell docks" -Level Debug

        # Query Thunderbolt devices
        $tbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%THUNDERBOLT%' OR Name LIKE '%Thunderbolt%'" -ErrorAction Stop

        $results = @()

        foreach ($device in $tbDevices) {
            # Look for Dell WD series identifiers in device names or DeviceID
            $isWDDock = ($device.Name -match 'Dell.*WD[-\s]?\d+') -or
                        ($device.Description -match 'Dell.*WD[-\s]?\d+') -or
                        ($device.DeviceID -match 'VID_413C')

            if ($isWDDock) {
                Write-Log "Found Dell dock via Thunderbolt: $($device.Name)" -Level Debug

                # Extract model from device name
                $model = 'Dell WD Series'
                if ($device.Name -match '(WD[-\s]?\d+\w*)') {
                    $model = "Dell $($matches[1])"
                } elseif ($device.Description -match '(WD[-\s]?\d+\w*)') {
                    $model = "Dell $($matches[1])"
                } elseif ($device.DeviceID -match 'VID_413C&PID_([0-9A-F]{4})') {
                    # Try to determine model from PID
                    $detectedPid = $matches[1]
                    $model = switch ($detectedPid) {
                        { $_ -in @('B06E', 'B06F') } { 'Dell WD-19S' }
                        { $_ -in @('B0A0', 'B0A1') } { 'Dell WD-19DC' }
                        { $_ -in @('B06C', 'B06D') } { 'Dell WD-15' }
                        { $_ -in @('B0C3', 'B0C4') } { 'Dell WD-22TB4' }
                        default { 'Dell WD Series' }
                    }
                }

                # Try to extract serial number from various sources
                $serialNumber = 'Unknown'

                # Method 1: Check for serial in device name or description
                if ($device.Name -match '\(([A-Z0-9]{7,})\)') {
                    $serialNumber = $matches[1]
                } elseif ($device.Description -match '\(([A-Z0-9]{7,})\)') {
                    $serialNumber = $matches[1]
                }

                # Method 2: Try to get registry info for this device
                if ($serialNumber -eq 'Unknown') {
                    try {
                        $instanceId = $device.PNPDeviceID
                        if ($instanceId) {
                            # Query registry for device properties
                            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId"
                            if (Test-Path $regPath) {
                                $deviceProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                                if ($deviceProps.HardwareID) {
                                    # Some docks store serial in HardwareID
                                    foreach ($hwid in $deviceProps.HardwareID) {
                                        if ($hwid -match '\\([A-Z0-9]{7,})') {
                                            $serialNumber = $matches[1]
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Log "Could not query registry for serial: $($_.Exception.Message)" -Level Debug
                    }
                }

                # Method 3: Check if there's a parent USB hub device with serial info
                if ($serialNumber -eq 'Unknown' -and $device.DeviceID -match 'USB') {
                    try {
                        # Try to find parent dock device
                        $usbHubs = Get-CimInstance -ClassName Win32_USBHub -ErrorAction SilentlyContinue
                        foreach ($hub in $usbHubs) {
                            if ($hub.DeviceID -match 'VID_413C' -and $hub.Description -match 'WD') {
                                # Extract serial from hub DeviceID
                                if ($hub.DeviceID -match '\\([A-Z0-9]{7,})(&|$)') {
                                    $serialNumber = $matches[1]
                                    break
                                }
                            }
                        }
                    }
                    catch {
                        Write-Log "Could not query USB hubs for serial: $($_.Exception.Message)" -Level Debug
                    }
                }

                $dockInfo = [PSCustomObject]@{
                    DetectionMethod = 'ThunderboltEnumeration'
                    Model           = $model
                    SerialNumber    = $serialNumber
                    FirmwareVersion = 'N/A'
                    Status          = $device.Status
                    Connected       = ($device.Status -eq 'OK')
                    DeviceID        = $device.DeviceID
                    Manufacturer    = 'Dell Inc.'
                }

                $results += $dockInfo
            }
        }

        if ($results.Count -eq 0) {
            Write-Log "No Dell WD series docks found via Thunderbolt enumeration" -Level Debug
        }

        return $results
    }
    catch {
        Write-Log "Error querying Thunderbolt devices: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

#endregion

#region Main Script Logic

Write-Log "Starting Dell dock detection" -Level Info

# Initialize results array
$allDocks = @()

# Method 1: Try Dell Command | Monitor (most reliable)
if (Test-DellCommandMonitor) {
    Write-Log "Using Dell Command | Monitor for detection" -Level Info
    $dcimDocks = Get-DockFromDCIM

    if ($dcimDocks) {
        $allDocks += $dcimDocks
        Write-Log "Found $($dcimDocks.Count) dock(s) via Dell Command | Monitor" -Level Info
    }
}
else {
    Write-Log "Dell Command | Monitor not available, using fallback methods" -Level Warning
}

# Method 2: Try Dell SysInv namespace (available on Dell systems without DCM)
if ($allDocks.Count -eq 0) {
    Write-Log "Attempting Dell SysInv WMI query" -Level Info
    $sysInvDocks = Get-DockFromSysInv

    if ($sysInvDocks) {
        $allDocks += $sysInvDocks
        Write-Log "Found $($sysInvDocks.Count) dock(s) via Dell SysInv" -Level Info
    }
}

# Method 3: USB enumeration (fallback if WMI methods not available or found nothing)
if ($allDocks.Count -eq 0) {
    Write-Log "Attempting USB device enumeration" -Level Info
    $usbDocks = Get-DockFromUSB

    if ($usbDocks) {
        $allDocks += $usbDocks
        Write-Log "Found $($usbDocks.Count) dock(s) via USB enumeration" -Level Info
    }
}

# Method 4: Thunderbolt enumeration (final fallback)
if ($allDocks.Count -eq 0) {
    Write-Log "Attempting Thunderbolt device enumeration" -Level Info
    $tbDocks = Get-DockFromThunderbolt

    if ($tbDocks) {
        $allDocks += $tbDocks
        Write-Log "Found $($tbDocks.Count) dock(s) via Thunderbolt enumeration" -Level Info
    }
}

# Handle no docks found
if ($allDocks.Count -eq 0) {
    Write-Log "No Dell WD series docks detected on this system" -Level Warning

    $result = [PSCustomObject]@{
        DockDetected    = $false
        Message         = 'No Dell WD series docking stations detected'
        DetectionDate   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ComputerName    = $env:COMPUTERNAME
        Docks           = @()
    }

    switch ($OutputFormat) {
        'JSON' {
            return $result | ConvertTo-Json -Depth 5 -Compress
        }
        'Text' {
            return "No Dell WD series docking stations detected on $($env:COMPUTERNAME)"
        }
        default {
            return $result
        }
    }
}

# Deduplicate docks (multiple USB interfaces may represent the same physical dock)
$uniqueDocks = @()
$processedSerials = @{}

foreach ($dock in $allDocks) {
    # Create a unique key based on Model, SerialNumber, or ProductID
    $key = if ($dock.SerialNumber -and $dock.SerialNumber -ne 'Unknown') {
        # Use serial number as primary key if available
        $dock.SerialNumber
    } elseif ($dock.ProductID) {
        # Use ProductID for USB-detected docks
        "$($dock.ProductID)_$($dock.Model)"
    } else {
        # Use Model and DeviceID for other detection methods
        "$($dock.Model)_$($dock.DeviceID)"
    }

    # If this is a sub-interface (MI_XX) and we already have the parent, skip it
    if ($dock.DeviceID -match '&MI_\d+\\' -and $dock.SerialNumber -eq 'Unknown') {
        # Check if we have a better entry (parent device) with same model
        $parentExists = $allDocks | Where-Object {
            $_.Model -eq $dock.Model -and
            $_.DeviceID -notmatch '&MI_\d+\\' -and
            $_.SerialNumber -ne 'Unknown'
        }

        if ($parentExists) {
            Write-Log "Skipping sub-interface: $($dock.DeviceID)" -Level Debug
            continue
        }
    }

    # If we haven't seen this dock yet, or this one has better info, add/update it
    if (-not $processedSerials.ContainsKey($key)) {
        $processedSerials[$key] = $dock
    }
    else {
        # If current dock has serial and stored one doesn't, replace it
        $stored = $processedSerials[$key]
        if ($dock.SerialNumber -and $dock.SerialNumber -ne 'Unknown' -and
            ($stored.SerialNumber -eq 'Unknown' -or -not $stored.SerialNumber)) {
            $processedSerials[$key] = $dock
            Write-Log "Updated dock entry with better serial: $($dock.SerialNumber)" -Level Debug
        }
    }
}

# Convert hashtable to array
$uniqueDocks = $processedSerials.Values

# Prepare final output
$output = [PSCustomObject]@{
    DockDetected    = $true
    DockCount       = $uniqueDocks.Count
    DetectionDate   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ComputerName    = $env:COMPUTERNAME
    Docks           = $uniqueDocks
}

Write-Log "Successfully detected $($uniqueDocks.Count) unique dock(s)" -Level Info

# Return results in requested format
switch ($OutputFormat) {
    'JSON' {
        return $output | ConvertTo-Json -Depth 5 -Compress
    }
    'Text' {
        $textOutput = "Dell Dock Detection Results`n"
        $textOutput += "=" * 50 + "`n"
        $textOutput += "Computer: $($env:COMPUTERNAME)`n"
        $textOutput += "Detection Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        $textOutput += "Docks Found: $($allDocks.Count)`n`n"

        foreach ($dock in $allDocks) {
            $textOutput += "Dock Information:`n"
            $textOutput += "  Model: $($dock.Model)`n"
            $textOutput += "  Serial Number: $($dock.SerialNumber)`n"
            $textOutput += "  Detection Method: $($dock.DetectionMethod)`n"
            $textOutput += "  Connected: $($dock.Connected)`n"
            $textOutput += "  Status: $($dock.Status)`n"
            if ($dock.FirmwareVersion -ne 'N/A') {
                $textOutput += "  Firmware: $($dock.FirmwareVersion)`n"
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
