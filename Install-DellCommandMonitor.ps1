<#
.SYNOPSIS
    Installs Dell Command | Monitor on Dell systems.

.DESCRIPTION
    This script downloads and installs Dell Command | Monitor, which provides
    enhanced WMI classes for querying Dell hardware information including
    docking station serial numbers, firmware versions, and status.

.PARAMETER ForceReinstall
    If specified, will reinstall even if Dell Command | Monitor is already installed.

.PARAMETER SkipReboot
    If specified, suppresses any reboot prompts after installation.

.EXAMPLE
    .\Install-DellCommandMonitor.ps1
    Installs Dell Command | Monitor if not already present.

.EXAMPLE
    .\Install-DellCommandMonitor.ps1 -ForceReinstall
    Reinstalls Dell Command | Monitor even if already installed.

.NOTES
    Author: Intune Automation
    Version: 1.0
    Prerequisites:
    - Administrative privileges required
    - Dell system (Latitude, Precision, OptiPlex, etc.)
    - Internet connection for download
    - Windows 10/11

    Download URL: https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ForceReinstall,

    [Parameter(Mandatory = $false)]
    [switch]$SkipReboot
)

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages with timestamp.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error'   { Write-Error $logMessage }
        'Warning' { Write-Warning $logMessage }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Verbose $logMessage }
    }
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks if script is running with administrator privileges.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsDellSystem {
    <#
    .SYNOPSIS
        Checks if the system is a Dell computer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
        return ($manufacturer -match 'Dell')
    }
    catch {
        Write-Log "Error checking system manufacturer: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-DellCommandMonitorInstalled {
    <#
    .SYNOPSIS
        Checks if Dell Command | Monitor is already installed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Check for installed application
        $app = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Dell Command%Monitor%'" -ErrorAction SilentlyContinue

        if (-not $app) {
            # Fallback: Check registry for uninstall entries
            $registryPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            foreach ($path in $registryPaths) {
                $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -match 'Dell Command.*Monitor' }

                if ($apps) {
                    $app = $apps | Select-Object -First 1
                    break
                }
            }
        }

        # Check for DCIM WMI namespace
        $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue

        return [PSCustomObject]@{
            IsInstalled     = ($null -ne $app)
            WMIAvailable    = ($null -ne $namespace)
            Version         = if ($app) { $app.Version -or $app.DisplayVersion } else { $null }
            InstallLocation = if ($app) { $app.InstallLocation } else { $null }
        }
    }
    catch {
        Write-Log "Error checking Dell Command | Monitor installation: $($_.Exception.Message)" -Level Warning
        return [PSCustomObject]@{
            IsInstalled     = $false
            WMIAvailable    = $false
            Version         = $null
            InstallLocation = $null
        }
    }
}

function Get-LatestDellCommandMonitor {
    <#
    .SYNOPSIS
        Gets the latest Dell Command | Monitor download URL and version.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Dell Command | Monitor direct download (Universal Windows Application)
    # This is the latest version as of 2024 - update as needed
    return [PSCustomObject]@{
        Version     = '10.11.0'
        DownloadUrl = 'https://dl.dell.com/FOLDER11376969M/1/Dell-Command-Monitor-Application_0NV3P_WIN_10.11.0_A00.EXE'
        FileName    = 'Dell-Command-Monitor_10.11.0_A00.EXE'
        FileSize    = '~60 MB'
    }
}

