using System.Diagnostics;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using System.Windows.Forms;

namespace SlotPasteSetup;

internal static class Program
{
    private const string AppName = "SlotPaste";
    private const string UninstallKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SlotPaste";

    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            if (HasArgument(args, "/uninstall") || HasArgument(args, "--uninstall"))
            {
                Uninstall();
                return;
            }

            Install();
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "SlotPaste konnte nicht installiert werden:\n\n" + exception.Message,
                AppName,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }

    private static void Install()
    {
        string installDirectory = GetInstallDirectory();
        Directory.CreateDirectory(installDirectory);

        string scriptPath = Path.Combine(installDirectory, "SlotPaste.ps1");
        string iconPath = Path.Combine(installDirectory, "SlotPaste.ico");
        string appPath = Path.Combine(installDirectory, "SlotPaste.exe");
        string setupPath = Path.Combine(installDirectory, "SlotPaste-Setup.exe");

        WriteResource("SlotPaste.ps1", scriptPath);
        WriteResource("SlotPaste.ico", iconPath);
        WriteResource("SlotPaste.app.exe", appPath);

        string currentSetupPath = Environment.ProcessPath ?? string.Empty;
        if (!PathsEqual(currentSetupPath, setupPath))
        {
            File.Copy(currentSetupPath, setupPath, true);
        }

        string powershellPath = GetWindowsPowerShellPath();
        string shortcutPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
            "Programs",
            "SlotPaste.lnk");
        Directory.CreateDirectory(Path.GetDirectoryName(shortcutPath)!);
        CreateShortcut(
            shortcutPath,
            powershellPath,
            $"-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{scriptPath}\"",
            installDirectory,
            iconPath,
            "SlotPaste starten");

        using (RegistryKey uninstall = Registry.CurrentUser.CreateSubKey(UninstallKey)!)
        {
            uninstall.SetValue("DisplayName", AppName);
            uninstall.SetValue("DisplayVersion", "1.0");
            uninstall.SetValue("Publisher", "SlotPaste");
            uninstall.SetValue("InstallLocation", installDirectory);
            uninstall.SetValue("DisplayIcon", iconPath);
            uninstall.SetValue("UninstallString", $"\"{setupPath}\" /uninstall");
            uninstall.SetValue("NoModify", 1, RegistryValueKind.DWord);
            uninstall.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }

        StartInstalledApp(scriptPath, installDirectory);

        MessageBox.Show(
            "SlotPaste wurde für diesen Benutzer installiert.\n\n" +
            "Du findest es jetzt im Startmenü. Die Autostart-Option und die Tastenkürzel werden in SlotPaste eingestellt.",
            AppName,
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    private static void Uninstall()
    {
        string installDirectory = GetInstallDirectory();
        string shortcutPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
            "Programs",
            "SlotPaste.lnk");
        if (File.Exists(shortcutPath)) File.Delete(shortcutPath);

        using (RegistryKey? parent = Registry.CurrentUser.OpenSubKey(
                   "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall", true))
        {
            parent?.DeleteSubKeyTree("SlotPaste", false);
        }

        string currentSetupPath = Environment.ProcessPath ?? string.Empty;
        string cleanupPath = Path.Combine(Path.GetTempPath(), "SlotPaste-uninstall-" + Guid.NewGuid().ToString("N") + ".cmd");
        string deleteCurrentSetup = PathsEqual(currentSetupPath, Path.Combine(installDirectory, "SlotPaste-Setup.exe"))
            ? $"del /f /q \"{currentSetupPath}\"\r\n"
            : string.Empty;
        string cleanup = "@echo off\r\n" +
                         "timeout /t 1 /nobreak >nul\r\n" +
                         $"rmdir /s /q \"{installDirectory}\"\r\n" +
                         deleteCurrentSetup +
                         "del /f /q \"%~f0\"\r\n";
        File.WriteAllText(cleanupPath, cleanup);
        Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c \"{cleanupPath}\"",
            CreateNoWindow = true,
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Hidden
        });
    }

    private static void StartInstalledApp(string scriptPath, string installDirectory)
    {
        ProcessStartInfo startInfo = new()
        {
            FileName = GetWindowsPowerShellPath(),
            WorkingDirectory = installDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-WindowStyle");
        startInfo.ArgumentList.Add("Hidden");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        SetLocalPowerShellModulePath(startInfo);
        Process.Start(startInfo);
    }

    private static string GetInstallDirectory()
    {
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localAppData)) localAppData = AppContext.BaseDirectory;
        return Path.Combine(localAppData, "Programs", AppName);
    }

    private static string GetWindowsPowerShellPath()
    {
        string path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        return File.Exists(path) ? path : "powershell.exe";
    }

    private static void SetLocalPowerShellModulePath(ProcessStartInfo startInfo)
    {
        List<string> paths = new();
        string systemModules = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "Modules");
        string programModules = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "WindowsPowerShell", "Modules");
        if (Directory.Exists(systemModules)) paths.Add(systemModules);
        if (Directory.Exists(programModules)) paths.Add(programModules);
        if (paths.Count > 0) startInfo.Environment["PSModulePath"] = string.Join(";", paths);
    }

    private static void CreateShortcut(
        string shortcutPath,
        string targetPath,
        string arguments,
        string workingDirectory,
        string iconPath,
        string description)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell")
            ?? throw new InvalidOperationException("Windows-Shell-Verknüpfungen werden nicht unterstützt.");
        object shell = Activator.CreateInstance(shellType)
            ?? throw new InvalidOperationException("Windows-Shell konnte nicht gestartet werden.");
        try
        {
            dynamic shortcut = shellType.InvokeMember(
                "CreateShortcut",
                System.Reflection.BindingFlags.InvokeMethod,
                null,
                shell,
                new object[] { shortcutPath })!;
            shortcut.TargetPath = targetPath;
            shortcut.Arguments = arguments;
            shortcut.WorkingDirectory = workingDirectory;
            shortcut.IconLocation = iconPath + ",0";
            shortcut.Description = description;
            shortcut.Save();
        }
        finally
        {
            Marshal.FinalReleaseComObject(shell);
        }
    }

    private static void WriteResource(string resourceName, string targetPath)
    {
        using Stream resource = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("Installationsdatei fehlt: " + resourceName);
        using FileStream output = File.Create(targetPath);
        resource.CopyTo(output);
    }

    private static bool HasArgument(IEnumerable<string> args, string expected)
    {
        foreach (string arg in args)
        {
            if (string.Equals(arg, expected, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    private static bool PathsEqual(string first, string second)
    {
        return string.Equals(
            Path.GetFullPath(first),
            Path.GetFullPath(second),
            StringComparison.OrdinalIgnoreCase);
    }
}
