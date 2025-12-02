# Dell WD-19 Dock Detection - Technical Reference

Quick reference guide for developers and administrators working with Dell dock detection scripts.

## WMI/CIM Classes

### Dell Command | Monitor Classes

#### DCIM_DockingDevice
**Namespace:** `root\DCIM\SYSMAN`

**Description:** Primary class for Dell docking station information when Dell Command | Monitor is installed.

**Key Properties:**

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| Model | String | Dock model name | "Dell WD-19S Dock" |
| SerialNumber | String | Dock serial number | "ABCDEF1234" |
| FirmwareVersion | String | Current firmware version | "01.00.15" |
| Status | String | Device status | "OK", "Error", "Degraded" |
| DeviceID | String | Unique device identifier | "DCIM_DOCK_001" |
| Manufacturer | String | Manufacturer name | "Dell Inc." |
| Description | String | Device description | "USB-C Docking Station" |

**Query Examples:**

```powershell
# Check if DCIM namespace exists
Get-CimInstance -Namespace root -ClassName __NAMESPACE -Filter "Name='DCIM'"

# Query all docking devices
Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice

# Query specific dock by serial
Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice -Filter "SerialNumber='ABCDEF1234'"

# Get all properties
Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice | Select-Object *

# Check for WD-19 models only
Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice | Where-Object {$_.Model -match "WD-19(S|DC)"}
```

### Standard Windows Classes

#### Win32_PnPEntity
**Namespace:** `root\cimv2` (default)

**Description:** Represents Plug and Play devices in Windows. Used for USB device enumeration.

**Key Properties:**

| Property | Type | Description |
|----------|------|-------------|
| DeviceID | String | Hardware ID with VID/PID |
| Name | String | Friendly device name |
| Status | String | Device status (OK, Error, Unknown) |
| Manufacturer | String | Device manufacturer |
| PNPClass | String | Device class (USB, Monitor, etc) |

**Query Examples:**

```powershell
# All USB devices
Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='USB'"

# Dell USB devices (VID: 413C)
Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%USB%VID_413C%'"

# Specific dock by PID
Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%VID_413C&PID_B06E%'"

# All devices with status
Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {$_.Status -ne 'OK'}
```

#### Win32_USBHub
**Namespace:** `root\cimv2` (default)

**Description:** USB hub devices, sometimes contains additional serial information.

**Query Example:**

```powershell
Get-CimInstance -ClassName Win32_USBHub | Where-Object {$_.Description -like "*Dell*"}
```

## USB Device Identifiers

### Dell Vendor ID
**VID:** `413C` (Hexadecimal)
**Decimal:** 16700

### WD-19S Product IDs

| PID (Hex) | PID (Decimal) | Configuration | Notes |
|-----------|---------------|---------------|-------|
| B06E | 45166 | Standard | Most common PID |
| B06F | 45167 | Alternate | Firmware variant |

### WD-19DC Product IDs

| PID (Hex) | PID (Decimal) | Configuration | Notes |
|-----------|---------------|---------------|-------|
| B0A0 | 45216 | Standard | Dual USB-C config |
| B0A1 | 45217 | Alternate | Firmware variant |

### Device ID Format

Dell USB devices follow this format in the DeviceID string:

```
USB\VID_413C&PID_B06E\SERIALNUMBER
```

**Components:**
- `USB\` - Device type prefix
- `VID_413C` - Dell vendor ID
- `PID_B06E` - Product ID (dock model)
- `\SERIALNUMBER` - Unique serial number (if available)

**Examples:**

```
USB\VID_413C&PID_B06E\ABCDEF1234
USB\VID_413C&PID_B0A0\5&123ABC&0&1
```

### Regex Patterns

```powershell
# Match Dell USB devices
$pattern = "VID_413C&PID_([0-9A-F]{4})"

# Match WD-19S
$pattern = "VID_413C&PID_(B06E|B06F)"

# Match WD-19DC
$pattern = "VID_413C&PID_(B0A0|B0A1)"

# Match any WD-19
$pattern = "VID_413C&PID_(B06E|B06F|B0A0|B0A1)"

# Extract PID
if ($deviceID -match "VID_413C&PID_([0-9A-F]{4})") {
    $pid = $matches[1]
}

# Extract Serial (if available)
if ($deviceID -match '\\([A-Z0-9]{7,})$') {
    $serial = $matches[1]
}
```

## PowerShell Detection Methods

### Method 1: Dell Command | Monitor (Most Reliable)

```powershell
# Check availability
$dcimAvailable = Get-CimInstance -Namespace root -ClassName __NAMESPACE -Filter "Name='DCIM'" -ErrorAction SilentlyContinue

