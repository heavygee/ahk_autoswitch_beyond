#Requires AutoHotkey v2.0

global CONFIG_FILE := A_ScriptDir "\autoswitch mic for VR.ini"
global APP_CONFIG := LoadConfig()
; Do NOT key off VirtualDesktop.Service.exe because it can run persistently as a service
; even when user is not actively using Virtual Desktop for VR streaming.
global VD_PROCESS_NAMES := ["VirtualDesktop.Streamer.exe", "VirtualDesktop.Server.exe"]
global IS_STANDDOWN := false
global BROADCAST_UI_PATH := "C:\Program Files\NVIDIA Corporation\NVIDIA Broadcast\NVIDIA Broadcast UI.exe"
global BROADCAST_VERSION_OK := true
global TRAY_STATUS_ITEM := "Status: Active"
if !FileExist(CONFIG_FILE) {
    SaveConfig(APP_CONFIG)
}

CheckNvidiaBroadcastVersion()
InitializeTrayMenu()

ResolveDeviceId(partialName, direction := "Render") {
    svvPath := A_ScriptDir "\SoundVolumeView.exe"
    if !FileExist(svvPath) {
        return ""
    }

    escapedTerm := StrReplace(partialName, "'", "''")
    escapedSvvPath := StrReplace(svvPath, "'", "''")
    csvPath := A_Temp "\svv-devices.csv"
    escapedCsvPath := StrReplace(csvPath, "'", "''")
    escapedDirection := StrReplace(direction, "'", "''")
    psCommand := "$svv = '" escapedSvvPath "'; " .
        "$csv = '" escapedCsvPath "'; " .
        "& $svv /scomma $csv /Columns 'Name,Device Name,Command-Line Friendly ID,Direction,Type,Device State'; " .
        "$rows = Import-Csv -Path $csv -ErrorAction SilentlyContinue; " .
        "$term = '" escapedTerm "'; " .
        "$dir = '" escapedDirection "'; " .
        "$match = $rows | Where-Object { " .
        "$normName = ($_.'Name' -replace '^\d+\s*-\s*',''); " .
        "$normDeviceName = ($_.'Device Name' -replace '^\d+\s*-\s*',''); " .
        "$normId = ($_.'Command-Line Friendly ID' -replace '^\d+\s*-\s*',''); " .
        "$_.'Type' -eq 'Device' -and $_.'Direction' -eq $dir -and (" .
        "$_.'Name' -like ('*' + $term + '*') -or " .
        "$_.'Device Name' -like ('*' + $term + '*') -or " .
        "$_.'Command-Line Friendly ID' -like ('*' + $term + '*') -or " .
        "$normName -like ('*' + $term + '*') -or " .
        "$normDeviceName -like ('*' + $term + '*') -or " .
        "$normId -like ('*' + $term + '*')" .
        ") } | Sort-Object @{Expression={ if($_.'Device State' -eq 'Active'){0}else{1} }}, Name | Select-Object -First 1; " .
        "if ($match) { $match.'Command-Line Friendly ID' }"
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(Format('{} /c powershell -NoProfile -Command "{}"', A_ComSpec, psCommand))
    deviceId := Trim(exec.StdOut.ReadAll(), "`r`n`t ")
    return deviceId
}

ResolveDeviceIdFromAliases(aliases, direction := "Render") {
    for _, alias in aliases {
        id := ResolveDeviceId(alias, direction)
        if (id != "") {
            return id
        }
    }
    return ""
}

LoadConfig() {
    cfg := {}
    cfg.CaptureAliases := ParseAliasList(IniRead(CONFIG_FILE, "Devices", "CaptureAliases", "NVIDIA Broadcast|Broadcast"))
    cfg.VrRenderAliases := ParseAliasList(IniRead(CONFIG_FILE, "Devices", "VrRenderAliases", "Beyond|YondBe|Strap"))
    cfg.DesktopRenderAliases := ParseAliasList(IniRead(CONFIG_FILE, "Devices", "DesktopRenderAliases", "SteelSeries Arctis 1 Wireless|Arctis 1 Wireless|SteelSeries"))
    cfg.BroadcastVrMicSource := IniRead(CONFIG_FILE, "Broadcast", "VrMicSourceContains", "Beyond")
    cfg.BroadcastDesktopMicSource := IniRead(CONFIG_FILE, "Broadcast", "DesktopMicSourceContains", "USB audio CODEC")
    return cfg
}

