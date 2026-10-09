#Requires AutoHotkey v2.0
#SingleInstance Force
; SkillSnap - auto skillcheck for the extraction minigame:
; finds the yellow ring on screen and presses Space
; right as the shrinking red ring reaches the yellow zone.

Version  := "1.1.0"
RepoUrl  := "https://github.com/brageat/skillsnap"

CoordMode "Pixel", "Screen"
SetKeyDelay -1
ProcessSetPriority "High"

YellowColor := 0xF8A905, YellowVar := 30
RedColor    := 0xA00008, RedVar    := 0x40
; default (bar) skillcheck
BarYellow   := 0xF9C12C, BarYellowVar := 20
MarkerColor := 0xF1445A, MarkerVar    := 40

; ---------- saved settings ----------
IniFile := A_ScriptDir "\SkillSnap.ini"
ToggleKey    := IniRead(IniFile, "Settings", "ToggleKey", "F6")
LatencyMs    := Integer(IniRead(IniFile, "Settings", "LatencyMs", 45))
OnTop        := IniRead(IniFile, "Settings", "OnTop", 0) = 1
ShowHud      := IniRead(IniFile, "Settings", "ShowHud", 1) = 1
HudPos       := IniRead(IniFile, "Settings", "HudPos", "Top-right")
HudPositions := ["Top-left", "Top-right", "Bottom-left", "Bottom-right"]
DarkMode     := IniRead(IniFile, "Settings", "DarkMode", 1) = 1

global Active := false
; stats
global Clicks := 0, Seen := 0, Missed := 0, LastSpeed := 0, ActiveMs := 0, ActiveSince := 0
BaseSpeed := 0.24 / 2160                 ; normal ring speed (fraction of screen height per ms)
BarBaseSpeed := 0.58 / 2160              ; normal bar marker speed

; ---------- menu ----------
G := Gui("-MaximizeBox", "SkillSnap")
G.SetFont("s10", "Segoe UI")
G.OnEvent("Close", (*) => ExitApp())

G.SetFont("s16 bold")
StatusTxt := G.AddText("w260 Center cRed", "OFF")
G.SetFont("s10 norm")
StartBtn := G.AddButton("w260 h34", "Start")
StartBtn.OnEvent("Click", ToggleBot)

G.AddGroupBox("w260 h62 Section", "Toggle key")
KeyBox := G.AddEdit("xs+10 ys+24 w120 ReadOnly Center", ToggleKey)
SetBtn := G.AddButton("x+8 yp-1 w110", "Change key")
SetBtn.OnEvent("Click", CaptureKey)


G.AddGroupBox("xs w260 h96 Section", "Timing")
TimingTxt := G.AddText("xs+10 ys+22 w240", "")
TimingSl := G.AddSlider("xs+10 y+4 w240 Range0-150 ToolTip", LatencyMs)
G.SetFont("s8")
G.AddText("xs+10 y+0 w120", "◄ later")
G.AddText("x+0 w120 Right", "earlier ►")
G.SetFont("s10")
TimingSl.OnEvent("Change", (*) => (UpdateTimingText(), SaveSettings()))

TopCb := G.AddCheckbox("xs Checked" OnTop, "Always on top")
TopCb.OnEvent("Click", (*) => (G.Opt((TopCb.Value ? "+" : "-") "AlwaysOnTop"), SaveSettings()))
DarkCb := G.AddCheckbox("x+30 yp Checked" DarkMode, "Dark mode")
DarkCb.OnEvent("Click", (*) => (SaveSettings(), Reload()))

G.AddGroupBox("xs w260 h90 Section", "HUD")
HudCb := G.AddCheckbox("xs+10 ys+24 Checked" ShowHud, "Show stats HUD")
HudDd := G.AddDropDownList("xs+10 y+8 w140", HudPositions)
HudDd.Text := HudPos
ResetBtn := G.AddButton("x+8 yp-1 w82", "Reset stats")
HudCb.OnEvent("Click", (*) => (PlaceHud(), SaveSettings()))
HudDd.OnEvent("Change", (*) => (PlaceHud(), SaveSettings()))
ResetBtn.OnEvent("Click", ResetStats)

