Add-Type -Path ".\WinRT.Runtime.dll"
Add-Type -Path ".\Microsoft.Windows.SDK.NET.dll"
Add-Type -Path ".\Microsoft.WindowsAppRuntime.Bootstrap.Net.dll"
Add-Type -Path ".\Microsoft.InteractiveExperiences.Projection.dll"
Add-Type -Path ".\Microsoft.WinUI.dll"

$referencedAssemblies = @(
    "System.Threading" # for SynchronizationContext
    ".\WinRT.Runtime.dll"
    ".\Microsoft.Windows.SDK.NET.dll"
    ".\Microsoft.WindowsAppRuntime.Bootstrap.Net.dll"
    ".\Microsoft.InteractiveExperiences.Projection.dll"
    ".\Microsoft.WinUI.dll"
)

#Note: we remove warning CS1701: Assuming assembly reference 'System.Runtime, Version=6.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
#  used by 'Microsoft.WindowsAppRuntime.Bootstrap.Net'
#  matches identity 'System.Runtime, Version=8.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a' of 'System.Runtime',
#  you may need to supply runtime policy
Add-Type -ReferencedAssemblies $referencedAssemblies -CompilerOptions /nowarn:CS1701 -Language CSharp @"
using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.ApplicationModel.DynamicDependency;
using Windows.Graphics;
using Windows.UI.Popups;
using WinRT.Interop;

namespace BasicWinUI
{
    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            Bootstrap.Initialize(0x00010005); // asks for WinAppSDK version 1.5, or gets "Package dependency criteria could not be resolved" error
            XamlCheckProcessRequirements();
            Application.Start((p) =>
            {
                SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
                new App();
            });
            Bootstrap.Shutdown();
        }

        [DllImport("microsoft.ui.xaml")]
        private static extern void XamlCheckProcessRequirements();
    }

    public class App : Application
    {
        private MyWindow m_window;

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            if (m_window != null)
                return;

            m_window = new MyWindow();
            m_window.Activate();
        }
    }

    public class MyWindow : Window
    {
        public MyWindow()
        {
            Title = "Basic WinUI3";

            // set icon by path
            AppWindow.SetIcon("BasicWinUI.ico");

            // size & center
            var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Nearest);
            var width = 300; var height = 150;
            var rc = new RectInt32((area.WorkArea.Width - width) / 2, (area.WorkArea.Height - height) / 2, width, height);
            AppWindow.MoveAndResize(rc);

            // give a "dialog" look
            if (AppWindow.Presenter is OverlappedPresenter p)
            {
                p.IsMinimizable = false;
                p.IsMaximizable = false;
                p.IsResizable = false;
            }

            // create the content as a panel
            var panel = new StackPanel { Margin = new Thickness(10) };
            Content = panel;
            panel.Children.Add(new TextBlock { Text = "Are you sure you want to do this?", HorizontalAlignment = HorizontalAlignment.Center });

            // create a panel for buttons
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            panel.Children.Add(buttons);

            // add yes & no buttons
            var yes = new Button { Content = "Yes", Margin = new Thickness(10) };
            var no = new Button { Content = "No", Margin = new Thickness(10) };
            buttons.Children.Add(yes);
            buttons.Children.Add(no);

            no.Click += (s, e) => Close();
            yes.Click += async (s, e) =>
            {
                // show some other form
                var dlg = new MessageDialog("You did click yes", Title);
                InitializeWithWindow.Initialize(dlg, WindowNative.GetWindowHandle(this));
                await dlg.ShowAsync();
            };

            // focus on first button
            panel.Loaded += (s, e) => panel.Focus(FocusState.Keyboard);
        }
    }
}
"@;
 
[BasicWinUI.Program]::Main()