SaveConfig(cfg) {
    IniWrite(JoinAliasList(cfg.CaptureAliases), CONFIG_FILE, "Devices", "CaptureAliases")
    IniWrite(JoinAliasList(cfg.VrRenderAliases), CONFIG_FILE, "Devices", "VrRenderAliases")
    IniWrite(JoinAliasList(cfg.DesktopRenderAliases), CONFIG_FILE, "Devices", "DesktopRenderAliases")
    IniWrite(cfg.BroadcastVrMicSource, CONFIG_FILE, "Broadcast", "VrMicSourceContains")
    IniWrite(cfg.BroadcastDesktopMicSource, CONFIG_FILE, "Broadcast", "DesktopMicSourceContains")
}

ParseAliasList(value) {
    aliases := []
    for _, token in StrSplit(value, "|") {
        item := Trim(token)
        if (item != "") {
            aliases.Push(item)
        }
    }
    if (aliases.Length = 0) {
        aliases.Push(value)
    }
    return aliases
}

JoinAliasList(aliases) {
    output := ""
    for index, alias in aliases {
        if (index > 1) {
            output .= "|"
        }
        output .= alias
    }
    return output
}

BuildUniqueDeviceList(direction := "Render") {
    svvPath := A_ScriptDir "\SoundVolumeView.exe"
    if !FileExist(svvPath) {
        return []
    }
    csvPath := A_Temp "\svv-ui-devices.csv"
    try {
        RunWait(Format('"{}" /scomma "{}" /Columns "{}"', svvPath, csvPath, "Name,Device Name,Direction,Type"),, "Hide")
        rows := FileRead(csvPath)
    } catch Error as err {
        return []
    }
    devices := Map()
    for _, line in StrSplit(rows, "`n", "`r") {
        if (line = "" || InStr(line, "Name,Device Name,Direction,Type") = 1) {
            continue
        }
        cols := StrSplit(line, ",")
        if (cols.Length < 4) {
            continue
        }
        itemName := Trim(cols[1], '"')
        deviceName := Trim(cols[2], '"')
        itemDirection := Trim(cols[3], '"')
        itemType := Trim(cols[4], '"')
        if (itemType = "Device" && itemDirection = direction && deviceName != "") {
            devices[deviceName] := true
        } else if (itemType = "Device" && itemDirection = direction && itemName != "") {
            devices[itemName] := true
        }
    }
    list := []
    for name, _ in devices {
        list.Push(name)
    }
    return list
}

InitializeTrayMenu() {
    global TRAY_STATUS_ITEM
    A_TrayMenu.Add(TRAY_STATUS_ITEM, TrayStatusNoop)
    A_TrayMenu.Disable(TRAY_STATUS_ITEM)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Configure VR Audio Targets...", ShowConfigGui)
    A_TrayMenu.Add()
    UpdateStandDownState(true)
}

TrayStatusNoop(*) {
    ; Intentionally empty: status line is informational only.
}

IsVirtualDesktopRunning() {
    global VD_PROCESS_NAMES
    for _, procName in VD_PROCESS_NAMES {
        if ProcessExist(procName) {
            return true
        }
    }
    return false
}

UpdateStandDownState(force := false) {
    global IS_STANDDOWN, TRAY_STATUS_ITEM, BROADCAST_VERSION_OK
    newState := IsVirtualDesktopRunning()
    if (!force && newState = IS_STANDDOWN) {
        return
    }
    oldLabel := TRAY_STATUS_ITEM
    if (!BROADCAST_VERSION_OK) {
        TRAY_STATUS_ITEM := "Status: Unsupported NVIDIA Broadcast version"
        A_IconTip := "VR Audio Auto-Switch - UNSUPPORTED: requires NVIDIA Broadcast 1.4.x"
    } else if (newState) {
        TRAY_STATUS_ITEM := "Status: Stand-down (Virtual Desktop is running)"
        A_IconTip := "VR Audio Auto-Switch - STAND-DOWN (Virtual Desktop running)"
    } else {
        TRAY_STATUS_ITEM := "Status: Active"
        A_IconTip := "VR Audio Auto-Switch - Active"
    }
    try {
        A_TrayMenu.Rename(oldLabel, TRAY_STATUS_ITEM)
        A_TrayMenu.Disable(TRAY_STATUS_ITEM)
    }
    IS_STANDDOWN := newState
}

