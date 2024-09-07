#Requires AutoHotkey v2.0

SetTitleMatchMode(2)
DetectHiddenWindows(true)

; Monitor the vrmonitor.exe process
OnProcessStartStop("vrmonitor.exe", SteamVRStarted, SteamVRStopped)

SteamVRStarted() {
    RestartNvidiaBroadcast()
    ; SteamVR started, select "YondBe" microphone
    if WinExist("ahk_class RTXVoiceWindowClass")
    {
        WinActivate("ahk_class RTXVoiceWindowClass")

        ; Click on the "Speakers" tab (Button5) first, then pause
        ControlClick("Button5", "ahk_class RTXVoiceWindowClass")  ; Speakers tab
        Sleep(2000)

        ; Click on the "Microphone" tab (Button4)
        ControlClick("Button4", "ahk_class RTXVoiceWindowClass")  ; Microphone tab
        Sleep(500)

        ; Now attempt to change the microphone to "YondBe"
        ControlFocus("ComboBox6", "ahk_class RTXVoiceWindowClass")
        ControlClick("ComboBox6", "ahk_class RTXVoiceWindowClass")
        Sleep(100)
        Send("Y")  ; Select "YondBe"
        Sleep(100)
        Send("{Enter}")

        ; Close the NVIDIA Broadcast window (but don't kill the app)
        CloseNvidiaBroadcastWindow()
    }
}

SteamVRStopped() {
    RestartNvidiaBroadcast()
    ; SteamVR stopped, select "USB Mic"
    if WinExist("ahk_class RTXVoiceWindowClass")
    {
        WinActivate("ahk_class RTXVoiceWindowClass")

        ; Click on the "Speakers" tab (Button5) first, then pause
        ControlClick("Button5", "ahk_class RTXVoiceWindowClass")  ; Speakers tab
        Sleep(2000)

        ; Click on the "Microphone" tab (Button4)
        ControlClick("Button4", "ahk_class RTXVoiceWindowClass")  ; Microphone tab
        Sleep(500)

        ; Now attempt to change the microphone to "USB Mic"
        ControlFocus("ComboBox6", "ahk_class RTXVoiceWindowClass")
        ControlClick("ComboBox6", "ahk_class RTXVoiceWindowClass")
        Sleep(100)
        Send("U")  ; Select "USB Mic"
        Sleep(100)
        Send("{Enter}")

        ; Close the NVIDIA Broadcast window (but don't kill the app)
        CloseNvidiaBroadcastWindow()
    }
}

RestartNvidiaBroadcast() {
    ; Kill NVIDIA Broadcast if it's running
    if ProcessExist("NVIDIA Broadcast UI.exe") {
        ProcessClose("NVIDIA Broadcast UI.exe")
        Sleep(3000)  ; Wait for the process to fully close
    }

    ; Restart NVIDIA Broadcast
    Run("C:\Program Files\NVIDIA Corporation\NVIDIA Broadcast\NVIDIA Broadcast UI.exe")
    Sleep(5000)  ; Wait for the app to fully launch
}

CloseNvidiaBroadcastWindow() {
    ; Ensure the window is active before trying to close it
    if WinExist("ahk_class RTXVoiceWindowClass") {
        WinActivate("ahk_class RTXVoiceWindowClass")
        Sleep(500)
        WinClose("ahk_class RTXVoiceWindowClass")  ; Attempt to close the window
        Sleep(1000)  ; Wait and retry if necessary
        if WinExist("ahk_class RTXVoiceWindowClass")  ; Check if it’s still open
        {
            WinClose("ahk_class RTXVoiceWindowClass")  ; Try again
        }
    }
}

OnProcessStartStop(ProcessName, OnStartFunc, OnStopFunc) {
    static isProcessRunning := false
    Loop {
        if ProcessExist(ProcessName) {
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
