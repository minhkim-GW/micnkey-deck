# MicnKey Deck v1.3 - Settings window (point-and-click, no code). English by default, Vietnamese optional.
# Saved as UTF-8 with BOM so Windows PowerShell 5.1 shows Vietnamese text correctly.

$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $here 'config.json'
$logPath = Join-Path $here 'micnkey.log'
function Write-Log([string]$m) { try { Add-Content -Path $logPath -Value ("{0}  settings: {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding UTF8 } catch {} }
trap { Write-Log ("FATAL: " + $_.Exception.Message + " @ line " + $_.InvocationInfo.ScriptLineNumber); break }
Write-Log 'starting'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class SetNative { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
'@
[void][SetNative]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

# chỉ mở một cửa sổ Cài đặt
$mutex = New-Object System.Threading.Mutex($false, 'MicnKey_Settings')
if (-not $mutex.WaitOne(0)) { exit }

# ---- đọc cấu hình ----------------------------------------------------------
try { $cfg = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch {
    [void][System.Windows.Forms.MessageBox]::Show("Cannot read config.json:`n$($_.Exception.Message)", 'MicnKey Deck')
    exit
}
$script:lang = if ("$($cfg.language)" -eq 'vi') { 'vi' } else { 'en' }
function T([string]$en, [string]$vi) { if ($script:lang -eq 'vi') { $vi } else { $en } }
$script:dirty = $false
$script:KeyList = New-Object System.Collections.ArrayList
foreach ($k in @($cfg.keys)) { [void]$script:KeyList.Add($k) }

function Set-Prop($o, [string]$name, $val) {
    if ($null -eq $val -or ($val -is [string] -and $val -eq '') -or ($val -is [bool] -and -not $val)) {
        if ($o.PSObject.Properties[$name]) { $o.PSObject.Properties.Remove($name) }
    } else {
        Add-Member -InputObject $o -NotePropertyName $name -NotePropertyValue $val -Force
    }
}

# ---- kích thước theo DPI ---------------------------------------------------
$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $sc = $g0.DpiX / 96.0; $g0.Dispose()
function S([double]$v) { [int]($v * $sc) }
function P($x, $y) { New-Object System.Drawing.Point((S $x), (S $y)) }
function Z($w, $h) { New-Object System.Drawing.Size((S $w), (S $h)) }

$uiFont   = New-Object System.Drawing.Font('Segoe UI', 10)
$boldFont = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$iconFamily = 'Segoe MDL2 Assets'
foreach ($f in (New-Object System.Drawing.Text.InstalledFontCollection).Families) { if ($f.Name -eq 'Segoe Fluent Icons') { $iconFamily = $f.Name } }
$glyphFont = New-Object System.Drawing.Font($iconFamily, 13)

# ---- danh sách lựa chọn -----------------------------------------------------
$Icons = @(
    @('E720',(T 'Microphone' 'Micro')), @('E8B7',(T 'Folder' 'Thư mục')), @('E838',(T 'Open folder' 'Thư mục mở')), @('E896',(T 'Download' 'Tải xuống')),
    @('E724',(T 'Send' 'Gửi')), @('E751',(T 'New line' 'Xuống dòng')), @('E8BD',(T 'Chat' 'Tin nhắn')), @('E99A',(T 'Robot' 'Robot')),
    @('E8A5',(T 'Document' 'Tài liệu')), @('E715',(T 'Mail' 'Thư / Email')), @('E721',(T 'Search' 'Tìm kiếm')), @('E774',(T 'Website' 'Trang web')),
    @('E8C8',(T 'Copy' 'Copy')), @('E77F',(T 'Paste' 'Dán')), @('E7A7',(T 'Undo' 'Hoàn tác')), @('E713',(T 'Settings' 'Cài đặt')),
    @('E80F',(T 'Home' 'Nhà')), @('E734',(T 'Star' 'Ngôi sao')), @('E716',(T 'People' 'Người')), @('E787',(T 'Calendar' 'Lịch')),
    @('E768',(T 'Play' 'Phát')), @('E710',(T 'Plus' 'Dấu cộng'))
)
$Actions = @(
    @('folder', (T 'Open a folder' 'Mở một thư mục')),
    @('run',    (T 'Open a file, app or website' 'Mở file / ứng dụng / trang web')),
    @('text',   (T 'Paste saved text (a prompt)' 'Dán một đoạn chữ có sẵn')),
    @('keys',   (T 'Press keys for me (Enter, Ctrl+C...)' 'Bấm phím hộ (Enter, Ctrl+C...)')),
    @('open',   (T 'Open or switch to an app' 'Mở hoặc chuyển sang một app')),
    @('mic',    (T 'Smart microphone' 'Micro thông minh')),
    @('desktop',(T 'Show desktop (press again to restore)' 'Hiện desktop (bấm lại để trở về)'))
)
$KeyPresets = @(
    @('{ENTER}', (T 'Enter - send message' 'Enter - gửi tin nhắn')),
    @('+{ENTER}',(T 'Shift+Enter - new line' 'Shift+Enter - xuống dòng')),
    @('^c',      'Ctrl+C - copy'),
    @('^v',      (T 'Ctrl+V - paste' 'Ctrl+V - dán')),
    @('^z',      (T 'Ctrl+Z - undo' 'Ctrl+Z - hoàn tác')),
    @('^a',      (T 'Ctrl+A - select all' 'Ctrl+A - chọn tất cả')),
    @('{ESC}',   (T 'Esc - cancel' 'Esc - thoát / hủy')),
    @('{TAB}',   'Tab')
)
$Apps = @(
    @{ name = 'Claude';  match = 'claude';  launch = 'Claude';     web = 'https://claude.ai/new' },
    @{ name = 'ChatGPT'; match = 'chatgpt'; launch = 'ChatGPT';    web = 'https://chatgpt.com/' },
    @{ name = 'Gemini';  match = 'gemini';  launch = 'Gemini';     web = 'https://gemini.google.com/app' },
    @{ name = 'Chrome';  match = 'chrome';  launch = 'chrome.exe'; web = $null },
    @{ name = 'Edge';    match = 'msedge';  launch = 'msedge.exe'; web = $null }
)

# ---- cửa sổ ----------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = (T 'MicnKey Deck - Settings' 'MicnKey Deck - Cài đặt')
$form.Font = $uiFont
$form.ClientSize = Z 820 650
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White

function Add-Ctl($parent, $ctl, $x, $y, $w, $h) {
    $ctl.Location = P $x $y
    if ($w) { $ctl.Size = Z $w $h }
    $parent.Controls.Add($ctl)
    $ctl
}
function New-Lbl([string]$t) { $l = New-Object System.Windows.Forms.Label; $l.Text = $t; $l.AutoSize = $false; $l.TextAlign = 'MiddleLeft'; $l }
function New-Btn([string]$t) { $b = New-Object System.Windows.Forms.Button; $b.Text = $t; $b.FlatStyle = 'System'; $b }

# danh sách phím
$hdr = Add-Ctl $form (New-Lbl (T 'Keys (in pad order)' 'Các phím (theo thứ tự trên pad)')) 12 8 230 26
$hdr.Font = $boldFont
$lb = Add-Ctl $form (New-Object System.Windows.Forms.ListBox) 12 38 230 470
$lb.IntegralHeight = $false
$btnAdd  = Add-Ctl $form (New-Btn (T '+ Add key' '+ Thêm phím')) 12 516 112 32
$btnDel  = Add-Ctl $form (New-Btn (T 'Delete key' 'Xóa phím'))    130 516 112 32
$btnUp   = Add-Ctl $form (New-Btn (T 'Move up' 'Lên'))         12 554 112 32
$btnDown = Add-Ctl $form (New-Btn (T 'Move down' 'Xuống'))       130 554 112 32

# nhóm: phím đang chọn
$grp = Add-Ctl $form (New-Object System.Windows.Forms.GroupBox) 256 8 552 446
$grp.Text = (T 'Selected key' 'Phím đang chọn')
$grp.Font = $boldFont

function Add-Row($text, $y) { $l = Add-Ctl $grp (New-Lbl $text) 16 $y 150 30; $l.Font = $uiFont; $l }

[void](Add-Row (T 'Key label' 'Chữ trên phím') 28)
$txtLabel = Add-Ctl $grp (New-Object System.Windows.Forms.TextBox) 170 30 250 28
$txtLabel.Font = $uiFont

[void](Add-Row (T 'Icon' 'Biểu tượng') 66)
$cbIcon = Add-Ctl $grp (New-Object System.Windows.Forms.ComboBox) 170 66 250 30
$cbIcon.Font = $uiFont
$cbIcon.DropDownStyle = 'DropDownList'
$cbIcon.DrawMode = 'OwnerDrawFixed'
$cbIcon.ItemHeight = S 26
$cbIcon.MaxDropDownItems = 12
foreach ($i in $Icons) { [void]$cbIcon.Items.Add($i[1]) }
$cbIcon.Add_DrawItem({
    param($s, $e)
    $e.DrawBackground()
    if ($e.Index -lt 0) { return }
    $fg = if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) { [System.Drawing.SystemBrushes]::HighlightText } else { [System.Drawing.Brushes]::Black }
    $glyph = [string][char][Convert]::ToInt32($Icons[$e.Index][0], 16)
    $e.Graphics.TextRenderingHint = 'AntiAliasGridFit'
    $e.Graphics.DrawString($glyph, $glyphFont, $fg, [single]($e.Bounds.X + (S 4)), [single]($e.Bounds.Y + (S 3)))
    $e.Graphics.DrawString($Icons[$e.Index][1], $uiFont, $fg, [single]($e.Bounds.X + (S 34)), [single]($e.Bounds.Y + (S 3)))
})
$btnImg = Add-Ctl $grp (New-Btn (T 'Use my image...' 'Dùng ảnh riêng...')) 428 65 112 32
$btnImg.Font = $uiFont

[void](Add-Row (T 'Key color' 'Màu nền phím') 106)
$btnColor = Add-Ctl $grp (New-Btn '') 170 106 120 30
$btnColor.FlatStyle = 'Flat'
$btnColorReset = Add-Ctl $grp (New-Btn (T 'Default color' 'Màu mặc định')) 298 105 122 32
$btnColorReset.Font = $uiFont

[void](Add-Row (T 'What it does' 'Phím này làm gì') 146)
$cbAction = Add-Ctl $grp (New-Object System.Windows.Forms.ComboBox) 170 146 370 30
$cbAction.Font = $uiFont
$cbAction.DropDownStyle = 'DropDownList'
foreach ($a in $Actions) { [void]$cbAction.Items.Add($a[1]) }

# vùng thay đổi theo loại phím
$pnl = Add-Ctl $grp (New-Object System.Windows.Forms.Panel) 16 186 524 116
$pnl.Font = $uiFont
$lblDyn  = Add-Ctl $pnl (New-Lbl '') 0 2 150 30
$txtPath = Add-Ctl $pnl (New-Object System.Windows.Forms.TextBox) 154 4 280 28
$btnBrowse = Add-Ctl $pnl (New-Btn (T 'Browse...' 'Chọn...')) 440 2 84 32
$lblHint = Add-Ctl $pnl (New-Lbl '') 154 38 370 48
$lblHint.ForeColor = [System.Drawing.Color]::DimGray
$lblHint.TextAlign = 'TopLeft'
$txtText = Add-Ctl $pnl (New-Object System.Windows.Forms.TextBox) 154 4 370 104
$txtText.Multiline = $true
$txtText.ScrollBars = 'Vertical'
$cbKeys = Add-Ctl $pnl (New-Object System.Windows.Forms.ComboBox) 154 4 370 30
$cbKeys.DropDownStyle = 'DropDownList'
$cbApp = Add-Ctl $pnl (New-Object System.Windows.Forms.ComboBox) 154 4 370 30
$cbApp.DropDownStyle = 'DropDownList'
foreach ($a in $Apps) { [void]$cbApp.Items.Add($a.name) }

$chkWide = Add-Ctl $grp (New-Object System.Windows.Forms.CheckBox) 170 306 370 28
$chkWide.Text = (T 'Full-width key' 'Phím rộng hết cả hàng')
$chkWide.Font = $uiFont

[void](Add-Row (T 'Keyboard shortcut' 'Phím tắt bàn phím') 340)
$txtHot = Add-Ctl $grp (New-Object System.Windows.Forms.TextBox) 170 342 200 28
$txtHot.Font = $uiFont
$txtHot.ReadOnly = $true
$txtHot.BackColor = [System.Drawing.Color]::White
$btnHotClear = Add-Ctl $grp (New-Btn (T 'Remove' 'Bỏ phím tắt')) 376 341 110 32
$btnHotClear.Font = $uiFont
$lblHotHint = Add-Ctl $grp (New-Lbl (T 'Click the box, then press e.g. F9 or Ctrl + Alt + D' 'Bấm vào ô rồi nhấn, ví dụ F9 hoặc Ctrl + Alt + D')) 170 374 370 26
$lblHotHint.Font = $uiFont
$lblHotHint.ForeColor = [System.Drawing.Color]::DimGray

[void](Add-Row (T 'Number pad key' 'Phím bàn phím số') 406)
$cbNum = Add-Ctl $grp (New-Object System.Windows.Forms.ComboBox) 170 408 120 30
$cbNum.Font = $uiFont
$cbNum.DropDownStyle = 'DropDownList'
$NumKeys = @('', 'NumPad0','NumPad1','NumPad2','NumPad3','NumPad4','NumPad5','NumPad6','NumPad7','NumPad8','NumPad9','Divide','Multiply','Subtract','Add','Decimal')
foreach ($n in $NumKeys) { [void]$cbNum.Items.Add($(if ($n) { $n -replace '^NumPad', 'Num ' } else { (T '(none)' '(không)') })) }
$lblNumHint = Add-Ctl $grp (New-Lbl (T 'used in AI keys mode' 'dùng khi bật chế độ AI')) 298 406 240 30
$lblNumHint.Font = $uiFont
$lblNumHint.ForeColor = [System.Drawing.Color]::DimGray

# nhóm: cài đặt chung
$gen = Add-Ctl $form (New-Object System.Windows.Forms.GroupBox) 256 460 552 134
$gen.Text = (T 'General' 'Cài đặt chung')
$gen.Font = $boldFont
$l = Add-Ctl $gen (New-Lbl (T 'Opacity' 'Độ trong')) 16 26 70 30; $l.Font = $uiFont
$tbOpacity = Add-Ctl $gen (New-Object System.Windows.Forms.TrackBar) 86 24 150 36
$tbOpacity.Minimum = 50; $tbOpacity.Maximum = 100; $tbOpacity.TickFrequency = 10
$l = Add-Ctl $gen (New-Lbl (T 'Key size' 'Cỡ phím')) 252 26 64 30; $l.Font = $uiFont
$numSize = Add-Ctl $gen (New-Object System.Windows.Forms.NumericUpDown) 318 28 64 28
$numSize.Font = $uiFont; $numSize.Minimum = 60; $numSize.Maximum = 160; $numSize.Increment = 4
$l = Add-Ctl $gen (New-Lbl (T 'Columns' 'Số cột')) 400 26 54 30; $l.Font = $uiFont
$numCols = Add-Ctl $gen (New-Object System.Windows.Forms.NumericUpDown) 456 28 52 28
$numCols.Font = $uiFont; $numCols.Minimum = 1; $numCols.Maximum = 6
$chkAuto = Add-Ctl $gen (New-Object System.Windows.Forms.CheckBox) 16 62 230 28
$chkAuto.Text = (T 'Start with Windows' 'Tự mở khi bật máy')
$chkAuto.Font = $uiFont
$l = Add-Ctl $gen (New-Lbl (T 'AI keys on/off key' 'Phím bật/tắt chế độ AI')) 16 96 180 30; $l.Font = $uiFont
$cbLayer = Add-Ctl $gen (New-Object System.Windows.Forms.ComboBox) 200 96 120 30
$cbLayer.Font = $uiFont
$cbLayer.DropDownStyle = 'DropDownList'
$LayerKeys = @('Insert','Pause','Scroll','F12','off')
foreach ($n in $LayerKeys) { [void]$cbLayer.Items.Add($(if ($n -eq 'off') { (T '(off)' '(tắt)') } elseif ($n -eq 'Scroll') { 'Scroll Lock' } else { $n })) }
$cur = if ($cfg.layerToggle) { "$($cfg.layerToggle)" } else { 'Insert' }
$cbLayer.SelectedIndex = [math]::Max(0, [array]::IndexOf($LayerKeys, $cur))
$l = Add-Ctl $gen (New-Lbl (T 'turns the number pad into pad keys' 'biến bàn phím số thành phím của pad')) 328 96 218 30; $l.Font = $uiFont; $l.ForeColor = [System.Drawing.Color]::DimGray
$l = Add-Ctl $gen (New-Lbl 'Language / Ngôn ngữ') 252 62 140 30; $l.Font = $uiFont
$cbLang = Add-Ctl $gen (New-Object System.Windows.Forms.ComboBox) 394 62 140 30
$cbLang.Font = $uiFont
$cbLang.DropDownStyle = 'DropDownList'
[void]$cbLang.Items.Add('English'); [void]$cbLang.Items.Add('Tiếng Việt')
$cbLang.SelectedIndex = if ($script:lang -eq 'vi') { 1 } else { 0 }

$tbOpacity.Value = [int]([math]::Round(100 * [double]$(if ($null -ne $cfg.opacity) { $cfg.opacity } else { 0.92 })))
$numSize.Value   = [decimal]$(if ($cfg.keySize) { [math]::Min(160, [math]::Max(60, [int]$cfg.keySize)) } else { 92 })
$numCols.Value   = [decimal]$(if ($cfg.columns) { [math]::Min(6, [math]::Max(1, [int]$cfg.columns)) } else { 2 })
$chkAuto.Checked = [bool]$cfg.autostart

# nút dưới cùng
$lblStatus = Add-Ctl $form (New-Lbl '') 12 604 420 34
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$btnSave = Add-Ctl $form (New-Btn (T 'Save' 'Lưu')) 584 604 110 36
$btnSave.Font = $boldFont
$btnClose = Add-Ctl $form (New-Btn (T 'Close' 'Đóng')) 700 604 108 36
$form.AcceptButton = $btnSave

$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($btnSave, (T 'Save - the pad updates in about a second' 'Lưu lại - pad sẽ tự cập nhật sau 1 giây'))

# ---- hiển thị phím đang chọn ----------------------------------------------
$script:loading = $false
function Get-Cur { if ($lb.SelectedIndex -ge 0) { $script:KeyList[$lb.SelectedIndex] } else { $null } }
function Get-KeyTitle($k) {
    $t = "$($k.label)"
    if (-not $t) { $t = (T '(no label)' '(chưa đặt tên)') }
    if ($k.action -eq 'mic') { $t += (T '   [mic]' '   [micro]') }
    $t
}
function Update-List([int]$select) {
    $script:loading = $true
    $lb.BeginUpdate()
    $lb.Items.Clear()
    foreach ($k in $script:KeyList) { [void]$lb.Items.Add((Get-KeyTitle $k)) }
    $lb.EndUpdate()
    $script:loading = $false
    if ($lb.Items.Count -gt 0) { $lb.SelectedIndex = [math]::Min([math]::Max(0, $select), $lb.Items.Count - 1) }
    else { Show-Key }
}
function Set-ColorButton($k) {
    if ($k -and $k.color) {
        try { $btnColor.BackColor = [System.Drawing.ColorTranslator]::FromHtml("$($k.color)"); $btnColor.Text = ''; return } catch {}
    }
    $btnColor.BackColor = [System.Drawing.Color]::FromArgb(46, 46, 52)
    $btnColor.ForeColor = [System.Drawing.Color]::White
    $btnColor.Text = (T 'default' 'mặc định')
}

function Show-Panel([string]$action, $k) {
    foreach ($c in @($txtPath, $btnBrowse, $lblHint, $txtText, $cbKeys, $cbApp)) { $c.Visible = $false }
    $lblDyn.Visible = $true
    switch ($action) {
        'folder' {
            $lblDyn.Text = (T 'Folder' 'Thư mục')
            $txtPath.Visible = $true; $btnBrowse.Visible = $true; $lblHint.Visible = $true
            $txtPath.Text = "$($k.path)"
            $lblHint.Text = (T 'Click "Browse..." to pick a folder.' 'Bấm "Chọn..." để chọn thư mục.')
        }
        'run' {
            $lblDyn.Text = (T 'What to open' 'Mở cái gì')
            $txtPath.Visible = $true; $btnBrowse.Visible = $true; $lblHint.Visible = $true
            $txtPath.Text = "$($k.path)"
            $lblHint.Text = (T 'Pick a file or app, or paste a web link, e.g. https://claude.ai' 'Chọn một file hoặc ứng dụng, hoặc dán link web, ví dụ https://claude.ai')
        }
        'text' {
            $lblDyn.Text = (T 'Text to paste' 'Đoạn chữ sẽ dán')
            $txtText.Visible = $true
            $txtText.Text = "$($k.text)"
        }
        'keys' {
            $lblDyn.Text = (T 'Keys to press' 'Phím bấm hộ')
            $cbKeys.Visible = $true
            $cbKeys.Items.Clear()
            foreach ($p in $KeyPresets) { [void]$cbKeys.Items.Add($p[1]) }
            $idx = -1
            for ($i = 0; $i -lt $KeyPresets.Count; $i++) { if ($KeyPresets[$i][0] -ceq "$($k.keys)") { $idx = $i } }
            if ($idx -lt 0 -and $k.keys) { [void]$cbKeys.Items.Add((T 'Other: ' 'Khác: ') + "$($k.keys)"); $idx = $cbKeys.Items.Count - 1 }
            $cbKeys.SelectedIndex = $idx
        }
        'open' {
            $lblDyn.Text = (T 'App' 'Ứng dụng')
            $cbApp.Visible = $true
            $cbApp.SelectedIndex = -1
            for ($i = 0; $i -lt $Apps.Count; $i++) { if ("$($k.match)" -eq $Apps[$i].match) { $cbApp.SelectedIndex = $i } }
        }
        'mic' {
            $lblDyn.Text = (T 'How it works' 'Cách dùng')
            $lblHint.Visible = $true
            $lblHint.Location = P 154 4
            $lblHint.Size = Z 370 100
            $lblHint.Text = (T "Press 1: the app's own mic starts (yellow = connecting, red = speak).`r`nPress 2: stop. The text stays in the chat box for you to edit - nothing is sent.`r`nPressing Send while you talk stops the mic and sends the text." "Bấm lần 1: micro của app bật (vàng = đang kết nối, đỏ = nói đi).`r`nBấm lần 2: dừng. Chữ nằm sẵn trong ô để bạn sửa, chưa gửi.`r`nBấm Send khi đang nói: dừng micro rồi gửi luôn.")
            return
        }
        default { $lblDyn.Visible = $false }
    }
    $lblHint.Location = P 154 40
    $lblHint.Size = Z 370 48
}

function Show-Key {
    $k = Get-Cur
    $script:loading = $true
    $grp.Enabled = [bool]$k
    if ($k) {
        $txtLabel.Text = "$($k.label)"
        $cbIcon.SelectedIndex = -1
        for ($i = 0; $i -lt $Icons.Count; $i++) { if ($Icons[$i][0] -eq "$($k.glyph)") { $cbIcon.SelectedIndex = $i } }
        $btnImg.Text = if ($k.icon) { (T 'Image: ' 'Ảnh: ') + [System.IO.Path]::GetFileName("$($k.icon)") } else { (T 'Use my image...' 'Dùng ảnh riêng...') }
        Set-ColorButton $k
        $cbAction.SelectedIndex = -1
        for ($i = 0; $i -lt $Actions.Count; $i++) { if ($Actions[$i][0] -eq "$($k.action)") { $cbAction.SelectedIndex = $i } }
        Show-Panel "$($k.action)" $k
        $chkWide.Checked = [bool]$k.wide
        $txtHot.Text = "$($k.hotkey)"
        $cbNum.SelectedIndex = [math]::Max(0, [array]::IndexOf($NumKeys, "$($k.numpad)"))
    }
    $script:loading = $false
}

function Mark-Dirty { $script:dirty = $true; $lblStatus.Text = (T 'Unsaved changes.' 'Có thay đổi chưa lưu.'); $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange }

# ---- sự kiện ----------------------------------------------------------------
$lb.Add_SelectedIndexChanged({ if (-not $script:loading) { Show-Key } })

$txtLabel.Add_TextChanged({
    if ($script:loading) { return }
    $k = Get-Cur; if (-not $k) { return }
    Set-Prop $k 'label' $txtLabel.Text
    $script:loading = $true
    $lb.Items[$lb.SelectedIndex] = (Get-KeyTitle $k)
    $script:loading = $false
    Mark-Dirty
})

$cbIcon.Add_SelectedIndexChanged({
    if ($script:loading -or $cbIcon.SelectedIndex -lt 0) { return }
    $k = Get-Cur; if (-not $k) { return }
    Set-Prop $k 'glyph' $Icons[$cbIcon.SelectedIndex][0]
    Set-Prop $k 'icon' $null
    $btnImg.Text = (T 'Use my image...' 'Dùng ảnh riêng...')
    Mark-Dirty
})

$btnImg.Add_Click({
    $k = Get-Cur; if (-not $k) { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = (T 'Pick an image for this key (a transparent PNG looks best)' 'Chọn ảnh cho phím (PNG nền trong suốt là đẹp nhất)')
    $dlg.Filter = (T 'Images' 'Ảnh') + '|*.png;*.jpg;*.jpeg;*.ico;*.bmp'
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    $dir = Join-Path $here 'icons'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $name = [System.IO.Path]::GetFileName($dlg.FileName)
    $dest = Join-Path $dir $name
    if ($dlg.FileName -ne $dest) { Copy-Item -LiteralPath $dlg.FileName -Destination $dest -Force }
    Set-Prop $k 'icon' ("icons\" + $name)
    $btnImg.Text = (T 'Image: ' 'Ảnh: ') + $name
    Mark-Dirty
})

$btnColor.Add_Click({
    $k = Get-Cur; if (-not $k) { return }
    $dlg = New-Object System.Windows.Forms.ColorDialog
    $dlg.FullOpen = $true
    if ($k.color) { try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml("$($k.color)") } catch {} }
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    $c = $dlg.Color
    Set-Prop $k 'color' ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
    Set-ColorButton $k
    Mark-Dirty
})
$btnColorReset.Add_Click({ $k = Get-Cur; if ($k) { Set-Prop $k 'color' $null; Set-ColorButton $k; Mark-Dirty } })

$cbAction.Add_SelectedIndexChanged({
    if ($script:loading -or $cbAction.SelectedIndex -lt 0) { return }
    $k = Get-Cur; if (-not $k) { return }
    $new = $Actions[$cbAction.SelectedIndex][0]
    if ($new -eq 'mic') {
        $other = @($script:KeyList | Where-Object { $_ -ne $k -and $_.action -eq 'mic' })
        if ($other.Count -gt 0) {
            [void][System.Windows.Forms.MessageBox]::Show($form, (T 'The pad can have only one microphone key. Edit the existing one.' 'Pad chỉ nên có 1 phím micro. Hãy sửa phím micro đang có.'), 'MicnKey Deck')
            Show-Key; return
        }
        if (-not $k.apps)       { Set-Prop $k 'apps' 'claude|chatgpt' }
        if (-not $k.micProcess) { Set-Prop $k 'micProcess' 'claude|openai|chatgpt' }
        if (-not $k.patterns)   { Set-Prop $k 'patterns' @('^(stop|finish|end|done) dictation', '^starting dictation', '^dictate$', '^(start )?dictation$', '^(use )?microphone$', '^mic$') }
    }
    if ($new -eq 'folder' -and -not $k.path) { Set-Prop $k 'path' '%DOCUMENTS%' }
    if ($new -eq 'keys'   -and -not $k.keys) { Set-Prop $k 'keys' '{ENTER}' }
    if ($new -eq 'open'   -and -not $k.match) { $a = $Apps[0]; Set-Prop $k 'match' $a.match; Set-Prop $k 'launch' $a.launch; Set-Prop $k 'launchArgs' $null; Set-Prop $k 'web' $a.web }
    Set-Prop $k 'action' $new
    $script:loading = $true
    Show-Panel $new $k
    $lb.Items[$lb.SelectedIndex] = (Get-KeyTitle $k)
    $script:loading = $false
    Mark-Dirty
})

$txtPath.Add_TextChanged({ if (-not $script:loading) { $k = Get-Cur; if ($k) { Set-Prop $k 'path' $txtPath.Text; Mark-Dirty } } })
$txtText.Add_TextChanged({ if (-not $script:loading) { $k = Get-Cur; if ($k) { Set-Prop $k 'text' $txtText.Text; Mark-Dirty } } })

$btnBrowse.Add_Click({
    $k = Get-Cur; if (-not $k) { return }
    if ($k.action -eq 'folder') {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = (T 'Pick a folder for this key' 'Chọn thư mục cho phím này')
        $cur = [Environment]::ExpandEnvironmentVariables((("$($k.path)" -replace '(?i)%DOCUMENTS%', [Environment]::GetFolderPath('MyDocuments')) -replace '(?i)%DESKTOP%', [Environment]::GetFolderPath('Desktop')))
        if (Test-Path -LiteralPath $cur) { $dlg.SelectedPath = $cur }
        if ($dlg.ShowDialog($form) -eq 'OK') { $txtPath.Text = $dlg.SelectedPath }
    } else {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = (T 'Pick a file or app' 'Chọn file hoặc ứng dụng')
        $dlg.Filter = (T 'All files' 'Tất cả') + '|*.*'
        if ($dlg.ShowDialog($form) -eq 'OK') { $txtPath.Text = $dlg.FileName }
    }
})

$cbKeys.Add_SelectedIndexChanged({
    if ($script:loading -or $cbKeys.SelectedIndex -lt 0) { return }
    $k = Get-Cur; if (-not $k) { return }
    if ($cbKeys.SelectedIndex -lt $KeyPresets.Count) { Set-Prop $k 'keys' $KeyPresets[$cbKeys.SelectedIndex][0]; Mark-Dirty }
})

$cbApp.Add_SelectedIndexChanged({
    if ($script:loading -or $cbApp.SelectedIndex -lt 0) { return }
    $k = Get-Cur; if (-not $k) { return }
    $a = $Apps[$cbApp.SelectedIndex]
    Set-Prop $k 'match' $a.match; Set-Prop $k 'launch' $a.launch; Set-Prop $k 'launchArgs' $null; Set-Prop $k 'web' $a.web
    Mark-Dirty
})

$chkWide.Add_CheckedChanged({ if (-not $script:loading) { $k = Get-Cur; if ($k) { Set-Prop $k 'wide' $chkWide.Checked; Mark-Dirty } } })

$txtHot.Add_KeyDown({
    param($s, $e)
    $e.SuppressKeyPress = $true
    $k = Get-Cur; if (-not $k) { return }
    if ($e.KeyCode -in @('ControlKey','Menu','ShiftKey','LWin','RWin')) { return }
    if ($e.KeyCode -in @('Back','Delete') -and -not $e.Control -and -not $e.Alt) { $txtHot.Text = ''; Set-Prop $k 'hotkey' $null; Mark-Dirty; return }
    $isF = ($e.KeyCode.ToString() -match '^F([1-9]|1[0-9]|2[0-4])$') -or ($e.KeyCode -in @('Pause','Scroll','Insert'))
    if (-not $e.Control -and -not $e.Alt -and -not $isF) { $lblHotHint.Text = (T 'Use Ctrl/Alt + a key, or F1-F24 / Pause alone' 'Dùng Ctrl/Alt + phím, hoặc F1-F24 / Pause riêng'); $lblHotHint.ForeColor = [System.Drawing.Color]::DarkOrange; return }
    $parts = @()
    if ($e.Control) { $parts += 'Ctrl' }
    if ($e.Alt)     { $parts += 'Alt' }
    if ($e.Shift)   { $parts += 'Shift' }
    $parts += $e.KeyCode.ToString()
    $spec = $parts -join '+'
    $dup = @($script:KeyList | Where-Object { $_ -ne $k -and "$($_.hotkey)" -eq $spec })
    if ($dup.Count -gt 0) { $lblHotHint.Text = (T 'Already used by key: ' 'Phím tắt này đã dùng cho phím: ') + "$($dup[0].label)"; $lblHotHint.ForeColor = [System.Drawing.Color]::DarkOrange; return }
    $txtHot.Text = $spec
    Set-Prop $k 'hotkey' $spec
    $lblHotHint.Text = (T 'Click the box, then press e.g. F9 or Ctrl + Alt + D' 'Bấm vào ô rồi nhấn, ví dụ F9 hoặc Ctrl + Alt + D')
    $lblHotHint.ForeColor = [System.Drawing.Color]::DimGray
    Mark-Dirty
})
$btnHotClear.Add_Click({ $k = Get-Cur; if ($k) { $txtHot.Text = ''; Set-Prop $k 'hotkey' $null; Mark-Dirty } })

$btnAdd.Add_Click({
    $n = [pscustomobject]@{ label = (T 'New key' 'Phím mới'); glyph = 'E8B7'; action = 'folder'; path = '%DOCUMENTS%' }
    $pos = if ($lb.SelectedIndex -ge 0) { $lb.SelectedIndex + 1 } else { $script:KeyList.Count }
    # phím micro rộng nên để cuối; phím mới chèn trước nó
    $micIdx = -1
    for ($i = 0; $i -lt $script:KeyList.Count; $i++) { if ($script:KeyList[$i].action -eq 'mic') { $micIdx = $i } }
    if ($micIdx -ge 0 -and $pos -gt $micIdx) { $pos = $micIdx }
    $script:KeyList.Insert($pos, $n)
    Update-List $pos
    $txtLabel.Focus(); $txtLabel.SelectAll()
    Mark-Dirty
})
$btnDel.Add_Click({
    $k = Get-Cur; if (-not $k) { return }
    $r = [System.Windows.Forms.MessageBox]::Show($form, ((T 'Delete key: ' 'Xóa phím: ') + "$($k.label)?"), 'MicnKey Deck', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $i = $lb.SelectedIndex
    $script:KeyList.RemoveAt($i)
    Update-List $i
    Mark-Dirty
})
function Move-Key([int]$d) {
    $i = $lb.SelectedIndex; $j = $i + $d
    if ($i -lt 0 -or $j -lt 0 -or $j -ge $script:KeyList.Count) { return }
    $t = $script:KeyList[$i]; $script:KeyList[$i] = $script:KeyList[$j]; $script:KeyList[$j] = $t
    Update-List $j
    Mark-Dirty
}
$btnUp.Add_Click({ Move-Key -1 })
$btnDown.Add_Click({ Move-Key 1 })

foreach ($c in @($tbOpacity, $numSize, $numCols)) { $c.Add_ValueChanged({ if (-not $script:loading) { Mark-Dirty } }) }
$chkAuto.Add_CheckedChanged({ if (-not $script:loading) { Mark-Dirty } })
$cbLang.Add_SelectedIndexChanged({ if (-not $script:loading) { Mark-Dirty } })
$cbLayer.Add_SelectedIndexChanged({ if (-not $script:loading) { Mark-Dirty } })
$cbNum.Add_SelectedIndexChanged({
    if ($script:loading) { return }
    $k = Get-Cur; if (-not $k) { return }
    $n = $NumKeys[$cbNum.SelectedIndex]
    if ($n) {
        $dup = @($script:KeyList | Where-Object { $_ -ne $k -and "$($_.numpad)" -eq $n })
        if ($dup.Count -gt 0) {
            $lblNumHint.Text = (T 'already used by: ' 'đã dùng cho: ') + "$($dup[0].label)"; $lblNumHint.ForeColor = [System.Drawing.Color]::DarkOrange
            $script:loading = $true; $cbNum.SelectedIndex = [math]::Max(0, [array]::IndexOf($NumKeys, "$($k.numpad)")); $script:loading = $false
            return
        }
    }
    $lblNumHint.Text = (T 'used in AI keys mode' 'dùng khi bật chế độ AI'); $lblNumHint.ForeColor = [System.Drawing.Color]::DimGray
    Set-Prop $k 'numpad' $n
    Mark-Dirty
})

# ---- lưu ---------------------------------------------------------------------
function Save-Config {
    foreach ($k in $script:KeyList) {
        if (-not "$($k.label)".Trim()) { [void][System.Windows.Forms.MessageBox]::Show($form, (T 'Every key needs a label.' 'Có phím chưa có chữ. Hãy đặt tên cho mọi phím.'), 'MicnKey Deck'); return $false }
        if ($k.action -in @('folder','run') -and -not "$($k.path)".Trim()) {
            [void][System.Windows.Forms.MessageBox]::Show($form, ((T 'Choose what this key opens: ' 'Phím chưa chọn cần mở cái gì: ') + "$($k.label)"), 'MicnKey Deck'); return $false
        }
    }
    $out = [ordered]@{}
    foreach ($p in $cfg.PSObject.Properties) { if ($p.Name -ne 'keys') { $out[$p.Name] = $p.Value } }
    $out['keySize']   = [int]$numSize.Value
    $out['columns']   = [int]$numCols.Value
    $out['opacity']   = [math]::Round($tbOpacity.Value / 100.0, 2)
    $out['autostart'] = [bool]$chkAuto.Checked
    $out['layerToggle'] = $LayerKeys[[math]::Max(0, $cbLayer.SelectedIndex)]
    $out['language']  = if ($cbLang.SelectedIndex -eq 1) { 'vi' } else { 'en' }
    $out['keys']      = @($script:KeyList.ToArray())
    $json = $out | ConvertTo-Json -Depth 8
    try {
        Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $here 'config.backup.json') -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($cfgPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($form, ((T 'Could not save: ' 'Không lưu được: ') + $_.Exception.Message), 'MicnKey Deck'); return $false
    }
    Write-Log "saved $($script:KeyList.Count) keys"
    $script:dirty = $false
    $lblStatus.Text = (T 'Saved. The pad is updating...' 'Đã lưu. Pad đang cập nhật...')
    $lblStatus.ForeColor = [System.Drawing.Color]::SeaGreen
    return $true
}
$btnSave.Add_Click({
    $newLang = if ($cbLang.SelectedIndex -eq 1) { 'vi' } else { 'en' }
    if ((Save-Config) -and $newLang -ne $script:lang) {
        $script:relaunch = $true
        $form.Close()
    }
})
$btnClose.Add_Click({ $form.Close() })
$form.Add_FormClosing({
    param($s, $e)
    if ($script:dirty) {
        $r = [System.Windows.Forms.MessageBox]::Show($form, (T 'Save changes before closing?' 'Lưu thay đổi trước khi đóng?'), 'MicnKey Deck', 'YesNoCancel', 'Question')
        if ($r -eq 'Cancel') { $e.Cancel = $true; return }
        if ($r -eq 'Yes' -and -not (Save-Config)) { $e.Cancel = $true }
    }
})

Update-List 0
$lblStatus.Text = (T 'Pick a key on the left to edit it.' 'Chọn một phím bên trái để sửa.')
Write-Log 'opened'
[void]$form.ShowDialog()
$mutex.ReleaseMutex()
if ($script:relaunch) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $here 'Settings.ps1')`""
}
