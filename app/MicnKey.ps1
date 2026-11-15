# MicnKey Deck v1.3.1 - a floating mic + AI keypad for Windows
# https://github.com/  (MIT License)
# Runs on built-in Windows PowerShell 5.1. No install needed.
# Start it with Start-MicnKey.cmd. Keys are defined in config.json.
# NOTE: keep this file ASCII-only. Put non-English text in config.json.

$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $here 'config.json'
$cfgDefault = Join-Path $here 'config.default.json'
if (-not (Test-Path $cfgPath) -and (Test-Path $cfgDefault)) { Copy-Item $cfgDefault $cfgPath }
$logPath = Join-Path $here 'micnkey.log'

function Write-Log([string]$msg) {
    # Shared-mode append with a few retries, so a reader holding the file never blocks or loses a line.
    $line = ("{0}  {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $msg)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $fs = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write,
                    ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $fs.Write($bytes, 0, $bytes.Length); $fs.Close(); return
        } catch { Start-Sleep -Milliseconds 40 }
    }
}

trap {
    Write-Log ("FATAL: " + $_.Exception.Message + " @ line " + $_.InvocationInfo.ScriptLineNumber)
    break
}
Write-Log 'launching'


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName WindowsBase
# An error inside a click or timer handler must not close the pad: log it and carry on.
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch {}
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) try { Write-Log "error (pad kept running): $($e.Exception.Message)" } catch {} })
[System.AppDomain]::CurrentDomain.add_UnhandledException({ param($s, $e) try { Write-Log "fatal error: $($e.ExceptionObject)" } catch {} })

# ---- native helpers + a window that never steals focus --------------------
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;

// A rounded, glass-style key, drawn with anti-aliasing.
public class PadKey : Control {
    public string Label = "";
    public string Glyph = "";
    public Image Icon;
    public Font GlyphFont;
    public Color Base = Color.FromArgb(46, 46, 52);
    public Color Accent = Color.Empty;
    public Color ActiveColor = Color.FromArgb(0, 120, 212);
    public bool Active;
    public string Badge = "";
    public bool BadgeLit;
    public bool Pulse;
    bool hover, down;
    float phase;
    Timer pulseTimer;

    public PadKey() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        TabStop = false;
        Cursor = Cursors.Hand;
        pulseTimer = new Timer();
        pulseTimer.Interval = 40;
        pulseTimer.Tick += delegate { phase += 0.15f; Invalidate(); };
    }

    public void SetActive(bool on) { if (Active != on) { Active = on; Invalidate(); } }
    public void SetBadgeLit(bool on) { if (BadgeLit != on) { BadgeLit = on; Invalidate(); } }

    public void SetState(string label, Color accent, bool pulse) {
        Label = label; Accent = accent; Pulse = pulse;
        if (pulse) pulseTimer.Start(); else { pulseTimer.Stop(); phase = 0; }
        Invalidate();
        Update();
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }

    static int Clamp(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
    static Color Shift(Color c, int d) { return Color.FromArgb(c.A, Clamp(c.R + d), Clamp(c.G + d), Clamp(c.B + d)); }

    public static GraphicsPath Round(RectangleF r, float rad) {
        GraphicsPath p = new GraphicsPath();
        float d = rad * 2f;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.Clear(Parent != null ? Parent.BackColor : BackColor);

        float inset = down ? 3f : 1f;
        RectangleF r = new RectangleF(inset, inset, Width - 2 * inset - 1, Height - 2 * inset - 1);
        float rad = Math.Min(r.Width, r.Height) * 0.26f;

        Color c = !Accent.IsEmpty ? Accent : (Active ? ActiveColor : Base);
        if (Pulse) c = Shift(c, (int)(22 * Math.Sin(phase)));
        if (hover && !down) c = Shift(c, 16);
        if (down) c = Shift(c, -12);

        using (GraphicsPath path = Round(r, rad)) {
            using (LinearGradientBrush b = new LinearGradientBrush(r, Shift(c, 26), Shift(c, -10), 90f))
                g.FillPath(b, path);
            // glass sheen on the upper half
            RectangleF top = new RectangleF(r.X + 1, r.Y + 1, r.Width - 2, r.Height * 0.48f);
            using (GraphicsPath tp = Round(top, rad * 0.9f))
            using (LinearGradientBrush sb = new LinearGradientBrush(top, Color.FromArgb(46, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 90f))
                g.FillPath(sb, tp);
            using (Pen pen = new Pen(Color.FromArgb(Active ? 200 : 70, 255, 255, 255), Active ? 2f : 1f))
                g.DrawPath(pen, path);
        }

        StringFormat sf = new StringFormat();
        sf.Alignment = StringAlignment.Center;
        sf.LineAlignment = StringAlignment.Center;
        sf.Trimming = StringTrimming.EllipsisCharacter;
        sf.FormatFlags = StringFormatFlags.NoWrap;

        if (!string.IsNullOrEmpty(Badge)) {
            using (Font bf = new Font("Segoe UI Semibold", Math.Max(7f, Font.Size * 0.85f), FontStyle.Bold, GraphicsUnit.Pixel))
            using (Brush bb = new SolidBrush(BadgeLit ? Color.FromArgb(255, 120, 230, 140) : Color.FromArgb(120, 255, 255, 255)))
                g.DrawString(Badge, bf, bb, r.X + rad * 0.45f, r.Y + rad * 0.25f);
        }

        bool hasTop = Icon != null || (!string.IsNullOrEmpty(Glyph) && GlyphFont != null);
        if (hasTop) {
            float side = Math.Min(r.Height * 0.38f, r.Width * 0.5f);
            float cy = r.Y + r.Height * 0.40f;
            if (Icon != null) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(Icon, new RectangleF((Width - side) / 2f, cy - side / 2f, side, side));
            } else {
                using (Brush gb = new SolidBrush(Color.FromArgb(245, 255, 255, 255)))
                    g.DrawString(Glyph, GlyphFont, gb, new RectangleF(0, cy - side / 2f - 2, Width, side + 4), sf);
            }
            using (Brush lb = new SolidBrush(Color.FromArgb(220, 255, 255, 255)))
                g.DrawString(Label, Font, lb, new RectangleF(r.X + 4, r.Y + r.Height * 0.66f, r.Width - 8, r.Height * 0.26f), sf);
        } else {
            using (Brush lb = new SolidBrush(Color.FromArgb(240, 255, 255, 255)))
                g.DrawString(Label, Font, lb, new RectangleF(r.X + 4, r.Y, r.Width - 8, r.Height), sf);
        }
    }
}

public class PadForm : Form {
    public event Action<int> HotKey;
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            // WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST
            cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008;
            return cp;
        }
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0021) { m.Result = (IntPtr)3; return; }   // WM_MOUSEACTIVATE -> MA_NOACTIVATE
        if (m.Msg == 0x0312) {                                    // WM_HOTKEY
            Action<int> h = HotKey;
            if (h != null) h(m.WParam.ToInt32());
        }
        base.WndProc(ref m);
    }
}

