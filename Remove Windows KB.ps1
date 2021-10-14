$KBsToRemove = #('KB5000908', 'KB5000900')

foreach ($KB in $KBsToRemove) {
    $SearchUpdates = Invoke-Command { Dism /Online /Get-Packages | findstr 'Package_for' | findstr $KB }
    if ($SearchUpdates) {
        $Update = $SearchUpdates.split(":")[1].replace(' ', '')
        Write-Host "Update detected: $Update, running Dism /Online /Remove-Package"
        Invoke-Command { Dism /Online /Remove-Package /PackageName:$Update /Quiet /Norestart }
    }
    else {
        Write-Host "Update not found: $KB" 
    }
}