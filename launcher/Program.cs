using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;

namespace SlotPasteLauncher;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
            string launcherPath = Environment.ProcessPath
                ?? Process.GetCurrentProcess().MainModule?.FileName
                ?? string.Empty;
            string workingDirectory = Path.GetDirectoryName(launcherPath)
                ?? AppContext.BaseDirectory;
        string runtimeDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SlotPaste");

        try
        {
            string scriptPath;
            try
            {
                scriptPath = WriteEmbeddedScript(runtimeDirectory);
            }
            catch (UnauthorizedAccessException)
            {
                string fallbackRoot = Path.GetDirectoryName(launcherPath)
                    ?? AppContext.BaseDirectory;
                runtimeDirectory = Path.Combine(fallbackRoot, ".slotpaste-runtime");
                scriptPath = WriteEmbeddedScript(runtimeDirectory);
            }

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(powershellPath))
            {
                powershellPath = "powershell.exe";
            }

            string systemModules = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "Modules");
            string programModules = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "WindowsPowerShell", "Modules");
            List<string> modulePaths = new();
            if (Directory.Exists(systemModules)) modulePaths.Add(systemModules);
            if (Directory.Exists(programModules)) modulePaths.Add(programModules);

            ProcessStartInfo startInfo = new()
            {
                FileName = powershellPath,
                WorkingDirectory = workingDirectory,
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
            startInfo.Environment["SLOT_PASTE_LAUNCHER"] = launcherPath;
            if (modulePaths.Count > 0)
            {
                startInfo.Environment["PSModulePath"] = string.Join(";", modulePaths);
            }

            Process.Start(startInfo);
        }
        catch (Exception exception)
        {
            try
            {
                Directory.CreateDirectory(runtimeDirectory);
                File.WriteAllText(
                    Path.Combine(runtimeDirectory, "launcher-error.log"),
                    exception.ToString());
            }
            catch
            {
                // Der eigentliche Fehler wird unten weiterhin angezeigt.
            }

            MessageBox.Show(
                "SlotPaste konnte nicht gestartet werden:\n\n" + exception.Message,
                "SlotPaste",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string WriteEmbeddedScript(string runtimeDirectory)
    {
        Directory.CreateDirectory(runtimeDirectory);
        string scriptPath = Path.Combine(runtimeDirectory, "SlotPaste.ps1");
        using Stream? resource = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("SlotPaste.ps1");
        if (resource is null)
        {
            throw new InvalidOperationException("Die eingebettete SlotPaste-Datei wurde nicht gefunden.");
        }

        using FileStream scriptFile = File.Create(scriptPath);
        resource.CopyTo(scriptFile);

        using Stream? iconResource = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("SlotPaste.ico");
        if (iconResource is not null)
        {
            using FileStream iconFile = File.Create(Path.Combine(runtimeDirectory, "SlotPaste.ico"));
            iconResource.CopyTo(iconFile);
        }

        return scriptPath;
    }
}
