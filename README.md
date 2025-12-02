# Dell WD-19 Dock Detection Scripts

PowerShell scripts for detecting and inventorying Dell WD-19S and WD-19DC docking stations on Windows devices, designed for deployment via Microsoft Intune.

## Overview

These scripts provide multiple detection methods for Dell WD-19 series docking stations:
- Dell Command | Monitor WMI classes (most reliable)
- USB device enumeration with VID/PID matching
- Thunderbolt device detection

## Supported Dock Models

- **Dell WD-19S** - USB-C docking station
- **Dell WD-19DC** - Dual USB-C docking station

## Scripts Included

### 1. Get-DellDockInfo.ps1
Comprehensive detection script with multiple output formats.

**Features:**
- Multiple detection methods with automatic fallback
- Verbose logging for troubleshooting
- Flexible output formats (Object, JSON, Text)
- Error handling and status reporting

**Usage:**
```powershell
# Basic usage - returns object
.\Get-DellDockInfo.ps1

# JSON output for parsing
.\Get-DellDockInfo.ps1 -OutputFormat JSON

# Text output for display
.\Get-DellDockInfo.ps1 -OutputFormat Text

# Include all Dell docks (not just WD-19 series)
.\Get-DellDockInfo.ps1 -IncludeAllDocks

# Enable verbose logging
.\Get-DellDockInfo.ps1 -Verbose
```

### 2. Intune-DockDetection.ps1
Lightweight detection script for Intune Proactive Remediations.

**Exit Codes:**
- `0` - Dock detected (compliant)
- `1` - No dock detected or error (non-compliant)

**Output:**
Outputs JSON to stdout containing detection results.

### 3. Intune-DockRemediation.ps1
Remediation script that writes dock information to registry.

**Registry Location:**
`HKLM:\SOFTWARE\Dell\DockInventory`

**Registry Values:**
- `LastDetection` - Timestamp of last detection
- `ComputerName` - Device name
- `DockCount` - Number of docks detected
- `DockModel` - Primary dock model
- `DockSerialNumber` - Primary dock serial number
- `DockFirmware` - Firmware version (if available)
- `DetectionMethod` - Method used for detection
- `AllDocks` - JSON array if multiple docks detected

## Technical Details

### Dell USB Device Identifiers

**Vendor ID:** `0x413C` (Dell Inc.)

**Product IDs:**
- WD-19S: `0xB06E`, `0xB06F`
- WD-19DC: `0xB0A0`, `0xB0A1`

### WMI/CIM Classes Used

**Dell Command | Monitor Classes:**
- Namespace: `root\DCIM\SYSMAN`
- Class: `DCIM_DockingDevice`
- Properties:
  - `Model` - Dock model name
  - `SerialNumber` - Dock serial number
  - `FirmwareVersion` - Current firmware version
  - `Status` - Connection status
  - `DeviceID` - Unique device identifier

**Standard Windows Classes:**
- `Win32_PnPEntity` - For USB device enumeration
- `Win32_USBHub` - For additional USB information

## Prerequisites

### Recommended
- **Dell Command | Monitor** installed on target devices
  - Download from Dell Support website
  - Provides most reliable detection method
  - Exposes DCIM WMI namespace with dock information

### Minimum Requirements
- Windows 10 version 1809 or later
- Windows 11 (all versions)
- PowerShell 5.1 or later
- Dell Latitude or Precision laptop
- WD-19S or WD-19DC dock connected

### Permissions
- Standard user context: Detection works with user permissions
- Administrator context: Recommended for full WMI access and registry writes

## Intune Deployment

### Method 1: Proactive Remediations (Recommended)

**Step 1: Create Proactive Remediation**
1. Navigate to **Endpoint Manager** > **Reports** > **Endpoint Analytics** > **Proactive remediations**
2. Click **Create script package**
3. Configure:
   - **Name:** Dell WD-19 Dock Inventory
   - **Description:** Detects and inventories Dell WD-19S/DC docking stations

**Step 2: Upload Scripts**
- **Detection script:** Upload `Intune-DockDetection.ps1`
- **Remediation script:** Upload `Intune-DockRemediation.ps1`

**Step 3: Configure Settings**
- **Run this script using logged-on credentials:** No (Use system context)
- **Enforce script signature check:** No (unless you sign the scripts)
- **Run script in 64-bit PowerShell:** Yes

**Step 4: Assign to Groups**
- Assign to device groups containing Dell Latitude/Precision laptops
- Set schedule (recommended: Daily)

### Method 2: Custom Device Configuration

Deploy as a scheduled task using Intune Configuration Profile.

**Step 1: Create PowerShell Script Package**
1. Navigate to **Devices** > **Scripts** > **Add** > **Windows 10 and later**
2. Upload `Get-DellDockInfo.ps1`
3. Configure:
   - **Run script in 64-bit PowerShell:** Yes
   - **Run this script using logged-on credentials:** No
   - **Enforce script signature check:** No

**Step 2: Create Scheduled Task**
Create a Configuration Profile with a scheduled task XML that runs the script daily.

### Method 3: Manual Deployment

For testing or small-scale deployment:

```powershell
# Copy script to target device
Copy-Item .\Get-DellDockInfo.ps1 -Destination "C:\ProgramData\DellScripts\"

# Run manually
PowerShell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\DellScripts\Get-DellDockInfo.ps1" -OutputFormat JSON

# Schedule with Task Scheduler
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\ProgramData\DellScripts\Get-DellDockInfo.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -TaskName "Dell Dock Inventory" -Action $action -Trigger $trigger -RunLevel Highest
```