CheckNvidiaBroadcastVersion() {
    global BROADCAST_UI_PATH, BROADCAST_VERSION_OK
    version := GetInstalledNvidiaBroadcastVersion()
    if (version = "") {
        version := GetBroadcastProductVersionFromFile(BROADCAST_UI_PATH)
    }
    if !FileExist(BROADCAST_UI_PATH) {
        BROADCAST_VERSION_OK := false
        MsgBox "NVIDIA Broadcast UI executable was not found at:`n" BROADCAST_UI_PATH "`n`nThis tool requires NVIDIA Broadcast 1.4.x.", "NVIDIA Broadcast Requirement"
        return false
    }

    if !IsBroadcastVersionSupported(version) {
        BROADCAST_VERSION_OK := false
        MsgBox "Detected NVIDIA Broadcast version: " version "`n`nThis V2 tool currently supports NVIDIA Broadcast 1.4.x only.`nIf you need 2.1.0+, you are out of luck - this technique does not work with it.", "Unsupported NVIDIA Broadcast Version"
        return false
    }

    BROADCAST_VERSION_OK := true
    return true
}

IsBroadcastVersionSupported(version) {
    return (SubStr(version, 1, 4) = "1.4.")
}

GetInstalledNvidiaBroadcastVersion() {
    psCommand := "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | " .
        "Where-Object { $_.DisplayName -like 'NVIDIA Broadcast *' -and $_.DisplayVersion } | " .
        "Sort-Object DisplayVersion -Descending | Select-Object -First 1 -ExpandProperty DisplayVersion)"
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(Format('{} /c powershell -NoProfile -Command "{}"', A_ComSpec, psCommand))
    return Trim(exec.StdOut.ReadAll(), "`r`n`t ")
}

GetBroadcastProductVersionFromFile(filePath) {
    if !FileExist(filePath) {
        return ""
    }
    escapedPath := StrReplace(filePath, "'", "''")
    psCommand := "$v=[System.Diagnostics.FileVersionInfo]::GetVersionInfo('" escapedPath "'); $v.ProductVersion"
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(Format('{} /c powershell -NoProfile -Command "{}"', A_ComSpec, psCommand))
    return Trim(exec.StdOut.ReadAll(), "`r`n`t ")
}

ShowConfigGui(*) {
    global APP_CONFIG, BROADCAST_VERSION_OK
    renderDevices := BuildUniqueDeviceList("Render")
    captureDevices := BuildUniqueDeviceList("Capture")

    cfgGui := Gui("+AlwaysOnTop", "VR Audio Config")
    cfgGui.SetFont("s10", "Segoe UI")
    cfgGui.AddText("w780", "Pick what you want while in VR vs on desktop. Advanced alias tuning is behind 'Advanced...'.")
    if !BROADCAST_VERSION_OK {
        cfgGui.SetFont("s10 cRed Bold", "Segoe UI")
        cfgGui.AddText("w780 y+8", "NOT ACTIVE: This tool requires NVIDIA Broadcast 1.4.x. If you need 2.1.0+, this technique will not work.")
        cfgGui.SetFont("s10 cDefault Norm", "Segoe UI")
    }
    if IsVirtualDesktopRunning() {
        cfgGui.SetFont("s10 cRed Bold", "Segoe UI")
        cfgGui.AddText("w780 y+8", "NOT ACTIVE due to presence of Virtual Desktop which handles audio inputs/outputs in VR.")
        cfgGui.SetFont("s10 cDefault Norm", "Segoe UI")
    }

    leftX := 20
    rightX := 410
    topY := 44
    colW := 360
    groupY := topY + 40
    groupH := 210

    cfgGui.SetFont("s18", "Segoe UI Emoji")
    cfgGui.AddText(Format("x{} y{} w{} Center", leftX, topY, colW), "🥽 Audio in VR")
    cfgGui.AddText(Format("x{} y{} w{} Center", rightX, topY, colW), "🖥️ Audio on Desktop")

    cfgGui.SetFont("s10", "Segoe UI")
    cfgGui.AddGroupBox(Format("x{} y{} w{} h{}", leftX, groupY, colW, groupH), "")
    cfgGui.AddGroupBox(Format("x{} y{} w{} h{}", rightX, groupY, colW, groupH), "")

    cfgGui.AddText(Format("x{} y{} w{}", leftX + 14, groupY + 28, colW - 28), "Input (mic source in NVIDIA Broadcast)")
    vrInputPick := cfgGui.AddDropDownList(Format("x{} y{} w{}", leftX + 14, groupY + 50, colW - 28), captureDevices)
    cfgGui.AddText(Format("x{} y{} w{}", leftX + 14, groupY + 92, colW - 28), "Output (Windows default + comms output)")
    vrOutputPick := cfgGui.AddDropDownList(Format("x{} y{} w{}", leftX + 14, groupY + 114, colW - 28), renderDevices)

    cfgGui.AddText(Format("x{} y{} w{}", rightX + 14, groupY + 28, colW - 28), "Input (mic source in NVIDIA Broadcast)")
    desktopInputPick := cfgGui.AddDropDownList(Format("x{} y{} w{}", rightX + 14, groupY + 50, colW - 28), captureDevices)
    cfgGui.AddText(Format("x{} y{} w{}", rightX + 14, groupY + 92, colW - 28), "Output (Windows default + comms output)")
    desktopOutputPick := cfgGui.AddDropDownList(Format("x{} y{} w{}", rightX + 14, groupY + 114, colW - 28), renderDevices)

    SetDropDownSelectionByContains(vrInputPick, captureDevices, APP_CONFIG.BroadcastVrMicSource)
    SetDropDownSelectionByAliases(vrOutputPick, renderDevices, APP_CONFIG.VrRenderAliases)
    SetDropDownSelectionByContains(desktopInputPick, captureDevices, APP_CONFIG.BroadcastDesktopMicSource)
    SetDropDownSelectionByAliases(desktopOutputPick, renderDevices, APP_CONFIG.DesktopRenderAliases)

    buttonY := groupY + groupH + 14
    saveBtn := cfgGui.AddButton(Format("x{} y{} w120 h32", leftX, buttonY), "Save")
    advancedBtn := cfgGui.AddButton(Format("x{} y{} w140 h32", leftX + 132, buttonY), "Advanced...")
    cancelBtn := cfgGui.AddButton(Format("x{} y{} w120 h32", leftX + 284, buttonY), "Cancel")

    saveBtn.OnEvent("Click", (*) => SaveSimpleConfigFromGui(cfgGui, vrInputPick, vrOutputPick, desktopInputPick, desktopOutputPick))
    advancedBtn.OnEvent("Click", (*) => ShowAdvancedConfigGui())
    cancelBtn.OnEvent("Click", (*) => cfgGui.Destroy())
    cfgGui.Show("AutoSize Center")
}

