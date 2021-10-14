param (
    [ValidateSet('WebClient', 'WebRequest', 'FileCopy')]$DownloadMethod = 'WebClient',    
    $DownloadUrl = 'https://zoom.us/client/latest/ZoomInstallerFull.msi',
    $Filename = 'ZoomInstallerFull.msi',
    $DownloadDirectory = "$ENV:windir\temp",
    $AdditionalArguments = '' # Note: "/i installer.msi /qn /norestart /log" is ran by default
)

function Start-PrerequisteSteps {
    # Any pre installations steps go here.
}

function Start-AdditionalSteps {
    # Any post installation steps go here.  This function will be ran once installation is verified    
}

function Confirm-Installation {
    Param ($ProductName, $Version)
    $AppKeys = Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $AppKeys += Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($AppKey in $AppKeys) {
        $AppKey = $AppKey | Get-ItemProperty
        if ($AppKey.DisplayName -eq $ProductName) {
            Write-Host "$ProductName ($($AppKey.DisplayVersion)) is detected"
            if (!$Version) { return $true }# Version not specified, return true if just Name detected}
            if ([version]$AppKey.DisplayVersion -ge [version]$Version ) {
                Write-Host "$Version or greater is detected"
                return $true
            }
        }
    }
    Write-Host "$ProductName ($Version) is not detected"
    return $false
}

function Get-MsiProperties {
    <#
        jcolby
        This function is for getting the properties from an msi installer.

        http://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/
        https://technotes.khitrenovich.com/check-msi-version-powershell/
        https://social.technet.microsoft.com/Forums/en-US/1d50d2f7-f532-40b5-859e-d5cacab1f337/pull-a-msi-property-from-a-powershell-custom-object?forum=winserverpowershell
    #>
    
    param([System.IO.FileInfo]$Path)

    $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
    $MsiDatabase = $WindowsInstaller.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $Null, $WindowsInstaller, @($Path.FullName, 0))
    $Query = 'SELECT * FROM Property'
    $View = $MsiDatabase.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $MsiDatabase, ($Query))
    $View.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $View, $null)

    $MsiProperties = @{}
    while ($Record = $View.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $View, $null)) {
        $name = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 1)
        $value = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 2)
        $MsiProperties.Add($name, $value)
    }

    # Cleanup - commit db, close view, run garbage collection and release ComObject
    $MsiDatabase.GetType().InvokeMember('Commit', 'InvokeMethod', $null, $MsiDatabase, $null)
    $View.GetType().InvokeMember('Close', 'InvokeMethod', $null, $View, $null)           
    $MsiDatabase = $null
    $View = $null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
    [System.GC]::Collect()

    return $MsiProperties
}

$InstallerPath = "$DownloadDirectory\$Filename"
$MsiArguments = "/i `"$InstallerPath`" /qn /norestart /log `"$env:TEMP\$Filename.log`"" + " $($AdditionalArguments)"

try {
    
    switch ($DownloadMethod) {
        'WebClient' {
            # This is the preferred download method as it is substantially faster but sometimes not allowed
            Write-Host "Downloading $DownloadUrl"
            $WebClient = New-Object Net.WebClient
            $WebClient.DownloadFile($DownloadUrl, $InstallerPath)
        }
        'WebRequest' {
            # Use this method when WebClient doesnt work, ie dropbox. *Re dropbox urls, set query string dl=1
            Write-Host "Downloading $DownloadUrl"
            Invoke-WebRequest $DownloadUrl -OutFile $InstallerPath
        }
        'FileCopy' {
            # Copy from local / Unc
            Write-Host "Copying $DownloadUrl"
            Copy-Item -Path $DownloadUrl -Destination $InstallerPath -Force -Confirm:$false
        }
    }
    
    # Get msi details and versions for comparison
    $MsiProductName = (Get-MsiProperties -Path $InstallerPath).ProductName
    [version]$MsiProductVersion = (Get-MsiProperties -Path $InstallerPath).ProductVersion

    Write-Host 'Checking for existing installation...'
    if (Confirm-Installation -ProductName $MsiProductName -Version $MsiProductVersion ) { return }
    
    Start-PrerequisteSteps
    
    # Run installer
    Write-Host "Installing $MsiProductName ($MsiProductVersion)"
    Write-Host "Install Command = {msiexec.exe $MsiArguments}"
    Start-Process msiexec.exe -ArgumentList $MsiArguments -Wait -NoNewWindow
        
    #Verify
    if (Confirm-Installation -ProductName $MsiProductName -Version $MsiProductVersion -eq $false) { return }
    
    Start-AdditionalSteps
}
catch {
    Write-Warning "Oops, Something went wrong: `n$_"
}
finally {
    # Cleanup
    Remove-Item "$InstallerPath" -Force -Confirm:$false -ErrorAction Ignore
}