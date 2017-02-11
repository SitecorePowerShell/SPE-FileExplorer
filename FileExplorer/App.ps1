#region Dialog Setup
$accelerator = [PSObject].Assembly.GetType("System.Management.Automation.TypeAccelerators")
Add-Type -AssemblyName PresentationCore, PresentationFramework -PassThru | Where-Object IsPublic | ForEach-Object { $accelerator::Add($_.Name,$_) }

$currentDirectory = Split-Path $script:MyInvocation.MyCommand.Path

[xml]$xaml = Get-Content -Path (Join-Path -Path $currentDirectory -ChildPath  "MainWindow.xaml")
$reader = New-Object System.Xml.XmlNodeReader $xaml 
[Window]$window = [XamlReader]::Load($reader)


$window.FindName("MainFrame").Source = (Join-Path -Path $currentDirectory -ChildPath  "FileExplorer.xaml")
[xml]$xaml = Get-Content -Path (Join-Path -Path $currentDirectory -ChildPath  "FileExplorer.xaml")
$reader = New-Object System.Xml.XmlNodeReader $xaml 
$window.Content = [XamlReader]::Load($reader)

$content = $window.Content
#endregion

Import-Module -Name SPE

$session = New-ScriptSession -Username "admin" -Password "b" -ConnectionUri "https://spe.dev.local"

<# Custom variables #>
$queryFileList = { 
    Get-ChildItem -Path "$($SitecorePackageFolder)" | 
        Where-Object { !$_.PSIsContainer } |
        Select-Object -ExpandProperty Name
}

function Check-Service {
    param(
        [ValidateSet("FileUpload","FileDownload")]
        [string]$Service,
        
        [pscustomobject]$Session
    )

    Invoke-RemoteScript -ScriptBlock {
        switch($params.Service) {
            "FileUpload" {[Cognifide.PowerShell.Core.Settings.WebServiceSettings]::ServiceEnabledFileUpload}
            "FileDownload" {[Cognifide.PowerShell.Core.Settings.WebServiceSettings]::ServiceEnabledFileDownload}
        } 
    } -Session $session -Argument @{"Service"=$Service}
}

<# Wire-up the UI #>
$btnRefresh = [Button]($content.FindName("btnRefresh"))
$btnDelete = [Button]($content.FindName("btnDelete"))
$btnUpload = [Button]($content.FindName("btnUpload"))
$btnDownload = [Button]($content.FindName("btnDownload"))

$lstFiles = [ListBox]($content.FindName("lstFiles"))

$lstFiles.ItemsSource = @(Invoke-RemoteScript -ScriptBlock $queryFileList -Session $session)

$btnRefresh.Add_Click({
    $lstFiles.ItemsSource = @(Invoke-RemoteScript -ScriptBlock $queryFileList -Session $session)
})

$btnDelete.Add_Click({
    $fileName = $lstFiles.SelectedValue
    if($fileName) {
        $result = [MessageBox]::Show("Fixin' to delete $($fileName)?", "Delete", [MessageBoxButton]::OKCancel, [MessageBoxImage]::Warning)
        if($result -eq [MessageBoxResult]::OK) {
            Invoke-RemoteScript -Session $session -ScriptBlock { Remove-Item -Path "$($SitecorePackageFolder)\$($params.fileName)" } -Arguments @{"fileName"=$fileName}
        }
    } else {
        return [MessageBox]::Show("Please select a file to delete.", "Delete", [MessageBoxButton]::OK, [MessageBoxImage]::Information)
    }

    $lstFiles.ItemsSource = @(Invoke-RemoteScript -ScriptBlock $queryFileList -Session $session)
})

$btnUpload.Add_Click({
    if(!(Check-Service -Service FileUpload -Session $session)) {
        return [MessageBox]::Show("The file upload service is disabled.", "Service Disabled", [MessageBoxButton]::OK, [MessageBoxImage]::Warning)
    }

    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    if($dialog.ShowDialog()) {
        Get-Item -Path $dialog.FileName | Send-RemoteItem -Session $session -RootPath Package -Destination "\"
    }
    
    $lstFiles.ItemsSource = @(Invoke-RemoteScript -ScriptBlock $queryFileList -Session $session)
})

$btnDownload.Add_Click({
    if(!(Check-Service -Service FileDownload -Session $session)) {
        return [MessageBox]::Show("The file upload service is disabled.", "Service Disabled", [MessageBoxButton]::OK, [MessageBoxImage]::Warning)
    }

    $fileName = $lstFiles.SelectedValue
    if($fileName) {
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.FileName = $fileName
        if($dialog.ShowDialog()) {
            $folder = $dialog.FileName
            Receive-RemoteItem -Session $session -Path $fileName -Destination $folder -RootPath Package
        }
    } else {
        return [MessageBox]::Show("Please select a file to download.", "Download", [MessageBoxButton]::OK, [MessageBoxImage]::Information)
    }

    $lstFiles.ItemsSource = @(Invoke-RemoteScript -ScriptBlock $queryFileList -Session $session)
})

<# Display the window #>
$window.Dispatcher.InvokeAsync{$window.ShowDialog()}.Wait()

Stop-ScriptSession -Session $session