## Collecting Inventory Data

### Option 1: Registry Query
After remediation runs, query the registry:

```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory"
```

### Option 2: Azure Log Analytics
Modify the remediation script to send data to Log Analytics:

```powershell
# Add to Intune-DockRemediation.ps1
$workspaceId = "YOUR_WORKSPACE_ID"
$sharedKey = "YOUR_SHARED_KEY"
$logType = "DellDockInventory"

# Build JSON payload
$json = @{
    ComputerName = $env:COMPUTERNAME
    DockModel = $primaryDock.Model
    SerialNumber = $primaryDock.SerialNumber
    DetectionDate = (Get-Date).ToString('o')
} | ConvertTo-Json

# Send to Log Analytics (requires Send-OMSAPIIngestionFile function)
```

### Option 3: Export from Intune
Proactive Remediations report shows device status and output.

## Troubleshooting

### No Dock Detected

**Check 1: Physical Connection**
```powershell
# Verify USB devices are detected
Get-PnpDevice -Class USB | Where-Object {$_.Manufacturer -like "*Dell*"}
```

**Check 2: Dell Command | Monitor**
```powershell
# Check if DCIM namespace exists
Get-CimInstance -Namespace root -ClassName __NAMESPACE | Where-Object {$_.Name -eq "DCIM"}

# Query dock devices directly
Get-CimInstance -Namespace root\DCIM\SYSMAN -ClassName DCIM_DockingDevice
```

**Check 3: USB VID/PID**
```powershell
# List all Dell USB devices
Get-PnpDevice | Where-Object {$_.DeviceID -match "VID_413C"}
```

### Serial Number Shows as "Unknown"

This occurs when using USB enumeration fallback. Solutions:
1. Install Dell Command | Monitor for accurate serial numbers
2. Check if serial is available in device's DeviceID string
3. Query additional WMI classes (Win32_USBHub, Win32_SerialPort)

### Permission Errors

Run in elevated PowerShell session:
```powershell
Start-Process PowerShell -Verb RunAs -ArgumentList "-File .\Get-DellDockInfo.ps1"
```

### Verbose Logging

Enable detailed logging for troubleshooting:
```powershell
.\Get-DellDockInfo.ps1 -Verbose -Debug
```

## Example Output

### Object Output
```powershell
DockDetected    : True
DockCount       : 1
DetectionDate   : 2025-12-02 14:30:15
ComputerName    : LAPTOP-ABC123
Docks           : {@{DetectionMethod=DellCommandMonitor; Model=Dell WD-19S; SerialNumber=ABCDEF1234; FirmwareVersion=01.00.15; Status=OK; Connected=True}}
```

### JSON Output
```json
{
  "DockDetected": true,
  "DockCount": 1,
  "DetectionDate": "2025-12-02 14:30:15",
  "ComputerName": "LAPTOP-ABC123",
  "Docks": [
    {
      "DetectionMethod": "DellCommandMonitor",
      "Model": "Dell WD-19S",
      "SerialNumber": "ABCDEF1234",
      "FirmwareVersion": "01.00.15",
      "Status": "OK",
      "Connected": true,
      "DeviceID": "USB\\VID_413C&PID_B06E\\ABCDEF1234",
      "Manufacturer": "Dell Inc."
    }
  ]
}
```

### Text Output
```
Dell Dock Detection Results
==================================================
Computer: LAPTOP-ABC123
Detection Date: 2025-12-02 14:30:15
Docks Found: 1

Dock Information:
  Model: Dell WD-19S
  Serial Number: ABCDEF1234
  Detection Method: DellCommandMonitor
  Connected: True
  Status: OK
  Firmware: 01.00.15
```

## Best Practices

1. **Deploy Dell Command | Monitor** via Intune to all Dell devices for best results
2. **Test scripts** on a pilot group before full deployment
3. **Monitor Proactive Remediation reports** for detection success rates
4. **Set appropriate schedule** - Daily during business hours recommended
5. **Use device filters** to target only Dell Latitude/Precision devices
6. **Implement centralized logging** for enterprise-wide inventory
7. **Regular reporting** on dock firmware versions for update management

## Security Considerations

- Scripts run in SYSTEM context for full access
- No sensitive data is collected (only hardware identifiers)
- Registry writes are to HKLM (requires elevation)
- No network connections made by default scripts
- Scripts do not modify dock settings or firmware

## Customization

### Add Additional Dock Models

Edit the PID arrays in the scripts:

```powershell
$wd19PIDs = @(
    'B06E',  # WD-19S
    'B06F',  # WD-19S (alternate)
    'B0A0',  # WD-19DC
    'B0A1',  # WD-19DC (alternate)
    'XXXX'   # Add new model PID here
)
```

### Change Registry Location

Modify the registry path variable:

```powershell
$registryPath = 'HKLM:\SOFTWARE\YourCompany\DockInventory'
```

### Add Custom Logging

Insert custom logging functions:

```powershell
function Send-ToLogAnalytics {
    # Your custom logging implementation
}
```

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review Intune Proactive Remediation logs
3. Test script manually with -Verbose flag
4. Verify Dell Command | Monitor installation

## Version History

**v1.0** (2025-12-02)
- Initial release
- Support for WD-19S and WD-19DC models
- Multiple detection methods
- Intune deployment scripts
- Comprehensive error handling

## License

These scripts are provided as-is for use in enterprise environments.
