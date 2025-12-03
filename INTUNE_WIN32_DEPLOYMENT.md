# Dell Command | Monitor - Intune Win32 App Deployment Guide

Complete step-by-step guide for packaging and deploying Dell Command | Monitor as an Intune Win32 application.

---

## Prerequisites

### Required Software

1. **Microsoft Win32 Content Prep Tool**
   - Download: https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
   - File: `IntuneWinAppUtil.exe`

2. **Dell Command | Monitor Installer**
   - Download from Dell Support: https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=904df
   - Latest version: 10.12.3 (as of December 2025)
   - File name: `Dell-Command-Monitor_10.12.3_A00.EXE`

3. **Intune Administrator Access**
   - Global Administrator or Intune Service Administrator role
   - Access to Microsoft Intune admin center

### Required Permissions

- Intune App Manager or Administrator
- Ability to create and assign applications in Intune
- Access to create device groups in Azure AD

---

## Part 1: Download Dell Command | Monitor

### Step 1: Download from Dell Support

1. Open web browser and navigate to:
   ```
   https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=904df
   ```

2. Click the **"Download"** button

3. Save the file to a dedicated folder on your computer:
   ```
   C:\IntuneApps\DellCommandMonitor\
   ```

4. Verify the downloaded file:
   - File name: `Dell-Command-Monitor_10.12.3_A00.EXE` (or similar)
   - File size: ~60-80 MB
   - File type: Executable (.EXE)

### Step 2: Test the Installer Locally (Optional but Recommended)

Before packaging, test the silent installation on a test machine:

```powershell
# Test silent install
.\Dell-Command-Monitor_10.12.3_A00.EXE /s /v/qn

# Wait for installation to complete (3-5 minutes)

# Verify installation
Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'"
```

If the installation succeeds and the WMI namespace appears, you're ready to package!

---

## Part 2: Configure Email Notifications

Before creating the installation scripts, configure email notifications to receive installation status updates.

### Email Configuration Options

The installation script will send email notifications for:
- ✅ Successful installations
- ❌ Failed installations
- ⚠️ Non-Dell systems (skipped)
- ⏩ Already installed (skipped)
- 🔄 Reboot required

### Option 1: Office 365 / Microsoft 365 (Recommended)

**Requirements:**
- Mailbox or shared mailbox in your Microsoft 365 tenant
- App password (if MFA is enabled)

**Configuration:**
```powershell
$emailEnabled = $true
$smtpServer = "smtp.office365.com"
$smtpPort = 587
$emailFrom = "intune-alerts@yourcompany.com"
$emailTo = "your.email@yourcompany.com"
$emailUser = "intune-alerts@yourcompany.com"
$emailPassword = "YourAppPasswordHere"
```

**To create an app password:**
1. Go to https://mysignins.microsoft.com/security-info
2. Click "+ Add sign-in method" > "App password"
3. Name it "Intune DCM Notifications"
4. Copy the generated password and use it in the script

### Option 2: Gmail

**Configuration:**
```powershell
$emailEnabled = $true
$smtpServer = "smtp.gmail.com"
$smtpPort = 587
$emailFrom = "your-account@gmail.com"
$emailTo = "your.email@yourcompany.com"
$emailUser = "your-account@gmail.com"
$emailPassword = "YourGmailAppPassword"
```

**To create a Gmail app password:**
1. Go to https://myaccount.google.com/security
2. Enable 2-Step Verification if not already enabled
3. Go to "App passwords"
4. Generate a new app password for "Mail"
5. Use the 16-character password in the script

### Option 3: Custom SMTP Server

For corporate SMTP servers (with or without authentication):

**With Authentication:**
```powershell
$emailEnabled = $true
$smtpServer = "smtp.yourcompany.com"
$smtpPort = 587  # Use 587 for TLS or 25 for standard
$emailFrom = "intune-alerts@yourcompany.com"
$emailTo = "your.email@yourcompany.com"
$emailUser = "smtp-username"
$emailPassword = "smtp-password"
```

**Without Authentication (Internal SMTP Relay):**
```powershell
$emailEnabled = $true
$smtpServer = "smtp.yourcompany.com"
$smtpPort = 25  # Standard SMTP port
$emailFrom = "intune-alerts@yourcompany.com"
$emailTo = "your.email@yourcompany.com"
$emailUser = $null  # No credentials needed
$emailPassword = $null
```

### Option 4: Disable Email Notifications

