# cd 'C:\change\this'
Add-Type -Path ".\WinRT.Runtime.dll"
Add-Type -Path ".\Microsoft.Windows.SDK.NET.dll"
Add-Type -Path ".\Microsoft.WindowsAppRuntime.Bootstrap.Net.dll"
Add-Type -Path ".\Microsoft.InteractiveExperiences.Projection.dll"
Add-Type -Path ".\Microsoft.WinUI.dll"

# //Setup runspacepool and shared variable
$ConcurrentDict = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$State = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$RunspaceVariable = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new('ConcurrentDict', $ConcurrentDict, $null)
$State.Variables.Add($RunspaceVariable)
$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $([int]$env:NUMBER_OF_PROCESSORS + 1), $State, (Get-Host))
$RunspacePool.Open()
$Powershell = [PowerShell]::Create()
$Powershell.RunspacePool = $RunspacePool

$AppSetup = @'
# cd 'C:\change\this'
Add-Type -Path ".\WinRT.Runtime.dll"
Add-Type -Path ".\Microsoft.Windows.SDK.NET.dll"
Add-Type -Path ".\Microsoft.WindowsAppRuntime.Bootstrap.Net.dll"
Add-Type -Path ".\Microsoft.InteractiveExperiences.Projection.dll"
Add-Type -Path ".\Microsoft.WinUI.dll"

class PwshWinUIApp : Microsoft.UI.Xaml.Application, Microsoft.UI.Xaml.Markup.IXamlMetadataProvider {
    # //App is able to load without Microsoft.UI.Xaml.Markup.IXamlMetadataProvider but interaction such as clicking a button will crash the terminal without it.

    $MainWindow
    $provider = [Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider]::new()
    static [bool]$OkWasClicked
    $SharedConcurrentDictionary

    [Microsoft.UI.Xaml.Markup.IXamlType]GetXamlType([type]$type) {
        return $this.provider.GetXamlType($type)
    }
    [Microsoft.UI.Xaml.Markup.IXamlType]GetXamlType([string]$fullname) {
        return $this.provider.GetXamlType($fullname)
    }
    [Microsoft.UI.Xaml.Markup.XmlnsDefinition[]]GetXmlnsDefinitions() {
        return $this.provider.GetXmlnsDefinitions()
    }

    PwshWinUIApp() {}
    PwshWinUIApp($SharedConcurrentDictionary) {
        $this.SharedConcurrentDictionary = $SharedConcurrentDictionary
    }
    OnLaunched([Microsoft.UI.Xaml.LaunchActivatedEventArgs]$a) {
        if ($null -ne $this.MainWindow) { return }

        # //Don't know why this line is problematic or how to get it to work in powershell. But the app works without it.
        # $this.Resources.MergedDictionaries.Add([Microsoft.UI.Xaml.Controls.XamlControlsResources]::new())
        
        $xaml = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
                <StackPanel
                    HorizontalAlignment="Center"
                    VerticalAlignment="Center"
                    Orientation="Horizontal">
                    <TextBlock Text="{Binding tbContent, Mode=TwoWay}" Margin="10" />
                    <Button x:Name="okButton" Margin="10">OK</Button>
                    <Button x:Name="cancelButton" Margin="10">Cancel</Button>
                </StackPanel>
            </Window>'

        $this.MainWindow = [Microsoft.UI.Xaml.Markup.XamlReader]::Load($xaml)

        $ClassScope = $this
        $WindowScope = $this.MainWindow
        
        $this.SharedConcurrentDictionary.App = $ClassScope # Terminal will crash on most properties and the object itself when printing to terminal.
        $this.SharedConcurrentDictionary.Window = $WindowScope
        $this.SharedConcurrentDictionary.Dispatcher = $WindowScope.DispatcherQueue

        $this.SharedConcurrentDictionary.OnloadFinished = $true
        # $this.MainWindow.Activate()
    }
    static [bool] Run($SharedConcurrentDictionary) {
        [Microsoft.Windows.ApplicationModel.DynamicDependency.Bootstrap]::Initialize(0x0010005)

        [Microsoft.UI.Xaml.Application]::Start({
            [PwshWinUIApp]::new($SharedConcurrentDictionary)
        })
        [Microsoft.Windows.ApplicationModel.DynamicDependency.Bootstrap]::Shutdown()
        return [PwshWinUIApp]::OkWasClicked
    }
}

[PwshWinUIApp]::Run($ConcurrentDict)
'@

# //Start app without window
$AppSetupScriptBlock = [scriptblock]::Create($AppSetup)
$null = $Powershell.AddScript($AppSetupScriptBlock)
$Handle = $Powershell.BeginInvoke()

# //Optional binding to class
[NoRunspaceAffinity()]
class binder {
    # //Should inherit IPropertyNotifyChanged
    # //or a dependency object
    binder(){}
    $tbContent = 'Without IPropertyNotifyChanged, this will not update'
}
$ConcurrentDict.binder = [binder]::new()

# //Wait for app to finish loading
while ($ConcurrentDict.OnloadFinished -ne $true) {
    Start-Sleep -Milliseconds 50
}

# //Send actions to dispatcher such as setting up buttons (Could also bind buttons through a class like above)
$null = $ConcurrentDict.Dispatcher.TryEnqueue([scriptblock]::create({
    # //This is inside the Window thread/runspace
    # //Because ConcurrentDict is a shared variable, the Window thread can also access it
    # //We have less access compared to wpf, where you could traverse the wpf object on any thread.
    # //If you call $ConcurrentDict.Window.Content outside of this thread, it will be empty.

    $sp = $ConcurrentDict.Window.Content
    $ConcurrentDict.Window.Content.DataContext = $ConcurrentDict.binder

    $ok = $sp.FindName("okButton")
    $cancel = $sp.FindName("cancelButton")
    
    $ok.add_Click([scriptblock]::create({
        param($s, $e)
        Write-Verbose "sender is: $($s.Name)" -Verbose
        
        [PwshWinUIApp]::OkWasClicked = $true
        
        $ConcurrentDict.ThreadId = "Set from Thread Id: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)"
        $ConcurrentDict.Window.Close()
    }.ToString()))
    
    $cancel.add_Click([scriptblock]::create({
        param($s, $e)
        Write-Verbose "sender is: $($s.Name)" -Verbose
        
        $ConcurrentDict.ThreadId = "Set from Thread Id: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)"
        $ConcurrentDict.Window.Close()
    }.ToString()))
}.ToString()))

# //Finally show the window via dispatcher
$Action = {$ConcurrentDict.Window.Activate()}.ToString()
$NoContextAction = [scriptblock]::create($Action)
$null = $ConcurrentDict.Window.DispatcherQueue.TryEnqueue($NoContextAction)

"Current Thread Id: $([System.Threading.Thread]::CurrentThread.ManagedThreadId)"
$ConcurrentDict
