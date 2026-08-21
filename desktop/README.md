# desktop/localsync.service

Advertises this desktop as `_localsync._tcp` on the local network, so LocalSync's phone-side auto-discovery (`lib/services/discovery_service.dart`) can find it without typing an IP address by hand. Port matches whatever SSH is actually running on - 22 is the default used throughout `docs/desktop-setup.md`, change it inside the file if the desktop's SSH runs on a different port.

## Install

```
sudo cp desktop/localsync.service /etc/avahi/services/
sudo systemctl restart avahi-daemon
```

Requires avahi-daemon installed and running - see `docs/desktop-setup.md`'s Auto-discovery section for the full setup on Debian-based Linux and macOS.

## Real bug, found and fixed 2026-08-21

The file used to carry an explanatory comment directly inside the XML (`<!-- ... -->`). One line of that comment mentioned a shell flag combo containing two consecutive hyphens - which XML strictly forbids anywhere inside a comment body, only at the open/close markers. avahi-daemon silently rejected the entire file (`journalctl -u avahi-daemon` showed "Failed to load service group file... ignoring"), so nothing was ever actually advertised, despite the daemon itself running fine.

Fixed by moving all explanation out of the `.service` file entirely, into this README instead - the XML file itself is now minimal, nothing left to accidentally break the same way on a future edit.
