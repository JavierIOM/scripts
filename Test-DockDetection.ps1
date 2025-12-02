<#
.SYNOPSIS
    Test script for validating Dell dock detection functionality.

.DESCRIPTION
    Comprehensive test script that validates all detection methods and provides
    detailed diagnostic information for troubleshooting dock detection issues.

    This script performs:
    - Environment validation
    - Dell Command | Monitor availability check
    - WMI/CIM namespace enumeration
    - USB device detection
    - Dock detection using all methods
    - Performance benchmarking
    - Detailed reporting

.PARAMETER GenerateReport
    Generates a detailed HTML report of test results.

.PARAMETER ExportPath
    Path to export test results. Defaults to current directory.

.EXAMPLE
    .\Test-DockDetection.ps1
    Runs all tests and displays results in console.

.EXAMPLE
    .\Test-DockDetection.ps1 -GenerateReport -ExportPath "C:\Temp"
    Runs tests and generates HTML report in C:\Temp.

.NOTES
    Author: Intune Automation
    Version: 1.0
    Use this script to validate dock detection before Intune deployment.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$GenerateReport,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = (Get-Location).Path
)

#region Test Result Tracking

$testResults = @{
    TestDate = Get-Date
    ComputerName = $env:COMPUTERNAME
    Tests = @()
    Summary = @{
        Total = 0
        Passed = 0
        Failed = 0
        Warning = 0
    }
}

function Add-TestResult {
    param(
        [string]$TestName,
        [string]$Category,
        [ValidateSet('Pass', 'Fail', 'Warning')]
        [string]$Result,
        [string]$Message,
        [object]$Details = $null
    )

    $test = [PSCustomObject]@{
        TestName = $TestName
        Category = $Category
        Result = $Result
        Message = $Message
        Details = $Details
        Timestamp = Get-Date
    }

    $testResults.Tests += $test
    $testResults.Summary.Total++

    switch ($Result) {
        'Pass' { $testResults.Summary.Passed++ }
        'Fail' { $testResults.Summary.Failed++ }
        'Warning' { $testResults.Summary.Warning++ }
    }

    # Display result
    $color = switch ($Result) {
        'Pass' { 'Green' }
        'Fail' { 'Red' }
        'Warning' { 'Yellow' }
    }

    Write-Host "[$Result] $TestName - $Message" -ForegroundColor $color
}

#endregion

#region Test Functions

