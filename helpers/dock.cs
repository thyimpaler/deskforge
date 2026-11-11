// deskforge dock + home helper for the Rainmeter skins deskforge\Dock and deskforge\Home.
//   dock.exe              main loop: tracks open windows, pushes labels and states to the dock,
//                         hides the dock under true full-screen apps, reserves the dock strip as an AppBar,
//                         owns the hotkeys (Win+Z toggles Home, Esc closes Home while it is open),
//                         and plays the wake reveal after an unlock or resume when desk.inc turns it on.
//   dock.exe act N        a dock slot was clicked: focus, minimize or launch.
//   dock.exe go N         Home row N (1-based, from apps.txt): focus the app if open, otherwise launch it.
//   dock.exe go lock|power
//   dock.exe home|close   toggle or close Home.
//   dock.exe search       close Home and open Windows search (Win+S).
//   dock.exe vol up|down|mute, dock.exe bri up|down
//   dock.exe alert "TITLE" "BODY"   show the alert band once (needs the alert addon).
// Apps come from @Resources\apps.txt (name|path, written by install.ps1 from homeApps in desk.json).
// Colours come from @Resources\theme.inc, the dock edge and switches from @Resources\desk.inc.
// No keyboard hooks: only RegisterHotKey. No network. Exits when Rainmeter closes.
// Build: helpers\build.ps1 (csc /target:winexe /r:System.Management.dll, C# 5, .NET Framework 4)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

static class Dock
{
    const string Cfg = "deskforge";
    class App { public string Key, Label, Exe, Cls, File; }

    static readonly string Res = AppDomain.CurrentDomain.BaseDirectory;
    static List<App> Apps = new List<App>();
    static int Pinned = 0;
    const int Slots = 13;
    static Dictionary<string, string> Theme = new Dictionary<string, string>();
    static Dictionary<string, string> Desk = new Dictionary<string, string>();