function Install-DellCommandMonitorPackage {
    <#
    .SYNOPSIS
        Downloads and installs Dell Command | Monitor.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DownloadUrl,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    try {
        # Create temp directory
        $tempDir = Join-Path -Path $env:TEMP -ChildPath "DellCommandMonitor_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Created temporary directory: $tempDir" -Level Info

        # Download installer
        $installerPath = Join-Path -Path $tempDir -ChildPath $FileName
        Write-Log "Downloading Dell Command | Monitor from: $DownloadUrl" -Level Info

        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
            Write-Log "Download completed: $installerPath" -Level Success
        }
        catch {
            Write-Log "Failed to download installer: $($_.Exception.Message)" -Level Error
            return $false
        }

        # Verify download
        if (-not (Test-Path -Path $installerPath)) {
            Write-Log "Installer file not found after download" -Level Error
            return $false
        }

        $fileSize = (Get-Item -Path $installerPath).Length / 1MB
        Write-Log "Downloaded file size: $([math]::Round($fileSize, 2)) MB" -Level Info

        # Install silently
        Write-Log "Starting installation (this may take several minutes)..." -Level Info

        $installArgs = @(
            '/s',           # Silent installation
            '/v/qn'         # MSI quiet mode with no UI
        )

        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Log "Installation completed successfully" -Level Success

            # Wait for WMI namespace to become available
            Write-Log "Waiting for DCIM WMI namespace to initialize..." -Level Info
            $timeout = 30
            $elapsed = 0
            $namespaceAvailable = $false

            while ($elapsed -lt $timeout) {
                Start-Sleep -Seconds 2
                $elapsed += 2

                $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue
                if ($namespace) {
                    $namespaceAvailable = $true
                    Write-Log "DCIM WMI namespace is now available" -Level Success
                    break
                }
            }

            if (-not $namespaceAvailable) {
                Write-Log "DCIM WMI namespace not detected after installation. A system reboot may be required." -Level Warning
            }

            return $true
        }
        else {
            Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Error during installation: $($_.Exception.Message)" -Level Error
        return $false
    }
    finally {
        # Cleanup
        if (Test-Path -Path $tempDir) {
            try {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up temporary files" -Level Info
            }
            catch {
                Write-Log "Could not clean up temporary directory: $tempDir" -Level Warning
            }
        }
    }
}

#endregion

#region Main Script Logic

Write-Log "========================================" -Level Info
Write-Log "Dell Command | Monitor Installation Script" -Level Info
Write-Log "========================================" -Level Info

# Check for administrator privileges
if (-not (Test-IsAdministrator)) {
    Write-Log "This script requires administrator privileges. Please run as Administrator." -Level Error
    exit 1
}

Write-Log "Running with administrator privileges" -Level Success

# Check if system is Dell
if (-not (Test-IsDellSystem)) {
    Write-Log "This script is designed for Dell systems only." -Level Error
    Write-Log "Current manufacturer: $((Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer)" -Level Info
    exit 1
}

Write-Log "Confirmed Dell system" -Level Success

# Check current installation status
Write-Log "Checking current Dell Command | Monitor installation status..." -Level Info
$currentInstall = Test-DellCommandMonitorInstalled

if ($currentInstall.IsInstalled) {
    Write-Log "Dell Command | Monitor is currently installed" -Level Info
    Write-Log "Version: $($currentInstall.Version)" -Level Info
    Write-Log "WMI Namespace Available: $($currentInstall.WMIAvailable)" -Level Info

    if (-not $ForceReinstall) {
        Write-Log "Installation already complete. Use -ForceReinstall to reinstall." -Level Success
        exit 0
    }
    else {
        Write-Log "ForceReinstall specified. Proceeding with reinstallation..." -Level Warning
    }
}
else {
    Write-Log "Dell Command | Monitor is not installed" -Level Info
}

# Get latest version info
Write-Log "Retrieving latest Dell Command | Monitor version information..." -Level Info
$latestVersion = Get-LatestDellCommandMonitor

Write-Log "Latest Version: $($latestVersion.Version)" -Level Info
Write-Log "Estimated Download Size: $($latestVersion.FileSize)" -Level Info

# Download and install
Write-Log "Beginning installation process..." -Level Info
$installSuccess = Install-DellCommandMonitorPackage -DownloadUrl $latestVersion.DownloadUrl -FileName $latestVersion.FileName

if ($installSuccess) {
    Write-Log "========================================" -Level Success
    Write-Log "Installation completed successfully!" -Level Success
    Write-Log "========================================" -Level Success

    # Final verification
    $finalCheck = Test-DellCommandMonitorInstalled
    if ($finalCheck.WMIAvailable) {
        Write-Log "DCIM WMI namespace is available and ready to use" -Level Success
    }
    else {
        Write-Log "DCIM WMI namespace not yet available. A system reboot may be required." -Level Warning

        if (-not $SkipReboot) {
            Write-Log "Consider rebooting the system to complete installation." -Level Warning
        }
    }

    exit 0
}
else {
    Write-Log "========================================" -Level Error
    Write-Log "Installation failed. Please check the logs above for details." -Level Error
    Write-Log "========================================" -Level Error
    exit 1
}

#endregion
