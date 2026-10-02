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

<p align="center">
  <a href="https://amirhp-com.github.io/KeepMeUp/"><b>Website</b></a> · <a href="https://github.com/amirhp-com/KeepMeUp/releases/latest/download/KeepMeUp.zip"><b>Download</b></a>
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
- **Telegram remote control.** From your phone you can keep it awake, set timers, lock, sleep and shut down, take screenshots and camera photos, show the desktop, open and quit apps, control volume and media, adjust brightness, read or set the clipboard, check Wi-Fi and IP, run shell commands, and find files and send them to the chat. You choose which commands are allowed.
- **Alerts and schedules.** Get a Telegram message when the battery runs low, the charger is plugged or unplugged, or the Mac comes online, and repeat actions on a daily schedule (like sleep every weekday at 1 AM).
- **Private by design.** Your bot token is stored in a file only your user account can read, and only chats you approve can send commands. Powerful commands are off by default, and turning one on asks for your password or Touch ID. There are no servers, analytics or accounts.
- **Launch at login**, and keep-awake can resume after a restart.
- **Built-in updates.** KeepMeUp checks GitHub for new releases. It can download an update, install it in place and relaunch with one click.
- **Glass design** on macOS 26 and later, with a material fallback on older versions.
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
2. In KeepMeUp, open **Settings… → Telegram**, paste the token, switch on **Enable Telegram control** and click **Save & Connect**.
3. Follow the **Get started** steps: click **Open in Telegram**, tap **Start**, then click **Allow** on your Mac.
4. The bot replies with every command, and the menu next to the message box lists them too.

Only approved chats can control the Mac. Each paired chat shows up in Settings with its name, username and type (private chat, group or channel).

- **Private chats** are paired with `/start`.
- **Groups:** add the bot to the group and send `/pair` there. Only people who have already paired with the bot privately can send commands in the group.
- **Pairing closes** after your first chat is approved, so strangers who find your bot can't ask for access. To add another chat, click **Pair another chat**, which opens pairing for 5 minutes.

> [!IMPORTANT]
> Remote control is limited to the Telegram chats you approve on the Mac itself. Most commands that can see your screen, read files, use the camera or run code are **off by default** — you, the Mac's owner, turn each one on knowingly in **Settings → Commands**, and the app asks for your password or Touch ID first. You enable these at your own responsibility.

### Commands