    // ---------------------------------------------------------------- config files
    static Dictionary<string, string> ReadVars(string name)
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var line in File.ReadAllLines(Path.Combine(Res, name)))
            {
                int i = line.IndexOf('=');
                if (i > 0 && !line.StartsWith(";")) d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
            }
        }
        catch { }
        return d;
    }
    static string V(Dictionary<string, string> d, string k, string def) { string v; return d.TryGetValue(k, out v) && v.Length > 0 ? v : def; }

    static void LoadConfig()
    {
        Theme = ReadVars("theme.inc");
        Desk = ReadVars("desk.inc");
        Apps = new List<App>();
        try
        {
            int n = 0;
            foreach (var raw in File.ReadAllLines(Path.Combine(Res, "apps.txt"), Encoding.UTF8))
            {
                if (raw.StartsWith("#") || raw.IndexOf('|') < 0) continue;
                var p = raw.Split(new[] { '|' }, 2);
                string path = p[1].Trim();
                var a = new App { Key = (++n).ToString(), Label = Clean(p[0], 12), File = path, Exe = "\u0000" };
                if (path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) a.Exe = Path.GetFileName(path).ToLowerInvariant();
                if (a.Exe == "explorer.exe") a.Cls = "CabinetWClass";
                if (a.Exe == "wt.exe") a.Exe = "windowsterminal.exe";
                Apps.Add(a);
            }
        }
        catch { }
        Pinned = Math.Min(Apps.Count, 10);
    }

    // ---------------------------------------------------------------- win32
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct COPYDATASTRUCT { public IntPtr dwData; public int cbData; public IntPtr lpData; }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool altTab);
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string c, string t);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, ref COPYDATASTRUCT l);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool LockWorkStation();
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hgt, uint flags);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, uint flags, StringBuilder s, ref int size);

    class Win { public IntPtr H; public string Cls, Title, Path, Exe; }

    static readonly Dictionary<uint, string> PathCache = new Dictionary<uint, string>();
    static string PathOf(uint pid)
    {
        string p;
        if (PathCache.TryGetValue(pid, out p)) return p;
        p = "";
        IntPtr h = OpenProcess(0x1000, false, pid);
        if (h != IntPtr.Zero)
        {
            var sb = new StringBuilder(520); int n = sb.Capacity;
            if (QueryFullProcessImageName(h, 0, sb, ref n)) p = sb.ToString();
            CloseHandle(h);
        }
        PathCache[pid] = p;
        return p;
    }

    static List<Win> Snapshot(out bool homeVisible)
    {
        var list = new List<Win>(); bool hv = false;
        EnumWindows(delegate (IntPtr h, IntPtr l)
        {
            if (!IsWindowVisible(h)) return true;
            var c = new StringBuilder(128); GetClassName(h, c, 128); string cls = c.ToString();
            if (cls == "RainmeterMeterWindow")
            {
                var t = new StringBuilder(400); GetWindowText(h, t, 400);
                if (t.ToString().EndsWith("\\Home\\Home.ini", StringComparison.OrdinalIgnoreCase)) hv = true;
                return true;
            }
            if (GetWindow(h, 4) != IntPtr.Zero) return true;                 // owned popup
            int ex = GetWindowLong(h, -20);
            if ((ex & 0x80) != 0 && (ex & 0x40000) == 0) return true;        // tool window
            if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd" || cls == "Windows.UI.Core.CoreWindow") return true;
            int cloaked;
            if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
            var tt = new StringBuilder(300); GetWindowText(h, tt, 300);
            if (tt.Length == 0) return true;
            uint pid; GetWindowThreadProcessId(h, out pid);
            string path = PathOf(pid);
            list.Add(new Win { H = h, Cls = cls, Title = tt.ToString(), Path = path, Exe = Path.GetFileName(path).ToLowerInvariant() });
            return true;
        }, IntPtr.Zero);
        homeVisible = hv;
        return list;
    }

    static bool Match(App a, Win w)
    {
        if (w.Exe != a.Exe) return false;
        if (a.Cls != null && w.Cls != a.Cls) return false;
        return true;
    }

    // Unread count from a title like "(5) Inbox" or "[12+] Chat". 0 when there is none.
    static int Unread(string title)
    {
        var m = System.Text.RegularExpressions.Regex.Match(title, @"^\s*[\(\[](\d+)\+?[\)\]]");
        int n; return m.Success && int.TryParse(m.Groups[1].Value, out n) ? n : 0;
    }

    static readonly Dictionary<string, int> lastUnread = new Dictionary<string, int>();

    static void Alert(string title, string body)
    {
        if (V(Desk, "AddonAlert", "0") != "1") return;
        try
        {
            File.WriteAllText(Path.Combine(Res, "alert.inc"), "[Variables]\r\nATitle=" + Clean(title, 24) + "\r\nABody=" + Clean(body, 40) + "\r\n", Encoding.ASCII);
            Bang(FindSkin("\\Alert\\Alert.ini") != IntPtr.Zero ? "[!Refresh \"" + Cfg + "\\Alert\"]" : "[!ActivateConfig \"" + Cfg + "\\Alert\" \"Alert.ini\"]");
            System.Media.SystemSounds.Asterisk.Play();
        }
        catch { }
    }

    static void Bang(string bangs)
    {
        IntPtr h = FindWindow("DummyRainWClass", null);
        if (h == IntPtr.Zero) return;
        IntPtr p = Marshal.StringToHGlobalUni(bangs);
        try
        {
            var cds = new COPYDATASTRUCT { dwData = (IntPtr)1, cbData = (bangs.Length + 1) * 2, lpData = p };
            SendMessage(h, 0x004A, IntPtr.Zero, ref cds);
        }
        finally { Marshal.FreeHGlobal(p); }
    }

    static string Clean(string s, int max)
    {
        var sb = new StringBuilder();
        foreach (char ch in s.ToUpperInvariant())
        {
            if ((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == ' ') sb.Append(ch);
            if (sb.Length >= max) break;
        }
        return sb.ToString().Trim();
    }

    static string StateFile { get { return Path.Combine(Res, "dockstate.txt"); } }

    // ---------------------------------------------------------------- main loop state
    static IntPtr lastFg = IntPtr.Zero;
    static string lastSig = null;
    static bool lastFull = false, escOn = false;
    static int tick = 0;
    static Host host;

    // ---------------------------------------------------------------- home toggle (no fades: they tear on weak GPUs)
    static bool HomeOpen() { bool hv; Snapshot(out hv); return hv; }
    static void ShowHome() { Bang("[!Hide \"" + Cfg + "\\Dock\"][!Hide \"" + Cfg + "\\Wave\"][!Show \"" + Cfg + "\\Home\"][!ZPos 2 \"" + Cfg + "\\Home\"]"); }
    static void HideHome() { Bang("[!Hide \"" + Cfg + "\\Home\"]" + (lastFull ? "" : "[!Show \"" + Cfg + "\\Dock\"][!Show \"" + Cfg + "\\Wave\"]")); }
    static void ToggleHome() { if (HomeOpen()) HideHome(); else ShowHome(); }

    // ---------------------------------------------------------------- the dock strip is reserved as an AppBar
    // Registering the helper's window as an AppBar lets Explorer keep the work area itself.
    // Changing the work area directly fights Explorer and makes windows jump.
    const int DockH = 56;
    [StructLayout(LayoutKind.Sequential)] struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
    [DllImport("shell32.dll")] static extern IntPtr SHAppBarMessage(uint msg, ref APPBARDATA d);
    const int BarMsg = 0x0400 + 77;
    static bool barOn = false;
    static bool Top { get { return V(Desk, "DockEdge", "bottom") == "top"; } }
    static void BarSetPos()
    {
        var b = Screen.PrimaryScreen.Bounds;
        var d = new APPBARDATA { hWnd = host.Handle, uEdge = Top ? 1u : 3u };
        d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
        d.rc = Top ? new RECT { L = b.Left, T = b.Top, R = b.Right, B = b.Top + DockH } : new RECT { L = b.Left, T = b.Bottom - DockH, R = b.Right, B = b.Bottom };
        SHAppBarMessage(2, ref d);                       // ABM_QUERYPOS
        if (Top) d.rc.B = d.rc.T + DockH; else d.rc.T = d.rc.B - DockH;
        SHAppBarMessage(3, ref d);                       // ABM_SETPOS
    }
    static void EnforceWorkArea(bool reserve)
    {
        if (host == null) return;
        if (reserve && !barOn)
        {
            var d = new APPBARDATA { hWnd = host.Handle, uCallbackMessage = BarMsg };
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            SHAppBarMessage(0, ref d);                   // ABM_NEW
            barOn = true; BarSetPos();
        }
        else if (!reserve && barOn)
        {
            var d = new APPBARDATA { hWnd = host.Handle };
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            SHAppBarMessage(1, ref d);                   // ABM_REMOVE
            barOn = false;
        }
    }

    // ---------------------------------------------------------------- wake reveal
    static DateTime lastReveal = DateTime.MinValue;
    static void Reveal()
    {
        if (V(Desk, "WakeReveal", "0") != "1") return;
        if ((DateTime.Now - lastReveal).TotalSeconds < 10) return;
        lastReveal = DateTime.Now;
        try
        {
            File.WriteAllText(Path.Combine(Res, "bootseq.inc"),
                "[Variables]\r\nBTime=" + DateTime.Now.ToString("HH:mm") + "\r\nBNet=RESUMED\r\nBWid=-\r\nBDock=READY\r\n", Encoding.ASCII);
        }
        catch { }
        Bang("[!ActivateConfig \"" + Cfg + "\\Boot\" \"Boot.ini\"]");
    }

    static void Poll()
    {
        if (FindWindow("DummyRainWClass", null) == IntPtr.Zero) { EnforceWorkArea(false); Application.Exit(); return; }
        if (++tick % 80 == 0) PathCache.Clear();
        PushLevels();
        RaiseWave();

        bool homeVisible;
        var wins = Snapshot(out homeVisible);

        IntPtr fg = GetForegroundWindow();
        IntPtr root = fg == IntPtr.Zero ? fg : GetAncestor(fg, 3);
        var fc = new StringBuilder(64); GetClassName(fg, fc, 64);
        // A click on the dock makes Rainmeter foreground: keep the app that was focused before it.
        if (fc.ToString().StartsWith("Rainmeter") || fc.ToString() == "DummyRainWClass") root = lastFg; else lastFg = root;

        string cIdle = V(Theme, "Dim", "92,92,92"), cOpen = V(Theme, "Mid", "150,150,150"), cFocus = V(Theme, "Ink", "233,233,233");
        string cAccent = V(Theme, "Accent", "164,22,26"), cRule = V(Theme, "Rule", "34,34,34");
        var used = new HashSet<IntPtr>();
        var bang = new StringBuilder(); var state = new StringBuilder(); var sig = new StringBuilder();
        int slot = 0;
        int curUnread = 0;
        Action<string, IntPtr, bool, string> emit = delegate (string label, IntPtr pick, bool focused, string key)
        {
            slot++;
            int st = pick == IntPtr.Zero ? 0 : (focused && !IsIconic(pick) ? 2 : 1);
            string col = st == 0 ? cIdle : (st == 1 ? cOpen : cFocus);
            string idx = st == 0 ? cRule : cAccent;
            string text = slot.ToString("00") + "  " + label;
            if (curUnread > 0) { text += "  " + curUnread; if (st != 2) col = cAccent; }
            curUnread = 0;
            bang.Append("[!SetVariable T" + slot + " \"" + text + "\" \"" + Cfg + "\\Dock\"]");
            bang.Append("[!SetVariable C" + slot + " \"" + col + "\" \"" + Cfg + "\\Dock\"]");
            bang.Append("[!SetVariable K" + slot + " \"" + idx + "\" \"" + Cfg + "\\Dock\"]");
            state.Append(slot + "|" + pick.ToInt64() + "|" + st + "|" + key + "\n");
            sig.Append(text + st + pick.ToInt64() + ";");
        };

        for (int i = 0; i < Pinned; i++)
        {
            IntPtr pick = IntPtr.Zero; bool foc = false;
            int unread = 0;
            foreach (var w in wins)
                if (Match(Apps[i], w))
                {
                    used.Add(w.H);
                    if (w.H == root) { pick = w.H; foc = true; } else if (pick == IntPtr.Zero) pick = w.H;
                    unread = Math.Max(unread, Unread(w.Title));
                }
            int before;
            bool seen = lastUnread.TryGetValue(Apps[i].Key, out before);
            if (pick != IntPtr.Zero && seen && unread > before && !foc) Alert(Apps[i].Label, unread + (unread == 1 ? " UNREAD" : " UNREAD"));
            if (pick != IntPtr.Zero) lastUnread[Apps[i].Key] = unread;
            curUnread = unread;
            emit(Apps[i].Label, pick, foc, Apps[i].Key);
        }

        // Everything else that is open, grouped per app, sorted by label so slots don't jump around.
        var groups = new SortedDictionary<string, object[]>(StringComparer.Ordinal);
        foreach (var w in wins)
        {
            if (used.Contains(w.H)) continue;
            string label = null, key = "";
            for (int i = Pinned; i < Apps.Count; i++) if (Match(Apps[i], w)) { label = Apps[i].Label; key = Apps[i].Key; break; }
            if (label == null) label = w.Exe == "applicationframehost.exe" ? Clean(w.Title, 12) : Clean(Path.GetFileNameWithoutExtension(w.Path), 12);
            if (label.Length == 0) continue;
            object[] g;
            if (!groups.TryGetValue(label, out g)) { g = new object[] { IntPtr.Zero, false, key }; groups[label] = g; }
            if (w.H == root) { g[0] = w.H; g[1] = true; } else if ((IntPtr)g[0] == IntPtr.Zero) g[0] = w.H;
        }
        foreach (var kv in groups)
        {
            if (slot >= Slots) break;
            emit(kv.Key, (IntPtr)kv.Value[0], (bool)kv.Value[1], (string)kv.Value[2]);
        }
        for (int s = slot + 1; s <= Slots; s++) bang.Append("[!SetVariable T" + s + " \"\" \"" + Cfg + "\\Dock\"]");

        string sg = sig.ToString();
        if (sg != lastSig || tick % 8 == 0)   // resend now and then so a refreshed skin fills in again
        {
            if (sg != lastSig) { try { File.WriteAllText(StateFile, state.ToString()); } catch { } }
            lastSig = sg;
            bang.Append("[!UpdateMeterGroup D \"" + Cfg + "\\Dock\"][!Redraw \"" + Cfg + "\\Dock\"]");
            Bang(bang.ToString());
        }

        // True full-screen app (video, game, F11): get the dock out of the way.
        bool full = false;
        if (root != IntPtr.Zero)
        {
            bool known = false; foreach (var w in wins) if (w.H == root) { known = true; break; }
            RECT r;
            if (known && GetWindowRect(root, out r))
            {
                var b = Screen.PrimaryScreen.Bounds;
                full = r.L == b.Left && r.T == b.Top && r.R == b.Right && r.B == b.Bottom;
            }
        }
        if (full != lastFull) { lastFull = full; if (!homeVisible) Bang(full ? "[!Hide \"" + Cfg + "\\Dock\"][!Hide \"" + Cfg + "\\Wave\"]" : "[!Show \"" + Cfg + "\\Dock\"][!Show \"" + Cfg + "\\Wave\"]"); }
        EnforceWorkArea(true);

        // Esc closes Home, but only while Home is on screen.
        if (homeVisible != escOn)
        {
            if (homeVisible) escOn = RegisterHotKey(host.Handle, 2, 0, 0x1B);
            else { UnregisterHotKey(host.Handle, 2); escOn = false; }
        }
    }

    class Host : Form
    {
        protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == BarMsg && m.WParam.ToInt32() == 1) BarSetPos();
            if (m.Msg == 0x0312)
            {
                int id = m.WParam.ToInt32();
                if (id == 1) ToggleHome();
                else if (id == 2) HideHome();
            }
            base.WndProc(ref m);
        }
    }

    // ---------------------------------------------------------------- volume + brightness
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IntPtr col);
        [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr p);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr p);
        [PreserveSig] int GetChannelCount(out int c);
        [PreserveSig] int SetMasterVolumeLevel(float db, ref Guid ctx);
        [PreserveSig] int SetMasterVolumeLevelScalar(float f, ref Guid ctx);
        [PreserveSig] int GetMasterVolumeLevel(out float db);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float f);
        [PreserveSig] int SetChannelVolumeLevel(uint n, float db, ref Guid ctx);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint n, float f, ref Guid ctx);
        [PreserveSig] int GetChannelVolumeLevel(uint n, out float db);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint n, out float f);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m);
    }

    static IAudioEndpointVolume Endpoint()
    {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCom());
        IMMDevice dev;
        if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return null;   // render, multimedia
        Guid iid = typeof(IAudioEndpointVolume).GUID; object o;
        if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return null;
        return (IAudioEndpointVolume)o;
    }

    static int GetVol(out bool mute)
    {
        mute = false;
        try { var e = Endpoint(); if (e == null) return -1; float f; e.GetMasterVolumeLevelScalar(out f); e.GetMute(out mute); return (int)Math.Round(f * 100); }
        catch { return -1; }
    }

    static void StepVol(int d)
    {
        try
        {
            var e = Endpoint(); if (e == null) return;
            float f; e.GetMasterVolumeLevelScalar(out f);
            int v = Math.Max(0, Math.Min(100, (int)Math.Round(f * 100) + d));
            Guid g = Guid.Empty;
            e.SetMasterVolumeLevelScalar(v / 100f, ref g);
            if (d > 0) e.SetMute(false, ref g);
        }
        catch { }
    }

    static void ToggleMute()
    {
        try { var e = Endpoint(); if (e == null) return; bool m; e.GetMute(out m); Guid g = Guid.Empty; e.SetMute(!m, ref g); }
        catch { }
    }

    // Built-in display only (WMI). Returns -1 when the display has no software brightness.
    static int GetBri()
    {
        try
        {
            using (var s = new ManagementObjectSearcher("root\\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness"))
                foreach (ManagementObject o in s.Get()) return Convert.ToInt32(o["CurrentBrightness"]);
        }
        catch { }
        return -1;
    }

    static void StepBri(int d)
    {
        try
        {
            int b = GetBri(); if (b < 0) return;
            int v = Math.Max(10, Math.Min(100, b + d));   // floor at 10 so the screen stays readable
            using (var s = new ManagementObjectSearcher("root\\WMI", "SELECT * FROM WmiMonitorBrightnessMethods"))
                foreach (ManagementObject o in s.Get()) { o.InvokeMethod("WmiSetBrightness", new object[] { (uint)1, (byte)v }); break; }
        }
        catch { }
    }

    const int BarW = 72;
    static string LevelBang(int vol, bool mute, int bri)
    {
        string vt = vol < 0 ? "--" : (mute ? "MUTE" : vol.ToString());
        int vw = (vol < 0 || mute) ? 1 : Math.Max(1, vol * BarW / 100);
        string bt = bri < 0 ? "--" : bri.ToString();
        int bw = bri < 0 ? 1 : Math.Max(1, bri * BarW / 100);
        string d = " \"" + Cfg + "\\Dock\"]";
        return "[!SetVariable Vol \"" + vt + "\"" + d + "[!SetVariable VolW " + vw + d
             + "[!SetVariable Bri \"" + bt + "\"" + d + "[!SetVariable BriW " + bw + d
             + "[!UpdateMeterGroup V" + d + "[!Redraw" + d;
    }

    static volatile int curVol = -1, curBri = -1;
    static volatile bool curMute = false;
    static int pVol = -2, pBri = -2; static bool pMute = false;

    static void LevelThread()
    {
        while (true)
        {
            bool m; int v = GetVol(out m);
            curVol = v; curMute = m; curBri = GetBri();
            Thread.Sleep(2500);
        }
    }

    static void PushLevels()
    {
        int v = curVol, b = curBri; bool m = curMute;
        if (v == pVol && b == pBri && m == pMute && tick % 20 != 0) return;
        pVol = v; pBri = b; pMute = m;
        Bang(LevelBang(v, m, b));
    }

    // ---------------------------------------------------------------- wave z-order
    // The wave addon draws on the dock's edge, so it must sit above the dock window. Both are topmost;
    // whenever the dock ends up above the wave, lift the wave (no move, no activate).
    static IntPtr waveWin = IntPtr.Zero, dockWin = IntPtr.Zero;

    static IntPtr FindSkin(string tail)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate (IntPtr h, IntPtr l)
        {
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            if (c.ToString() != "RainmeterMeterWindow") return true;
            var t = new StringBuilder(300); GetWindowText(h, t, 300);
            if (t.ToString().EndsWith(tail, StringComparison.OrdinalIgnoreCase)) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    static void RaiseWave()
    {
        if (V(Desk, "AddonWave", "0") != "1") return;
        if (waveWin == IntPtr.Zero || !IsWindow(waveWin)) waveWin = FindSkin("\\Wave\\Wave.ini");
        if (dockWin == IntPtr.Zero || !IsWindow(dockWin)) dockWin = FindSkin("\\Dock\\Dock.ini");
        if (waveWin == IntPtr.Zero || dockWin == IntPtr.Zero) return;
        int guard = 0;
        for (IntPtr h = GetWindow(waveWin, 3); h != IntPtr.Zero && guard < 400; h = GetWindow(h, 3), guard++)   // windows above the wave
            if (h == dockWin) { SetWindowPos(waveWin, (IntPtr)(-1), 0, 0, 0, 0, 0x0013); return; }             // TOPMOST, NOSIZE|NOMOVE|NOACTIVATE
    }

    // ---------------------------------------------------------------- actions
    static void Focus(IntPtr h)
    {
        if (IsIconic(h)) ShowWindow(h, 9);
        SwitchToThisWindow(h, true);
        SetForegroundWindow(h);
    }

    static void Launch(App a)
    {
        try { Process.Start(new ProcessStartInfo(a.File) { UseShellExecute = true }); } catch { }
    }

    static App Find(string key) { foreach (var a in Apps) if (a.Key == key) return a; return null; }

    static void Go(string key, bool allowMinimize, int st, IntPtr known)
    {
        if (key == "lock") { LockWorkStation(); return; }
        if (key == "power")
        {
            // Opens the normal Windows "Shut down Windows" dialog. Nothing happens until the user picks an option there.
            try { Type shT = Type.GetTypeFromProgID("Shell.Application"); object sh = Activator.CreateInstance(shT); shT.InvokeMember("ShutdownWindows", System.Reflection.BindingFlags.InvokeMethod, null, sh, null); } catch { }
            return;
        }
        var a = Find(key); if (a == null) return;
        IntPtr h = known != IntPtr.Zero && IsWindow(known) ? known : IntPtr.Zero;
        if (h == IntPtr.Zero)
        {
            bool hv; foreach (var w in Snapshot(out hv)) if (Match(a, w)) { h = w.H; break; }
        }
        if (h == IntPtr.Zero) { Launch(a); return; }
        if (allowMinimize && st == 2 && !IsIconic(h)) ShowWindow(h, 6); else Focus(h);
    }

    [STAThread]
    static void Main(string[] args)
    {
        SetProcessDPIAware();
        LoadConfig();
        if (args.Length >= 2 && args[0] == "act")
        {
            try
            {
                foreach (var line in File.ReadAllLines(StateFile))
                {
                    var p = line.Split('|');
                    if (p.Length < 4 || p[0] != args[1]) continue;
                    IntPtr h = (IntPtr)long.Parse(p[1]); int st = int.Parse(p[2]);
                    if (p[3].Length > 0) Go(p[3], true, st, h);
                    else if (h != IntPtr.Zero && IsWindow(h)) { if (st == 2 && !IsIconic(h)) ShowWindow(h, 6); else Focus(h); }
                    break;
                }
            }
            catch { }
            return;
        }
        if (args.Length >= 2 && args[0] == "go") { HideHome(); Go(args[1], false, 0, IntPtr.Zero); return; }
        if (args.Length >= 2 && (args[0] == "vol" || args[0] == "bri"))
        {
            if (args[0] == "vol") { if (args[1] == "up") StepVol(5); else if (args[1] == "down") StepVol(-5); else ToggleMute(); }
            else StepBri(args[1] == "up" ? 10 : -10);
            bool mm; int vv = GetVol(out mm);
            Bang(LevelBang(vv, mm, GetBri()));
            return;
        }
        if (args.Length >= 1 && args[0] == "alert") { Alert(args.Length > 1 ? args[1] : "ALERT", args.Length > 2 ? args[2] : ""); return; }
        if (args.Length >= 1 && args[0] == "home") { ToggleHome(); return; }
        if (args.Length >= 1 && args[0] == "close") { HideHome(); return; }
        if (args.Length >= 1 && args[0] == "search")
        {
            HideHome();
            Thread.Sleep(220);
            keybd_event(0x5B, 0, 0, UIntPtr.Zero); keybd_event(0x53, 0, 0, UIntPtr.Zero);       // Win+S
            keybd_event(0x53, 0, 2, UIntPtr.Zero); keybd_event(0x5B, 0, 2, UIntPtr.Zero);
            return;
        }

        bool created;
        using (var m = new Mutex(true, "deskforgeDockHelper", out created))
        {
            if (!created) return;
            host = new Host();
            IntPtr hh = host.Handle;
            bool ok = RegisterHotKey(hh, 1, 0x0008 | 0x4000, 0x5A);          // Win+Z
            if (!ok) RegisterHotKey(hh, 1, 0x0001 | 0x0002 | 0x4000, 0x5A);   // fallback Ctrl+Alt+Z
            SessionSwitchEventHandler onSwitch = delegate (object s, SessionSwitchEventArgs e) { if (e.Reason == SessionSwitchReason.SessionUnlock) host.BeginInvoke(new Action(Reveal)); };
            PowerModeChangedEventHandler onPower = delegate (object s, PowerModeChangedEventArgs e) { if (e.Mode == PowerModes.Resume) host.BeginInvoke(new Action(Reveal)); };
            SystemEvents.SessionSwitch += onSwitch;
            SystemEvents.PowerModeChanged += onPower;
            var t = new System.Windows.Forms.Timer { Interval = 700 };
            t.Tick += delegate { try { Poll(); } catch { } };
            t.Start();
            new Thread(LevelThread) { IsBackground = true }.Start();
            Application.Run();
            SystemEvents.SessionSwitch -= onSwitch;
            SystemEvents.PowerModeChanged -= onPower;
            UnregisterHotKey(hh, 1); UnregisterHotKey(hh, 2);
            EnforceWorkArea(false);
        }
    }
}
