// Tiny Spotify now-playing reader for the deskforge Rainmeter skin.
// Reads Spotify's window title ("Artist - Song"), writes nowplaying.txt (line 1 song, line 2 artist)
// only when it changes. Idle priority, single instance, exits when Rainmeter is no longer running.
// Build: csc /target:winexe /out:nowplaying.exe nowplaying.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class NowPlaying
{
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);

    static string FindTitle()
    {
        var pids = new System.Collections.Generic.HashSet<uint>();
        foreach (var p in Process.GetProcessesByName("Spotify")) { pids.Add((uint)p.Id); p.Dispose(); }
        if (pids.Count == 0) return "";
        string found = "";
        EnumWindows((h, l) =>
        {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (!pids.Contains(pid)) return true;
            var cls = new StringBuilder(64); GetClassName(h, cls, 64);
            if (!cls.ToString().StartsWith("Chrome_WidgetWin")) return true;
            var t = new StringBuilder(512); GetWindowText(h, t, 512);
            var s = t.ToString();
            // Paused or idle Spotify shows "Spotify", "Spotify Free" or "Spotify Premium"
            if (s.Contains(" - ") && !s.StartsWith("Spotify")) { found = s; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    static bool RainmeterAlive()
    {
        var r = Process.GetProcessesByName("Rainmeter");
        bool alive = r.Length > 0;
        foreach (var p in r) p.Dispose();
        return alive;
    }

    [STAThread]
    static void Main()
    {
        bool created;
        using (var m = new Mutex(true, "deskforgeNowPlaying", out created))
        {
            if (!created) return;
            try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.Idle; } catch { }
            string dir = AppDomain.CurrentDomain.BaseDirectory;
            string file = Path.Combine(dir, "nowplaying.txt");
            string last = null;
            var utf8 = new UTF8Encoding(false);
            while (RainmeterAlive())
            {
                string title = FindTitle();
                if (title != last)
                {
                    string song = "", artist = "";
                    int i = title.IndexOf(" - ", StringComparison.Ordinal);
                    if (i > 0) { artist = title.Substring(0, i); song = title.Substring(i + 3); }
                    try { File.WriteAllText(file, song + "\n" + artist, utf8); last = title; } catch { }
                }
                Thread.Sleep(1500);
            }
            try { File.WriteAllText(file, "\n", utf8); } catch { }
        }
    }
}
