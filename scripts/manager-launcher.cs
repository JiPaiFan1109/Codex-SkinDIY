using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("Codex 换肤管理中心")]
[assembly: AssemblyDescription("Codex 换肤管理中心")]
[assembly: AssemblyProduct("Codex 换肤管理中心")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace CodexDynamicSkin {
  static class ManagerProgram {
    [STAThread]
    static int Main(string[] args) {
      bool created;
      using (var mutex = new Mutex(true, "CodexDynamicSkinManager", out created)) {
        if (!created) { MessageBox.Show("换肤管理中心已经打开。", "Codex 换肤管理中心"); return 0; }
        try {
          string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
          string script = Path.Combine(root, "scripts", "manage-background.ps1");
          if (!File.Exists(script)) throw new FileNotFoundException("安装文件不完整，请重新安装换肤管理中心。", script);
          string arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \"" + script + "\" -InstallRoot \"" + root + "\"";
          // Isolated package verification can open the real UI without changing Codex.
          if (args.Length == 1 && args[0] == "--prepare-only") arguments += " -PrepareOnly";
          var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"), arguments);
          info.WorkingDirectory = root;
          info.UseShellExecute = false;
          info.CreateNoWindow = true;
          info.WindowStyle = ProcessWindowStyle.Hidden;
          using (var process = Process.Start(info)) {
            process.WaitForExit();
            if (process.ExitCode != 0) throw new Exception("管理中心启动失败，请重新安装；如果仍然失败，请检查安装目录中的日志。");
          }
          return 0;
        } catch (Exception error) {
          MessageBox.Show(error.Message, "Codex 换肤管理中心", MessageBoxButtons.OK, MessageBoxIcon.Warning);
          return 1;
        } finally { mutex.ReleaseMutex(); }
      }
    }
  }
}