G.SetFont("s8 cGray")
NoteTxt := G.AddText("xs w260", "Run Roblox windowed / borderless fullscreen.")
VersionLink := G.AddLink("xs w260", "v" Version " · Checking for updates...")
VersionLink.OnEvent("Click", (*) => Run(RepoUrl "/releases/latest"))
G.SetFont("s10 cDefault")

if OnTop
    G.Opt("+AlwaysOnTop")
if DarkMode
    ApplyDarkMode(G)
UpdateTimingText()
RegisterKey(ToggleKey)
G.Show()

; ---------- mini HUD (click-through overlay) ----------
Hud := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "SkillSnap HUD")
Hud.BackColor := "15181D"
Hud.MarginX := 10, Hud.MarginY := 8
Hud.SetFont("s10 bold cRed", "Consolas")
HudStatus := Hud.AddText("w200", "● BOT OFF")
Hud.SetFont("s9 norm cE6E6E6")
HudBody := Hud.AddText("w200 r5", "")
WinSetTransparent 215, Hud
UpdateHud()
PlaceHud()
SetTimer UpdateHud, 1000

PlaceHud() {
    if !HudCb.Value {
        Hud.Hide()
        return
    }
    Hud.Show("NoActivate AutoSize")
    ; WinGetPos/WinMove use real pixels (Hud.Move would apply DPI scaling)
    ; (AHK names are case-insensitive, so don't mix w/W or h/H)
    WinGetPos(, , &hudW, &hudH, Hud)
    scrW := A_ScreenWidth, scrH := A_ScreenHeight
    pos := HudDd.Text
    x := InStr(pos, "left") ? 12 : scrW - hudW - 12
    y := InStr(pos, "Top") ? Round(scrH * 0.12) : scrH - hudH - Round(scrH * 0.22)
    WinMove x, y, , , Hud
}

UpdateHud() {
    secs := (ActiveMs + (Active ? A_TickCount - ActiveSince : 0)) // 1000
    HudBody.Value := "Presses:      " Clicks "`n"
                   . "Skillchecks:  " Seen "`n"
                   . "Missed:       " Missed "`n"
                   . "Speed:        " (LastSpeed ? Format("{:.1f}x", LastSpeed) : "-") "`n"
                   . "Run time:     " Format("{:02}:{:02}", secs // 60, Mod(secs, 60))
}

ResetStats(*) {
    global Clicks := 0, Seen := 0, Missed := 0, LastSpeed := 0, ActiveMs := 0
    global ActiveSince := A_TickCount
    UpdateHud()
}

; ---------- update check ----------
SetTimer CheckForUpdate, -1500           ; after the menu has appeared

CheckForUpdate() {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("GET", "https://api.github.com/repos/brageat/skillsnap/releases/latest", false)
        req.SetRequestHeader("User-Agent", "SkillSnap")
        req.Send()
        if (req.Status != 200 || !RegExMatch(req.ResponseText, '"tag_name"\s*:\s*"v?([\d.]+)"', &m))
            throw Error("bad response")
        latest := m[1]
    } catch {
        VersionLink.Text := "v" Version " · Couldn't check for updates (<a>open page</a>)"
        return
    }
    if (CompareVersions(latest, Version) <= 0) {
        VersionLink.Text := "v" Version " · Up to date"
        return
    }
    VersionLink.Text := "v" Version " · <a>Update available: v" latest " - download</a>"
    if MsgBox("A new version of SkillSnap is available!`n`n"
            . "You have:  v" Version "`nNewest:    v" latest "`n`n"
            . "Open the download page?", "SkillSnap update", "YesNo Iconi Owner" G.Hwnd) = "Yes"
        Run RepoUrl "/releases/latest"
}

; Returns >0 if a is newer than b, <0 if older, 0 if equal ("1.2.0" style).
CompareVersions(a, b) {
    pa := StrSplit(a, "."), pb := StrSplit(b, ".")
    loop Max(pa.Length, pb.Length) {
        x := A_Index <= pa.Length ? Integer(pa[A_Index]) : 0
        y := A_Index <= pb.Length ? Integer(pb[A_Index]) : 0
        if (x != y)
            return x - y
    }
    return 0
}

; ---------- menu logic ----------
ApplyDarkMode(g) {
    g.BackColor := "1E1F22"
    ; dark title bar (attribute 20 on newer Windows 10/11, 19 on older builds)
    if DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 20, "Int*", 1, "Int", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 19, "Int*", 1, "Int", 4)
    for ctl in g {
        switch ctl.Type, false {
            case "Button":
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
            case "DDL", "Edit":
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctl.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)
                ctl.Opt("Background2B2D31")
                ctl.SetFont("cE6E6E6")
            case "CheckBox", "GroupBox":
                ; themed checkboxes/groupboxes ignore text color, so drop the theme
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctl.Hwnd, "Str", "", "Str", "")
                ctl.SetFont("cE6E6E6")
            case "Text":
                if (ctl != StatusTxt)
                    ctl.SetFont(ctl = NoteTxt ? "c8A8A8A" : "cE6E6E6")
            case "Link":
                ctl.SetFont("c8A8A8A")
        }
    }
}

