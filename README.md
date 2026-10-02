<p align="center">
  <img src="assets/logo.png" width="160" alt="KeepMeUp logo">
</p>

<h1 align="center">KeepMeUp</h1>

<p align="center">
  A free, open-source menu bar app that keeps your Mac awake, and lets you control it from Telegram.
  <br>
  Native Swift · Universal (Apple Silicon + Intel) · macOS 13 Ventura or later
</p>

<p align="center">
  <a href="https://github.com/amirhp-com/KeepMeUp/releases/latest"><img src="https://img.shields.io/github/v/release/amirhp-com/KeepMeUp?label=download" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-native-black" alt="Apple Silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
</p>

---

## Features

- **One-click keep-awake.** Blocks display sleep, the screensaver and idle system sleep, whatever your Energy and Lock Screen settings say. Turn it off and macOS goes back to normal.
- **Timers.** After 15 minutes, 30 minutes, 1 hour, 2 hours or any time you type (`45m`, `1h30m`, `2:15`), KeepMeUp can:
  - stop keeping awake
  - turn the display off
  - start the screensaver
  - lock the screen
  - sleep, restart or shut down
- **Quick actions.** Display off, screensaver, lock and sleep, one click each from the menu.
- **Telegram remote control.** Turn it on or off, set timers, lock, sleep, shut down, take a screenshot or check the battery from your phone.
- **Private by design.** Your bot token stays in the macOS Keychain, and only chats you approve can send commands. There are no servers, analytics or accounts.
- **Launch at login**, and keep-awake can resume after a restart.
- **Universal binary.** Built natively for M-series chips, and runs on Intel Macs too.

## Install

1. Download `KeepMeUp.zip` from the [latest release](https://github.com/amirhp-com/KeepMeUp/releases/latest).
2. Unzip it and move **KeepMeUp.app** to `/Applications`.
3. The app is free and not notarized, so the first time you open it, **right-click → Open → Open**.
   If macOS still blocks it, go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/KeepMeUp.app
   ```

A ☕️ cup appears in the menu bar. It is filled while your Mac is being kept awake.

### Build from source

You need the Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/amirhp-com/KeepMeUp.git
cd KeepMeUp
./scripts/build-app.sh
open dist/KeepMeUp.app
```

The script builds a universal `arm64` + `x86_64` binary, packages `dist/KeepMeUp.app` and zips it. To sign with your own Developer ID, set `SIGN_IDENTITY="Developer ID Application: …"`.

## Telegram remote control

1. In Telegram, open [@BotFather](https://t.me/BotFather), send `/newbot` and copy the token it gives you.
2. In KeepMeUp, open **Settings… → Telegram**, paste the token and switch on **Enable Telegram control**.
3. Send `/pair` to your new bot, then click **Allow** in the prompt that appears on your Mac.

Only approved private chats can control the Mac. Groups, channels and every other chat are ignored. To pair another device later, click **Allow a new /pair for 5 minutes**. You can also add or remove chat IDs by hand.

| Command | What it does |
| --- | --- |
| `/status` | Shows keep-awake state, the running timer and the battery |
| `/on [time]` | Keeps the Mac awake, optionally for a set time (`/on 2h`) |
| `/off [time]` | Stops keeping awake now, or after a delay (`/off 30m`) |
| `/timer <time> <action>` | Schedules an action: `off`, `displayoff`, `screensaver`, `lock`, `sleep`, `restart`, `shutdown` (`/timer 1h30m shutdown`) |
| `/cancel` | Cancels the running timer |
| `/displayoff` | Turns the display off |
| `/screensaver` | Starts the screensaver |
| `/lock` | Locks the screen |
| `/sleep` | Puts the Mac to sleep |
| `/restart` | Restarts (asks you to confirm first) |
| `/shutdown` | Shuts down (asks you to confirm first) |
| `/screenshot` | Sends a screenshot of every display |
| `/info` | Shows battery, uptime, load, memory and disk |
| `/help` | Lists all commands |

Durations can be written as `30` (minutes), `45m`, `2h`, `1h30m`, `90s` or `1:30`.

## Permissions

| Permission | Needed for | Where |
| --- | --- | --- |
| Automation → System Events | Restart and shut down | Asked the first time you use them |
| Screen Recording | `/screenshot` | System Settings → Privacy & Security → Screen Recording |

Keeping the Mac awake, display off, screensaver, lock and sleep don't need any permission.

## FAQ

**Does it work with the lid closed?**
macOS sleeps a closed MacBook unless an external display, keyboard and power adapter are connected (clamshell mode). KeepMeUp follows the same rule.

**How do I check that it's working?**
Run `pmset -g assertions` in Terminal. While KeepMeUp is active, you'll see its `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep` entries.

**What happens if I quit the app?**
The power assertions are released right away, and your normal sleep settings apply again.

## Contributing

Issues and pull requests are welcome. If you find KeepMeUp useful, please give it a ⭐️.

## License

[MIT](LICENSE) © 2026 [AmirhpCom](https://amirhp.com)
