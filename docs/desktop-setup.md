# Desktop setup for LocalSync

LocalSync syncs a phone's Obsidian vault to a folder on a desktop computer over the local network (Wi-Fi hotspot, the same Wi-Fi network, or USB tether) - nothing goes through a third-party server.

Obsidian is a PKM (personal knowledge management) app LocalSync supports today;
Logseq and other PKMs are a longer-term direction, not built yet.
- this guide is accurate to what LocalSync actually does right now.

2 things needed on the desktop before linking a vault in LocalSync:
- **Git**
- **SSH access**

The Git bare repository itself no longer needs a manual step (2026-08-28) - LocalSync creates it on the desktop automatically, the first time it pairs, over the same SSH access pairing already sets up. Nothing to run by hand unless you want a specific existing path reused (see [Git bare repository](#-3-git-bare-repository) below).

This guide covers Debian-based Linux (Linux Mint, Ubuntu, Raspberry Pi 5, and similar) and macOS.

**Automated option**: `desktop/setup.yml` is an Ansible playbook that does everything below automatically - git, SSH, the bare repository, and auto-discovery. Real, tested against a live desktop, idempotent (safe to re-run, only changes what's actually missing).
```
ansible-playbook desktop/setup.yml
```
On macOS it also installs a persistent LaunchDaemon for auto-discovery (survives a reboot, unlike the manual `dns-sd -R` command further down this guide). Windows isn't covered - no native SSH-by-default, no apt/brew equivalent, a genuinely separate problem, not an oversight.

```mermaid
graph LR
    A["Phone<br/>Obsidian vault"] -- "LocalSync app,<br/>over SSH" --> B[("Git bare repository,<br/>on the desktop")]
    C["Desktop<br/>Obsidian vault"] -- "git push / pull" --> B
    style B fill:#00FF41,stroke:#333,stroke-width:2px,color:#000
```

The Git bare repository is the thing both sides (desktop and phone) actually sync through - not a normal folder with files in it, just git history.

Neither device talks to the other directly, and a second synced copy of the vault's text notes is itself a convenient backup - if one device is lost or fails, the other still has everything (binary attachments aren't covered by this - kept out of scope here deliberately).

The desktop side of the sync (the `git push / pull` step above) can run by hand, or automated via `desktop/localsync_sync.sh` - see [Desktop-side sync automation](#-desktop-side-sync-automation-optional) below. It is not installed on the desktop automatically by anything - it's a file in this repo you copy over and set up yourself, once.

If both are already set up (git is installed, SSH is reachable), skip to [Settings values](#settings-values).

## 🌿 1. Git

**Debian-based Linux (Linux Mint, Ubuntu, Raspberry Pi 5, and similar)** - usually already installed. Check and install if missing:
```
git --version
sudo apt update && sudo apt install -y git
```

**macOS** - installing the Xcode Command Line Tools installs git:
```
git --version
```
If that prompts an install of developer tools, accept - git comes with it, no separate download needed.

## 🔐 2. SSH access

LocalSync's phone-to-desktop sync runs entirely over SSH. Pairing (the one-time step that authorizes a phone) also connects over SSH, using the desktop login password - SSH needs to be running before pairing.

**Debian-based Linux** - SSH server isn't installed by default:
```
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

**macOS** - the SSH server is built in, just switched off by default:
- **System Settings → General → Sharing → Remote Login** → turn on.
- Optionally, restrict it to one user account rather than "All users."

**Either platform** - confirm the desktop login password will work over SSH (needed for pairing specifically, not for ongoing sync):
```
grep -i passwordauthentication /etc/ssh/sshd_config
```
If it says `PasswordAuthentication no`, change it to `yes`, then restart SSH (`sudo systemctl restart ssh` on Linux; toggle Remote Login off/on on macOS). This can go back to `no` after pairing once, if preferred - ongoing sync uses the key pairing installs, not the password.

## 📦 3. Git bare repository

**Automatic as of 2026-08-28** - the first time LocalSync pairs with this desktop, it creates the bare repository itself at whatever path is typed into Settings, using the SSH access pairing just installed (`git_service.dart`'s `_ensureBareRepoExists()`). Nothing to run here by hand for a fresh setup.

A single, recommended path if the Settings field is otherwise empty - no need to decide this from scratch:
```
/home/username/Documents/Git/LocalSync/vault.git
```
(macOS: `/Users/username/Documents/Git/LocalSync/vault.git`)

Type the **full absolute path** into LocalSync's Settings; the folder and bare repo both get created automatically if they don't already exist. Only run `git init --bare <path>` by hand if pointing at a specific path you've already created for another reason - the automatic step is idempotent and never touches a bare repo that already exists.

## 📡 Auto-discovery (optional)

The desktop's IP address is the one setting that genuinely drifts - it changes every time the phone switches between USB tether and Hotspot Wi-Fi. This step lets LocalSync find it automatically instead of typing it in by hand each time. Skip this section entirely and enter the IP manually if preferred - it's optional, not required for the app to work.

**Debian-based Linux**:
```
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
sudo cp desktop/localsync.service /etc/avahi/services/
```
The service file (`desktop/localsync.service` in this repo) advertises the desktop as `_localsync._tcp` on port 22 - change the port inside the file first if SSH runs somewhere else.

**macOS**: Bonjour is built in, no install needed. Advertise the service ad-hoc for testing:
```
dns-sd -R "LocalSync" _localsync._tcp local 22
```
This only lasts while that terminal command keeps running - a persistent version needs a LaunchDaemon, not covered here yet.

In LocalSync's Settings, tap the 📡 icon next to **IP address - desktop** to search - if the desktop is reachable and advertising, its address fills in automatically.

## ⚙️ Settings values

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
Look for the address on whichever interface the phone actually connects through - USB tethering and Wi-Fi hotspot show up as different interfaces, and the address changes when switching between them.

**Git bare repo path** - the exact absolute path from step 3 above (written out in full, not with `~`).

## 🤝 4. Phone pairing

In LocalSync, follow the walkthrough: drag the phone icon onto the desktop icon → enter the desktop login password when prompted.

This is used once, over the SSH connection, to install the phone's own key into `~/.ssh/authorized_keys` on the desktop

- the password itself is never stored anywhere.

## 📓 5. Vault linking

Kebab menu → **Add another vault** (or the first-run setup flow upon install, for a first vault). For an Obsidian vault folder that already exists, use **"Already have a vault set up? Link it directly"** on the first screen to skip the from-scratch vault-creation walkthrough.

## 🔁 Desktop-side sync automation (optional)

`desktop/localsync_sync.sh` keeps the desktop's own working copy (a real Obsidian vault open on the desktop, or just a synced folder for Tier 0) up to date against the bare repository - fetch, compare, and either fast-forward or a real three-way merge with the same conflict repair the phone app itself uses (markdown conflict callouts, Kanban-safe, and a back-up-both-keep-ours safety net for any non-text file). Real, tested against local temp repos including a same-run markdown + binary conflict - not yet tested against a live bare repo over real SSH from another machine.

It is **not** installed or run automatically by anything - copy it onto the desktop yourself, once:
```
mkdir -p ~/Documents/Scripts
cp desktop/localsync_sync.sh ~/Documents/Scripts/
chmod +x ~/Documents/Scripts/localsync_sync.sh
```

Configure via environment variables (or edit the defaults directly in the script) - they must match what's set in LocalSync's own Settings screen on the phone:
```
export LOCALSYNC_VAULT=~/Documents/LocalSync/vault        # desktop working copy
export LOCALSYNC_BARE_REPO=~/Documents/Git/localsync.git  # same path as Settings -> Git bare repo path
```

Run it by hand to test:
```
~/Documents/Scripts/localsync_sync.sh
```

To run it periodically instead of by hand, add a cron entry (`crontab -e`):
```
*/5 * * * * ~/Documents/Scripts/localsync_sync.sh
```
Logs to `~/.localsync_sync.log` by default (`LOCALSYNC_LOG` to change it) - check there first if a scheduled run doesn't seem to be doing anything.

## 🧪 Before linking a real vault

Test the whole flow once with a throwaway Obsidian vault first - create an empty vault with nothing important in it, link it, edit a note on each side, confirm sync works both ways. Once that's confirmed working, link the real vault. This costs a few minutes and removes any guesswork about whether a first real sync is safe.

## 🛠️ Troubleshooting

LocalSync's own error dialogs (tap the vault name in the app bar, or the failure screen during setup) show a plain-language diagnosis, a fix, and - critically - the raw underlying error, so guessing shouldn't be necessary. Most connection failures trace back to one of:
- The desktop is asleep, or not on the same network as the phone right now.
- The IP address changed since it was last entered (see the Settings values section above).
- SSH isn't actually running (`sudo systemctl status ssh` on Linux; check Remote Login is on, on macOS).