If you don't want email notifications:
```powershell
$emailEnabled = $false
```

### Email Format

Emails will be sent in HTML format with:
- **Subject line:** `[SUCCESS]` or `[FAILURE]` Dell Command Monitor Installation - COMPUTER-NAME
- **Computer details:** Name, manufacturer, model, serial number, OS version, user
- **Installation status:** Success/Failure with details
- **Full installation log:** Complete log content for troubleshooting

**Example success email:**
```
Subject: [SUCCESS] Dell Command Monitor Installation - LAPTOP-ABC123

Status: SUCCESS
Computer Name: LAPTOP-ABC123
Date/Time: 2025-12-03 14:30:15
Manufacturer: Dell Inc.
Model: Latitude 7420
Serial Number: 5JQXYZ3
OS Version: Windows 11 Pro
Details: Installation completed successfully. DCIM namespace is available.

[Installation Log]
[2025-12-03 14:28:45] [Info] Starting Dell Command | Monitor installation
[2025-12-03 14:28:46] [Info] Dell system detected: Dell Inc.
...
```

---

## Part 3: Create Installation Wrapper Scripts

Create wrapper scripts for better control over installation, logging, and email notifications.

### Step 1: Create Install Script

Create `Install-DCM.ps1` in `C:\IntuneApps\DellCommandMonitor\`:

```powershell
<#
.SYNOPSIS
    Installs Dell Command | Monitor silently for Intune deployment.
.DESCRIPTION
    Wrapper script for Dell Command Monitor installation via Intune.
    Provides enhanced logging, exit code handling, and email notifications.
#>

[CmdletBinding()]
param()

# Initialize
$exitCode = 0
$installerName = "Dell-Command-Monitor_10.12.3_A00.EXE"
$installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerName
$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DCM-Install.log"

# Email Configuration
$emailEnabled = $true
$smtpServer = "mail.yourdomain.com"  # Replace with your SMTP server
$smtpPort = 25  # Standard SMTP port (no auth)
$emailFrom = "intune-alerts@yourdomain.com"
$emailTo = "your.email@yourdomain.com"  # Replace with your email
$emailSubject = "Dell Command Monitor Installation - $env:COMPUTERNAME"
# No credentials required for internal SMTP relay
$emailUser = $null
$emailPassword = $null

# Function to write logs
function Write-InstallLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logPath -Value $logMessage -Force
    Write-Host $logMessage
}