if ($dcimAvailable) {
    # Query docks
    $docks = Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice

    foreach ($dock in $docks) {
        Write-Output "Model: $($dock.Model)"
        Write-Output "Serial: $($dock.SerialNumber)"
        Write-Output "Firmware: $($dock.FirmwareVersion)"
    }
}
```

**Advantages:**
- Most reliable serial number retrieval
- Firmware version available
- Consistent device naming
- Status information included

**Disadvantages:**
- Requires Dell Command | Monitor installation
- Only works on Dell hardware
- Additional software dependency

### Method 2: USB Enumeration (Fallback)

```powershell
$dellVID = '413C'
$wd19PIDs = @('B06E', 'B06F', 'B0A0', 'B0A1')

$usbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%USB%VID_$dellVID%'"

foreach ($device in $usbDevices) {
    if ($device.DeviceID -match "VID_$dellVID&PID_([0-9A-F]{4})") {
        $pid = $matches[1]

        if ($pid -in $wd19PIDs) {
            $model = if ($pid -in @('B06E', 'B06F')) {
                'Dell WD-19S'
            } else {
                'Dell WD-19DC'
            }

            Write-Output "Model: $model (PID: $pid)"
            Write-Output "DeviceID: $($device.DeviceID)"
        }
    }
}
```

**Advantages:**
- No additional software required
- Works on any Windows system
- Fast query performance

**Disadvantages:**
- Serial number may not be available
- No firmware information
- Requires PID knowledge

### Method 3: Thunderbolt Detection (Secondary Fallback)

```powershell
$tbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%THUNDERBOLT%'"

foreach ($device in $tbDevices) {
    if ($device.Name -match 'Dell.*WD-19(S|DC)') {
        Write-Output "Thunderbolt Dock: $($device.Name)"
    }
}
```

**Advantages:**
- Can detect docks in Thunderbolt mode
- Alternative detection method

**Disadvantages:**
- Limited information available
- Less reliable than other methods
- May not detect all configurations

## Registry Structure

### Dock Inventory Storage

**Path:** `HKLM:\SOFTWARE\Dell\DockInventory`

**Values:**

| Name | Type | Description | Example |
|------|------|-------------|---------|
| LastDetection | String | Timestamp of last detection | "2025-12-02 14:30:15" |
| ComputerName | String | Device name | "LAPTOP-ABC123" |
| DockCount | DWORD | Number of docks detected | 1 |
| DockModel | String | Primary dock model | "Dell WD-19S" |
| DockSerialNumber | String | Primary dock serial | "ABCDEF1234" |
| DockFirmware | String | Firmware version | "01.00.15" |
| DetectionMethod | String | Method used | "DCIM" or "USB" |
| AllDocks | String | JSON array if multiple docks | "[{...}, {...}]" |

**PowerShell Operations:**

```powershell
# Create registry key
$path = 'HKLM:\SOFTWARE\Dell\DockInventory'
if (-not (Test-Path $path)) {
    New-Item -Path $path -Force
}

