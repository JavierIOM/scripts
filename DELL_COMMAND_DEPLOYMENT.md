# Dell Command | Monitor Deployment Guide

This guide covers deploying Dell Command | Monitor via Microsoft Intune to enable full dock detection capabilities.

## Why Dell Command | Monitor?

Dell Command | Monitor provides:
- **Full serial numbers** from docking stations
- **Firmware versions** for all connected Dell peripherals
- **Hardware health monitoring** via WMI
- **DCIM WMI namespace** with comprehensive device information

Without it, dock serial numbers are often unavailable through standard Windows APIs.

---

## Deployment Options

### Option 1: Intune Win32 App (Recommended)

This method deploys Dell Command | Monitor as a managed application in Intune.

#### Step 1: Prepare the Application Package

1. Download the installation script:
   ```powershell
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JavierIOM/scripts/main/Install-DellCommandMonitor.ps1" -OutFile "Install-DellCommandMonitor.ps1"
   ```

2. Create the install command file (`install.cmd`):
   ```batch
   @echo off
   PowerShell.exe -ExecutionPolicy Bypass -File Install-DellCommandMonitor.ps1 -SkipReboot
   ```

3. Create the uninstall command file (`uninstall.cmd`):
   ```batch
   @echo off
   wmic product where "name like '%%Dell Command%%Monitor%%'" call uninstall /nointeractive
   ```

4. Download the Microsoft Win32 Content Prep Tool:
   ```
   https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
   ```

5. Create the `.intunewin` package:
   ```powershell
   .\IntuneWinAppUtil.exe -c "C:\DellCommand" -s "install.cmd" -o "C:\Output"
   ```

#### Step 2: Create Win32 App in Intune

1. Navigate to **Microsoft Intune admin center** > **Apps** > **Windows** > **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

**App Information:**
- Name: `Dell Command | Monitor`
- Description: `Provides enhanced WMI access to Dell hardware including dock serial numbers`
- Publisher: `Dell Inc.`

**Program:**
- Install command: `install.cmd`
- Uninstall command: `uninstall.cmd`
- Install behavior: `System`
- Device restart behavior: `Determine behavior based on return codes`

**Requirements:**
- Operating system architecture: `64-bit`
- Minimum operating system: `Windows 10 1809`
- Manufacturer: `Dell Inc.` (Use custom requirement rule)

**Detection Rules:**
- Rule type: `Use a custom detection script`
- Script file: Upload `Intune-DellCommandDetection.ps1`
- Run script as 32-bit process: `No`
- Enforce script signature check: `No`

**Return Codes:**
- `0` - Success
- `1` - Failed
- `3010` - Soft reboot

#### Step 3: Assign to Dell Devices

1. Click **Assignments**
2. Under **Required**, click **Add group**
3. Select your Dell device group (filter by manufacturer if needed)
4. Click **Review + save**

#### Step 4: Monitor Deployment

1. Navigate to **Apps** > **Dell Command | Monitor** > **Device install status**
2. Monitor installation progress
3. Check for any failures and review logs

---

### Option 2: Intune Proactive Remediations

Use Proactive Remediations for automatic installation when Dell Command | Monitor is missing.

#### Step 1: Create Remediation Package

1. Navigate to **Intune admin center** > **Reports** > **Endpoint analytics** > **Proactive remediations**
2. Click **Create script package**

**Basics:**
- Name: `Install Dell Command | Monitor`
- Description: `Ensures Dell Command | Monitor is installed on all Dell systems`

**Settings:**
- Detection script: Upload `Intune-DellCommandDetection.ps1`
- Remediation script: Upload `Install-DellCommandMonitor.ps1`
- Run this script using logged-on credentials: `No` (run as SYSTEM)
- Enforce script signature check: `No`
- Run script in 64-bit PowerShell: `Yes`

#### Step 2: Assign to Dell Devices

1. Click **Assignments**
2. Add your Dell device group
3. Schedule:
   - Frequency: `Daily`
   - Start time: `2:00 AM`

---

### Option 3: Manual Installation via IWR

For quick testing or manual deployment:

```powershell
# Download and run installer
iwr -useb https://raw.githubusercontent.com/JavierIOM/scripts/main/Install-DellCommandMonitor.ps1 | iex
```

