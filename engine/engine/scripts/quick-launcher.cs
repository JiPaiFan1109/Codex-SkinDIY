using System;
using System.Diagnostics;
using System.IO;

namespace CodexDynamicSkin {
  static class Program {
    [STAThread]
    static void Main() {
      try {
        string launcherDirectory = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        string root = Directory.GetParent(launcherDirectory).Parent.FullName;
        string script = Path.Combine(root, "engine", "scripts", "launch-dream-skin.ps1");
        var info = new ProcessStartInfo(
          Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
          "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \"" + script.Replace("\"", "\\\"") + "\"");
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WindowStyle = ProcessWindowStyle.Hidden;
        Process.Start(info);
      } catch {
        // The guarded PowerShell launcher owns user-visible diagnostics.
      }
    }
  }
}