UpdateTimingText() {
    TimingTxt.Value := "Press " TimingSl.Value " ms ahead (default 45)"
}

SaveSettings() {
    IniWrite ToggleKey, IniFile, "Settings", "ToggleKey"
    IniWrite TimingSl.Value, IniFile, "Settings", "LatencyMs"
    IniWrite TopCb.Value, IniFile, "Settings", "OnTop"
    IniWrite HudCb.Value, IniFile, "Settings", "ShowHud"
    IniWrite HudDd.Text, IniFile, "Settings", "HudPos"
    IniWrite DarkCb.Value, IniFile, "Settings", "DarkMode"
}

; "*" = still fires while Shift/Ctrl/Alt are held (e.g. sprinting); it also uses
; the keyboard hook, which works more reliably while a game has focus.
RegisterKey(key) {
    try {
        Hotkey "*" key, ToggleBot, "On"
        return true
    } catch {
        MsgBox "Can't use '" key "' as a hotkey.", "SkillSnap", "Icon!"
        return false
    }
}

; Waits for the next key press and makes it the toggle key (Esc cancels).
CaptureKey(*) {
    global ToggleKey
    try Hotkey "*" ToggleKey, "Off"          ; so pressing the old key doesn't toggle the bot
    SetBtn.Text := "Press a key..."
    SetBtn.Enabled := false
    KeyBox.Value := "..."
    ih := InputHook("L0 T8")
    ih.KeyOpt("{All}", "E")
    ih.Start()
    ih.Wait()
    newKey := ih.EndKey
    if (ih.EndReason = "EndKey" && newKey != "Escape" && RegisterKey(newKey)) {
        ToggleKey := newKey
        SaveSettings()
    } else {
        RegisterKey(ToggleKey)
    }
    KeyBox.Value := ToggleKey
    SetBtn.Text := "Change key"
    SetBtn.Enabled := true
}

ToggleBot(*) {
    global Active := !Active, ActiveMs, ActiveSince
    if Active
        ActiveSince := A_TickCount
    else
        ActiveMs += A_TickCount - ActiveSince
    StatusTxt.Value := Active ? "ON" : "OFF"
    StatusTxt.SetFont(Active ? "cGreen" : "cRed")
    StartBtn.Text := Active ? "Stop" : "Start"
    HudStatus.Value := Active ? "● BOT ON" : "● BOT OFF"
    HudStatus.SetFont(Active ? "c3DDC84" : "cRed")
    UpdateHud()
    SetTimer Scan, Active ? 15 : 0
}

