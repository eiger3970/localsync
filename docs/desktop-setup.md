# Desktop setup for LocalSync

LocalSync syncs a phone's Obsidian vault to a folder on a desktop computer over the local network (Wi-Fi hotspot or the same Wi-Fi network) — nothing goes through a third-party server. Obsidian is the PKM (personal knowledge management app) LocalSync supports today; Logseq and other PKMs are a longer-term direction, not built yet — this guide is accurate to what LocalSync actually does right now.

Before linking a vault in the app, the desktop needs three things: **git**, **SSH access**, and **a bare git repository**. This guide covers Debian-based Linux (Linux Mint, Ubuntu, and similar) and macOS.

```mermaid
graph LR
    A["Phone<br/>Obsidian vault"] -- "LocalSync app,<br/>over SSH" --> B[("Bare git repository,<br/>on the desktop")]
    C["Desktop<br/>Obsidian vault"] -- "git push / pull" --> B
```

The bare repository is the thing both sides actually sync through — not a normal folder with files in it, just git history. Neither device talks to the other directly.

If all three are already set up (a bare repo exists, SSH is reachable), skip to [Settings values](#settings-values).

## 1. Git

**Debian-based Linux (Linux Mint, Ubuntu, and similar)** — usually already installed. Check and install if missing:
```
git --version
sudo apt update && sudo apt install -y git
```

**macOS** — installing the Xcode Command Line Tools installs git:
```
git --version
```
If that prompts an install of developer tools, accept — git comes with it, no separate download needed.

## 2. SSH access

LocalSync's phone-to-desktop sync runs entirely over SSH. Pairing (the one-time step that authorizes a phone) also connects over SSH, using the desktop login password — SSH needs to be running before pairing.

**Debian-based Linux** — SSH server isn't installed by default:
```
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

**macOS** — the SSH server is built in, just switched off by default:
- **System Settings → General → Sharing → Remote Login** → turn on.
- Optionally, restrict it to one user account rather than "All users."

**Either platform** — confirm the desktop login password will work over SSH (needed for pairing specifically, not for ongoing sync):
```
grep -i passwordauthentication /etc/ssh/sshd_config
```
If it says `PasswordAuthentication no`, change it to `yes`, then restart SSH (`sudo systemctl restart ssh` on Linux; toggle Remote Login off/on on macOS). This can go back to `no` after pairing once, if preferred — ongoing sync uses the key pairing installs, not the password.

## 3. Bare git repository

```
mkdir -p ~/Documents/LocalSync_repos
git init --bare ~/Documents/LocalSync_repos/my_vault.git
```

Any name and location works — `my_vault.git` and the path above are just an example. Note the **full absolute path** (e.g. `/home/username/Documents/LocalSync_repos/my_vault.git`, or on macOS `/Users/username/Documents/LocalSync_repos/my_vault.git`) — this exact path goes into LocalSync's Settings.

## Settings values

LocalSync's kebab menu → **Settings** needs two things, both with a ⓘ help button in the app itself showing the same commands:

**IP address - desktop**
```
# Debian-based Linux
ip -4 addr show
```
```
# macOS
ipconfig getifaddr en0
```
Look for the address on whichever interface the phone actually connects through — USB tethering and Wi-Fi hotspot show up as different interfaces, and the address changes when switching between them.

**Git bare repo path** — the exact absolute path from step 3 above (written out in full, not with `~`).

## 4. Phone pairing

In LocalSync: drag the phone icon onto the desktop icon → enter the desktop login password when prompted. This is used once, over the SSH connection, to install the phone's own key into `~/.ssh/authorized_keys` on the desktop — the password itself is never stored anywhere.

## 5. Vault linking

Kebab menu → **Add another vault** (or the first-run setup flow, for a first vault). For an Obsidian vault folder that already exists, use **"Already have a vault set up? Link it directly"** on the first screen to skip the from-scratch vault-creation walkthrough.

## Troubleshooting

LocalSync's own error dialogs (tap the vault name in the app bar, or the failure screen during setup) show a plain-language diagnosis, a fix, and — critically — the raw underlying error, so guessing shouldn't be necessary. Most connection failures trace back to one of:
- The desktop is asleep, or not on the same network as the phone right now.
- The IP address changed since it was last entered (see the Settings values section above).
- SSH isn't actually running (`sudo systemctl status ssh` on Linux; check Remote Login is on, on macOS).