function Test-Environment {
    Write-Host "`n=== Environment Tests ===" -ForegroundColor Cyan

    # Test 1: PowerShell Version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Add-TestResult -TestName "PowerShell Version" -Category "Environment" -Result Pass `
            -Message "PowerShell $($psVersion.ToString()) detected" -Details $psVersion
    } else {
        Add-TestResult -TestName "PowerShell Version" -Category "Environment" -Result Fail `
            -Message "PowerShell 5.1+ required, found $($psVersion.ToString())" -Details $psVersion
    }

    # Test 2: Operating System
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.Caption -match "Windows (10|11)") {
        Add-TestResult -TestName "Operating System" -Category "Environment" -Result Pass `
            -Message "$($os.Caption) Build $($os.BuildNumber)" -Details $os
    } else {
        Add-TestResult -TestName "Operating System" -Category "Environment" -Result Warning `
            -Message "Windows 10/11 recommended, found $($os.Caption)" -Details $os
    }

    # Test 3: Execution Policy
    $execPolicy = Get-ExecutionPolicy
    if ($execPolicy -in @('Unrestricted', 'RemoteSigned', 'Bypass')) {
        Add-TestResult -TestName "Execution Policy" -Category "Environment" -Result Pass `
            -Message "Execution Policy: $execPolicy" -Details $execPolicy
    } else {
        Add-TestResult -TestName "Execution Policy" -Category "Environment" -Result Warning `
            -Message "Restrictive policy detected: $execPolicy" -Details $execPolicy
    }

    # Test 4: Administrator Rights
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Add-TestResult -TestName "Administrator Rights" -Category "Environment" -Result Pass `
            -Message "Running with administrative privileges" -Details $isAdmin
    } else {
        Add-TestResult -TestName "Administrator Rights" -Category "Environment" -Result Warning `
            -Message "Not running as administrator - some tests may be limited" -Details $isAdmin
    }

    # Test 5: Dell Hardware
    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if ($manufacturer -match "Dell") {
        Add-TestResult -TestName "Hardware Vendor" -Category "Environment" -Result Pass `
            -Message "Dell hardware detected: $manufacturer" -Details $manufacturer
    } else {
        Add-TestResult -TestName "Hardware Vendor" -Category "Environment" -Result Warning `
            -Message "Non-Dell hardware: $manufacturer (dock detection may not work)" -Details $manufacturer
    }
}

function Test-DellCommandMonitor {
    Write-Host "`n=== Dell Command | Monitor Tests ===" -ForegroundColor Cyan

    # Test 1: DCIM Namespace
    try {
        $dcimNamespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction Stop

        if ($dcimNamespace) {
            Add-TestResult -TestName "DCIM Namespace" -Category "Dell Command Monitor" -Result Pass `
                -Message "Dell Command | Monitor DCIM namespace found" -Details $dcimNamespace

            # Test 2: SYSMAN Namespace
            try {
                $sysmanNamespace = Get-CimInstance -Namespace 'root\DCIM' -ClassName '__NAMESPACE' -Filter "Name='SYSMAN'" -ErrorAction Stop

                if ($sysmanNamespace) {
                    Add-TestResult -TestName "SYSMAN Namespace" -Category "Dell Command Monitor" -Result Pass `
                        -Message "SYSMAN namespace accessible" -Details $sysmanNamespace

                    # Test 3: DCIM_DockingDevice Class
                    try {
                        $dockClass = Get-CimClass -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction Stop

                        if ($dockClass) {
                            Add-TestResult -TestName "DCIM_DockingDevice Class" -Category "Dell Command Monitor" -Result Pass `
                                -Message "Docking device WMI class available" -Details $dockClass.CimClassProperties.Name

                            # Test 4: Query Docking Devices
                            try {
                                $dockDevices = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction Stop

                                if ($dockDevices) {
                                    $dockCount = ($dockDevices | Measure-Object).Count
                                    Add-TestResult -TestName "Docking Device Query" -Category "Dell Command Monitor" -Result Pass `
                                        -Message "Found $dockCount docking device(s)" -Details $dockDevices
                                } else {
                                    Add-TestResult -TestName "Docking Device Query" -Category "Dell Command Monitor" -Result Warning `
                                        -Message "WMI query successful but no docking devices found" -Details $null
                                }
                            } catch {
                                Add-TestResult -TestName "Docking Device Query" -Category "Dell Command Monitor" -Result Fail `
                                    -Message "Failed to query docking devices: $($_.Exception.Message)" -Details $_.Exception
                            }
                        }
                    } catch {
                        Add-TestResult -TestName "DCIM_DockingDevice Class" -Category "Dell Command Monitor" -Result Fail `
                            -Message "DCIM_DockingDevice class not found" -Details $_.Exception
                    }
                }
            } catch {
                Add-TestResult -TestName "SYSMAN Namespace" -Category "Dell Command Monitor" -Result Fail `
                    -Message "SYSMAN namespace not accessible" -Details $_.Exception
            }
        }
    } catch {
        Add-TestResult -TestName "DCIM Namespace" -Category "Dell Command Monitor" -Result Fail `
            -Message "Dell Command | Monitor not detected - DCIM namespace not found" -Details $_.Exception
    }
}

function Test-USBDetection {
    Write-Host "`n=== USB Device Detection Tests ===" -ForegroundColor Cyan

    # Test 1: Query All USB Devices
    try {
        $usbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='USB'" -ErrorAction Stop
        $usbCount = ($usbDevices | Measure-Object).Count

        if ($usbCount -gt 0) {
            Add-TestResult -TestName "USB Device Enumeration" -Category "USB Detection" -Result Pass `
                -Message "Successfully enumerated $usbCount USB device(s)" -Details $usbCount
        } else {
            Add-TestResult -TestName "USB Device Enumeration" -Category "USB Detection" -Result Warning `
                -Message "No USB devices found" -Details $null
        }
    } catch {
        Add-TestResult -TestName "USB Device Enumeration" -Category "USB Detection" -Result Fail `
            -Message "Failed to enumerate USB devices: $($_.Exception.Message)" -Details $_.Exception
    }

    # Test 2: Dell USB Devices
    try {
        $dellVID = '413C'
        $dellUSBDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%USB%VID_$dellVID%'" -ErrorAction Stop
        $dellCount = ($dellUSBDevices | Measure-Object).Count

        if ($dellCount -gt 0) {
            Add-TestResult -TestName "Dell USB Devices" -Category "USB Detection" -Result Pass `
                -Message "Found $dellCount Dell USB device(s)" -Details $dellUSBDevices
        } else {
            Add-TestResult -TestName "Dell USB Devices" -Category "USB Detection" -Result Warning `
                -Message "No Dell USB devices found (VID: $dellVID)" -Details $null
        }
    } catch {
        Add-TestResult -TestName "Dell USB Devices" -Category "USB Detection" -Result Fail `
            -Message "Failed to query Dell USB devices: $($_.Exception.Message)" -Details $_.Exception
    }

    # Test 3: WD-19 Dock Detection via USB
    try {
        $wd19PIDs = @('B06E', 'B06F', 'B0A0', 'B0A1')
        $dellVID = '413C'
        $dockDevices = @()

        $allUSB = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%USB%VID_$dellVID%'" -ErrorAction Stop

        foreach ($device in $allUSB) {
            if ($device.DeviceID -match "VID_$dellVID&PID_([0-9A-F]{4})") {
                $pid = $matches[1]
                if ($pid -in $wd19PIDs) {
                    $dockDevices += $device
                }
            }
        }

        if ($dockDevices.Count -gt 0) {
            Add-TestResult -TestName "WD-19 Dock via USB" -Category "USB Detection" -Result Pass `
                -Message "WD-19 dock detected via USB enumeration" -Details $dockDevices
        } else {
            Add-TestResult -TestName "WD-19 Dock via USB" -Category "USB Detection" -Result Warning `
                -Message "No WD-19 docks found via USB (PIDs: $($wd19PIDs -join ', '))" -Details $null
        }
    } catch {
        Add-TestResult -TestName "WD-19 Dock via USB" -Category "USB Detection" -Result Fail `
            -Message "Error detecting WD-19 docks: $($_.Exception.Message)" -Details $_.Exception
    }
}

function Test-PerformanceBenchmark {
    Write-Host "`n=== Performance Benchmark ===" -ForegroundColor Cyan

    # Test 1: DCIM Query Performance
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $dcimCheck = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue
        if ($dcimCheck) {
            $dockDevices = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction SilentlyContinue
        }
    } catch {}
    $stopwatch.Stop()

    if ($stopwatch.ElapsedMilliseconds -lt 5000) {
        Add-TestResult -TestName "DCIM Query Performance" -Category "Performance" -Result Pass `
            -Message "DCIM query completed in $($stopwatch.ElapsedMilliseconds)ms" -Details $stopwatch.ElapsedMilliseconds
    } else {
        Add-TestResult -TestName "DCIM Query Performance" -Category "Performance" -Result Warning `
            -Message "DCIM query slow: $($stopwatch.ElapsedMilliseconds)ms (target: <5000ms)" -Details $stopwatch.ElapsedMilliseconds
    }

    # Test 2: USB Query Performance
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $usbDevices = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE '%USB%VID_413C%'" -ErrorAction SilentlyContinue
    } catch {}
    $stopwatch.Stop()

    if ($stopwatch.ElapsedMilliseconds -lt 3000) {
        Add-TestResult -TestName "USB Query Performance" -Category "Performance" -Result Pass `
            -Message "USB query completed in $($stopwatch.ElapsedMilliseconds)ms" -Details $stopwatch.ElapsedMilliseconds
    } else {
        Add-TestResult -TestName "USB Query Performance" -Category "Performance" -Result Warning `
            -Message "USB query slow: $($stopwatch.ElapsedMilliseconds)ms (target: <3000ms)" -Details $stopwatch.ElapsedMilliseconds
    }
}