public static class PadNative {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint procId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    public static void RoundCorners(IntPtr h) {
        int round = 2;              // DWMWCP_ROUND (Windows 11)
        DwmSetWindowAttribute(h, 33, ref round, 4);
        int noBorder = unchecked((int)0xFFFFFFFE);   // DWMWA_COLOR_NONE
        DwmSetWindowAttribute(h, 34, ref noBorder, 4);
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    public static string ClassOf(IntPtr h) {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }
    public static List<IntPtr> Children(IntPtr parent) {
        List<IntPtr> list = new List<IntPtr>();
        EnumChildWindows(parent, delegate(IntPtr h, IntPtr l) { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
    public static string Title(IntPtr h) {
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, 512);
        return sb.ToString();
    }
}
'@

# ---- single instance: a new launch replaces the running pad ----------------
$mutex = New-Object System.Threading.Mutex($false, 'MicnKey_SingleInstance')
if (-not $mutex.WaitOne(0)) {
    $old = [PadNative]::FindWindow($null, 'MicnKey_Main')
    if ($old -ne [IntPtr]::Zero) { [void][PadNative]::PostMessage($old, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }   # WM_CLOSE
    $got = $false
    try { $got = $mutex.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) {
        # Older pads have no window title to find: stop that pad process directly.
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'MicnKey\.ps1' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        try { $got = $mutex.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    }
    if (-not $got) { Write-Log 'another MicnKey is running and did not close'; exit }
    Write-Log 'replaced the running pad'
}

[void][PadNative]::SetProcessDPIAware()
# Warm up UI Automation now. Its first use can switch the process to DPI-aware,
# which would shrink and move the pad if it happened after the window exists.
try {
    $warm = [System.Windows.Automation.AutomationElement]::RootElement
    $null = $warm.Current.BoundingRectangle
    $null = $warm.FindFirst([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
} catch {}

# ---- Core Audio: which processes have the microphone open right now -------
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorCo {}

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 {
    int GetAudioSessionControl(IntPtr a, int b, out IntPtr c);
    int GetSimpleAudioVolume(IntPtr a, int b, out IntPtr c);
    int GetSessionEnumerator(out IAudioSessionEnumerator e);
}

[ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator {
    int GetCount(out int count);
    int GetSession(int index, out IAudioSessionControl2 session);
}

[ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 {
    int GetState(out int state);
    int GetDisplayName(out IntPtr s);
    int SetDisplayName(IntPtr a, IntPtr b);
    int GetIconPath(out IntPtr s);
    int SetIconPath(IntPtr a, IntPtr b);
    int GetGroupingParam(out Guid g);
    int SetGroupingParam(IntPtr a, IntPtr b);
    int RegisterAudioSessionNotification(IntPtr a);
    int UnregisterAudioSessionNotification(IntPtr a);
    int GetSessionIdentifier(out IntPtr s);
    int GetSessionInstanceIdentifier(out IntPtr s);
    int GetProcessId(out uint pid);
}

public static class MicSessions {
    // Process IDs with an ACTIVE capture (microphone) stream on the default input devices.
    public static uint[] ActivePids() {
        List<uint> pids = new List<uint>();
        IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCo());
        foreach (int role in new int[] { 0, 2 }) {             // eConsole, eCommunications
            IMMDevice dev;
            if (en.GetDefaultAudioEndpoint(1, role, out dev) != 0 || dev == null) continue;  // 1 = eCapture
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object o;
            if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0 || o == null) continue;
            IAudioSessionEnumerator se;
            if (((IAudioSessionManager2)o).GetSessionEnumerator(out se) != 0 || se == null) continue;
            int n;
            se.GetCount(out n);
            for (int i = 0; i < n; i++) {
                IAudioSessionControl2 c;
                if (se.GetSession(i, out c) != 0 || c == null) continue;
                int state; uint pid;
                c.GetState(out state);
                c.GetProcessId(out pid);
                if (state == 1 && !pids.Contains(pid)) pids.Add(pid);   // 1 = AudioSessionStateActive
                Marshal.ReleaseComObject(c);
            }
            Marshal.ReleaseComObject(se);
            Marshal.ReleaseComObject(o);
            Marshal.ReleaseComObject(dev);
        }
        Marshal.ReleaseComObject(en);
        return pids.ToArray();
    }
}
'@

# ---- config ---------------------------------------------------------------
try {
    $cfg = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Log "config.json error: $($_.Exception.Message)"
    [void][System.Windows.Forms.MessageBox]::Show("config.json has an error, MicnKey Deck could not start:`n`n$($_.Exception.Message)", 'MicnKey Deck')
    exit
}
function Get-Cfg($name, $default) { if ($null -ne $cfg.$name) { $cfg.$name } else { $default } }
$browserRx = 'chrome|msedge|firefox|brave|opera'

# ---- shortcuts (first run) -----------------------------------------------
function Set-PadShortcut([string]$lnkPath) {
    if (Test-Path $lnkPath) { return }
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $here 'MicnKey.ps1')`""
    $sc.WorkingDirectory = $here
    $sc.WindowStyle      = 7
    $sc.Description      = 'MicnKey Deck - mic and AI keypad'
    $ico = Join-Path $here 'MicnKey.ico'
    if (Test-Path $ico) { $sc.IconLocation = $ico }
    $sc.Save()
    Write-Log "shortcut created: $lnkPath"
}
try {
    Set-PadShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MicnKey Deck.lnk')
    Set-PadShortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'MicnKey Deck.lnk')
    $startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'MicnKey Deck.lnk'
    if ($cfg.autostart) { Set-PadShortcut $startupLnk }
    elseif (Test-Path $startupLnk) { Remove-Item $startupLnk; Write-Log 'autostart shortcut removed' }
} catch { Write-Log "shortcut error: $($_.Exception.Message)" }

# ---- helpers --------------------------------------------------------------
function Get-ForegroundInfo {
    $h = [PadNative]::GetForegroundWindow()
    [uint32]$procId = 0
    [void][PadNative]::GetWindowThreadProcessId($h, [ref]$procId)
    $name = ''
    try { $name = (Get-Process -Id $procId).ProcessName } catch {}
    New-Object PSObject -Property @{ Handle = $h; Title = [PadNative]::Title($h); Process = $name }
}

function Wait-ModifiersUp {
    # When a physical hotkey fired us, Ctrl/Alt/Shift/Win may still be held down.
    for ($i = 0; $i -lt 40; $i++) {
        $down = $false
        foreach ($vk in 0x10, 0x11, 0x12, 0x5B, 0x5C) {
            if (([PadNative]::GetAsyncKeyState($vk) -band 0x8000) -ne 0) { $down = $true }
        }
        if (-not $down) { return }
        Start-Sleep -Milliseconds 25
    }
}

function Send-WinH {
    Wait-ModifiersUp
    [PadNative]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero)   # Win down
    [PadNative]::keybd_event(0x48, 0, 0, [UIntPtr]::Zero)   # H down
    [PadNative]::keybd_event(0x48, 0, 2, [UIntPtr]::Zero)   # H up
    [PadNative]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)   # Win up
}

$script:wokenUp = @{}
function Get-WebChildren($hwnd) {
    # Chromium / WebView2 content lives in child windows with these class names.
    @([PadNative]::Children($hwnd) | Where-Object { [PadNative]::ClassOf($_) -match 'Chrome_RenderWidgetHostHWND|Chrome_WidgetWin' })
}
function Enable-WebAccessibility($hwnd) {
    # Chromium only builds its accessibility tree when asked. WM_GETOBJECT (0x3D) with
    # lParam 1 on the render window is the standard wake-up call.
    $kids = Get-WebChildren $hwnd
    $fresh = $false
    foreach ($k in $kids) {
        if (-not $script:wokenUp.ContainsKey("$k")) { $script:wokenUp["$k"] = $true; $fresh = $true }
        [void][PadNative]::SendMessage($k, 0x003D, [IntPtr]::Zero, [IntPtr]1)
    }
    if ($fresh) { Start-Sleep -Milliseconds 700 }
}
function Find-Buttons($hwnd) {
    $AE   = [System.Windows.Automation.AutomationElement]
    $cond = New-Object System.Windows.Automation.PropertyCondition(
                $AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    Enable-WebAccessibility $hwnd
    $all = @($AE::FromHandle($hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond))
    if ($all.Count -le 4) {
        foreach ($k in (Get-WebChildren $hwnd)) {
            try { $all += @($AE::FromHandle($k).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) } catch {}
        }
    }
    $all
}

# Fast lookup: ask UI Automation for a button with one of these exact names. Much
# faster than listing every button and reading each name across processes.
$script:startNames = @('Dictate', 'Start dictation', 'Dictation', 'Use microphone')
# Never press these: they open a live voice conversation, not dictation into the chat box.
$script:notDictation = 'voice mode|voice chat|voice conversation|start voice|talk to'
$script:stopNames  = @('Stop dictation', 'Finish dictation', 'Done dictation', 'End dictation', 'Submit dictation')
function Find-ButtonByName($hwnd, [string[]]$names) {
    $AE = [System.Windows.Automation.AutomationElement]
    try {
        Enable-WebAccessibility $hwnd
        $nameConds = @($names | ForEach-Object { New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $_) })
        $byName = if ($nameConds.Count -gt 1) { New-Object System.Windows.Automation.OrCondition(,[System.Windows.Automation.Condition[]]$nameConds) } else { $nameConds[0] }
        $isBtn  = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
        $cond   = New-Object System.Windows.Automation.AndCondition($isBtn, $byName)
        foreach ($el in @($AE::FromHandle($hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond))) {
            try { if ($el.Current.IsEnabled -and -not $el.Current.IsOffscreen -and "$($el.Current.Name)" -notmatch $script:notDictation) { return $el } } catch {}
        }
    } catch { Write-Log "fast find failed: $($_.Exception.Message)" }
    return $null
}

function Invoke-Element($el) {
    $p = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) {
        $p.Invoke(); return 'invoke'
    }
    # No Invoke support: click its center with the mouse, then put the cursor back.
    $r   = $el.Current.BoundingRectangle
    $old = [System.Windows.Forms.Cursor]::Position
    [void][PadNative]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    [PadNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)   # left down
    [PadNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)   # left up
    Start-Sleep -Milliseconds 60
    [void][PadNative]::SetCursorPos($old.X, $old.Y)
    return 'mouse'
}

# ---- chat box (composer) helpers --------------------------------------------
function Get-AiRx { if ($script:micKey -and $script:micKey.apps) { "$($script:micKey.apps)" } else { 'claude|chatgpt|gemini' } }
function Get-AppName([string]$text) {
    if ($text -match 'claude')  { return 'Claude' }
    if ($text -match 'chatgpt') { return 'ChatGPT' }
    if ($text -match 'gemini')  { return 'Gemini' }
    return 'app'
}

function Find-Composer($hwnd) {
    # The chat box is the lowest visible, focusable text field in the window.
    $AE   = [System.Windows.Automation.AutomationElement]
    $cond = New-Object System.Windows.Automation.OrCondition(
                (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)),
                (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
    Enable-WebAccessibility $hwnd
    $best = $null; $bestY = -1
    try {
        foreach ($e in @($AE::FromHandle($hwnd).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond))) {
            try {
                if (-not $e.Current.IsEnabled -or $e.Current.IsOffscreen) { continue }
                $r = $e.Current.BoundingRectangle
                if ($r.IsEmpty -or $r.Width -lt 120 -or $r.Height -gt 400) { continue }
                if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Document -and -not $e.Current.IsKeyboardFocusable) { continue }
                if ($r.Bottom -gt $bestY) { $best = $e; $bestY = $r.Bottom }
            } catch {}
        }
    } catch {}
    $best
}

function Get-ComposerText($el) {
    if (-not $el) { return $null }
    try {
        $p = $null
        if ($el.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$p)) { return $p.DocumentRange.GetText(-1) }
        if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$p)) { return $p.Current.Value }
    } catch {}
    return $null
}

function Focus-Composer($hwnd) {
    $c = Find-Composer $hwnd
    if (-not $c) { return $false }
    try {
        $c.SetFocus()
        Start-Sleep -Milliseconds 60
        [System.Windows.Forms.SendKeys]::SendWait('^{END}')     # caret to the end of the draft
        return $true
    } catch { Write-Log "focus composer failed: $($_.Exception.Message)"; return $false }
}

function Test-FocusIsText {
    try {
        $f = [System.Windows.Automation.AutomationElement]::FocusedElement
        return ($f -and $f.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit)
    } catch { return $false }
}

function Send-PadKeys($key) {
    Wait-ModifiersUp
    $fg = Get-ForegroundInfo
    $isAi = ("$($fg.Process) $($fg.Title)" -match (Get-AiRx))
    $isEnter = ("$($key.keys)" -match '\{ENTER\}')
    if ($isAi -and $isEnter -and "$($key.keys)" -notmatch '^\+') {
        # Send while dictating = stop the mic, wait for the text, then send it.
        if ($script:micState -in @('connecting','live')) {
            $script:sendAfterDraft = $true
            if (Stop-Dictation $fg) { return 'stopping - will send' }
            $script:sendAfterDraft = $false
            return 'could not stop the mic'
        }
        if ($script:micState -eq 'transcribing') {
            if ($script:sendAfterDraft) {
                # second press: stop waiting and send whatever is in the box
                Write-Log 'send: pressed again while transcribing - sending now'
                Finish-Draft $true
                return 'sent'
            }
            $script:sendAfterDraft = $true
            return 'will send when the text is ready'
        }
        if (-not (Test-FocusIsText)) {
            if (-not (Focus-Composer $fg.Handle)) {
                Write-Log "keys: no chat box found in '$($fg.Title)' - sending anyway"
            }
            Write-Log "keys: focused the chat box in $(Get-AppName "$($fg.Process) $($fg.Title)")"
        }
    }
    [System.Windows.Forms.SendKeys]::SendWait($key.keys)
    Write-Log "keys: $($key.keys) -> $($fg.Process)"
    return $key.label
}

function Stop-Dictation($fg) {
    $quick = Find-ButtonByName $fg.Handle $script:stopNames
    if ($quick) {
        $name = "$($quick.Current.Name)"
        $how = Invoke-Element $quick
        Write-Log "send: pressed '$name' first ($how)"
        Start-MicWatch $fg.Handle $name
        return $true
    }
    try {
        foreach ($b in (Find-Buttons $fg.Handle)) {
            try {
                $name = "$($b.Current.Name)"
                $name = $name -replace '\s*\([^)]*\)\s*$', ''
                if ($b.Current.IsEnabled -and $name -match '^(stop|finish|end|done) dictation') {
                    $how = Invoke-Element $b
                    Write-Log "send: pressed '$name' first ($how)"
                    Start-MicWatch $fg.Handle $name
                    return $true
                }
            } catch {}
        }
    } catch { Write-Log "send: stop failed: $($_.Exception.Message)" }
    Write-Log 'send: no stop button found'
    return $false
}

# ---- language-independent mic button memory ---------------------------------
# Each app's mic and stop buttons are remembered by things that do not change with the
# app's language: their internal id, their style class, and where they sit relative to
# the chat box. Learned automatically whenever the English name matches, or taught by
# right-clicking the MIC key.
$learnPath = Join-Path $here 'mic-learned.json'
$script:learned = @{}
try {
    if (Test-Path $learnPath) {
        $raw = Get-Content $learnPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $script:learned[$p.Name] = $p.Value }
    }
} catch { Write-Log "mic memory unreadable: $($_.Exception.Message)" }

function Save-Learned {
    try {
        $o = [ordered]@{}
        foreach ($k in $script:learned.Keys) { $o[$k] = $script:learned[$k] }
        [System.IO.File]::WriteAllText($learnPath, ($o | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    } catch { Write-Log "mic memory not saved: $($_.Exception.Message)" }
}

function Get-ButtonSig($btn, $hwnd) {
    $r = $btn.Current.BoundingRectangle
    $sig = [ordered]@{ name = "$($btn.Current.Name)"; id = "$($btn.Current.AutomationId)"; cls = "$($btn.Current.ClassName)"; dx = $null; dy = $null }
    $comp = Find-Composer $hwnd
    if ($comp -and -not $r.IsEmpty) {
        $cr = $comp.Current.BoundingRectangle
        $sig.dx = [int]($cr.Right - ($r.X + $r.Width / 2))
        $sig.dy = [int]($cr.Bottom - ($r.Y + $r.Height / 2))
    }
    [pscustomobject]$sig
}

function Remember-Button([string]$app, [string]$phase, $btn, $hwnd) {
    try {
        $sig = Get-ButtonSig $btn $hwnd
        if (-not $script:learned.ContainsKey($app)) { $script:learned[$app] = [pscustomobject]@{} }
        Add-Member -InputObject $script:learned[$app] -NotePropertyName $phase -NotePropertyValue $sig -Force
        Save-Learned
        Write-Log "mic: remembered $app $phase button (id='$($sig.id)' class='$($sig.cls)' offset=$($sig.dx),$($sig.dy))"
    } catch { Write-Log "mic: could not remember button: $($_.Exception.Message)" }
}

function Get-ButtonAt([int]$x, [int]$y) {
    try {
        $AE = [System.Windows.Automation.AutomationElement]
        $el = $AE::FromPoint((New-Object System.Windows.Point($x, $y)))
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        for ($i = 0; $el -and $i -lt 6; $i++) {
            if ($el.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { return $el }
            $el = $walker.GetParent($el)
        }
    } catch {}
    return $null
}

function Find-BySig($buttons, $sig, $hwnd) {
    if (-not $sig) { return $null }
    # 1. internal id - the most reliable, the same in every language
    if ($sig.id) {
        foreach ($b in $buttons) { try { if ($b.Current.IsEnabled -and "$($b.Current.AutomationId)" -eq $sig.id) { return @($b, 'id') } } catch {} }
    }
    # 2. position next to the chat box (+ style class when there is one)
    if ($null -ne $sig.dx) {
        $comp = Find-Composer $hwnd
        if ($comp) {
            $cr = $comp.Current.BoundingRectangle
            $px = [int]($cr.Right - $sig.dx); $py = [int]($cr.Bottom - $sig.dy)
            $hit = Get-ButtonAt $px $py
            if ($hit -and $hit.Current.IsEnabled -and (-not $sig.cls -or "$($hit.Current.ClassName)" -eq $sig.cls)) { return @($hit, 'position') }
            # nearest button with the same style class within 40 px
            if ($sig.cls) {
                $best = $null; $bestD = 40
                foreach ($b in $buttons) {
                    try {
                        if ("$($b.Current.ClassName)" -ne $sig.cls -or -not $b.Current.IsEnabled) { continue }
                        $r = $b.Current.BoundingRectangle
                        $d = [math]::Sqrt([math]::Pow(($r.X + $r.Width / 2) - $px, 2) + [math]::Pow(($r.Y + $r.Height / 2) - $py, 2))
                        if ($d -lt $bestD) { $best = $b; $bestD = $d }
                    } catch {}
                }
                if ($best) { return @($best, 'class+position') }
            }
        }
    }
    return $null
}

$script:lastAiHwnd = [IntPtr]::Zero

function Invoke-Mic($key) {
    $fg = Get-ForegroundInfo
    $isAiApp = ("$($fg.Process) $($fg.Title)" -match $key.apps)
    if (-not $isAiApp -and $script:lastAiHwnd -ne [IntPtr]::Zero -and [PadNative]::IsWindow($script:lastAiHwnd)) {
        # Not in an AI app: jump back to the AI app you used last and use its mic.
        Show-Window $script:lastAiHwnd
        Start-Sleep -Milliseconds 350
        $fg = Get-ForegroundInfo
        $isAiApp = ("$($fg.Process) $($fg.Title)" -match $key.apps)
    }
    if (-not $isAiApp) {
        if ("$($key.fallback)" -eq 'winh') { Send-WinH; return 'Windows mic (Win+H)' }
        return 'open Claude / ChatGPT / Gemini first'
    }
    $app = Get-AppName "$($fg.Process) $($fg.Title)"
    if ($script:micState -eq 'transcribing') {
        # MIC while the text is still coming in: stop waiting, leave the draft to edit
        $script:sendAfterDraft = $false
        Finish-Draft $true
        return 'draft ready'
    }
    $phase = if ($script:micState -in @('connecting','live','transcribing')) { 'stop' } else { 'start' }
    $t0 = Get-Date
    if ($phase -eq 'start' -and $script:micBtn) {
        # instant feedback while we look for the app's button
        $script:micBtn.SetState('Starting...', [System.Drawing.Color]::FromArgb(214, 140, 0), $false)
        $script:micBtn.Refresh()
    }

    # 0. fast path: the same button we pressed last time in this window
    $ck = "$($fg.Handle)|$phase"
    $cached = $script:btnCache[$ck]
    if ($cached) {
        try {
            $n = ("$($cached.Current.Name)" -replace '\s*\([^)]*\)\s*$', '')
            $stopName = ($n -match '^(stop|finish|end|done|starting) dictation')
            if ($cached.Current.IsEnabled -and -not $cached.Current.IsOffscreen -and ($stopName -eq ($phase -eq 'stop')) -and $n -notmatch $script:notDictation) {
                $how = Invoke-Element $cached
                Start-MicWatch $fg.Handle $n
                Write-Log ("mic: '{0}' in {1} via {2} (cached, {3:N0} ms)" -f $n, $app, $how, ((Get-Date) - $t0).TotalMilliseconds)
                return "$app mic"
            }
        } catch {}
        $script:btnCache.Remove($ck)
    }
    # 0b. fast path: exact English button names
    $quick = Find-ButtonByName $fg.Handle $(if ($phase -eq 'start') { $script:startNames } else { $script:stopNames })
    if ($quick) {
        $n = "$($quick.Current.Name)"
        $script:btnCache[$ck] = $quick
        $how = Invoke-Element $quick
        Start-MicWatch $fg.Handle $n
        Write-Log ("mic: '{0}' in {1} via {2} (by name, {3:N0} ms)" -f $n, $app, $how, ((Get-Date) - $t0).TotalMilliseconds)
        return "$app mic"
    }
    try {
        $buttons = Find-Buttons $fg.Handle
        if ($buttons.Count -le 4) { Start-Sleep -Milliseconds 900; $buttons = Find-Buttons $fg.Handle }

        # 1. English names (also teaches the pad this app's buttons)
        $passes = if ($phase -eq 'start') { @($true, $false) } else { @($false) }   # start: prefer a real start button
        foreach ($skipStop in $passes) {
        foreach ($pattern in $key.patterns) {
            foreach ($b in $buttons) {
                $name = ''
                try { if (-not $b.Current.IsEnabled) { continue }; $name = ("$($b.Current.Name)" -replace '\s*\([^)]*\)\s*$', '') } catch { continue }
                if ($name -and $name -match $pattern -and $name -notmatch $script:notDictation) {
                    $isStop = ($name -match '^(stop|finish|end|done|starting) dictation')
                    if ($skipStop -and $isStop) { continue }
                    if ($name -notmatch '^starting') { Remember-Button $app $(if ($isStop) { 'stop' } else { 'start' }) $b $fg.Handle }
                    if ($name -notmatch '^starting') { $script:btnCache["$($fg.Handle)|$(if ($isStop) { 'stop' } else { 'start' })"] = $b }
                    $how = Invoke-Element $b
                    Start-MicWatch $fg.Handle $name
                    Write-Log ("mic: '{0}' in {1} via {2} ({3:N0} ms)" -f $name, $app, $how, ((Get-Date) - $t0).TotalMilliseconds)
                    return "$app mic"
                }
            }
        }
        }
        # 2. remembered button (any language)
        $mem = $script:learned[$app]
        if ($mem) {
            $found = Find-BySig $buttons $mem.$phase $fg.Handle
            if ($found) {
                $how = Invoke-Element $found[0]
                $label = if ($phase -eq 'stop') { 'finish dictation' } else { 'dictate' }
                Start-MicWatch $fg.Handle $label
                Write-Log "mic: $phase button in $app found by $($found[1]) ('$($found[0].Current.Name)') via $how"
                return "$app mic"
            }
        }
        $seen = @(); foreach ($b in $buttons) { try { if ($b.Current.Name) { $seen += $b.Current.Name } } catch {} }
        Write-Log "mic: no $phase button in $app ($($buttons.Count) buttons). Names: $(($seen | Select-Object -First 80) -join ' | ')"
    } catch {
        Write-Log "mic: UI Automation error: $($_.Exception.Message)"
    }
    return 'right-click MIC to teach me the mic button'
}

# ---- teach mode: right-click the MIC key -----------------------------------
$script:teachStep = 0
$script:teachTimer = New-Object System.Windows.Forms.Timer
$script:teachTimer.Interval = 1000
$script:teachTimer.Add_Tick({
    $script:teachLeft--
    if ($script:teachLeft -gt 0) {
        $what = if ($script:teachStep -eq 1) { 'MIC' } else { 'STOP / finish' }
        $script:title.Text = "  hover over the app's $what button... $($script:teachLeft)"
        return
    }
    $script:teachTimer.Stop()
    $pt = [System.Windows.Forms.Cursor]::Position
    $btn = Get-ButtonAt $pt.X $pt.Y
    $fg = Get-ForegroundInfo
    $app = Get-AppName "$($fg.Process) $($fg.Title)"
    if (-not $btn -or $app -eq 'app') {
        $script:title.Text = '  no button under the mouse - try again'
        Write-Log "teach: nothing usable under the mouse ($($fg.Process))"
        $script:teachStep = 0
        return
    }
    $phase = if ($script:teachStep -eq 1) { 'start' } else { 'stop' }
    Remember-Button $app $phase $btn $fg.Handle
    if ($script:teachStep -eq 1) {
        $script:teachStep = 2
        $script:teachLeft = 7
        $script:title.Text = "  got it. Start dictation in $app, then hover over STOP... 7"
        $script:teachTimer.Start()
    } else {
        $script:teachStep = 0
        $script:title.Text = "  learned $app mic + stop"
    }
})
function Start-Teach {
    $script:teachStep = 1
    $script:teachLeft = 5
    $script:title.Text = "  hover over the app's MIC button... 5"
    $script:teachTimer.Start()
    Write-Log 'teach: started'
}

function Open-App($key) {
    $win = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and ($_.ProcessName -notmatch $browserRx -or "$($key.match)" -match $browserRx) -and
        ($_.ProcessName -match $key.match -or $_.MainWindowTitle -match $key.match)
    } | Select-Object -First 1
    if ($win) {
        $h = $win.MainWindowHandle
        if ([PadNative]::IsIconic($h)) { [void][PadNative]::ShowWindow($h, 9) }   # SW_RESTORE
        [void][PadNative]::SetForegroundWindow($h)
        Write-Log "open: activated $($win.ProcessName)"
        return "-> $($key.label)"
    }
    $target = "$($key.launch)"
    if ($target -and $target -notmatch '[:\\/.]') {
        # A plain app name, e.g. "Notion": find it among the installed apps (Start menu).
        try {
            $app = @((New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items()) |
                Where-Object { $_.Name -like "*$target*" } | Select-Object -First 1
            if ($app) {
                Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($app.Path)"
                Write-Log "open: launched installed app '$($app.Name)'"
                return "start $($key.label)"
            }
        } catch { Write-Log "open: app lookup failed: $($_.Exception.Message)" }
        if ($key.web) {
            Start-Process "$($key.web)"
            Write-Log "open: '$target' not installed - opened $($key.web)"
            return "web: $($key.label)"
        }
        Write-Log "open: no installed app named '$target'"
        return "app not found: $target"
    }
    if ($key.launchArgs) { Start-Process $key.launch -ArgumentList $key.launchArgs }
    else                 { Start-Process $key.launch }
    Write-Log "open: launched $($key.launch) $($key.launchArgs)"
    return "start $($key.label)"
}

function Get-DownloadsFolder {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($v) { return [Environment]::ExpandEnvironmentVariables($v) }
    } catch {}
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Resolve-PadPath([string]$p) {
    # Special names that follow the real folder even when Windows moved it (e.g. into OneDrive)
    $p = $p -replace '(?i)%DOCUMENTS%', [Environment]::GetFolderPath('MyDocuments').Replace('$', '$$')
    $p = $p -replace '(?i)%DESKTOP%',   [Environment]::GetFolderPath('Desktop').Replace('$', '$$')
    $p = $p -replace '(?i)%PICTURES%',  [Environment]::GetFolderPath('MyPictures').Replace('$', '$$')
    $p = $p -replace '(?i)%DOWNLOADS%', (Get-DownloadsFolder).Replace('$', '$$')
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($p -match '^~') { $p = $env:USERPROFILE + $p.Substring(1) }
    $p
}

function Find-FolderWindow([string]$path) {
    # Returns the window handle of an open File Explorer window already showing this folder.
    $want = $path.TrimEnd('\').ToLowerInvariant()
    try {
        foreach ($w in @((New-Object -ComObject Shell.Application).Windows())) {
            try {
                if ("$($w.FullName)" -notmatch 'explorer\.exe$') { continue }
                $p = "$($w.Document.Folder.Self.Path)".TrimEnd('\').ToLowerInvariant()
                if ($p -eq $want) { return [IntPtr][long]$w.HWND }
            } catch {}
        }
    } catch {}
    return [IntPtr]::Zero
}

function Show-Window([IntPtr]$h) {
    if ([PadNative]::IsIconic($h)) { [void][PadNative]::ShowWindow($h, 9) }   # SW_RESTORE
    [void][PadNative]::SetForegroundWindow($h)
}

function Open-Target($key) {
    $target = Resolve-PadPath "$($key.path)"
    if (-not $target) { return 'no path set' }
    if (Test-Path -LiteralPath $target -PathType Container) {
        $full = (Resolve-Path -LiteralPath $target).ProviderPath
        $h = Find-FolderWindow $full
        if ($h -ne [IntPtr]::Zero) {
            Show-Window $h
            Write-Log "folder: switched to open window for $full"
            return "-> $($key.label)"
        }
        Start-Process explorer.exe -ArgumentList "`"$full`""
    } elseif ($key.args) {
        Start-Process $target -ArgumentList $key.args
    } else {
        Start-Process $target          # file, program, or URL
    }
    Write-Log "run: $target"
    return "-> $($key.label)"
}

function Restart-Pad {
    $ps1 = Join-Path $here 'MicnKey.ps1'
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
}

function Invoke-KeyAction($key) {
    try {
        switch ($key.action) {
            'mic'  { $msg = Invoke-Mic $key; if ($script:micState -eq 'idle') { Set-MicState 'idle' } }
            'open' { $msg = Open-App $key }
            'folder' { $msg = Open-Target $key }
            'desktop' { (New-Object -ComObject Shell.Application).ToggleDesktop(); Write-Log 'desktop: toggled'; $msg = $key.label }
            'run'    { $msg = Open-Target $key }
            'keys' { $msg = Send-PadKeys $key }
            'text' {
                Wait-ModifiersUp
                [System.Windows.Forms.Clipboard]::SetText($key.text)
                [System.Windows.Forms.SendKeys]::SendWait('^v')
                $msg = $key.label
            }
            default { $msg = "unknown action: $($key.action)" }
        }
    } catch {
        $msg = 'error - see voicepad.log'
        Write-Log "ERROR in '$($key.label)': $($_.Exception.Message)"
    }
    $script:title.Text = "  $msg"
}

# ---- mic state: idle -> connecting -> live -> idle ------------------------
$script:micBtn   = $null
$script:micKey   = $null
$script:btnCache = @{}
$script:micHwnd  = [IntPtr]::Zero
$script:micState = 'idle'
$script:sendAfterDraft = $false
$script:micStart = Get-Date

function Set-MicState([string]$state) {
    $script:micState = $state
    $b = $script:micBtn
    if (-not $b) { return }
    switch ($state) {
        'connecting'   { $b.SetState('Connecting...',   [System.Drawing.Color]::FromArgb(214, 140, 0), $false) }
        'live'         { $b.SetState('SPEAK NOW',       [System.Drawing.Color]::FromArgb(222, 50, 62), $true) }
        'transcribing' { $b.SetState('Transcribing...', [System.Drawing.Color]::FromArgb(58, 96, 170), $true) }
        'ready'        { $b.SetState('Draft ready - edit or Send', [System.Drawing.Color]::FromArgb(36, 140, 82), $false) }
        default        { $b.SetState("$($script:micKey.label)", [System.Drawing.Color]::Empty, $false) }
    }
}

function Test-MicInUse([string]$rx) {
    # $true when a process of the target app has the microphone open, $false when not,
    # $null when Windows audio can't be queried (then the pad falls back to the app's buttons).
    try { $pids = [MicSessions]::ActivePids() } catch { Write-Log "mic audio query failed: $($_.Exception.Message)"; return $null }
    foreach ($p in $pids) {
        try { if ((Get-Process -Id $p -ErrorAction Stop).ProcessName -match $rx) { return $true } } catch {}
    }
    return $false
}

function Write-MicSessions {
    try {
        $names = @([MicSessions]::ActivePids() | ForEach-Object { try { "$((Get-Process -Id $_).ProcessName)#$_" } catch { "pid$_" } })
        Write-Log "mic: apps holding the microphone: $($names -join ', ')"
    } catch { Write-Log "mic audio query failed: $($_.Exception.Message)" }
}

function Test-DictationUi($hwnd) {
    foreach ($b in (Find-Buttons $hwnd)) {
        try { if ($b.Current.IsEnabled -and ("$($b.Current.Name)" -replace '\s*\([^)]*\)\s*$', '') -match '^(stop|finish|submit|end|done) dictation') { return $true } } catch {}
    }
    return $false
}

$script:micTimer = New-Object System.Windows.Forms.Timer
$script:micTimer.Interval = 300
$script:tickBusy = $false
$script:micTimer.Add_Tick({
    # UI Automation calls and SendKeys pump messages, so this tick can be re-entered
    # while it is still running; never run two at once.
    if ($script:tickBusy) { return }
    $script:tickBusy = $true
    try {
        $age = ((Get-Date) - $script:micStart).TotalSeconds
        switch ($script:micState) {
            'connecting' {
                $live = Test-MicInUse "$($script:micKey.micProcess)"
                if ($null -eq $live) { $live = Test-DictationUi $script:micHwnd }
                if (-not $script:micDiag -and $age -gt 3) { $script:micDiag = $true; Write-MicSessions }
                if ($live) { Set-MicState 'live'; Write-Log ("mic: live after {0:N1}s" -f $age) }
                elseif ($age -gt 15) {
                    Set-MicState 'idle'; $script:micTimer.Stop()
                    $script:title.Text = '  mic did not start'
                    Write-Log 'mic: microphone never opened within 15s'
                }
            }
            'live' {
                $live = Test-MicInUse "$($script:micKey.micProcess)"
                if ($null -eq $live) { $live = Test-DictationUi $script:micHwnd }
                if (-not $live) { Write-Log 'mic: microphone closed'; Start-Transcribing }
            }
            'transcribing' {
                $t = ((Get-Date) - $script:trStart).TotalSeconds
                if ($t -lt 0.6) { return }
                # find the chat box once, then just read it (a full window scan every tick is slow)
                if (-not $script:trComposer) { $script:trComposer = Find-Composer $script:micHwnd }
                $txt = Get-ComposerText $script:trComposer
                if ($null -eq $txt -and $script:trComposer -and $t -gt 2) {
                    $script:trComposer = Find-Composer $script:micHwnd
                    $txt = Get-ComposerText $script:trComposer
                }
                $now    = "$txt".Trim()
                $before = "$($script:trBefore)".Trim()
                if ($null -ne $txt -and $now -ne '' -and $now -ne $before) {
                    # new text arrived: done once it stops changing for one tick
                    if ($now -eq $script:trLast) { Finish-Draft $true } else { $script:trLast = $now }
                } elseif ($null -eq $txt) {
                    if ($t -gt 2.5) { Finish-Draft $true }      # can't read the box: trust the app
                } elseif ($t -gt 8) {
                    # nothing new after 8 s: send anyway if asked to, otherwise give up quietly
                    Finish-Draft ([bool]$script:sendAfterDraft)
                }
            }
            'ready' {
                if (((Get-Date) - $script:readyAt).TotalSeconds -gt 4) { Set-MicState 'idle'; $script:micTimer.Stop() }
            }
            default { $script:micTimer.Stop() }
        }
    } catch { Write-Log "mic watch error: $($_.Exception.Message)" }
    finally { $script:tickBusy = $false }
})

function Start-Transcribing {
    $script:trStart  = Get-Date
    $script:trLast   = $null
    $script:trComposer = $null
    Set-MicState 'transcribing'
    $script:micTimer.Start()
}

function Finish-Draft([bool]$gotText) {
    if ($script:micState -ne 'transcribing') { return }   # already finished
    $script:micTimer.Stop()
    $script:micState = 'finishing'
    if ($gotText -and $script:sendAfterDraft) {
        $script:sendAfterDraft = $false
        [void](Focus-Composer $script:micHwnd)
        Start-Sleep -Milliseconds 120
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Set-MicState 'idle'; $script:micTimer.Stop()
        $script:title.Text = '  sent'
        Write-Log ("send: sent after dictation ({0:N1}s)" -f ((Get-Date) - $script:trStart).TotalSeconds)
        return
    }
    $script:sendAfterDraft = $false
    if ($gotText) {
        [void](Focus-Composer $script:micHwnd)
        $script:readyAt = Get-Date
        Set-MicState 'ready'
        $script:micTimer.Start()
        $script:title.Text = '  draft ready'
        Write-Log ("mic: draft ready after {0:N1}s" -f ((Get-Date) - $script:trStart).TotalSeconds)
    } else {
        Set-MicState 'idle'; $script:micTimer.Stop()
        $script:title.Text = '  no text came back'
        Write-Log 'mic: transcription produced no text'
    }
}

function Start-MicWatch($hwnd, [string]$clicked) {
    $script:micHwnd  = $hwnd
    $script:micStart = Get-Date
    $script:micDiag  = $false
    if ($clicked -match '^(stop|finish|end|done)') {
        # keep the snapshot from when dictation started; take one only if the user started it in the app
        if ($script:micState -eq 'idle') { $script:trBefore = Get-ComposerText (Find-Composer $hwnd) }
        Start-Transcribing
    } elseif ($clicked -match '^(cancel|starting dictation)') {
        Set-MicState 'idle'; $script:micTimer.Stop()
    } else {
        $script:trBefore = Get-ComposerText (Find-Composer $hwnd)
        Set-MicState 'connecting'
        $script:micTimer.Start()
    }
}

# ---- build the pad --------------------------------------------------------
$g0    = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$scale = $g0.DpiX / 96.0
$g0.Dispose()
$size = [int]([int](Get-Cfg 'keySize' 92) * $scale)
$gap  = [int](10 * $scale)
$top  = [int](38 * $scale)
$cols = [int](Get-Cfg 'columns' 2)
if ($cols -lt 1) { $cols = 1 }

$bg = [System.Drawing.Color]::FromArgb(20, 20, 24)

# icon font: Segoe Fluent Icons (Windows 11) or Segoe MDL2 Assets (Windows 10)
$iconFamily = 'Segoe MDL2 Assets'
foreach ($f in (New-Object System.Drawing.Text.InstalledFontCollection).Families) {
    if ($f.Name -eq 'Segoe Fluent Icons') { $iconFamily = $f.Name }
}
$glyphFont = New-Object System.Drawing.Font($iconFamily, [single]($size * 0.30), [System.Drawing.GraphicsUnit]::Pixel)
$labelFont = New-Object System.Drawing.Font('Segoe UI Semibold', [single]($size * 0.14), [System.Drawing.GraphicsUnit]::Pixel)
$smallFont = New-Object System.Drawing.Font('Segoe UI', [single](12 * $scale), [System.Drawing.GraphicsUnit]::Pixel)
$chromeFont = New-Object System.Drawing.Font($iconFamily, [single](13 * $scale), [System.Drawing.GraphicsUnit]::Pixel)
$gearFont   = New-Object System.Drawing.Font($iconFamily, [single](19 * $scale), [System.Drawing.GraphicsUnit]::Pixel)

function ConvertTo-Glyph([string]$hex) {
    if (-not $hex) { return '' }
    try { return [string][char][Convert]::ToInt32($hex, 16) } catch { return '' }
}

$form = New-Object PadForm
$form.Text            = 'MicnKey_Main'
$form.FormBorderStyle = 'None'
$form.StartPosition   = 'Manual'
$form.TopMost         = $true
$form.ShowInTaskbar   = $false
$form.BackColor       = $bg
$form.Opacity         = [double](Get-Cfg 'opacity' 0.92)

$script:title = New-Object System.Windows.Forms.Label
$title.Text      = '  MicnKey Deck'
$title.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 160)
$title.BackColor = $bg
$title.Font      = $smallFont
$title.TextAlign = 'MiddleLeft'
$title.Location  = New-Object System.Drawing.Point(0, 0)
$title.Cursor    = [System.Windows.Forms.Cursors]::SizeAll
$form.Controls.Add($title)

function New-ChromeButton([string]$glyphHex, [string]$tip) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = ConvertTo-Glyph $glyphHex
    $l.Font      = $chromeFont
    $l.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 160)
    $l.BackColor = $bg
    $l.TextAlign = 'MiddleCenter'
    $l.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $l.Add_MouseEnter({ param($s, $e) $s.ForeColor = [System.Drawing.Color]::White })
    $l.Add_MouseLeave({ param($s, $e) $s.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 160) })
    (New-Object System.Windows.Forms.ToolTip).SetToolTip($l, $tip)
    $form.Controls.Add($l)
    $l
}
$close = New-ChromeButton 'E8BB' 'Close MicnKey Deck'
$close.Add_Click({ $form.Close() })
$gear = New-ChromeButton 'E713' 'Settings - add, remove and change keys'
$gear.Add_Click({
    $settings = Join-Path $here 'Settings.ps1'
    if (Test-Path $settings) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$settings`""
    } else {
        Start-Process notepad.exe -ArgumentList "`"$cfgPath`""
    }
})

