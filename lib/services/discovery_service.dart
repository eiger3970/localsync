// services/discovery_service.dart
//
// 2026-08-21: real auto-discovery, item 2 of the IAP build order -
// "the actual barrier to entry" (repeated across this project's whole
// history) has always been manually typing the desktop's IP address,
// which drifts every time it switches between USB tether and Hotspot
// Wi-Fi. This finds it automatically via mDNS instead, scoped
// specifically to the IP - the Git bare repo path is a one-time value
// that doesn't drift the same way, so it stays manual for now (real
// scope decision, not an oversight - broadening this to auto-fill the
// path too is a later step if it turns out to matter).
//
// Requires the desktop to be advertising _localsync._tcp via mDNS -
// see docs/desktop-setup.md's Auto-discovery section for the avahi
// service file. Nothing on the phone side can make an un-advertising
// desktop discoverable; this only finds a desktop that's actually
// broadcasting.

import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';

const kMdnsServiceType = '_localsync._tcp.local';

class DiscoveryService {
  /// Returns the desktop's current IP address, or null if nothing
  /// answered within [timeout]. Never throws - a missing/misconfigured
  /// desktop responder is an expected, common case (not every user
  /// will have set up avahi advertising), not an error condition.
  Future<String?> findDesktopIp({Duration timeout = const Duration(seconds: 5)}) async {
    final client = MDnsClient();
    try {
      await client.start();
      // 2026-09-01: real bug - only the PTR lookup below had its own
      // .timeout(); the SRV and A-record lookups nested inside it had
      // none at all. A device that answers the first mDNS query but
      // never answers the follow-ups (stale/misconfigured record) hung
      // this forever - "searches for more than 5 seconds, just forever"
      // was real, not a UI perception issue. One overall timeout around
      // the whole lookup chain guarantees the promised bound regardless
      // of which specific step stalls.
      return await _lookup(client).timeout(timeout, onTimeout: () => null);
    } on SocketException {
      // No local network reachable at all (e.g. cellular-only, no
      // Wi-Fi/tether) - same "expected, not an error" reasoning as a
      // plain timeout.
      return null;
    } finally {
      client.stop();
    }
  }

  Future<String?> _lookup(MDnsClient client) async {
    final ptrStream = client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(kMdnsServiceType));
    await for (final ptr in ptrStream) {
      final srvStream = client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName));
      await for (final srv in srvStream) {
        final ipStream = client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target));
        await for (final ip in ipStream) {
          return ip.address.address;
        }
      }
    }
    return null;
  }
}