ShowAdvancedConfigGui(*) {
    global APP_CONFIG, BROADCAST_VERSION_OK
    renderDevices := BuildUniqueDeviceList("Render")
    captureDevices := BuildUniqueDeviceList("Capture")
    broadcastCaptureDevices := FilterDeviceList(captureDevices, "Broadcast")
    if (broadcastCaptureDevices.Length = 0) {
        broadcastCaptureDevices := ["NVIDIA Broadcast"]
    }
    standDown := IsVirtualDesktopRunning()

    cfgGui := Gui("+AlwaysOnTop", "VR Audio Config - Advanced")
    cfgGui.SetFont("s10", "Segoe UI")
    cfgGui.AddText("w780", "Power-user mode. Keep fallback aliases with |. These groups map directly to IN VR and ON DESKTOP behavior.")
    if !BROADCAST_VERSION_OK {
        cfgGui.SetFont("s10 cRed Bold", "Segoe UI")
        cfgGui.AddText("w780 y+8", "NOT ACTIVE: This tool requires NVIDIA Broadcast 1.4.x. If you need 2.1.0+, this technique will not work.")
        cfgGui.SetFont("s10 cDefault Norm", "Segoe UI")
    }
    if (standDown) {
        cfgGui.SetFont("s10 cRed Bold", "Segoe UI")
        cfgGui.AddText("w780 y+8", "NOT ACTIVE due to presence of Virtual Desktop which handles audio inputs/outputs in VR.")
        cfgGui.SetFont("s10 cDefault Norm", "Segoe UI")
    }
    x := 18, w := 780
    contentOffset := standDown ? 30 : 0
    sharedY := 58 + contentOffset
    sharedH := 132
    vrY := sharedY + sharedH + 10
    vrH := 184
    desktopY := vrY + vrH + 10
    desktopH := 184
    buttonY := desktopY + desktopH + 12

    cfgGui.AddGroupBox(Format("x{} y{} w{} h{}", x, sharedY, w, sharedH), "Shared Input - NVIDIA Broadcast")
    cfgGui.AddText(Format("x{} y{} w{}", x + 12, sharedY + 24, w - 24), "To ensure this tool works with NVIDIA Broadcast as expected, leave this as NVIDIA Broadcast.")
    cfgGui.AddText(Format("x{} y{} w{}", x + 12, sharedY + 46, w - 24), "Windows microphone aliases:")
    captureEdit := cfgGui.AddEdit(Format("x{} y{} w{}", x + 12, sharedY + 68, w - 24), JoinAliasList(APP_CONFIG.CaptureAliases))
    capturePick := cfgGui.AddDropDownList(Format("x{} y{} w{}", x + 12, sharedY + 96, 580), broadcastCaptureDevices)
    captureUseBtn := cfgGui.AddButton(Format("x{} y{} w{}", x + 602, sharedY + 96, 166), "Use Picked Broadcast")

    cfgGui.AddGroupBox(Format("x{} y{} w{} h{}", x, vrY, w, vrH), "In VR")
    cfgGui.AddText(Format("x{} y{} w{}", x + 12, vrY + 24, w - 24), "Output aliases:")
    vrRenderEdit := cfgGui.AddEdit(Format("x{} y{} w{}", x + 12, vrY + 46, w - 24), JoinAliasList(APP_CONFIG.VrRenderAliases))
    vrRenderPick := cfgGui.AddDropDownList(Format("x{} y{} w{}", x + 12, vrY + 74, 580), renderDevices)
    vrRenderUseBtn := cfgGui.AddButton(Format("x{} y{} w{}", x + 602, vrY + 74, 166), "Use Picked Device")
    cfgGui.AddText(Format("x{} y{} w{}", x + 12, vrY + 108, w - 24), "Input while in VR (will be set in NVIDIA Broadcast for you):")
    vrMicSourceEdit := cfgGui.AddEdit(Format("x{} y{} w{}", x + 12, vrY + 130, w - 24), APP_CONFIG.BroadcastVrMicSource)
    vrMicSourcePick := cfgGui.AddDropDownList(Format("x{} y{} w{}", x + 12, vrY + 158, 580), captureDevices)
    vrMicSourceUseBtn := cfgGui.AddButton(Format("x{} y{} w{}", x + 602, vrY + 158, 166), "Use Picked Device")

    cfgGui.AddGroupBox(Format("x{} y{} w{} h{}", x, desktopY, w, desktopH), "On Desktop")
    cfgGui.AddText(Format("x{} y{} w{}", x + 12, desktopY + 24, w - 24), "Output aliases:")
    desktopRenderEdit := cfgGui.AddEdit(Format("x{} y{} w{}", x + 12, desktopY + 46, w - 24), JoinAliasList(APP_CONFIG.DesktopRenderAliases))
    desktopRenderPick := cfgGui.AddDropDownList(Format("x{} y{} w{}", x + 12, desktopY + 74, 580), renderDevices)
    desktopRenderUseBtn := cfgGui.AddButton(Format("x{} y{} w{}", x + 602, desktopY + 74, 166), "Use Picked Device")
    cfgGui.AddText(Format("x{} y{} w{}", x + 12, desktopY + 108, w - 24), "Input on desktop (will be set in NVIDIA Broadcast for you):")
    desktopMicSourceEdit := cfgGui.AddEdit(Format("x{} y{} w{}", x + 12, desktopY + 130, w - 24), APP_CONFIG.BroadcastDesktopMicSource)
    desktopMicSourcePick := cfgGui.AddDropDownList(Format("x{} y{} w{}", x + 12, desktopY + 158, 580), captureDevices)
    desktopMicSourceUseBtn := cfgGui.AddButton(Format("x{} y{} w{}", x + 602, desktopY + 158, 166), "Use Picked Device")

    ; Keep dropdowns aligned with current text values to avoid UI confusion.
    SetDropDownSelectionByAliases(capturePick, broadcastCaptureDevices, APP_CONFIG.CaptureAliases)
    SetDropDownSelectionByAliases(vrRenderPick, renderDevices, APP_CONFIG.VrRenderAliases)
    SetDropDownSelectionByContains(vrMicSourcePick, captureDevices, APP_CONFIG.BroadcastVrMicSource)
    SetDropDownSelectionByAliases(desktopRenderPick, renderDevices, APP_CONFIG.DesktopRenderAliases)
    SetDropDownSelectionByContains(desktopMicSourcePick, captureDevices, APP_CONFIG.BroadcastDesktopMicSource)

    saveBtn := cfgGui.AddButton(Format("x{} y{} w120 h32", x, buttonY), "Save")
    cancelBtn := cfgGui.AddButton(Format("x{} y{} w120 h32", x + 132, buttonY), "Cancel")

    captureUseBtn.OnEvent("Click", (*) => ApplyDropdownSelection(captureEdit, capturePick))
    vrRenderUseBtn.OnEvent("Click", (*) => ApplyDropdownSelection(vrRenderEdit, vrRenderPick))
    desktopRenderUseBtn.OnEvent("Click", (*) => ApplyDropdownSelection(desktopRenderEdit, desktopRenderPick))
    vrMicSourceUseBtn.OnEvent("Click", (*) => ApplyDropdownSelection(vrMicSourceEdit, vrMicSourcePick))
    desktopMicSourceUseBtn.OnEvent("Click", (*) => ApplyDropdownSelection(desktopMicSourceEdit, desktopMicSourcePick))
    saveBtn.OnEvent("Click", (*) => SaveConfigFromGui(cfgGui, captureEdit, vrRenderEdit, desktopRenderEdit, vrMicSourceEdit, desktopMicSourceEdit))
    cancelBtn.OnEvent("Click", (*) => cfgGui.Destroy())
    cfgGui.Show("AutoSize Center")
}

