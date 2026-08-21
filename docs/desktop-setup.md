# Desktop setup for LocalSync

LocalSync syncs your phone's Obsidian vault to a folder on a desktop computer over your local network (Wi-Fi hotspot or the same Wi-Fi network) — nothing goes through a third-party server. Before linking a vault in the app, your desktop needs three things: **git**, **SSH access**, and **a bare git repository**. This guide covers Linux Mint and macOS.

If you already have all three set up (a bare repo exists, SSH is reachable), skip to [Getting your Settings values](#getting-your-settings-values).

## 1. Install git

**Linux Mint** — usually already installed. Check and install if missing:
```
git --version
sudo apt update && sudo apt install -y git
```

**macOS** — installing the Xcode Command Line Tools installs git:
```
git --version
```
If that prompts you to install developer tools, accept — this installs git along with it. No separate download needed.

## 2. Enable SSH access

LocalSync's phone-to-desktop sync runs entirely over SSH. Pairing (the one-time step that authorizes your phone) also connects over SSH, using your desktop login password — so SSH needs to be running before you pair.

**Linux Mint** — SSH server isn't installed by default:
```
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

**macOS** — the SSH server is built in, just switched off by default:
- **System Settings → General → Sharing → Remote Login** → turn on.
- Optionally, restrict it to your own user account rather than "All users."

**Either platform** — confirm your desktop login password will work over SSH (needed for pairing specifically, not for ongoing sync):
```
grep -i passwordauthentication /etc/ssh/sshd_config
```
If it says `PasswordAuthentication no`, change it to `yes`, then restart SSH (`sudo systemctl restart ssh` on Linux; toggle Remote Login off/on on macOS). You can turn it back to `no` after pairing once, if you prefer — ongoing sync uses the key that pairing installs, not your password.

## 3. Create a bare git repository

This is the actual thing your phone and desktop both sync through — not a normal folder with files in it, just the git history.

```
mkdir -p ~/Documents/LocalSync_repos
git init --bare ~/Documents/LocalSync_repos/my_vault.git
```

Pick any name and location — `my_vault.git` and the path above are just an example. Remember the **full absolute path** (e.g. `/home/yourname/Documents/LocalSync_repos/my_vault.git`, or on macOS `/Users/yourname/Documents/LocalSync_repos/my_vault.git`) — you'll enter this exact path in LocalSync's Settings.

## Getting your Settings values

LocalSync's kebab menu → **Settings** needs two things, both with a ⓘ help button in the app itself that shows the same commands:

**IP address - desktop**
```
# Linux Mint
ip -4 addr show
```
```
# macOS
ipconfig getifaddr en0
```
Look for the address on whichever interface your phone actually connects through — USB tethering and Wi-Fi hotspot show up as different interfaces, and the address changes when you switch between them.

**Git bare repo path** — the exact absolute path from step 3 above (e.g. `~/Documents/LocalSync_repos/my_vault.git`, written out in full, not with `~`).

## 4. Pair your phone

In LocalSync: drag the phone icon onto the desktop icon → enter your desktop login password when prompted. This is used once, over the SSH connection, to install your phone's own key into `~/.ssh/authorized_keys` on the desktop — the password itself is never stored anywhere.

## 5. Link the vault

Kebab menu → **Add another vault** (or the first-run setup flow if this is your first vault). If you already have an Obsidian vault folder ready to sync, use **"Already have a vault set up? Link it directly"** on the first screen to skip the from-scratch vault-creation walkthrough.

## Troubleshooting

If pairing or syncing fails, LocalSync's own error dialogs (tap the vault name in the app bar, or the failure screen during setup) show a plain-language diagnosis, a fix, and — critically — the raw underlying error, so you don't need to guess. Most connection failures trace back to one of:
- The desktop is asleep or not on the same network as the phone right now.
- The IP address changed since it was last entered (see step above).
- SSH isn't actually running (`sudo systemctl status ssh` on Linux; check Remote Login is on, on macOS).