# drag the pad by its title strip
$script:dragging = $false
$script:dragOff  = New-Object System.Drawing.Point(0, 0)
$title.Add_MouseDown({ param($s, $e) $script:dragging = $true; $script:dragOff = $e.Location })
$title.Add_MouseUp({ $script:dragging = $false })
$title.Add_MouseMove({
    if ($script:dragging) {
        $p = [System.Windows.Forms.Cursor]::Position
        $form.Location = New-Object System.Drawing.Point(($p.X - $script:dragOff.X), ($p.Y - $script:dragOff.Y))
    }
})

function Get-NumpadLabel([string]$k) {
    switch -regex ($k) {
        '^NumPad(\d)$' { return $Matches[1] }
        '^Decimal$'     { return '.' }
        '^Divide$'      { return '/' }
        '^Multiply$'    { return '*' }
        '^Subtract$'    { return '-' }
        '^Add$'         { return '+' }
        default         { return $k }
    }
}
$script:allBtns = @()
$y = 0; $col = 0
$hotkeys = @{}
$hotId   = 1
foreach ($key in $cfg.keys) {
    if ($key.wide -and $col -ne 0) { $col = 0; $y++ }
    $btn = New-Object PadKey
    $w = if ($key.wide) { $size * $cols + $gap * ($cols - 1) } else { $size }
    $btn.Size      = New-Object System.Drawing.Size($w, $size)
    $btn.Location  = New-Object System.Drawing.Point(($gap + $col * ($size + $gap)), ($top + $y * ($size + $gap)))
    $btn.BackColor = $bg
    $btn.Font      = $labelFont
    $btn.GlyphFont = $glyphFont
    $btn.Label     = "$($key.label)"
    $btn.Glyph     = ConvertTo-Glyph "$($key.glyph)"
    if ($key.color) {
        try {
            $keyColor = [System.Drawing.ColorTranslator]::FromHtml("$($key.color)")
            if ($key.action -in @('open','folder')) { $btn.ActiveColor = $keyColor } else { $btn.Base = $keyColor }
        } catch { Write-Log "bad color: $($key.color)" }
    }
    if ($key.numpad) { $btn.Badge = Get-NumpadLabel "$($key.numpad)" }
    $script:allBtns += $btn
    $btn.Tag = $key

    if ($key.icon) {
        $iconPath = Resolve-PadPath "$($key.icon)"
        if (-not [System.IO.Path]::IsPathRooted($iconPath)) { $iconPath = Join-Path $here $iconPath }
        if (Test-Path -LiteralPath $iconPath) {
            try { $btn.Icon = [System.Drawing.Image]::FromFile($iconPath) } catch { Write-Log "icon failed: $iconPath" }
        } else { Write-Log "icon not found: $iconPath" }
    }

    if ($key.action -eq 'mic') { $script:micBtn = $btn; $script:micKey = $key }
    $btn.Add_MouseClick({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            if ($s.Tag.action -eq 'mic') { Start-Teach }
            return
        }
        Invoke-KeyAction $s.Tag
    })
    $form.Controls.Add($btn)

    if ($key.hotkey) { $hotkeys[$hotId] = $key; $hotId++ }

    if ($key.wide) { $col = 0; $y++ } else { $col++; if ($col -ge $cols) { $col = 0; $y++ } }
}
$rows = if ($col -eq 0) { $y } else { $y + 1 }

