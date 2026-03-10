# AutoHotkey VR Audio Auto-Switch V2

This repo currently includes a SteamVR watcher script: `autoswitch mic for VR.ahk`.

## Requirements

- AutoHotkey v2
- NVIDIA Broadcast v1.4.0.38 (required for this V2 workflow)
  - Download: [NVIDIA_Broadcast_Offline_Ada_v1.4.0.38.exe](https://international.download.nvidia.com/Windows/broadcast/1.4.0.38/NVIDIA_Broadcast_Offline_Ada_v1.4.0.38.exe)

### Important Version Warning

NVIDIA Broadcast `2.1.0` is currently out and this technique does not work with it.
If you need `2.1.0+`, you are out of luck with this approach right now.

It automates three things:

- Windows default audio playback device
- Windows default communications playback device
- NVIDIA Broadcast microphone source dropdown

## Why this exists

Windows has separate "default device" and "default communications device" routing, and a lot of apps - especially Discord - will use comms routing in ways that feel random if you only set one of them.

So this script explicitly sets both, every time, to avoid half-switched audio.

## Current behavior

When SteamVR starts:

- Windows default input and comms input -> `NVIDIA Broadcast`
- NVIDIA Broadcast mic source -> item containing `Beyond`
- Windows default output and comms output -> Beyond strap device (matched by aliases)

When SteamVR stops:

- Windows default input and comms input remain -> `NVIDIA Broadcast`
- NVIDIA Broadcast mic source -> item containing `USB audio CODEC`
- Windows default output and comms output -> `SteelSeries Arctis 1 Wireless`

## Customize for your setup

You can configure this without touching code:

1. Right-click the tray icon for `autoswitch mic for VR.exe`
2. Click `Configure VR Audio Targets...`
3. In the main screen, use the left `Audio in VR` panel and right `Audio on Desktop` panel to pick:
   - Input
   - Output
4. Save

Use `Advanced...` only if you want alias-level tuning and fallback patterns.

Advanced mode is grouped by:

- `In VR`
- `On Desktop`
- Shared NVIDIA Broadcast input defaults

Settings are stored in `autoswitch mic for VR.ini` next to the script/exe.

Use stable substrings, not exact full names. Windows may prepend changing prefixes like `2-` or `3-`.

Alias fields support pipe-delimited fallback values, for example:

- `Beyond|YondBe|Strap`
- `SteelSeries Arctis 1 Wireless|Arctis 1 Wireless|SteelSeries`

## Virtual Desktop Stand-down

If Virtual Desktop is running, this tool intentionally stands down and does not change audio routing.

- Tray status changes to stand-down mode
- Config windows show a loud warning that the tool is not active
- This avoids fighting Virtual Desktop, which already manages VR audio paths

## Tooling

The script prefers `SoundVolumeView.exe` (for unique device IDs), then falls back to `nircmd.exe`.

Keep these files next to the script/exe:

- `SoundVolumeView.exe` - [tool page](https://www.nirsoft.net/utils/sound_volume_view.html) - [direct download (x64 zip)](https://www.nirsoft.net/utils/soundvolumeview-x64.zip)
- `nircmd.exe` - [tool page](https://www.nirsoft.net/utils/nircmd.html) - [direct download (zip)](https://www.nirsoft.net/utils/nircmd.zip)

`SoundVolumeView.exe` is used first because it can target unique audio device IDs and avoid ambiguous labels like multiple `Speakers` devices.