FilterDeviceList(items, containsText) {
    filtered := []
    for _, item in items {
        if InStr(item, containsText) {
            filtered.Push(item)
        }
    }
    return filtered
}

NormalizeDeviceLabel(name) {
    trimmed := Trim(name)
    if (trimmed = "") {
        return trimmed
    }
    return RegExReplace(trimmed, "^\d+\s*-\s*")
}

SetDropDownSelectionByContains(dropdown, items, needle) {
    match := Trim(needle)
    if (match = "") {
        return
    }
    for _, item in items {
        if InStr(item, match) {
            dropdown.Text := item
            return
        }
    }
}

SetDropDownSelectionByAliases(dropdown, items, aliases) {
    for _, alias in aliases {
        for _, item in items {
            if InStr(item, alias) {
                dropdown.Text := item
                return
            }
        }
    }
}

SaveSimpleConfigFromGui(cfgGui, vrInputPick, vrOutputPick, desktopInputPick, desktopOutputPick) {
    global APP_CONFIG
    vrInput := NormalizeDeviceLabel(vrInputPick.Text)
    vrOutput := NormalizeDeviceLabel(vrOutputPick.Text)
    desktopInput := NormalizeDeviceLabel(desktopInputPick.Text)
    desktopOutput := NormalizeDeviceLabel(desktopOutputPick.Text)

    if (vrInput = "" || vrOutput = "" || desktopInput = "" || desktopOutput = "") {
        MsgBox "Please select all four devices before saving."
        return
    }

    APP_CONFIG.BroadcastVrMicSource := vrInput
    APP_CONFIG.VrRenderAliases := [vrOutput]
    APP_CONFIG.BroadcastDesktopMicSource := desktopInput
    APP_CONFIG.DesktopRenderAliases := [desktopOutput]

    SaveConfig(APP_CONFIG)
    cfgGui.Destroy()
    MsgBox "Saved simple config to:`n" CONFIG_FILE
}

