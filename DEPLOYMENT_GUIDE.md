# Dell WD-19 Dock Detection - Intune Deployment Guide

Quick reference guide for deploying Dell dock detection scripts in Microsoft Intune.

## Quick Start

**Total deployment time:** 15-20 minutes

### Step-by-Step Deployment

#### 1. Prepare Prerequisites (5 minutes)

**Required:**
- Intune Administrator or Endpoint Security Manager role
- Access to Microsoft Endpoint Manager admin center
- Target device group(s) defined

**Recommended:**
- Dell Command | Monitor deployed to target devices
- Pilot group of 10-20 devices for testing

#### 2. Create Proactive Remediation (5 minutes)

1. Navigate to: https://endpoint.microsoft.com
2. Go to **Reports** > **Endpoint Analytics** > **Proactive remediations**
3. Click **+ Create script package**

**Configuration:**

| Setting | Value |
|---------|-------|
| Name | Dell WD-19 Dock Inventory |
| Description | Automatically detects and inventories Dell WD-19S and WD-19DC docking stations connected to Dell laptops |
| Publisher | IT Operations |

#### 3. Upload Scripts (2 minutes)

**Detection Script:**
- Upload: `Intune-DockDetection.ps1`
- This script checks if a WD-19 dock is present

**Remediation Script:**
- Upload: `Intune-DockRemediation.ps1`
- This script writes dock details to registry

#### 4. Configure Script Settings (3 minutes)

| Setting | Recommended Value | Notes |
|---------|-------------------|-------|
| Run this script using the logged-on credentials | **No** | Use SYSTEM context for registry access |
| Enforce script signature check | **No** | Unless you digitally sign scripts |
| Run script in 64-bit PowerShell Host | **Yes** | Required for proper WMI access |

#### 5. Configure Scope Tags (Optional)

Add scope tags if using RBAC in your environment.

#### 6. Assign to Device Groups (3 minutes)

**Target Groups:**
- Dell Latitude Laptops
- Dell Precision Workstations
- All Dell Devices (if you have a dynamic group)

**Schedule Settings:**

| Setting | Recommended Value |
|---------|-------------------|
| Run frequency | **Daily** |
| Run time | **9:00 AM** (or during typical work hours) |

#### 7. Review and Create (2 minutes)

Review all settings and click **Create**.

## Verification Steps

### Immediate Verification (Within 1 hour)

1. **Check Deployment Status**
   - Navigate to the Proactive Remediation package
   - Click **Device status**
   - Verify devices are showing up

2. **Test on Pilot Device**
   - Connect WD-19 dock to pilot device
   - Force Intune sync on device:
     ```
     Settings > Accounts > Access work or school > [Your account] > Info > Sync
     ```
   - Wait 5-10 minutes
   - Check results in Endpoint Manager

### Registry Verification (On target device)

Open PowerShell as Administrator:

```powershell
# Check if registry key exists
Test-Path "HKLM:\SOFTWARE\Dell\DockInventory"

# View all dock inventory data
Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory"

# Check specific values
(Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory").DockSerialNumber
```

Expected output:
```
LastDetection     : 2025-12-02 09:15:32
ComputerName      : LAPTOP-ABC123
DockCount         : 1
DockModel         : Dell WD-19S
DockSerialNumber  : ABCDEF1234
DockFirmware      : 01.00.15
DetectionMethod   : DCIM
```

### Report Verification (After 24 hours)

1. Navigate to **Reports** > **Endpoint Analytics** > **Proactive remediations**
2. Click your **Dell WD-19 Dock Inventory** package
3. Review tabs:
   - **Overview**: Success rate, device count
   - **Device status**: Per-device results
   - **Device performance**: Execution times

## Collecting Inventory Reports

### Method 1: Manual Registry Query via PowerShell

Run on each device or remotely:

```powershell
# Local query
Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory"

# Remote query (requires WinRM)
Invoke-Command -ComputerName LAPTOP-ABC123 -ScriptBlock {
    Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory"
}

# Query multiple devices
$computers = Get-Content C:\temp\computerlist.txt
$computers | ForEach-Object {
    Invoke-Command -ComputerName $_ -ScriptBlock {
        [PSCustomObject]@{
            Computer = $env:COMPUTERNAME
            DockModel = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory" -ErrorAction SilentlyContinue).DockModel
            SerialNumber = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory" -ErrorAction SilentlyContinue).DockSerialNumber
            LastDetection = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory" -ErrorAction SilentlyContinue).LastDetection
        }
    }
} | Export-Csv C:\temp\DockInventory.csv -NoTypeInformation
```