$formW = $gap + $cols * ($size + $gap)
$formH = $top + $rows * ($size + $gap)
$form.ClientSize = New-Object System.Drawing.Size($formW, $formH)
# big, easy-to-hit Settings button
$gearW = [int]($top * 1.5)
$gear.Font       = $gearFont
$gear.BackColor  = [System.Drawing.Color]::FromArgb(56, 56, 64)
$gear.ForeColor  = [System.Drawing.Color]::White
$gear.Add_MouseLeave({ param($s, $e) $s.ForeColor = [System.Drawing.Color]::White })
$gear.Add_MouseEnter({ param($s, $e) $s.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212) })
$gear.Add_MouseLeave({ param($s, $e) $s.BackColor = [System.Drawing.Color]::FromArgb(56, 56, 64) })
$title.Size      = New-Object System.Drawing.Size(($formW - $top - $gearW - 4), $top)
$gear.Size       = New-Object System.Drawing.Size($gearW, ($top - 6))
$gear.Location   = New-Object System.Drawing.Point(($formW - $top - $gearW - 2), 3)
$close.Size      = New-Object System.Drawing.Size($top, $top)
$close.Location  = New-Object System.Drawing.Point(($formW - $top), 0)

# position: last saved spot, else bottom-right
$posFile = Join-Path $here 'pad-position.txt'
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($wa.Right - $formW - 24), ($wa.Bottom - $formH - 24))
try {
    if (Test-Path $posFile) {
        $xy = (Get-Content $posFile -Raw).Trim() -split ','
        $pt = New-Object System.Drawing.Point([int]$xy[0], [int]$xy[1])
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            $a = $scr.WorkingArea
            if ($a.Contains($pt)) {
                # keep the whole pad on screen
                $x = [math]::Max($a.Left, [math]::Min($pt.X, $a.Right - $formW))
                $y = [math]::Max($a.Top,  [math]::Min($pt.Y, $a.Bottom - $formH))
                $form.Location = New-Object System.Drawing.Point([int]$x, [int]$y)
            }
        }
    }
} catch {}
# ---- keep the pad findable ---------------------------------------------------
# Show-desktop, full-screen apps or a screen change can hide the pad or push it
# off screen. A watchdog puts it back on top every 2 s, and a "show pad" hotkey
# (Ctrl+Alt+P by default) brings it back to the bottom-right corner.
function Show-Pad([bool]$fromHotkey) {
    try {
        $h = $form.Handle
        $r = New-Object System.Drawing.Rectangle($form.Location, $form.Size)
        $onScreen = $false
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            $i = [System.Drawing.Rectangle]::Intersect($scr.WorkingArea, $r)
            if ($i.Width -ge 80 -and $i.Height -ge 80) { $onScreen = $true }
        }
        if (-not $onScreen) {
            $a = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $form.Location = New-Object System.Drawing.Point(($a.Right - $form.Width - 24), ($a.Bottom - $form.Height - 24))
            Write-Log 'pad: was off screen - moved back'
        }
        if (-not $form.Visible -or [PadNative]::IsIconic($h)) {
            [void][PadNative]::ShowWindow($h, 4)        # SW_SHOWNOACTIVATE
            $form.Visible = $true
            Write-Log 'pad: was hidden - shown again'
        }
        # HWND_TOPMOST, no move/size/activate, show
        [void][PadNative]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010 -bor 0x0040)
        if ($fromHotkey) { $script:title.Text = '  here I am' }
    } catch {}
}
$script:keepTimer = New-Object System.Windows.Forms.Timer
$script:keepTimer.Interval = 2000
$script:keepTimer.Add_Tick({ Show-Pad $false })
$form.Add_Shown({ $script:keepTimer.Start() })