ApplyDropdownSelection(targetEdit, sourceDropdown) {
    selected := Trim(sourceDropdown.Text)
    if (selected != "") {
        targetEdit.Value := selected
    }
}

SaveConfigFromGui(cfgGui, captureEdit, vrRenderEdit, desktopRenderEdit, vrMicSourceEdit, desktopMicSourceEdit) {
    global APP_CONFIG
    APP_CONFIG.CaptureAliases := ParseAliasList(captureEdit.Value)
    APP_CONFIG.VrRenderAliases := ParseAliasList(vrRenderEdit.Value)
    APP_CONFIG.DesktopRenderAliases := ParseAliasList(desktopRenderEdit.Value)
    APP_CONFIG.BroadcastVrMicSource := Trim(vrMicSourceEdit.Value)
    APP_CONFIG.BroadcastDesktopMicSource := Trim(desktopMicSourceEdit.Value)
    SaveConfig(APP_CONFIG)
    cfgGui.Destroy()
    MsgBox "Saved config to:`n" CONFIG_FILE
}

ResolveAudioDeviceName(partialName) {
    escaped := StrReplace(partialName, "'", "''")
    psCommand := "$term = '" escaped "'; " .
        "(Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render' -ErrorAction SilentlyContinue | " .
        "ForEach-Object { " .
        "$props = Get-ItemProperty -Path ($_.PSPath + '\Properties') -ErrorAction SilentlyContinue; " .
        "$name = $props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},14'; " .
        "if (-not $name) { $name = $props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6' }; " .
        "if (-not $name) { $name = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2' }; " .
        "$name " .
        "}) | Where-Object { $_ -and $_ -like ('*' + $term + '*') } | Sort-Object -Unique | Select-Object -First 1"
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(Format('{} /c powershell -NoProfile -Command "{}"', A_ComSpec, psCommand))
    deviceName := Trim(exec.StdOut.ReadAll(), "`r`n`t ")
    return deviceName
}

