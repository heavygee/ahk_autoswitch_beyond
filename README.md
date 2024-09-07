# Auto-Switch Microphone Inputs for NVIDIA Broadcast with SteamVR

## Problem Overview
For users who rely on NVIDIA Broadcast for audio processing both inside and outside of VR, there is a recurring issue where the microphone input needs to be changed automatically when transitioning between SteamVR and non-VR environments.

When in VR (i.e., using SteamVR), you will prefer to use the Beyond microphone. However, outside of VR, you might want to revert to a different, non-VR microphone. Manually changing this input device, in NVIDIA Broadcast every time is tedious. Using Banana Voicemeeter(sic) is one solution, as this can then control and combine microphone inputs, allowing you to "use both" mics all the time. This can lead to undesired audio effects however, and choosing only one input is cleaner.

### The Crux of the Problem
We need a way to automatically:
1. Switch to the preferred microphone (e.g., "Beyond Mic") when SteamVR starts.
2. Revert to the non-VR microphone when SteamVR stops.

Moreover, NVIDIA Broadcast doesn't always handle these changes gracefully (at least, not with AHK). In fact, it often requires a **restart** to ensure that the user interface and settings are reset correctly, which adds to the complexity of the solution.

## Solution: AutoHotkey v2 Script

### Key Steps:
- We use **AutoHotkey v2** to automatically monitor the SteamVR process (`vrmonitor.exe`).
- When SteamVR starts, the script:
  1. **Kills and restarts NVIDIA Broadcast** to reset the interface.
  2. **Switches to the "Beyond Mic"** or your preferred VR microphone.
- When SteamVR stops, the script:
  1. Restarts NVIDIA Broadcast.
  2. **Switches to your non-VR microphone** (e.g., "USB Mic").
  3. Closes the NVIDIA Broadcast window once the input has been successfully changed.

### Manual Preparation
Before running the script, you'll need to:
1. **Manually rename** both your VR microphone (e.g., "Beyond Mic") and your non-VR microphone (e.g., "USB Mic") in **Windows Sound Settings** to unique names. This allows the script to accurately switch between the two microphones based on their unique first letters. Yes, this is clunky, but it works.
   - Example: Rename the VR mic to something like `YondBe` and the non-VR mic to `USB Mic`. Y, U. 
   
To rename the devices:
- Open the **Recording** tab in the Sound Control Panel by pressing `Win + R`, typing:
```control mmsys.cpl,,1```
and pressing `Enter`.
- Right-click the device(s) you want to rename (Beyond and your normal non-vr mic) and choose **Rename**.

   
2. Make sure you point the script to the correct **NVIDIA Broadcast executable**. The default path used is:

```C:\Program Files\NVIDIA Corporation\NVIDIA Broadcast\NVIDIA Broadcast UI.exe```

If your path is different, you'll need to update the script accordingly.

### How to Use the Script

1. **Download and Install AutoHotkey v2**: The script requires AutoHotkey v2 to function. You can download it from the [AutoHotkey website](https://www.autohotkey.com/).

2. **Configure the Script**: In the provided `.ahk` script, make the following customizations:
 - **Device Names**: Ensure the `YondBe` and `USB Mic` names are correctly reflected. If your microphones have different names, you’ll need to update them in the script (look for where the `Send("Y")` and `Send("U")` commands are issued).
 - **NVIDIA Broadcast Path**: If your NVIDIA Broadcast installation is in a different location, update the path in the script where `Run()` is called to reflect your system's setup. The default path in the script is:
   ```ahk
   Run("C:\\Program Files\\NVIDIA Corporation\\NVIDIA Broadcast\\NVIDIA Broadcast UI.exe")
   ```

3. **Run the Script**: Once everything is configured, simply run the `.ahk` file. The script will monitor for the SteamVR process and switch microphone inputs automatically when VR is started or stopped.

### Why This Works
By integrating device name changes with AutoHotkey and incorporating a full restart of NVIDIA Broadcast, this script effectively handles the nuances of switching audio inputs when SteamVR starts or stops, automating a task that otherwise would be tedious and error-prone.

Feel free to adjust the script based on your specific microphone device names and setup!

P.S. there is an ICO file in the images folder if you want compile the AHK to an exe for ease of running at startup.