$form.Add_FormClosing({ try { Set-Content -Path $posFile -Value "$($form.Location.X),$($form.Location.Y)" } catch {} })
$form.Add_HandleCreated({ try { [PadNative]::RoundCorners($form.Handle) } catch {} })

# ---- live reload: saving config.json restarts the pad -----------------------
$script:reloadTimer = New-Object System.Windows.Forms.Timer
$script:reloadTimer.Interval = 800
$script:reloadTimer.Add_Tick({
    $script:reloadTimer.Stop()
    try {
        $null = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $script:title.Text = '  config error - not reloaded'
        Write-Log "config.json error, not reloaded: $($_.Exception.Message)"
        return
    }
    Write-Log 'config.json changed - reloading'
    Restart-Pad
})
$watcher = New-Object System.IO.FileSystemWatcher($here, 'config.json')
$watcher.NotifyFilter = [System.IO.NotifyFilters]'LastWrite, Size, FileName'
$watcher.SynchronizingObject = $form
$watcher.Add_Changed({ $script:reloadTimer.Stop(); $script:reloadTimer.Start() })
$watcher.Add_Renamed({ $script:reloadTimer.Stop(); $script:reloadTimer.Start() })
$watcher.EnableRaisingEvents = $true

# ---- highlight the key of the window you are in ----------------------------
$script:lastFg = ''
$script:fgTimer = New-Object System.Windows.Forms.Timer
$script:fgTimer.Interval = 400
$script:fgTimer.Add_Tick({
    try {
        $h = [PadNative]::GetForegroundWindow()
        if ($h -eq $form.Handle) { return }
        $t = [PadNative]::Title($h)
        $sig = "$h|$t"
        if ($sig -eq $script:lastFg) { return }
        $script:lastFg = $sig
        [uint32]$procId = 0
        [void][PadNative]::GetWindowThreadProcessId($h, [ref]$procId)
        $proc = ''
        try { $proc = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch {}
        if ("$proc $t" -match (Get-AiRx)) { $script:lastAiHwnd = $h }
        foreach ($b in $script:allBtns) {
            $k = $b.Tag
            $on = $false
            if ($k.action -eq 'open' -and $k.match) {
                $on = ($proc -match $k.match) -or (($proc -match $browserRx) -and ($t -match $k.match))
            } elseif ($k.action -eq 'folder' -and $k.path -and $proc -eq 'explorer') {
                $leaf = Split-Path -Leaf ((Resolve-PadPath "$($k.path)").TrimEnd('\'))
                $on = ($t -ieq $leaf) -or ($t -like "$leaf - *")
            }
            $b.SetActive($on)
        }
    } catch {}
})
$form.Add_Shown({ $script:fgTimer.Start() })

# ---- AI keys mode: a toggle key turns the number pad into pad keys ---------
$script:layerOn   = $false
$script:layerIds  = @{}
$layerToggle = "$(Get-Cfg 'layerToggle' 'Insert')"
$LAYER_TOGGLE_ID = 900
$SHOW_PAD_ID     = 901

function Register-Spec([int]$id, [string]$spec) {
    $mods = 0; $vk = 0
    foreach ($part in ($spec -split '\+')) {
        switch ($part.Trim().ToLower()) {
            'alt'   { $mods = $mods -bor 1 }
            'ctrl'  { $mods = $mods -bor 2 }
            'shift' { $mods = $mods -bor 4 }
            'win'   { $mods = $mods -bor 8 }
            default { $vk = [int][System.Windows.Forms.Keys]$part.Trim() }
        }
    }
    if (-not [PadNative]::RegisterHotKey($form.Handle, $id, $mods, $vk)) {
        Write-Log "hotkey '$spec' is taken by another app"
        return $false
    }
    return $true
}

function Set-Layer([bool]$on) {
    foreach ($id in @($script:layerIds.Keys)) { [void][PadNative]::UnregisterHotKey($form.Handle, $id) }
    $script:layerIds = @{}
    $script:layerOn = $on
    if ($on) {
        $i = 1000
        foreach ($b in $script:allBtns) {
            $k = $b.Tag
            if (-not $k.numpad) { continue }
            try { if (Register-Spec $i "$($k.numpad)") { $script:layerIds[$i] = $k } } catch { Write-Log "bad numpad key '$($k.numpad)'" }
            $i++
        }
        $numOff = -not [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::NumLock)
        $script:title.Text = if ($numOff) { '  AI keys ON - turn NumLock on' } else { '  AI keys ON: number pad' }
        $script:title.ForeColor = [System.Drawing.Color]::FromArgb(120, 230, 140)
        Write-Log "AI keys ON ($($script:layerIds.Count) number-pad keys)"
    } else {
        $script:title.Text = '  AI keys OFF'
        Write-Log 'AI keys OFF'
    }
    foreach ($b in $script:allBtns) { $b.SetBadgeLit($on) }
}

# ---- a title strip that teaches itself ------------------------------------
# When nothing else is being said, the strip shows how to turn on the number-pad
# keys (or that they are on). Status messages fade back to this after a few seconds.
function Get-IdleTitle {
    if ($layerToggle -and $layerToggle -ne 'off') {
        if ($script:layerOn) { return "  AI keys ON  ($layerToggle = off)" }
        return "  $layerToggle = number-pad keys"
    }
    return '  MicnKey Deck'
}
function Set-IdleTitle {
    $script:settingIdle = $true
    $script:title.Text = Get-IdleTitle
    $script:title.ForeColor = if ($script:layerOn) { [System.Drawing.Color]::FromArgb(120, 230, 140) } else { [System.Drawing.Color]::FromArgb(150, 150, 160) }
    $script:settingIdle = $false
}
$script:titleTimer = New-Object System.Windows.Forms.Timer
$script:titleTimer.Interval = 6000
$script:titleTimer.Add_Tick({
    $script:titleTimer.Stop()
    # keep live mic messages; everything else goes back to the hint
    if ($script:micState -in @('idle', 'ready')) { Set-IdleTitle } else { $script:titleTimer.Start() }
})
$script:title.Add_TextChanged({
    if (-not $script:settingIdle) { $script:titleTimer.Stop(); $script:titleTimer.Start() }
})
if ($layerToggle -and $layerToggle -ne 'off') {
    $script:title.Add_DoubleClick({ Set-Layer (-not $script:layerOn) })
    (New-Object System.Windows.Forms.ToolTip).SetToolTip($script:title,
        "Press $layerToggle (or double-click here) to turn your number pad into these keys.`nThe small number on each key is its number-pad key. Drag here to move the pad.")
}
$form.Add_Shown({ Set-IdleTitle })

# ---- physical hotkeys -----------------------------------------------------
$form.add_HotKey([Action[int]]{
    param($id)
    if ($id -eq $LAYER_TOGGLE_ID) { Set-Layer (-not $script:layerOn); return }
    if ($id -eq $SHOW_PAD_ID) { Show-Pad $true; return }
    if ($script:layerIds.ContainsKey($id)) { Invoke-KeyAction $script:layerIds[$id]; return }
    if ($hotkeys.ContainsKey($id)) { Invoke-KeyAction $hotkeys[$id] }
})
$form.Add_Shown({
    foreach ($id in $hotkeys.Keys) {
        $spec = "$($hotkeys[$id].hotkey)"
        try { [void](Register-Spec $id $spec) } catch { Write-Log "bad hotkey '$spec': $($_.Exception.Message)" }
    }
    # "show pad" hotkey: the one in config.json, else the first free one of these
    $showKey = "$(Get-Cfg 'showHotkey' '')"
    if ($showKey -ne 'off') {
        $tries = @(); if ($showKey) { $tries += $showKey }
        $tries += @('Ctrl+Alt+P', 'Ctrl+Alt+Space', 'Ctrl+Shift+Alt+P')
        foreach ($t in $tries) {
            $ok = $false
            try { $ok = Register-Spec $SHOW_PAD_ID $t } catch {}
            if ($ok) { $script:showKeyUsed = $t; Write-Log "show-pad hotkey: $t"; break }
        }
    }
    if ($layerToggle -and $layerToggle -ne 'off') {
        try { [void](Register-Spec $LAYER_TOGGLE_ID $layerToggle) } catch { Write-Log "bad AI-mode toggle '$layerToggle'" }
    }
})
$form.Add_FormClosed({
    foreach ($id in $hotkeys.Keys) { [void][PadNative]::UnregisterHotKey($form.Handle, $id) }
    foreach ($id in @($script:layerIds.Keys)) { [void][PadNative]::UnregisterHotKey($form.Handle, $id) }
    [void][PadNative]::UnregisterHotKey($form.Handle, $LAYER_TOGGLE_ID)
    [void][PadNative]::UnregisterHotKey($form.Handle, $SHOW_PAD_ID)
})

Write-Log "--- MicnKey Deck v1.3.1 started (scale $scale, icons: $iconFamily) ---"
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
Write-Log "--- MicnKey Deck stopped ---"
$mutex.ReleaseMutex()
