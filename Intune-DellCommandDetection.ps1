<#
.SYNOPSIS
    Intune detection script for Dell Command | Monitor.

.DESCRIPTION
    Detects if Dell Command | Monitor is installed and the DCIM WMI namespace is available.
    Used as a detection script in Intune Win32 app deployment.

.NOTES
    Author: Intune Automation
    Version: 1.0

    Exit Codes:
    - 0: Dell Command | Monitor is installed and WMI is available
    - 1: Not installed or WMI namespace not available
#>

try {
    # Check for DCIM WMI namespace (most reliable indicator)
    $namespace = Get-CimInstance -Namespace 'root' -ClassName '__NAMESPACE' -Filter "Name='DCIM'" -ErrorAction SilentlyContinue

    if ($namespace) {
        # Verify we can query the docking device class
        $testQuery = Get-CimInstance -Namespace 'root\DCIM\SYSMAN' -ClassName 'DCIM_DockingDevice' -ErrorAction SilentlyContinue

        if ($null -ne $testQuery -or $?) {
            Write-Output "Dell Command | Monitor is installed and functional"
            exit 0
        }
    }

    # If we get here, it's not properly installed
    Write-Output "Dell Command | Monitor not detected or not functional"
    exit 1
}
catch {
    Write-Output "Error detecting Dell Command | Monitor: $($_.Exception.Message)"
    exit 1
}