# Function to send email notification
function Send-InstallEmail {
    param(
        [string]$Status,  # "SUCCESS" or "FAILURE"
        [string]$Details,
        [string]$LogContent
    )

    if (-not $emailEnabled) {
        Write-InstallLog "Email notifications disabled, skipping email"
        return
    }

    try {
        Write-InstallLog "Preparing email notification..."

        # Get computer details
        $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        $manufacturer = $computerInfo.Manufacturer
        $model = $computerInfo.Model
        $serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
        $osVersion = $osInfo.Caption
        $userName = $computerInfo.UserName
        $installDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Determine status color and icon
        if ($Status -eq "SUCCESS") {
            $statusColor = "#28a745"
            $statusIcon = "✓"
            $emailSubjectFull = "[SUCCESS] $emailSubject"
        }
        else {
            $statusColor = "#dc3545"
            $statusIcon = "✗"
            $emailSubjectFull = "[FAILURE] $emailSubject"
        }

        # Build HTML email body
        $emailBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 800px; margin: 0 auto; padding: 20px; }
        .header { background-color: $statusColor; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
        .header h1 { margin: 0; font-size: 24px; }
        .status-icon { font-size: 48px; margin-bottom: 10px; }
        .content { background-color: #f8f9fa; padding: 20px; border: 1px solid #dee2e6; }
        .info-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .info-table td { padding: 10px; border-bottom: 1px solid #dee2e6; }
        .info-table td:first-child { font-weight: bold; width: 180px; background-color: #e9ecef; }
        .log-section { background-color: #fff; padding: 15px; border: 1px solid #dee2e6; border-radius: 5px; margin-top: 20px; }
        .log-content { background-color: #f4f4f4; padding: 10px; border-radius: 3px; font-family: 'Courier New', monospace; font-size: 12px; white-space: pre-wrap; word-wrap: break-word; max-height: 400px; overflow-y: auto; }
        .footer { text-align: center; margin-top: 20px; color: #6c757d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="status-icon">$statusIcon</div>
            <h1>Dell Command | Monitor Installation $Status</h1>
        </div>
        <div class="content">
            <h2>Installation Details</h2>
            <table class="info-table">
                <tr>
                    <td>Status</td>
                    <td><strong style="color: $statusColor;">$Status</strong></td>
                </tr>
                <tr>
                    <td>Computer Name</td>
                    <td>$env:COMPUTERNAME</td>
                </tr>
                <tr>
                    <td>Date/Time</td>
                    <td>$installDate</td>
                </tr>
                <tr>
                    <td>Manufacturer</td>
                    <td>$manufacturer</td>
                </tr>
                <tr>
                    <td>Model</td>
                    <td>$model</td>
                </tr>
                <tr>
                    <td>Serial Number</td>
                    <td>$serialNumber</td>
                </tr>
                <tr>
                    <td>OS Version</td>
                    <td>$osVersion</td>
                </tr>
                <tr>
                    <td>Current User</td>
                    <td>$userName</td>
                </tr>
                <tr>
                    <td>Details</td>
                    <td>$Details</td>
                </tr>
            </table>

            <div class="log-section">
                <h3>Installation Log</h3>
                <div class="log-content">$LogContent</div>
            </div>
        </div>
        <div class="footer">
            <p>This is an automated notification from Microsoft Intune</p>
            <p>Dell Command | Monitor Deployment - $(Get-Date -Format 'yyyy')</p>
        </div>
    </div>
</body>
</html>
"@

        # Build mail parameters
        $mailParams = @{
            From       = $emailFrom
            To         = $emailTo
            Subject    = $emailSubjectFull
            Body       = $emailBody
            BodyAsHtml = $true
            SmtpServer = $smtpServer
            Port       = $smtpPort
        }

        # Add credentials if provided
        if ($emailUser -and $emailPassword) {
            $securePassword = ConvertTo-SecureString $emailPassword -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($emailUser, $securePassword)
            $mailParams.Add('Credential', $credential)
            $mailParams.Add('UseSsl', $true)
        }

        Send-MailMessage @mailParams -ErrorAction Stop
        Write-InstallLog "Email notification sent successfully to $emailTo"
    }
    catch {
        Write-InstallLog "Failed to send email notification: $($_.Exception.Message)" "WARNING"
    }
}

Write-InstallLog "Starting Dell Command | Monitor installation"

# Check if running on Dell system
try {
    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if ($manufacturer -notmatch 'Dell') {
        Write-InstallLog "Not a Dell system. Manufacturer: $manufacturer" "WARNING"
        Write-InstallLog "Exiting with success (no action needed on non-Dell systems)"

        # Send email for non-Dell system
        $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
        Send-InstallEmail -Status "SUCCESS" -Details "Skipped installation (non-Dell system: $manufacturer)" -LogContent $logContent

        exit 0
    }
    Write-InstallLog "Dell system detected: $manufacturer"
}
catch {
    Write-InstallLog "Error checking manufacturer: $($_.Exception.Message)" "ERROR"

    # Send email for error
    $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
    Send-InstallEmail -Status "FAILURE" -Details "Error checking manufacturer: $($_.Exception.Message)" -LogContent $logContent

    exit 1603
}

# Verify installer exists
if (-not (Test-Path -Path $installerPath)) {
    Write-InstallLog "Installer not found: $installerPath" "ERROR"

    # Send email for missing installer
    $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
    Send-InstallEmail -Status "FAILURE" -Details "Installer file not found: $installerPath" -LogContent $logContent

    exit 1603
}
Write-InstallLog "Installer found: $installerPath"

# Check if already installed
try {
    $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue
    if ($namespace) {
        Write-InstallLog "Dell Command | Monitor already installed (DCIM namespace exists)" "WARNING"
        Write-InstallLog "Exiting with success (already installed)"

        # Send email for already installed
        $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
        Send-InstallEmail -Status "SUCCESS" -Details "Already installed (DCIM namespace exists)" -LogContent $logContent

        exit 0
    }
}
catch {
    Write-InstallLog "Error checking for existing installation: $($_.Exception.Message)" "WARNING"
}

# Run installer
Write-InstallLog "Starting installation process..."
try {
    $installArgs = @('/s', '/v/qn')
    $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

    $exitCode = $process.ExitCode
    Write-InstallLog "Installer exit code: $exitCode"

    if ($exitCode -eq 0) {
        Write-InstallLog "Installation completed successfully"

        # Wait for WMI namespace (up to 30 seconds)
        Write-InstallLog "Waiting for DCIM WMI namespace to initialize..."
        $timeout = 30
        $elapsed = 0
        $namespaceReady = $false

        while ($elapsed -lt $timeout) {
            Start-Sleep -Seconds 2
            $elapsed += 2

            $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue
            if ($namespace) {
                Write-InstallLog "DCIM WMI namespace is available"
                $namespaceReady = $true
                break
            }
        }

        if (-not $namespaceReady) {
            Write-InstallLog "DCIM namespace not available after $timeout seconds. A reboot may be required." "WARNING"

            # Send email for soft reboot required
            $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
            Send-InstallEmail -Status "SUCCESS" -Details "Installation completed but requires reboot (DCIM namespace not yet available)" -LogContent $logContent

            # Return 3010 to indicate soft reboot
            exit 3010
        }

        Write-InstallLog "Installation and verification complete"

        # Send success email
        $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
        Send-InstallEmail -Status "SUCCESS" -Details "Installation completed successfully. DCIM namespace is available." -LogContent $logContent

        exit 0
    }
    elseif ($exitCode -eq 3010) {
        Write-InstallLog "Installation succeeded but requires reboot"

        # Send email for reboot required
        $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
        Send-InstallEmail -Status "SUCCESS" -Details "Installation succeeded but requires reboot (exit code 3010)" -LogContent $logContent

        exit 3010
    }
    else {
        Write-InstallLog "Installation failed with exit code: $exitCode" "ERROR"

        # Send failure email
        $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
        Send-InstallEmail -Status "FAILURE" -Details "Installation failed with exit code: $exitCode" -LogContent $logContent

        exit $exitCode
    }
}
catch {
    Write-InstallLog "Error during installation: $($_.Exception.Message)" "ERROR"

    # Send failure email
    $logContent = Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue
    Send-InstallEmail -Status "FAILURE" -Details "Exception during installation: $($_.Exception.Message)" -LogContent $logContent

    exit 1603
}
```

### Step 2: Create Install Command File

Create `install.cmd` in `C:\IntuneApps\DellCommandMonitor\`:

```batch
@echo off
REM Dell Command Monitor Installation Wrapper
REM Executes PowerShell installation script

PowerShell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0Install-DCM.ps1"
exit /b %ERRORLEVEL%
```

### Step 3: Create Uninstall Script

Create `Uninstall-DCM.ps1` in `C:\IntuneApps\DellCommandMonitor\`:

```powershell
<#
.SYNOPSIS
    Uninstalls Dell Command | Monitor.
#>

$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DCM-Uninstall.log"

function Write-UninstallLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Force
    Write-Host "[$timestamp] $Message"
}

Write-UninstallLog "Starting Dell Command | Monitor uninstallation"

# Method 1: Try WMI uninstall
try {
    $app = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Dell Command%Monitor%'" -ErrorAction SilentlyContinue
    if ($app) {
        Write-UninstallLog "Found via WMI: $($app.Name)"
        $result = $app | Invoke-CimMethod -MethodName Uninstall
        if ($result.ReturnValue -eq 0) {
            Write-UninstallLog "Uninstalled successfully via WMI"
            exit 0
        }
    }
}
catch {
    Write-UninstallLog "WMI uninstall failed: $($_.Exception.Message)"
}

# Method 2: Try registry-based uninstall
try {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Dell Command.*Monitor' }

        foreach ($app in $apps) {
            if ($app.UninstallString) {
                Write-UninstallLog "Found uninstall string: $($app.UninstallString)"
                $uninstallString = $app.UninstallString -replace 'msiexec.exe', '' -replace '/I', '/X'
                $arguments = "$uninstallString /qn /norestart"
                Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -NoNewWindow
                Write-UninstallLog "Uninstall command executed"
                exit 0
            }
        }
    }
}
catch {
    Write-UninstallLog "Registry-based uninstall failed: $($_.Exception.Message)"
}

Write-UninstallLog "Dell Command | Monitor not found or already uninstalled"
exit 0
```

### Step 4: Create Uninstall Command File

Create `uninstall.cmd` in `C:\IntuneApps\DellCommandMonitor\`:

```batch
@echo off
REM Dell Command Monitor Uninstallation Wrapper

PowerShell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0Uninstall-DCM.ps1"
exit /b %ERRORLEVEL%
```

### Step 5: Verify Folder Structure

Your folder should now look like this:

```
C:\IntuneApps\DellCommandMonitor\
├── Dell-Command-Monitor_10.12.3_A00.EXE
├── install.cmd
├── Install-DCM.ps1
├── uninstall.cmd
└── Uninstall-DCM.ps1
```

---

## Part 3: Package with IntuneWinAppUtil

### Step 1: Download Win32 Content Prep Tool

1. Go to: https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool/releases
2. Download the latest `IntuneWinAppUtil.exe`
3. Save to: `C:\IntuneApps\`

### Step 2: Package the Application

1. Open PowerShell as Administrator

2. Navigate to the tool location:
   ```powershell
   cd C:\IntuneApps
   ```

3. Run the packaging tool:
   ```powershell
   .\IntuneWinAppUtil.exe
   ```

4. When prompted, enter the following:

   **Source folder:**
   ```
   C:\IntuneApps\DellCommandMonitor
   ```

   **Setup file:**
   ```
   install.cmd
   ```

   **Output folder:**
   ```
   C:\IntuneApps\Output
   ```

   **Catalog folder (optional):**
   ```
   n
   ```
   (Press Enter to skip)

5. The tool will create: `C:\IntuneApps\Output\install.intunewin`

### Step 3: Verify Package

Check that the `.intunewin` file was created:

```powershell
Get-ChildItem C:\IntuneApps\Output\install.intunewin
```

Expected output:
```
Name              Size (approx)
----              -------------
install.intunewin 60-80 MB
```

---

## Part 4: Upload to Microsoft Intune

### Step 1: Access Intune Admin Center

1. Open browser and go to: https://intune.microsoft.com
2. Sign in with admin credentials
3. Navigate to: **Apps** > **All apps**

### Step 2: Create New Win32 App

1. Click **+ Add**
2. Select **Windows app (Win32)** from dropdown
3. Click **Select**

### Step 3: App Information

1. Click **Select app package file**
2. Browse and select: `C:\IntuneApps\Output\install.intunewin`
3. Click **OK**

4. Fill in the app information:

   **Name:**
   ```
   Dell Command | Monitor
   ```

   **Description:**
   ```
   Dell Command | Monitor provides enhanced WMI access to Dell hardware information including docking station serial numbers, firmware versions, and system health monitoring.
   ```

   **Publisher:**
   ```
   Dell Inc.
   ```

   **App Version:**
   ```
   10.12.3
   ```

   **Information URL (optional):**
   ```
   https://www.dell.com/support/kbdoc/en-us/000177080/dell-command-monitor
   ```

   **Privacy URL (optional):**
   ```
   https://www.dell.com/learn/us/en/uscorp1/policies-privacy
   ```

   **Category (optional):**
   Select: **Computer Management**

   **Display this as a featured app in the Company Portal:**
   ```
   No
   ```

   **Logo (optional):**
   Upload a Dell logo or leave blank

5. Click **Next**

### Step 4: Program Configuration

**Install command:**
```
install.cmd
```

**Uninstall command:**
```
uninstall.cmd
```

**Install behavior:**
```
System
```

**Device restart behavior:**
```
Determine behavior based on return codes
```

**Return codes:**

Keep the default return codes and add one custom code:

| Return Code | Code Type |
|-------------|-----------|
| 0 | Success |
| 1707 | Success |
| 3010 | Soft reboot |
| 1641 | Hard reboot |
| 1618 | Retry |

Click **Next**

### Step 5: Requirements

**Operating system architecture:**
```
☑ 64-bit
☐ 32-bit
```

**Minimum operating system:**
```
Windows 10 1809
```

**Disk space required (MB):**
```
200
```

**Physical memory required (MB):**
```
100
```

**Number of processors required:**
```
1
```

**CPU speed required (MHz):**
```
1
```

**Additional requirement rules:**
Click **+ Add** to add a custom requirement:

**Requirement type:**
```
Registry
```

**Key path:**
```
HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\BIOS
```

**Value name:**
```
SystemManufacturer
```

**Registry key requirement:**
```
String comparison
```

**Operator:**
```
Equals
```

**Value:**
```
Dell Inc.
```

**Associated with a 32-bit app on 64-bit clients:**
```
No
```

Click **OK**

This ensures the app only installs on Dell systems.

Click **Next**

### Step 6: Detection Rules

**Rules format:**
```
Use a custom detection script
```

1. Click **Select** under "Script file"

2. Create a detection script file `Detect-DCM.ps1`:

```powershell
# Dell Command Monitor Detection Script for Intune
try {
    # Check for DCIM WMI namespace
    $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue

    if ($namespace) {
        # Verify we can query the DCIM classes
        $testQuery = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction SilentlyContinue

        if ($null -ne $testQuery -or $?) {
            Write-Output "Dell Command | Monitor is installed and functional"
            exit 0
        }
    }

    # Not detected
    exit 1
}
catch {
    # Error means not installed
    exit 1
}
```

3. Upload `Detect-DCM.ps1`

4. **Run script as 32-bit process on 64-bit clients:**
   ```
   No
   ```

5. **Enforce script signature check:**
   ```
   No
   ```

Click **Next**

### Step 7: Dependencies

No dependencies required.

Click **Next**

### Step 8: Supersedence

No supersedence required (unless updating from older version).

Click **Next**

### Step 9: Assignments

**Required assignments:**

1. Click **+ Add group** under **Required**

2. Select your Dell devices group:
   - If you don't have one, create a dynamic Azure AD device group with this rule:
   ```
   (device.deviceManufacturer -eq "Dell Inc.")
   ```

3. Click **Select**

**Available for enrolled devices (optional):**

Leave empty or add groups that can install from Company Portal.

**Uninstall assignments:**

Leave empty unless you need to remove DCM from specific devices.

Click **Next**

### Step 10: Review + Create

1. Review all settings
2. Click **Create**
3. Wait for upload to complete (5-10 minutes depending on file size)

---

## Part 5: Monitor Deployment

### Step 1: View Deployment Status

1. In Intune admin center, go to: **Apps** > **All apps**
2. Find **Dell Command | Monitor**
3. Click on it
4. Click **Device install status** under **Monitor**

### Step 2: Check Installation Progress

You'll see a list of devices with status:

- **Installed**: Successfully installed
- **Installing**: Currently installing
- **Failed**: Installation failed
- **Not applicable**: Device doesn't meet requirements (not Dell)
- **Not installed**: Pending installation

### Step 3: Troubleshoot Failures

If installations fail:

1. Click on a failed device
2. View error code and details
3. Common issues:

   **Error 0x87D1041C - Requirement not met:**
   - Device is not a Dell system
   - Check device manufacturer in Azure AD

   **Error 0x80070643 - Fatal error during installation:**
   - Installer failed
   - Check device logs: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`

   **Error 0x87D1041A - Detection script failed:**
   - DCM installed but DCIM namespace not available
   - Device may need reboot

### Step 4: View Installation Logs on Device

On a target device, check these logs:

**Intune Management Extension Log:**
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log
```

**Custom Installation Log:**
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DCM-Install.log
```

**AgentExecutor Log:**
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log
```

---

## Part 6: Verification

### Verify on a Test Device

1. **Check if app was deployed:**
   ```powershell
   Get-ChildItem "C:\Program Files\WindowsApps\" | Where-Object { $_.Name -match "Dell" }
   ```

2. **Check DCIM namespace:**
   ```powershell
   Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'"
   ```

3. **Query dock information:**
   ```powershell
   Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice'
   ```

4. **Run dock detection script:**
   ```powershell
   iwr -useb https://raw.githubusercontent.com/JavierIOM/scripts/main/Get-DellDockInfo-DCMOnly.ps1 | iex
   ```

   Expected output:
   ```
   DockDetected  : True
   DockCount     : 1
   Model         : Dell WD-19S
   SerialNumber  : ABCD1234567
   ```

---

## Part 7: Update Deployment (Future Updates)

When Dell releases a new version:

### Step 1: Download New Version
Download the latest installer from Dell Support

### Step 2: Update Package Files
1. Replace the old .EXE file with the new one
2. Update version number in `Install-DCM.ps1` (line 10)
3. Update installer name in script

### Step 3: Repackage
Run IntuneWinAppUtil again with the updated source folder

### Step 4: Update Intune App
1. Go to the app in Intune
2. Click **Properties**
3. Click **Edit** next to "App package file"
4. Upload new `.intunewin` file
5. Update "App version" field
6. Click **Save**

### Step 5: Existing Devices
Devices will automatically upgrade on next Intune sync (every 8 hours by default)

---

## Troubleshooting

### Common Issues and Solutions

**Issue: "App installation failed with error code 0x80070643"**

**Solution:**
- Installer failed to run
- Check if device has enough disk space (200+ MB free)
- Check install log: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DCM-Install.log`
- Try manual installation on device to see actual error

---

**Issue: "Detection script indicates app is not installed after installation"**

**Solution:**
- DCIM namespace may not be ready yet
- Reboot the device
- Wait 30 minutes and force Intune sync: `Settings > Accounts > Access work or school > Info > Sync`

---

**Issue: "Installation succeeds but dock serial numbers still show as 'Unknown'"**

**Solution:**
- DCM may need a reboot to initialize
- Check if DCIM namespace is available:
  ```powershell
  Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice'
  ```
- If class not found, reboot device

---

**Issue: "App shows as 'Not applicable' for Dell devices"**

**Solution:**
- Check custom requirement rule
- Verify registry path: `HKLM\HARDWARE\DESCRIPTION\System\BIOS\SystemManufacturer`
- On affected device, run:
  ```powershell
  Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' | Select-Object SystemManufacturer
  ```
- If value doesn't match "Dell Inc." exactly, update the requirement rule

---

**Issue: "Intune shows installation pending but never installs"**

**Solution:**
- Check device Intune enrollment status
- Force sync from device: Settings > Accounts > Access work or school > Sync
- Check IME service is running:
  ```powershell
  Get-Service -Name "Microsoft Intune Management Extension"
  ```
- Check IME logs for errors

---

**Issue: "Package upload to Intune fails"**

**Solution:**
- File may be too large (limit is 8 GB)
- Check internet connection
- Try using Edge or Chrome (not IE)
- Clear browser cache and try again

---

## Best Practices

### Pre-Deployment

1. **Test in pilot group first** (10-20 devices)
2. **Monitor for 1-2 weeks** before full rollout
3. **Document known issues** and workarounds
4. **Create device groups** for phased deployment

### During Deployment

1. **Deploy in phases:**
   - Week 1: Pilot group (10-20 devices)
   - Week 2: Department 1 (100-200 devices)
   - Week 3: Department 2 (100-200 devices)
   - Week 4+: Remaining devices

2. **Monitor daily:**
   - Check install success rate
   - Review failed installations
   - Address issues before next phase

3. **Communicate with users:**
   - Notify of upcoming installation
   - Explain benefits (better hardware management)
   - Provide support contact

### Post-Deployment

1. **Set up monitoring:**
   - Weekly check of install status
   - Alert on high failure rates
   - Track compliance over time

2. **Schedule updates:**
   - Check Dell quarterly for DCM updates
   - Test updates in pilot before deploying
   - Document changes in version notes

3. **Integrate with dock detection:**
   - Deploy dock detection scripts via Proactive Remediations
   - Verify serial numbers are now being captured
   - Set up reporting for dock inventory

---

## Integration with Dock Detection Scripts

Once DCM is deployed, deploy the dock detection scripts:

### Step 1: Create Proactive Remediation

1. In Intune, go to: **Reports** > **Endpoint analytics** > **Proactive remediations**
2. Click **Create script package**
3. Name: "Dell Dock Inventory"
4. Detection script: Upload `Get-DellDockInfo-DCMOnly.ps1`
5. No remediation script needed (detection only)
6. Assign to Dell devices group
7. Schedule: Daily at 2:00 AM

### Step 2: Monitor Results

1. View proactive remediation reports
2. Export device dock information
3. Create Power BI dashboard (optional)

---

## Summary

You now have a complete, production-ready Intune Win32 app package for Dell Command | Monitor that:

✅ Only installs on Dell systems (custom requirement rule)
✅ Handles silent installation with proper error codes
✅ Waits for WMI namespace initialization
✅ Provides detailed logging for troubleshooting
✅ Gracefully handles non-Dell systems
✅ Supports uninstallation
✅ Can be monitored and updated through Intune

**Next Steps:**
1. Test on 2-3 pilot devices
2. Verify dock detection works with DCM installed
3. Roll out to larger pilot group
4. Monitor for 1-2 weeks
5. Deploy to production in phases

**Estimated Timeline:**
- Package creation: 30 minutes
- Intune configuration: 30 minutes
- Pilot deployment: 1 week
- Full deployment: 3-4 weeks

**Success Metrics:**
- Install success rate > 95%
- Detection script passes on all Dell devices
- Dock serial numbers captured via DCM on 100% of docked devices