function Test-RegistryAccess {
    Write-Host "`n=== Registry Access Tests ===" -ForegroundColor Cyan

    $testPath = 'HKLM:\SOFTWARE\Dell\DockInventory'

    # Test 1: Registry Write Access
    try {
        if (-not (Test-Path $testPath)) {
            New-Item -Path $testPath -Force | Out-Null
        }

        Set-ItemProperty -Path $testPath -Name 'TestWrite' -Value (Get-Date).ToString() -Force
        $value = (Get-ItemProperty -Path $testPath -Name 'TestWrite' -ErrorAction Stop).TestWrite

        if ($value) {
            Add-TestResult -TestName "Registry Write" -Category "Registry" -Result Pass `
                -Message "Successfully wrote to $testPath" -Details $value

            # Cleanup
            Remove-ItemProperty -Path $testPath -Name 'TestWrite' -ErrorAction SilentlyContinue
        }
    } catch {
        Add-TestResult -TestName "Registry Write" -Category "Registry" -Result Fail `
            -Message "Cannot write to registry: $($_.Exception.Message)" -Details $_.Exception
    }

    # Test 2: Registry Read Access
    try {
        if (Test-Path $testPath) {
            $regData = Get-ItemProperty -Path $testPath -ErrorAction Stop

            Add-TestResult -TestName "Registry Read" -Category "Registry" -Result Pass `
                -Message "Successfully read from $testPath" -Details $regData
        } else {
            Add-TestResult -TestName "Registry Read" -Category "Registry" -Result Warning `
                -Message "Registry path does not exist (will be created on first detection)" -Details $null
        }
    } catch {
        Add-TestResult -TestName "Registry Read" -Category "Registry" -Result Fail `
            -Message "Cannot read from registry: $($_.Exception.Message)" -Details $_.Exception
    }
}

#endregion

#region Report Generation

function Generate-HTMLReport {
    param(
        [object]$Results,
        [string]$OutputPath
    )

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Dell Dock Detection Test Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .summary-box { padding: 20px; border-radius: 5px; text-align: center; flex: 1; margin: 0 10px; }
        .summary-box h3 { margin: 0; font-size: 2em; }
        .summary-box p { margin: 5px 0; color: #666; }
        .pass-box { background-color: #d4edda; border: 1px solid #c3e6cb; }
        .fail-box { background-color: #f8d7da; border: 1px solid #f5c6cb; }
        .warning-box { background-color: #fff3cd; border: 1px solid #ffeaa7; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #0078d4; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .pass { color: #28a745; font-weight: bold; }
        .fail { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .details { font-size: 0.9em; color: #666; }
        .info { background-color: #e7f3ff; padding: 15px; border-left: 4px solid #0078d4; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Dell Dock Detection Test Report</h1>

        <div class="info">
            <strong>Computer:</strong> $($Results.ComputerName)<br>
            <strong>Test Date:</strong> $($Results.TestDate.ToString('yyyy-MM-dd HH:mm:ss'))<br>
            <strong>Total Tests:</strong> $($Results.Summary.Total)
        </div>

        <div class="summary">
            <div class="summary-box pass-box">
                <h3>$($Results.Summary.Passed)</h3>
                <p>Passed</p>
            </div>
            <div class="summary-box fail-box">
                <h3>$($Results.Summary.Failed)</h3>
                <p>Failed</p>
            </div>
            <div class="summary-box warning-box">
                <h3>$($Results.Summary.Warning)</h3>
                <p>Warnings</p>
            </div>
        </div>

        <h2>Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Category</th>
                    <th>Test Name</th>
                    <th>Result</th>
                    <th>Message</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($test in $Results.Tests) {
        $resultClass = $test.Result.ToLower()
        $html += @"
                <tr>
                    <td>$($test.Category)</td>
                    <td>$($test.TestName)</td>
                    <td class="$resultClass">$($test.Result)</td>
                    <td>$($test.Message)</td>
                </tr>
"@
    }

    $html += @"
            </tbody>
        </table>

        <h2>Recommendations</h2>
        <ul>
"@

    if ($Results.Summary.Failed -gt 0) {
        $html += "<li><strong>Critical Issues Detected:</strong> Review failed tests and resolve before deployment.</li>"
    }

    if ($Results.Tests | Where-Object {$_.TestName -eq "DCIM Namespace" -and $_.Result -eq "Fail"}) {
        $html += "<li><strong>Install Dell Command | Monitor:</strong> This provides the most reliable dock detection. Download from Dell Support.</li>"
    }

    if ($Results.Tests | Where-Object {$_.TestName -eq "Administrator Rights" -and $_.Result -eq "Warning"}) {
        $html += "<li><strong>Run as Administrator:</strong> Some tests require elevated privileges for full functionality.</li>"
    }

    if ($Results.Tests | Where-Object {$_.TestName -eq "WD-19 Dock via USB" -and $_.Result -eq "Warning"}) {
        $html += "<li><strong>No Dock Detected:</strong> Ensure a WD-19S or WD-19DC dock is connected and powered on.</li>"
    }

    $html += @"
        </ul>

        <div class="info" style="margin-top: 30px;">
            <strong>Next Steps:</strong><br>
            1. Review any failed or warning tests above<br>
            2. Install Dell Command | Monitor if not present<br>
            3. Connect a WD-19 dock and re-run tests<br>
            4. Once all tests pass, proceed with Intune deployment
        </div>
    </div>
</body>
</html>
"@

    $reportPath = Join-Path $OutputPath "DockDetectionTestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $html | Out-File -FilePath $reportPath -Encoding UTF8

    Write-Host "`nHTML Report generated: $reportPath" -ForegroundColor Green
    return $reportPath
}

#endregion

#region Main Execution

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "Dell Dock Detection - Comprehensive Test Suite" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Run all tests
Test-Environment
Test-DellCommandMonitor
Test-USBDetection
Test-PerformanceBenchmark
Test-RegistryAccess

# Display summary
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($testResults.Summary.Total)" -ForegroundColor White
Write-Host "Passed: $($testResults.Summary.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Summary.Failed)" -ForegroundColor Red
Write-Host "Warnings: $($testResults.Summary.Warning)" -ForegroundColor Yellow

# Generate report if requested
if ($GenerateReport) {
    Write-Host "`nGenerating HTML report..." -ForegroundColor Cyan
    $reportPath = Generate-HTMLReport -Results $testResults -OutputPath $ExportPath
    Start-Process $reportPath
}

# Return test results object
return $testResults

#endregion