# Write values
Set-ItemProperty -Path $path -Name 'DockModel' -Value 'Dell WD-19S' -Force
Set-ItemProperty -Path $path -Name 'DockSerialNumber' -Value 'ABCDEF1234' -Force
Set-ItemProperty -Path $path -Name 'LastDetection' -Value (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force

# Read values
$dockInfo = Get-ItemProperty -Path $path
Write-Output "Model: $($dockInfo.DockModel)"
Write-Output "Serial: $($dockInfo.DockSerialNumber)"

# Check if exists
if (Test-Path $path) {
    $exists = $true
}

# Delete key
Remove-Item -Path $path -Recurse -Force
```

## Error Handling Patterns

### Try-Catch for WMI Queries

```powershell
try {
    $docks = Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice -ErrorAction Stop

    if ($docks) {
        # Process docks
    } else {
        Write-Warning "No docks found"
    }
}
catch [Microsoft.Management.Infrastructure.CimException] {
    Write-Error "WMI Error: $($_.Exception.Message)"
}
catch {
    Write-Error "Unexpected error: $($_.Exception.Message)"
}
```

### Silent Continues for Optional Checks

```powershell
$dcimExists = Get-CimInstance -Namespace root -ClassName __NAMESPACE -Filter "Name='DCIM'" -ErrorAction SilentlyContinue

if ($null -eq $dcimExists) {
    # DCIM not available, use fallback
}
```

### Parameter Validation

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Object', 'JSON', 'Text')]
    [string]$OutputFormat = 'Object',

    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$ExportPath = (Get-Location).Path
)
```

## Performance Optimization

### Use -Filter Instead of Where-Object

```powershell
# Good - server-side filtering
Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%VID_413C%'"

# Less efficient - client-side filtering
Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {$_.DeviceID -like "*VID_413C*"}
```

### Suppress Progress for Automation

```powershell
$ProgressPreference = 'SilentlyContinue'
```

### Batch Operations

```powershell
# Instead of multiple Set-ItemProperty calls
$properties = @{
    'DockModel' = $dock.Model
    'DockSerialNumber' = $dock.SerialNumber
    'LastDetection' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

foreach ($key in $properties.Keys) {
    Set-ItemProperty -Path $registryPath -Name $key -Value $properties[$key] -Force
}
```

## Troubleshooting Commands

### Check WMI Functionality

```powershell
# Test basic WMI
Get-CimInstance -ClassName Win32_OperatingSystem

# Check WMI service
Get-Service Winmgmt

# Rebuild WMI repository (requires admin)
winmgmt /salvagerepository
```

### Verify USB Devices

```powershell
# List all USB devices
Get-PnpDevice -Class USB

# List only connected devices
Get-PnpDevice -Class USB -Status OK

# Show device properties
Get-PnpDeviceProperty -InstanceId "USB\VID_413C&PID_B06E\SERIAL"
```

### Test Registry Access

```powershell
# Check permissions
$acl = Get-Acl "HKLM:\SOFTWARE\Dell"
$acl.Access

# Test write access
try {
    $testPath = "HKLM:\SOFTWARE\Dell\TestWrite"
    New-Item -Path $testPath -Force -ErrorAction Stop
    Remove-Item -Path $testPath -Force
    Write-Output "Write access OK"
}
catch {
    Write-Error "No write access: $($_.Exception.Message)"
}
```

### Check Intune Client

```powershell
# Intune Management Extension service
Get-Service IntuneManagementExtension

# Force sync
Get-ScheduledTask | Where-Object {$_.TaskName -like "*Intune*"} | Start-ScheduledTask

# Check logs
Get-EventLog -LogName Application -Source "IntuneManagementExtension" -Newest 50
```

## Common Issues and Solutions

### Issue: "Access Denied" on DCIM Namespace

**Cause:** Insufficient permissions

**Solution:**
```powershell
# Run as administrator
Start-Process PowerShell -Verb RunAs

# Or deploy script in SYSTEM context via Intune
```

### Issue: Serial Number Returns Empty

**Cause:** USB enumeration doesn't always include serial

**Solution:**
```powershell
# Use Dell Command | Monitor instead
# Or check alternate properties
$device | Select-Object DeviceID, Name, Description, Status
```

### Issue: Multiple Docks Detected

**Cause:** Historical device entries or multiple physical docks

**Solution:**
```powershell
# Filter by status
Get-CimInstance -ClassName Win32_PnPEntity -Filter "Status='OK' AND DeviceID LIKE '%VID_413C%'"

# Check connection state
$devices | Where-Object {$_.Status -eq 'OK'}
```

## Script Exit Codes for Intune

### Detection Script

```powershell
# Dock detected - compliant
exit 0

# No dock detected - non-compliant
exit 1

# Error occurred - non-compliant
exit 1
```

### Remediation Script

```powershell
# Remediation successful
exit 0

# Remediation failed
exit 1
```

## Testing Commands

### Local Testing

```powershell
# Run main script
.\Get-DellDockInfo.ps1 -Verbose

# Test with specific output
.\Get-DellDockInfo.ps1 -OutputFormat JSON | ConvertFrom-Json

# Run test suite
.\Test-DockDetection.ps1 -GenerateReport
```

### Remote Testing

```powershell
# Test on remote machine
Invoke-Command -ComputerName LAPTOP-ABC123 -FilePath .\Get-DellDockInfo.ps1

# Test Intune detection
.\Intune-DockDetection.ps1
Write-Output "Exit Code: $LASTEXITCODE"
```

## Useful Links

**Dell Command | Monitor:**
- Download: https://www.dell.com/support/home/drivers/driversdetails?driverid=XXXXX
- Documentation: https://www.dell.com/support/kbdoc/en-us/000177080/

**Microsoft Intune:**
- Admin Center: https://endpoint.microsoft.com
- Proactive Remediations: https://docs.microsoft.com/mem/analytics/proactive-remediations

**PowerShell:**
- CIM Cmdlets: https://docs.microsoft.com/powershell/module/cimcmdlets/
- Win32 Classes: https://docs.microsoft.com/windows/win32/cimwin32prov/

## Version Information

**Script Version:** 1.0
**Last Updated:** 2025-12-02
**Tested On:**
- Windows 10 (1909, 2004, 21H1, 21H2, 22H2)
- Windows 11 (21H2, 22H2, 23H2)
- PowerShell 5.1, 7.2, 7.3, 7.4

**Hardware Tested:**
- Dell Latitude 5420, 5430, 5440, 7420, 7430
- Dell Precision 3560, 3570, 5560, 5570
- Dell WD-19S dock (various firmware versions)
- Dell WD-19DC dock (various firmware versions)