### Method 2: Intune Reporting (Recommended)

**Export Device Results:**

1. Go to Proactive Remediation package
2. Click **Device status** tab
3. Click **Export** button
4. Open exported CSV in Excel

**Key Columns:**
- Device name
- User
- Detection status (Pass/Fail)
- Pre-remediation detection output (JSON with dock details)
- Post-remediation output
- Last run time

### Method 3: Custom Device Inventory Script

Deploy via Intune Scripts to collect and centralize data:

```powershell
# Script: Export-DockInventory.ps1
$dockInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Dell\DockInventory" -ErrorAction SilentlyContinue

if ($dockInfo) {
    $output = [PSCustomObject]@{
        ComputerName    = $env:COMPUTERNAME
        DockModel       = $dockInfo.DockModel
        SerialNumber    = $dockInfo.DockSerialNumber
        Firmware        = $dockInfo.DockFirmware
        LastDetection   = $dockInfo.LastDetection
        DetectionMethod = $dockInfo.DetectionMethod
    }

    # Option 1: Output to Intune logs
    Write-Output ($output | ConvertTo-Json -Compress)

    # Option 2: Send to webhook or API
    # Invoke-RestMethod -Uri "https://yourapi.com/dockinventory" -Method Post -Body ($output | ConvertTo-Json) -ContentType "application/json"

    # Option 3: Write to file share
    # $output | Export-Csv "\\fileserver\share\DockInventory\$env:COMPUTERNAME.csv" -NoTypeInformation -Force
}
```

### Method 4: Azure Log Analytics (Advanced)

For enterprise-wide reporting, send data to Log Analytics workspace.

**Modify Intune-DockRemediation.ps1:**

```powershell
# Add after dock detection
function Send-LogAnalyticsData {
    param(
        [string]$workspaceId = "YOUR_WORKSPACE_ID",
        [string]$sharedKey = "YOUR_SHARED_KEY",
        [string]$logType = "DellDockInventory",
        [object]$logData
    )

    $json = $logData | ConvertTo-Json
    $body = [Text.Encoding]::UTF8.GetBytes($json)

    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length

    $xHeaders = "x-ms-date:" + $rfc1123date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $workspaceId,$encodedHash

    $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $authorization
        "Log-Type" = $logType
        "x-ms-date" = $rfc1123date
    }

    try {
        Invoke-RestMethod -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body
        return $true
    }
    catch {
        Write-Output "Error sending to Log Analytics: $($_.Exception.Message)"
        return $false
    }
}

# Use it
$logData = @{
    ComputerName = $env:COMPUTERNAME
    DockModel = $primaryDock.Model
    SerialNumber = $primaryDock.SerialNumber
    FirmwareVersion = $primaryDock.FirmwareVersion
    TimeGenerated = (Get-Date).ToString('o')
}

Send-LogAnalyticsData -logData $logData
```

**Query in Log Analytics:**

```kusto
DellDockInventory_CL
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by ComputerName_s
| project ComputerName_s, DockModel_s, SerialNumber_s, FirmwareVersion_s, TimeGenerated
| order by ComputerName_s asc
```

## Troubleshooting Common Issues

### Issue: Script runs but no dock detected

**Solution:**

1. Verify dock is physically connected and powered
2. Check Device Manager for dock devices
3. Install Dell Command | Monitor:
   ```powershell
   # Check if installed
   Get-WmiObject -Class __NAMESPACE -Namespace root | Where-Object {$_.Name -eq "DCIM"}
   ```
4. Run detection script manually with verbose output:
   ```powershell
   .\Get-DellDockInfo.ps1 -Verbose
   ```

### Issue: Serial number shows as "Unknown"

**Cause:** USB enumeration method can't always extract serial numbers

**Solution:**
- Deploy Dell Command | Monitor (provides reliable serial numbers)
- Serial may be in USB device ID - check manually:
  ```powershell
  Get-PnpDevice | Where-Object {$_.DeviceID -match "VID_413C&PID_B06E"}
  ```

### Issue: Script fails with "Access Denied"

**Cause:** Insufficient permissions for registry writes

**Solution:**
- Ensure "Run this script using the logged-on credentials" is set to **No**
- Script should run in SYSTEM context
- Verify in Device status logs