You can turn any command on or off in **Settings → Commands**. Commands that are off are hidden from the bot menu and refused. Commands marked 🛡 can see your screen, read files or run code. They start turned off, and turning one on asks for your password or Touch ID.

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
| `/restart` · `/shutdown` | Restarts or shuts down (asks you to confirm first) |
| `/desktop` | Hides every app so the desktop shows |
| `/show` | Brings the hidden apps back |
| `/screenshot` 🛡 | Sends a screenshot of every display |
| `/webcam` 🛡 | Takes a photo with the camera (the green camera light turns on) |
| `/info` | Shows battery, uptime, load, memory and disk |
| `/apps` | Lists running apps |
| `/open <app>` | Launches an app (`/open Safari`) |
| `/quit <app> [--force]` | Quits an app, or force quits it |
| `/caffeinate <app>` | Keeps the Mac awake only while that app is running |
| `/volume [0-100]` | Shows or sets the output volume |
| `/mute` | Mutes or unmutes the output |
| `/play` · `/next` · `/previous` | Media controls for whatever is playing |
| `/say <text>` | Speaks text out loud on the Mac |
| `/notify <text>` | Shows a notification on the Mac |
| `/clip [text]` 🛡 | Reads the clipboard, or sets it |
| `/wifi` | Wi-Fi network and signal |
| `/ip` | Local and public IP addresses |
| `/schedule <time> <action> [weekdays]` | Repeats an action daily (`/schedule 01:00 sleep weekdays`) |
| `/schedules` · `/unschedule <n>` | Lists or removes scheduled actions |
| `/upload` 🛡 | Send the bot a file and it's saved to Downloads |
| `/terminal` | Opens Terminal |
| `/term <command>` 🛡 | Runs a command in a Terminal window and sends a screenshot |
| `/run <command>` 🛡 | Runs a shell command and replies with the output (60-second limit; long output arrives as a file) |
| `/find <name>` 🛡 | Searches your whole home folder with Spotlight. Each result has tappable `/get_N` and `/openfile_N` links |
| `/desk [name]` 🛡 | Searches Desktop, or lists its newest items when no name is given |
| `/docs [name]` 🛡 | Searches Documents, or lists its newest items |
| `/dl [name]` 🛡 | Searches Downloads, or lists its newest items |
| `/recent [days]` 🛡 | Lists files you opened recently, like Finder's Recents (default 7 days) |
| `/get <path or number>` 🛡 | Sends a file to the chat (folders are zipped; Telegram's limit is 50 MB) |
| `/openfile <path or number>` 🛡 | Opens a file on the Mac |
| `/help` | Lists the commands that are turned on |

Durations can be written as `30` (minutes), `45m`, `2h`, `1h30m`, `90s` or `1:30`.

## Permissions

| Permission | Needed for | Where |
| --- | --- | --- |
| Automation → System Events | Restart and shut down | Asked the first time you use them |
| Automation → Terminal | `/term` | Asked the first time you use it |
| Screen Recording | `/screenshot`, `/term` | System Settings → Privacy & Security → Screen Recording |
| Camera | `/webcam` | Asked the first time, or System Settings → Privacy & Security → Camera |
| Files & Folders | `/find`, `/get`, file lists | Asked per folder, or System Settings → Privacy & Security |

Keeping the Mac awake, display off, screensaver, lock and sleep don't need any permission.

## FAQ

**Does it work with the lid closed?**
macOS sleeps a closed MacBook unless an external display, keyboard and power adapter are connected (clamshell mode). KeepMeUp follows the same rule.

**How do I check that it's working?**
Run `pmset -g assertions` in Terminal. While KeepMeUp is active, you'll see its `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep` entries.

**What happens if I quit the app?**
The power assertions are released right away, and your normal sleep settings apply again.

## Updating

KeepMeUp checks for new versions on launch and every few hours. You can turn this off in **Settings → About**. When an update is out, the menu shows an **Update** button: it downloads the release, replaces the app and relaunches it. Paired Telegram chats get a message about it too.

Every release zip comes with a `KeepMeUp.zip.sig` signature file. The app only installs updates whose signature matches the release key built into it.

### Publishing a release

```bash
swift scripts/release-key.swift generate   # once; prints the public key for Info.plist (KMUPublicEDKey)
./scripts/build-app.sh                     # builds and signs dist/KeepMeUp.zip
gh release create vX.Y.Z dist/KeepMeUp.zip dist/KeepMeUp.zip.sig
```

If a code signing certificate named **KeepMeUp Release** is in your keychain, the build script uses it. A self-signed one works. Keeping the same certificate across releases means macOS remembers permissions like Screen Recording after updates, because the ad-hoc signature changes with every build and macOS treats each build as a new app.

The private key stays in `~/.config/keepmeup/ed25519.key`. Back it up, because if it's lost, existing installs can't verify new releases.

## Security and disclaimer

KeepMeUp is a remote-control tool for **your own Mac**. It's open source, so you can read exactly what every command does before you trust it.

- Only the Telegram chats you approve on the Mac can send commands. Pairing is confirmed in a dialog on the Mac, and closes after the first chat so strangers can't request access.
- Commands that can see your screen, use the camera, read files or run code are **off by default**. You turn each one on knowingly, and the app asks for your password or Touch ID first.
- The bot token is stored in a file only your macOS account can read. There are no KeepMeUp servers, accounts or analytics — the app talks only to Telegram's API and, for `/ip`, a public IP-lookup service.
- macOS still enforces its own protections: the green camera light turns on for `/webcam`, and Screen Recording, Camera, Automation and Files permissions must be granted by you.

The more powerful commands exist for people who want them. Turning them on is your decision and your responsibility: anyone with access to an approved chat (or to your unlocked Telegram) can use whatever you've enabled. Enable only what you need, keep your Telegram account secure, and remove chats you no longer use.

KeepMeUp is provided "as is", without warranty of any kind, under the MIT License. You use it at your own risk; the author is not liable for any loss or damage from using it. See [LICENSE](LICENSE).

## Contributing

Issues and pull requests are welcome. If you find KeepMeUp useful, please give it a ⭐️.

## License

[MIT](LICENSE) © 2026 [AmirhpCom](https://amirhp.com)