; ---------- bot ----------
Scan() {
    if !Active
        return
    if FindRing(&cx, &cy, &r)
        DoRing(cx, cy, r)
    else if FindBar(&zl, &zr, &row)
        DoBar(zl, zr, row)
}

; Records the result of one skillcheck in the HUD stats.
CountCheck(pressed, speed, baseSpeed) {
    global Clicks, Seen, Missed, LastSpeed
    Seen++
    if pressed {
        Clicks++
        if speed
            LastSpeed := speed / (A_ScreenHeight * baseSpeed)
    } else if Active {
        Missed++
    }
    UpdateHud()
}

; ----- circle skillcheck: red ring shrinks onto the yellow ring -----
DoRing(cx, cy, r) {

    ; Track the red ring's radius and speed, then press LatencyMs before it
    ; reaches the yellow ring - this adapts to any skillcheck speed.
    target := r * 0.97                   ; red outer edge sitting on the yellow
    maxR := Round(r * 4.2)
    speed := 0, prevT := 0, prevR := 0
    pressed := false
    deadline := A_TickCount + 6000
    while Active && A_TickCount < deadline {
        t := Now()
        rr := RedRadius(cx, cy, maxR)
        if (rr < 0) {
            ; no red visible; if the yellow is gone too, the check is over
            if !PixelSearch(&_, &_, cx - r, cy - r - 2, cx + r, cy - r + 6, YellowColor, YellowVar)
                break
            continue
        }
        if (prevT = 0) {
            prevT := t, prevR := rr
        } else if (t - prevT >= 25) {
            v := (prevR - rr) / (t - prevT)      ; px per ms, positive = shrinking
            if (v > 0.005)
                speed := speed ? speed * 0.4 + v * 0.6 : v
            prevT := t, prevR := rr
        }
        if (rr <= target || (speed > 0 && (rr - target) / speed <= TimingSl.Value)) {
            Press()
            pressed := true
            break
        }
    }
    CountCheck(pressed, speed, BaseSpeed)
    ; Wait for this ring to disappear so we don't press it twice
    deadline := A_TickCount + 2500
    while A_TickCount < deadline && PixelSearch(&_, &_, cx - r, cy - r - 2, cx + r, cy - r + 6, YellowColor, YellowVar)
        Sleep 20
}

; ----- bar skillcheck: red marker slides right into the yellow zone -----
DoBar(zl, zr, row) {
    scrH := A_ScreenHeight
    target := (zl + zr) / 2                          ; aim the marker's center at the zone's center
    halfMarker := scrH * 0.0025
    searchL := Max(0, Round(zl - scrH * 0.6)), searchR := Round(zr + scrH * 0.02)
    speed := 0, prevT := 0, prevX := 0
    pressed := false
    deadline := A_TickCount + 6000
    while Active && A_TickCount < deadline {
        t := Now()
        if !PixelSearch(&mx, &_, searchL, row, searchR, row, MarkerColor, MarkerVar) {
            ; no marker; if the zone is gone too, the check is over
            if !PixelSearch(&_, &_, zl, row, zr, row, BarYellow, BarYellowVar)
                break
            continue
        }
        mc := mx + halfMarker
        if (prevT = 0) {
            prevT := t, prevX := mc
        } else if (t - prevT >= 25) {
            v := (mc - prevX) / (t - prevT)          ; px per ms, positive = moving right
            if (v > 0.01)
                speed := speed ? speed * 0.4 + v * 0.6 : v
            prevT := t, prevX := mc
        }
        if (mc >= target || (speed > 0 && (target - mc) / speed <= TimingSl.Value)) {
            Press()
            pressed := true
            break
        }
    }
    CountCheck(pressed, speed, BarBaseSpeed)
    ; Wait for this bar to disappear so we don't press it twice
    deadline := A_TickCount + 2500
    while A_TickCount < deadline && PixelSearch(&_, &_, zl, row, zr, row, BarYellow, BarYellowVar)
        Sleep 20
}