ResolveAudioDeviceNameFromAliases(aliases) {
    for _, alias in aliases {
        name := ResolveAudioDeviceName(alias)
        if (name != "") {
            return name
        }
    }
    return ""
}

SetDefaultAudioDeviceBySoundVolumeView(deviceId, setAsComms := false) {
    svvPath := A_ScriptDir "\SoundVolumeView.exe"
    if !FileExist(svvPath) {
        return false
    }
    try {
        RunWait(Format('"{}" /SetDefault "{}" 1', svvPath, deviceId),, "Hide")
        Sleep(300)
        if (setAsComms) {
            RunWait(Format('"{}" /SetDefault "{}" 2', svvPath, deviceId),, "Hide")
            Sleep(300)
        }
        return true
    } catch Error as err {
        return false
    }
}

; Function to set both default playback and communications devices
SetDefaultAudioDevice(deviceNameOrPartial, setAsComms := false, usePartialMatch := false, direction := "Render") {
    svvPath := A_ScriptDir "\SoundVolumeView.exe"
    nircmdPath := A_ScriptDir "\nircmd.exe"
    
    if !FileExist(svvPath) && !FileExist(nircmdPath) {
        MsgBox "No supported audio tool found. Expected SoundVolumeView.exe or nircmd.exe in: " A_ScriptDir
        return
    }

    deviceName := deviceNameOrPartial
    deviceId := ""
    if (usePartialMatch) {
        isArray := (Type(deviceNameOrPartial) = "Array")
        if (FileExist(svvPath)) {
            if (isArray) {
                deviceId := ResolveDeviceIdFromAliases(deviceNameOrPartial, direction)
            } else {
                deviceId := ResolveDeviceId(deviceNameOrPartial, direction)
            }
        }
        if (isArray) {
            resolvedName := ResolveAudioDeviceNameFromAliases(deviceNameOrPartial)
            missingName := ""
            for index, alias in deviceNameOrPartial {
                if (index > 1) {
                    missingName .= ", "
                }
                missingName .= alias
            }
        } else {
            resolvedName := ResolveAudioDeviceName(deviceNameOrPartial)
            missingName := deviceNameOrPartial
        }
        if (deviceId = "" && resolvedName = "") {
            MsgBox 'No audio output device found matching "' missingName '".'
            return
        }
        deviceName := resolvedName
    }

    if (deviceId != "") {
        if SetDefaultAudioDeviceBySoundVolumeView(deviceId, setAsComms) {
            return
        }
    }
    
    try {
        ; Set as default playback device
        if !FileExist(nircmdPath) {
            MsgBox "NirCmd not found at: " nircmdPath
            return
        }
        RunWait(Format('"{}" setdefaultsounddevice "{}" 1', nircmdPath, deviceName),, "Hide")
        Sleep(500)  ; Give Windows time to process the change
        
        ; Set as default communications device if requested
        if (setAsComms) {
            RunWait(Format('"{}" setdefaultsounddevice "{}" 1 2', nircmdPath, deviceName),, "Hide")
            Sleep(500)  ; Give Windows time to process the change
        }
    } catch Error as err {
        ; If there's an error, just continue - we don't want to interrupt the VR shutdown
    }
}

SetTitleMatchMode(2)
DetectHiddenWindows(true)

; Monitor the vrmonitor.exe process
OnProcessStartStop("vrmonitor.exe", SteamVRStarted, SteamVRStopped)