Or with parameters:

```powershell
# Download to file and run with parameters
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JavierIOM/scripts/main/Install-DellCommandMonitor.ps1" -OutFile "$env:TEMP\Install-DellCommandMonitor.ps1"
& "$env:TEMP\Install-DellCommandMonitor.ps1" -Verbose
```

---

## Verification

After installation, verify Dell Command | Monitor is working:

### Test 1: Check WMI Namespace

```powershell
Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'"
```

Expected output: Should return a namespace object.

### Test 2: Query Dock Information

```powershell
Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice'
```

Expected output: Should return dock information with serial numbers.

### Test 3: Run Dock Detection Script

```powershell
iwr -useb https://raw.githubusercontent.com/JavierIOM/scripts/main/Get-DellDockInfo.ps1 | iex
```

Expected output: Should show full dock information including serial numbers.

---

## Troubleshooting

### Issue: WMI Namespace Not Available After Installation

**Solution:**
1. Reboot the system
2. Check Windows Event Logs for Dell Command | Monitor service errors
3. Verify the Dell Command | Monitor service is running:
   ```powershell
   Get-Service -Name "Dell*Command*"
   ```

### Issue: Installation Fails with "Not a Dell System"

**Solution:**
- The script only runs on Dell systems
- Verify manufacturer:
  ```powershell
  (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
  ```

### Issue: Download Fails

**Solution:**
1. Check internet connectivity
2. Verify firewall rules allow access to `dl.dell.com`
3. Try manual download from Dell support website

### Issue: Installation Completes but Detection Fails

**Solution:**
1. Wait 5 minutes for WMI namespace initialization
2. Restart the WMI service:
   ```powershell
   Restart-Service -Name Winmgmt -Force
   ```
3. Reboot the system if issues persist

---

## Alternative: Direct Dell Download

If the script method doesn't work, download directly from Dell:

1. Visit: https://www.dell.com/support/home/en-us/product-support/product/command-monitor/drivers
2. Select your operating system
3. Download the latest version
4. Install with: `DellCommandMonitor.exe /s /v/qn`

---

## Post-Deployment Testing

After deploying to your fleet:

1. **Week 1**: Deploy to pilot group (10-20 devices)
   - Monitor installation success rate
   - Verify dock detection works with serials
   - Check for any system performance impact

2. **Week 2-3**: Deploy to broader groups
   - Expand to 100-500 devices
   - Monitor Intune compliance reports

3. **Week 4+**: Full deployment
   - Deploy to all Dell devices
   - Set up recurring detection with dock inventory script

---

## Integration with Dock Detection Script

Once Dell Command | Monitor is deployed, the `Get-DellDockInfo.ps1` script will automatically:
- Detect the DCIM namespace
- Use Dell Command | Monitor for dock queries
- Return full serial numbers and firmware versions
- Provide more accurate and complete dock information

---

## Maintenance

### Updating Dell Command | Monitor

Dell releases updates periodically. To update:

1. Update the download URL in `Install-DellCommandMonitor.ps1`
2. Update the version number
3. Re-deploy via Intune Win32 app (users will get the update)

### Monitoring

Set up Intune compliance reports to track:
- Installation success rate
- WMI namespace availability
- Dock detection success rate

---

## Best Practices

1. **Deploy to Dell devices only** - Use manufacturer filters in Intune assignments
2. **Schedule installations during maintenance windows** - Reduces user disruption
3. **Allow automatic reboots** - Some systems need a reboot for WMI to initialize
4. **Monitor first 48 hours** - Catch any deployment issues early
5. **Keep version updated** - Check Dell support quarterly for updates

---

## Support Resources

- **Dell Command | Monitor Documentation**: https://www.dell.com/support/manuals/en-us/command-monitor
- **Dell Support**: https://www.dell.com/support
- **Intune Documentation**: https://learn.microsoft.com/en-us/mem/intune/

---

## Summary

Dell Command | Monitor is essential for getting complete dock information. Deploy it via Intune Win32 app or Proactive Remediations, then run the dock detection script to get full serial numbers and firmware details from all connected WD series docks.