; Locates the bar's yellow zone: returns its left/right x and the row through the bar's middle.
FindBar(&zl, &zr, &row) {
    scrW := A_ScreenWidth, scrH := A_ScreenHeight
    startY := 0
    loop 12 {
        if !PixelSearch(&tx, &ty, 0, startY, scrW - 1, scrH - 1, BarYellow, BarYellowVar)
            return false
        startY := ty + Round(scrH * 0.01) + 1
        ; the bar slides in from below; wait until it stops moving
        loop 8 {
            Sleep 40
            if !PixelSearch(&_, &ty2, tx - 2, ty - Round(scrH * 0.04), tx + 2, ty + Round(scrH * 0.04), BarYellow, BarYellowVar)
                break
            if (ty2 = ty)
                break
            ty := ty2
        }
        row := ty + Round(scrH * 0.024)
        span := Round(scrH * 0.05)
        if !PixelSearch(&zl, &_, tx - span, row, tx + span, row, BarYellow, BarYellowVar)
            continue
        if !PixelSearch(&zr, &_, tx + span, row, tx - span, row, BarYellow, BarYellowVar)
            continue
        zoneW := zr - zl
        if (zoneW < scrH * 0.008 || zoneW > scrH * 0.035)
            continue
        ; the yellow zone sits between two light-grey parts
        gap := Round(scrH * 0.008)
        if !IsLightGrey(PixelGetColor(zl - gap, row)) || !IsLightGrey(PixelGetColor(zr + gap, row))
            continue
        return true
    }
    return false
}

IsLightGrey(c) {
    r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
    return r > 0x90 && g > 0x90 && b > 0x90 && Abs(r - b) < 0x20 && Abs(r - g) < 0x20
}

; Distance from the center to the outermost red pixel (searching inward from the right), or -1.
RedRadius(cx, cy, maxR) {
    if PixelSearch(&x, &_, cx + maxR, cy, cx, cy, RedColor, RedVar)
        return x - cx
    return -1
}

; High-resolution time in ms (A_TickCount is only ~15 ms accurate).
Now() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c * 1000 / freq
}

Press() {
    Send "{Space down}"
    Sleep 25
    Send "{Space up}"
}

; Locates the yellow ring: returns center (cx, cy) and outer radius r.
FindRing(&cx, &cy, &r) {
    scrW := A_ScreenWidth, scrH := A_ScreenHeight
    d := Round(scrH * 0.09)                 ; search box larger than any ring
    startY := 0
    loop 12 {
        if !PixelSearch(&tx, &ty, 0, startY, scrW - 1, scrH - 1, YellowColor, YellowVar)
            return false
        startY := ty + Round(scrH * 0.01) + 1
        ; bottom edge (search upward from below)
        if !PixelSearch(&_, &by, tx - d, ty + d, tx + d, ty, YellowColor, YellowVar)
            continue
        midY := (ty + by) // 2
        ; left edge and right edge on the middle row
        if !PixelSearch(&lx, &_, tx - d, midY - 1, tx + d, midY + 1, YellowColor, YellowVar)
            continue
        if !PixelSearch(&rx, &_, tx + d, midY - 1, tx - d, midY + 1, YellowColor, YellowVar)
            continue
        ringW := rx - lx, ringH := by - ty
        ; must be roughly round and a sensible size
        if (ringH < scrH * 0.015 || ringH > scrH * 0.085 || Abs(ringW - ringH) > ringH * 0.2)
            continue
        cx := (lx + rx) // 2, cy := midY, r := Round((ringW + ringH) / 4)
        ; center of the ring is dark grey
        c := PixelGetColor(cx, cy)
        if ((c >> 16) & 0xFF) > 0x70 || ((c >> 8) & 0xFF) > 0x70 || (c & 0xFF) > 0x70
            continue
        return true
    }
    return false
}
