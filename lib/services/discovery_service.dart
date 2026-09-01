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
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:dartssh2/dartssh2.dart';
import 'ssh_key_paths.dart';

const kMdnsServiceType = '_localsync._tcp.local';

class DiscoveryService {
  /// Returns the desktop's current IP address, or null if nothing
  /// answered within [timeout]. Never throws - a missing/misconfigured
  /// desktop responder is an expected, common case (not every user
  /// will have set up avahi advertising), not an error condition.
  Future<String?> findDesktopIp({Duration timeout = const Duration(seconds: 5)}) async {
    // 2026-09-01: real bug, round 3 - confirmed on a real device (USB
    // cable, Wi-Fi off, no iOS Local Network permission popup ever
    // appearing) that the native multicast socket call itself can
    // block below Dart's event loop - not a Dart-level hang, so
    // neither of the two prior Future.timeout()/Future.any() fixes
    // could touch it. mDNS fundamentally cannot work without an
    // active Wi-Fi interface (confirmed elsewhere already - USB
    // tether is unreliable for multicast on iOS even when it does
    // something). Checking that first and skipping the native call
    // entirely, rather than attempting a call already confirmed able
    // to hang the whole isolate.
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) {
      return null;
    }
    final client = MDnsClient();
    try {
      // 2026-09-01: real bug, round 2 - the first fix only wrapped the
      // lookup chain, not client.start() itself. If start() (opening
      // the multicast socket, joining the group) ever stalls - a real
      // possibility on iOS if the Local Network permission prompt is
      // still pending/unanswered - the timeout below never even started
      // counting, so "still forever" after the first fix would be
      // explained by this. Timeout now wraps start()+lookup() together,
      // so nothing inside this function can run unbounded.
      return await _startAndLookup(client)
          .timeout(timeout, onTimeout: () => null);
    } on SocketException {
      // No local network reachable at all (e.g. cellular-only, no
      // Wi-Fi/tether) - same "expected, not an error" reasoning as a
      // plain timeout.
      return null;
    } finally {
      client.stop();
    }
  }

  // 2026-09-01: real feedback - mDNS's own native multicast call is the
  // one confirmed able to hang below Dart's event loop (see
  // findDesktopIp()'s header comment) - not something a fallback using
  // the SAME mechanism could ever fix. This is a genuinely different
  // path: plain TCP connect() probes, which go through the normal Dart
  // socket API a Future.timeout() can actually preempt.
  //
  // Disambiguating "which host is actually the desktop" doesn't need a
  // vendor/MAC lookup (not reliably possible from an iOS app anyway -
  // Apple doesn't expose the local ARP table to third-party apps,
  // unlike a desktop OS) - the phone already holds a private key that
  // only the real, previously-paired desktop has installed in its
  // authorized_keys. A real SSH auth handshake is a strictly stronger
  // and simpler signal than guessing from a hostname/vendor: any host
  // that accepts it IS the paired desktop, full stop.
  //
  // 2026-09-01: real bug, live device - "USB cable connected, IP not
  // found" on a phone with no prior successful pairing. The original
  // version bailed out before even scanning if no local keypair
  // existed, which meant a genuinely new user got zero benefit from
  // this even on a cable link with only one real candidate on the
  // other end. Fixed: the port-22 scan (stage 1, no key/pairing needed
  // at all) now always runs. Auth-verification (stage 2) still needs a
  // key and is skipped cleanly if none exists yet, rather than the
  // whole function bailing. If verification can't run or nothing
  // verifies, but exactly ONE host answered on port 22, there's no
  // real ambiguity to guess wrong on - a personal iPhone hotspot/cable
  // link realistically has only the desktop listening on 22 - so that
  // single candidate is returned unverified (stage 3). More than one
  // open host with nothing verified stays a real "can't tell which"
  // case and correctly falls through to Manual setup.
  Future<String?> scanAndVerifyDesktop({
    required String username,
    Duration portTimeout = const Duration(milliseconds: 400),
    Duration authTimeout = const Duration(seconds: 3),
  }) async {
    final localIps = <String>{
      for (final iface in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false))
        for (final addr in iface.addresses) addr.address,
    };
    if (localIps.isEmpty) return null;

    // Real subnet masks aren't available cross-platform from dart:io -
    // iOS has no public API for them - so this assumes /24 off each
    // local address, which comfortably covers both a typical home/
    // office LAN and Apple Personal Hotspot's own 172.20.10.0/28 (a
    // subset of that /24).
    final candidates = <String>{};
    for (final ip in localIps) {
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
      for (var i = 1; i <= 254; i++) {
        final candidate = '$prefix.$i';
        if (!localIps.contains(candidate)) candidates.add(candidate);
      }
    }

    // Stage 1: cheap parallel TCP connect probe on port 22 - rules out
    // the ~250 addresses with nothing listening in well under a second,
    // before spending time on any real SSH handshake.
    final open = <String>[];
    await Future.wait(candidates.map((ip) async {
      try {
        final socket = await Socket.connect(ip, 22, timeout: portTimeout);
        socket.destroy();
        open.add(ip);
      } catch (_) {
        // Closed/filtered/unreachable - the overwhelming common case
        // for a /24 scan, not an error worth surfacing.
      }
    }));
    if (open.isEmpty) return null;

    // Stage 2: real SSH key auth against each host with 22 open - only
    // possible once this phone actually has a keypair (from a prior
    // pairing attempt) and a username to try it with.
    if (username.isNotEmpty) {
      final privateKeyFile = File(await SshKeyPaths.privateKeyPath());
      if (await privateKeyFile.exists()) {
        final identities =
            SSHKeyPair.fromPem(await privateKeyFile.readAsString());
        for (final ip in open) {
          SSHSocket? socket;
          try {
            socket = await SSHSocket.connect(ip, 22, timeout: authTimeout);
            final client = SSHClient(socket,
                username: username, identities: identities);
            await client.authenticated.timeout(authTimeout);
            client.close();
            return ip;
          } catch (_) {
            socket?.close();
            continue;
          }
        }
      }
    }

    // Stage 3: no verified match - either no keypair yet (first
    // pairing) or none of the open hosts accepted this one. A single
    // open candidate is still worth returning unverified; see the
    // header comment for why that's safe here.
    if (open.length == 1) return open.first;
    return null;
  }

  Future<String?> _startAndLookup(MDnsClient client) async {
    await client.start();
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