SteamVRStarted() {
    global APP_CONFIG, IS_STANDDOWN, BROADCAST_VERSION_OK
    if !BROADCAST_VERSION_OK {
        return
    }
    UpdateStandDownState()
    if IS_STANDDOWN {
        return
    }
    ; Keep system default input/comms input on NVIDIA Broadcast while entering VR
    SetDefaultAudioDevice(APP_CONFIG.CaptureAliases, true, true, "Capture")
    Sleep(500)

    ; Set Windows default audio devices for VR first
    SetDefaultAudioDevice(APP_CONFIG.VrRenderAliases, true, true)  ; Match likely aliases across naming quirks
    Sleep(1000)  ; Give Windows time to process the audio change
    
    ; RestartNvidiaBroadcast()
    ; SteamVR started, select "YondBe" microphone and speaker
    if WinExist("ahk_class RTXVoiceWindowClass")
    {
        WinActivate("ahk_class RTXVoiceWindowClass")

        ; Set the microphone input to configured VR source text
        ControlClick("Button4", "ahk_class RTXVoiceWindowClass")  ; Microphone tab
        Sleep(500)
        ControlFocus("ComboBox6", "ahk_class RTXVoiceWindowClass")
        ControlClick("ComboBox6", "ahk_class RTXVoiceWindowClass")
        Sleep(150)
        SelectComboItemContains("ComboBox6", "ahk_class RTXVoiceWindowClass", APP_CONFIG.BroadcastVrMicSource)

        ; Close the NVIDIA Broadcast window (but don't kill the app)
        CloseNvidiaBroadcastWindow()
    }
}

SteamVRStopped() {
    global APP_CONFIG, IS_STANDDOWN, BROADCAST_VERSION_OK
    if !BROADCAST_VERSION_OK {
        return
    }
    UpdateStandDownState()
    if IS_STANDDOWN {
        return
    }
    ; Wait a bit for VR components to finish shutting down
    Sleep(2000)
    
    ; RestartNvidiaBroadcast()
    ; Keep system default input/comms input on NVIDIA Broadcast while leaving VR
    SetDefaultAudioDevice(APP_CONFIG.CaptureAliases, true, true, "Capture")
    Sleep(500)

    ; SteamVR stopped, select NVIDIA Broadcast source back to USB audio CODEC
    if WinExist("ahk_class RTXVoiceWindowClass")
    {
        WinActivate("ahk_class RTXVoiceWindowClass")

        ; Set the microphone input to configured desktop source text
        ControlClick("Button4", "ahk_class RTXVoiceWindowClass")  ; Microphone tab
        Sleep(500)
        ControlFocus("ComboBox6", "ahk_class RTXVoiceWindowClass")
        ControlClick("ComboBox6", "ahk_class RTXVoiceWindowClass")
        Sleep(150)
        SelectComboItemContains("ComboBox6", "ahk_class RTXVoiceWindowClass", APP_CONFIG.BroadcastDesktopMicSource)

        ; Close the NVIDIA Broadcast window (but don't kill the app)
        CloseNvidiaBroadcastWindow()
    }

    ; Wait a bit after NVIDIA Broadcast changes before changing Windows audio
    Sleep(1000)
    
    ; Set Windows default audio devices for desktop
    SetDefaultAudioDevice(APP_CONFIG.DesktopRenderAliases, true, true)  ; Set as both playback and comms device
}

RestartNvidiaBroadcast() {
    ; Disabled by request: do not kill/restart NVIDIA Broadcast automatically.
    ;if ProcessExist("NVIDIA Broadcast UI.exe") {
    ;    ProcessClose("NVIDIA Broadcast UI.exe")
    ;    Sleep(3000)
    ;}
    ;Run("C:\\Program Files\\NVIDIA Corporation\\NVIDIA Broadcast\\NVIDIA Broadcast UI.exe")
    ;Sleep(5000)
}

CloseNvidiaBroadcastWindow() {
    ; Ensure the window is active before trying to close it
    if WinExist("ahk_class RTXVoiceWindowClass") {
        WinActivate("ahk_class RTXVoiceWindowClass")
        Sleep(500)
        WinClose("ahk_class RTXVoiceWindowClass")  ; Attempt to close the window
        Sleep(1000)  ; Wait and retry if necessary
        if WinExist("ahk_class RTXVoiceWindowClass")  ; Check if it's still open
        {
            WinClose("ahk_class RTXVoiceWindowClass")  ; Try again
        }
    }
}

SelectComboItemContains(controlName, windowTitle, partialText) {
    try {
        items := ControlGetItems(controlName, windowTitle)
        for index, item in items {
            if InStr(item, partialText) {
                ControlChooseIndex(index, controlName, windowTitle)
                return true
            }
        }
    } catch Error as err {
    }
    return false
}

OnProcessStartStop(ProcessName, OnStartFunc, OnStopFunc) {
    static isProcessRunning := false
    static wasStandDown := false
    global IS_STANDDOWN
    Loop {
        UpdateStandDownState()
        currentStandDown := IS_STANDDOWN
        processNow := ProcessExist(ProcessName)

        if (currentStandDown) {
            isProcessRunning := !!processNow
            wasStandDown := true
            Sleep(1000)
            continue
        }

        if (wasStandDown && processNow) {
            isProcessRunning := true
            OnStartFunc()
            wasStandDown := false
            Sleep(1000)
            continue
        }
        wasStandDown := false

        if processNow {
            if !isProcessRunning {
                isProcessRunning := true
                OnStartFunc()  ; Call start function directly
            }
        } else {
            if isProcessRunning {
                isProcessRunning := false
                OnStopFunc()  ; Call stop function directly
            }
        }
        Sleep(1000)
    }
}