### Issue: Devices not receiving script

**Cause:** Assignment or policy targeting issue

**Solution:**
1. Check device group membership
2. Verify device compliance
3. Force Intune sync on device
4. Check assignment filters

### Issue: Script runs but takes too long

**Expected runtime:** 5-15 seconds

**If longer:**
- Check for WMI issues: `Get-CimInstance -ClassName Win32_OperatingSystem`
- Rebuild WMI repository: `winmgmt /salvagerepository`
- Check disk performance

## Advanced Configurations

### Configuration 1: Filter by Firmware Version

Detect only docks with outdated firmware:

```powershell
# Add to detection script
$minimumFirmware = [version]"01.00.15"
$currentFirmware = [version]$dock.FirmwareVersion

if ($currentFirmware -lt $minimumFirmware) {
    Write-Output "Firmware update needed"
    exit 1  # Non-compliant
}
```

### Configuration 2: Alert on No Dock

Send notification if expected dock is missing:

```powershell
# Add to remediation script
if ($docks.Count -eq 0) {
    # Send email or Teams notification
    # Call webhook
    Invoke-RestMethod -Uri "https://your-webhook-url" -Method Post -Body (@{
        text = "Warning: No dock detected on $env:COMPUTERNAME"
    } | ConvertTo-Json)
}
```

### Configuration 3: Scheduled Reporting

Create recurring report via Intune or scheduled task:

```powershell
# Weekly report script
$allDevices = Get-IntuneManagedDevice
$dockReport = @()

foreach ($device in $allDevices) {
    # Query registry via PSRemoting or device management API
    # Compile report
}

$dockReport | Export-Csv "\\fileserver\reports\DockInventory_$(Get-Date -Format 'yyyy-MM-dd').csv"
```

## Maintenance

### Weekly Tasks
- Review Proactive Remediation success rates
- Investigate failed detections
- Monitor execution time trends

### Monthly Tasks
- Export and analyze inventory data
- Identify devices without docks (potential unused laptops)
- Check for firmware updates needed
- Review for new dock models to add

### Quarterly Tasks
- Update Product ID lists if new dock models released
- Review and optimize detection methods
- Update documentation with lessons learned

## Support Contacts

**Dell Command | Monitor:**
- Download: https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=xxxxx
- Documentation: Dell TechCenter

**Microsoft Intune:**
- Intune Admin Center: https://endpoint.microsoft.com
- Documentation: https://docs.microsoft.com/en-us/mem/intune/

**Script Issues:**
- Review verbose logs
- Check WMI functionality
- Verify Dell hardware compatibility

## Appendix: Device IDs Quick Reference

### Dell USB Vendor ID
**VID:** `413C`

### WD-19S Product IDs
- `B06E` - Standard configuration
- `B06F` - Alternate configuration

### WD-19DC Product IDs
- `B0A0` - Standard configuration
- `B0A1` - Alternate configuration

### Full Device ID Examples
```
USB\VID_413C&PID_B06E\ABCDEF1234
USB\VID_413C&PID_B0A0\GHIJKL5678
```

## Deployment Checklist

- [ ] Pilot group defined and tested
- [ ] Dell Command | Monitor deployment scheduled
- [ ] Scripts uploaded to Intune
- [ ] Script settings configured correctly
- [ ] Device groups assigned
- [ ] Schedule configured (daily recommended)
- [ ] Scope tags applied (if applicable)
- [ ] Verification test completed on pilot devices
- [ ] Registry keys verified on sample devices
- [ ] Reporting method selected and configured
- [ ] Documentation updated for support team
- [ ] Monitoring alerts configured (optional)
- [ ] Full deployment approved
- [ ] Success criteria defined (e.g., 95% success rate)

## Success Metrics

Track these KPIs:

| Metric | Target | Current |
|--------|--------|---------|
| Detection success rate | >95% | ___ |
| Devices with docks | ___ | ___ |
| Unique dock serial numbers | ___ | ___ |
| Script execution time (avg) | <15s | ___ |
| Failed detections | <5% | ___ |
| Coverage (% of fleet) | 100% | ___ |

## Next Steps After Deployment

1. **Week 1:** Monitor daily, resolve any issues
2. **Week 2-4:** Analyze patterns, optimize if needed
3. **Month 2:** Establish baseline inventory
4. **Ongoing:** Regular reporting and maintenance
