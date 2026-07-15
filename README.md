# Frida Launcher — iOS (jailbroken) 🚀

A native **Swift / SwiftUI** port of the Android [Frida Launcher](https://github.com/thecybersandeep/Frida-Launcher), for managing
`frida-server` on **jailbroken iOS devices** with a single tap.

> ⚠️ **This app only works on a jailbroken device.** It downloads, installs, and controls
> `frida-server` as **root**. On a stock (non-jailbroken) iOS device none of the privileged
> operations can run — Apple's sandbox forbids executing arbitrary binaries and touching
> system paths. This is by design and cannot be worked around in a normal App Store app.

---

## What it does

Same feature set as the Android app, retargeted for iOS:

- **Device insights** — detects architecture (`arm64` / `arm`) and frida-server install/running state.
- **Version picker** — lists Frida releases from GitHub and lets you enter any custom version.
- **One-tap install** — downloads the correct `frida-server-<ver>-ios-<arch>.xz`, decompresses it,
  and installs it as root.
- **Start / Stop / Uninstall / Refresh**, plus **custom flags** and a flags reference.
- **Live log panel** with copy/clear.

## How it maps from the Android original

| Concern | Android (`FridaUtils.kt`) | iOS (this port) |
|---|---|---|
| Root execution | long-lived `su` pipe | `RootShell` via `posix_spawn` of `/bin/sh -c` (`Engine/RootShell.swift`) |
| Install path | `/data/local/tmp/frida-server` | `<jbroot>/usr/sbin/frida-server` (`Engine/FridaPaths.swift`) |
| Jailbreak layout | n/a | rootless (`/var/jb`) vs rootful (`/`) auto-detected |
| Arch filter | `android-(arm\|arm64\|x86\|x86_64)` | `ios-(arm64\|arm)` (`Engine/FridaEngine.swift`) |
| HTTP | OkHttp | `URLSession` async |
| JSON | Gson | `Codable` |
| XZ decompress | `org.tukaani:xz` | **SWCompression** (`Engine/XZDecompressor.swift`) |
| UI | `MainActivity` + XML layouts | SwiftUI (`Views/…`) |
| State | `ViewModel` + `LiveData` | `ObservableObject` + `@Published` (`ViewModel/FridaViewModel.swift`) |
| Coroutines | `viewModelScope` / `Dispatchers.IO` | `Task` / `Task.detached` |

## Source layout

```
FridaLauncher/
  App/              FridaLauncherApp.swift, Info.plist
  Engine/           FridaEngine, RootShell, FridaPaths, XZDecompressor, FridaModels
  ViewModel/        FridaViewModel.swift
  Views/            ContentView + sheets (CustomFlags, CustomVersion, FlagsHelp, About), Theme
  Utils/            Logger, DeviceInfo
  Assets.xcassets/  AppIcon (generated from logo.png, flattened onto the dark theme bg)
```

---

## Building

### Option A — Xcode (recommended for development)

Requires [XcodeGen](https://github.com/yonicd/XcodeGen) and Xcode.

```bash
cd ios
xcodegen generate          # creates FridaLauncher.xcodeproj (pulls in SWCompression via SPM)
open FridaLauncher.xcodeproj
```

Build the app, then sign the resulting binary with the jailbreak entitlements:

```bash
ldid -Sentitlements.plist "$(find ~/Library/Developer/Xcode/DerivedData -name FridaLauncher -type f)"
```

Deploy the `.app` to `/Applications` on the device (e.g. via `scp` + `uicache`), or package it
into a `.deb` (below).

### Option B — Theos (builds a `.deb` for Sileo/Zebra)

```bash
cd ios
export THEOS_DEVICE_IP=<device-ip>
make package install
```

> **XZ note:** `SWCompression` is a SwiftPM package. Under Theos you must vendor it (add it as a
> `SUBPROJECTS` or drop its sources in) — the SPM graph isn't resolved by Theos automatically.
> The Xcode path handles this for you.

---

## Signing & entitlements

`entitlements.plist` grants the app the privileges a rootful jailbreak app needs
(`platform-application`, `com.apple.private.security.no-container`, `task_for_pid-allow`, …).
The app calls `setuid(0)` at launch (`RootShell.ensureRoot()`); on a rootful jailbreak it then
runs every shell command as root.

The downloaded `frida-server` binary from Frida's GitHub releases ships **pre-signed** with the
entitlements it needs, so it runs as-is once installed. If your jailbreak requires re-signing
system binaries, re-run `ldid -S` on the installed binary.

---

## Security / authorization note

Frida is a dual-use dynamic-instrumentation toolkit. This launcher is intended for **authorized
security research and pentesting on devices you own or are permitted to test**. You are
responsible for complying with applicable law and the terms of any system you instrument.
