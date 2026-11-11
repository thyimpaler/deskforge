// Live market feed for the deskforge wallpaper skins (deskforge\Tape, deskforge\Depth).
// Fetches Binance public data (no key): 15m candles every 10s, order book every 4s.
// Computes pixel geometry here and pushes it to Rainmeter as ONE bang string via WM_COPYDATA,
// so Rainmeter only redraws. Idle priority, single instance, exits when Rainmeter closes.
// Build: helpers\build.ps1
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

static class Market
{
    const string Symbol = "BTCUSDT";
    const int Candles = 46;
    // Tape skin box (physical px): see Tape.ini
    const double TW = 850, TH = 200, Pad = 10;
    // Depth skin: 10 asks + 10 bids, 22px rows, bars right-aligned at x=244, max bar 200px
    const int Levels = 10, Row = 22; const double BarRight = 244, BarMax = 200, Bin = 10;

    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    [StructLayout(LayoutKind.Sequential)]
    struct COPYDATASTRUCT { public IntPtr dwData; public int cbData; public IntPtr lpData; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string c, string t);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, ref COPYDATASTRUCT l);

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

    static string Get(string path)
    {
        foreach (var host in new[] { "https://api.binance.com", "https://data-api.binance.vision" })
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(host + path);
                req.Timeout = 6000; req.ReadWriteTimeout = 6000; req.UserAgent = "deskforge-desk";
                using (var r = req.GetResponse())
                using (var s = new System.IO.StreamReader(r.GetResponseStream())) return s.ReadToEnd();
            }
            catch { }
        }
        return null;
    }

    static string N(double v) { return Math.Round(v, 1).ToString("0.#", Inv); }
    static string Rect(double x, double y, double w, double h, string col)
    {
        return "Rectangle " + N(x) + "," + N(y) + "," + N(Math.Max(w, 1)) + "," + N(Math.Max(h, 1)) + " | Fill Color " + col + " | StrokeWidth 0";
    }

    static string TapeBangs()
    {
        string json = Get("/api/v3/klines?symbol=" + Symbol + "&interval=15m&limit=" + Candles);
        if (json == null) return null;
        var ms = Regex.Matches(json, "\\[\\d+,\"([\\d.]+)\",\"([\\d.]+)\",\"([\\d.]+)\",\"([\\d.]+)\"");
        if (ms.Count < 2) return null;
        int n = ms.Count;
        var o = new double[n]; var hi = new double[n]; var lo = new double[n]; var c = new double[n];
        double max = double.MinValue, min = double.MaxValue;
        for (int i = 0; i < n; i++)
        {
            o[i] = double.Parse(ms[i].Groups[1].Value, Inv); hi[i] = double.Parse(ms[i].Groups[2].Value, Inv);
            lo[i] = double.Parse(ms[i].Groups[3].Value, Inv); c[i] = double.Parse(ms[i].Groups[4].Value, Inv);
            if (hi[i] > max) max = hi[i]; if (lo[i] < min) min = lo[i];
        }
        double span = Math.Max(max - min, 1e-9);
        Func<double, double> Y = v => Pad + (max - v) / span * (TH - 2 * Pad);
        double step = TW / Candles, body = 8;
        var sb = new StringBuilder();
        for (int i = 0; i < Candles; i++)
        {
            string wick = "Rectangle 0,0,1,1 | Fill Color 0,0,0,0 | StrokeWidth 0", bod = wick;
            int k = i - (Candles - n);
            if (k >= 0)
            {
                bool last = k == n - 1, up = c[k] >= o[k];
                string col = last ? "212,137,42,255" : (up ? "120,120,120,150" : "164,22,26,170");
                double x = i * step + (step - body) / 2;
                wick = Rect(x + body / 2 - 0.5, Y(hi[k]), 1, Y(lo[k]) - Y(hi[k]), col);
                double top = Y(Math.Max(o[k], c[k])), bot = Y(Math.Min(o[k], c[k]));
                bod = Rect(x, top, body, Math.Max(bot - top, 2), col);
            }
            sb.Append("[!SetVariable W" + (i + 1) + " \"" + wick + "\" \"deskforge\\Tape\"]");
            sb.Append("[!SetVariable B" + (i + 1) + " \"" + bod + "\" \"deskforge\\Tape\"]");
        }
        double ly = Y(c[n - 1]);
        sb.Append("[!SetVariable PriceY \"" + N(ly) + "\" \"deskforge\\Tape\"]");
        sb.Append("[!SetVariable Last \"" + c[n - 1].ToString("#,0", Inv) + "\" \"deskforge\\Tape\"]");
        sb.Append("[!UpdateMeterGroup T \"deskforge\\Tape\"][!Redraw \"deskforge\\Tape\"]");
        return sb.ToString();
    }

    static string DepthBangs()
    {
        string json = Get("/api/v3/depth?symbol=" + Symbol + "&limit=500");
        if (json == null) return null;
        int ai = json.IndexOf("\"asks\"", StringComparison.Ordinal);
        if (ai < 0) return null;
        var pairRx = new Regex("\\[\"([\\d.]+)\",\"([\\d.]+)\"\\]");
        var bids = pairRx.Matches(json.Substring(0, ai)); var asks = pairRx.Matches(json.Substring(ai));
        if (bids.Count == 0 || asks.Count == 0) return null;

        double bestBid = double.Parse(bids[0].Groups[1].Value, Inv), bestAsk = double.Parse(asks[0].Groups[1].Value, Inv);
        double bidTop = Math.Floor(bestBid / Bin) * Bin, askBot = Math.Ceiling(bestAsk / Bin) * Bin;
        if (askBot <= bidTop) askBot = bidTop + Bin;
        var askQ = new double[Levels]; var bidQ = new double[Levels];
        foreach (Match m in asks)
        {
            double p = double.Parse(m.Groups[1].Value, Inv), q = double.Parse(m.Groups[2].Value, Inv);
            int b = (int)Math.Floor((p - askBot) / Bin) + 1; if (b < 0) b = 0; if (b < Levels) askQ[b] += q;
        }
        foreach (Match m in bids)
        {
            double p = double.Parse(m.Groups[1].Value, Inv), q = double.Parse(m.Groups[2].Value, Inv);
            int b = (int)Math.Floor((bidTop - p) / Bin); if (b < 0) b = 0; if (b < Levels) bidQ[b] += q;
        }
        double maxQ = 1e-9;
        for (int i = 0; i < Levels; i++) { maxQ = Math.Max(maxQ, Math.Max(askQ[i], bidQ[i])); }
        int wallRow = -1; double wallQ = 0;
        var sb = new StringBuilder();
        // rows 1..10 = asks (highest at top), 11..20 = bids (highest at top)
        for (int r = 0; r < Levels * 2; r++)
        {
            bool isAsk = r < Levels;
            int b = isAsk ? (Levels - 1 - r) : (r - Levels);
            double q = isAsk ? askQ[b] : bidQ[b];
            double price = isAsk ? askBot + b * Bin : bidTop - b * Bin;
            if (q > wallQ) { wallQ = q; wallRow = r; }
            double w = 4 + Math.Sqrt(q / maxQ) * BarMax;
            string col = isAsk ? "52,52,52,200" : "40,40,40,200";
            sb.Append("[!SetVariable D" + (r + 1) + " \"" + Rect(BarRight - w, r * Row + (r >= Levels ? 8 : 0), w, 12, col) + "\" \"deskforge\\Depth\"]");
            sb.Append("[!SetVariable P" + (r + 1) + " \"" + price.ToString("#,0", Inv) + "\" \"deskforge\\Depth\"]");
        }
        // the biggest resting order (the "wall") gets the one accent
        if (wallRow >= 0)
        {
            double q = wallRow < Levels ? askQ[Levels - 1 - wallRow] : bidQ[wallRow - Levels];
            double w = 4 + Math.Sqrt(q / maxQ) * BarMax;
            sb.Append("[!SetVariable D" + (wallRow + 1) + " \"" + Rect(BarRight - w, wallRow * Row + (wallRow >= Levels ? 8 : 0), w, 12, "212,137,42,150") + "\" \"deskforge\\Depth\"]");
        }
        sb.Append("[!UpdateMeterGroup D \"deskforge\\Depth\"][!Redraw \"deskforge\\Depth\"]");
        return sb.ToString();
    }

    static bool RainmeterAlive()
    {
        var r = Process.GetProcessesByName("Rainmeter"); bool a = r.Length > 0; foreach (var p in r) p.Dispose(); return a;
    }

    [STAThread]
    static void Main()
    {
        bool created;
        using (var m = new Mutex(true, "deskforgeMarketFeed", out created))
        {
            if (!created) return;
            try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.Idle; } catch { }
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            DateTime nextTape = DateTime.MinValue;
            while (RainmeterAlive())
            {
                try
                {
                    if (DateTime.UtcNow >= nextTape)
                    {
                        var t = TapeBangs(); if (t != null) Bang(t);
                        nextTape = DateTime.UtcNow.AddSeconds(10);
                    }
                    var d = DepthBangs(); if (d != null) Bang(d);
                }
                catch { }
                Thread.Sleep(4000);
            }
        }
    }
}
