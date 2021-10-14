Param(
    $DownloadUrl = 'https://contoso.com/CoolStuff.exe',
    $Installer = 'CoolStuff.exe',
    [ValidateSet('WebClient', 'WebRequest', 'FileCopy')]$DownloadMethod = 'WebClient',
    $InstallDirectory = "$ENV:windir\Temp",
    $Arguments = '/quiet /norestart /log "C:\Windows\Temp\CoolStuff.log"',
    $ProductName = 'The Cool Stuff App',
    [version]$Version = '1.10.111.0'
)

function Start-PrerequisteSteps {
    # Any pre installations steps go here.
}
function Start-AdditionalSteps {
    # Any post installation steps go here.  This function will be ran once installation is verified    
}
function Confirm-Installation {
    $AppKeys = Get-ChildItem 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $AppKeys += Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($AppKey in $AppKeys) {
        $AppKey = $AppKey | Get-ItemProperty
        if ($AppKey.DisplayName -eq $ProductName) {
            Write-Host "$ProductName ($($AppKey.DisplayVersion)) is detected"
            if (!$Version) { return $true }
            if ([version]$AppKey.DisplayVersion -ge [version]$Version ) {
                Write-Host "$Version or greater is detected"
                return $true
            }
        }
    }
    Write-Host "$ProductName ($Version) is not detected"
    return $false
}

$InstallerPath = "$InstallDirectory\$Installer"

try {

    Write-Host 'Checking for existing installation...'
    if (Confirm-Installation) { return }

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
    
    Start-PrerequisteSteps 

    # Run the installer with provided arguments
    Write-Host "Installation Command: { `"$InstallerPath`" $Arguments }"
    Start-Process $InstallerPath -ArgumentList $Arguments -NoNewWindow -Wait
    
    Write-Host 'Verifying installation...'
    if (Confirm-Installation -eq $false) { return }
    
    Start-AdditionalSteps    
}
catch {
    Write-Warning "Oops, something went wrong:  $_"
}
finally {
    # Cleanup
    Remove-Item "$InstallerPath" -Force -Confirm:$false -ErrorAction Ignore
}