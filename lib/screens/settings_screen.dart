// screens/settings_screen.dart
//
// 2026-08-20: replaces the one-off "Desktop IP" dialog with a real
// screen, now that there are two related network/repo-target settings
// instead of one - Desktop IP (database_service.dart's getDesktopIp/
// setDesktopIp) and Bare repo path (getBareRepoPath/setBareRepoPath,
// added for genuine multi-repo support: bareRepoPath used to be a
// build-time constant, meaning every "Add another vault" attempt
// pointed at the exact same bare repo regardless of which folder was
// picked - a real architectural gap, not just a UI inconvenience).
//
// Both fields write straight to the live LinkingController (via
// updateDesktopIp/updateBareRepoPath) so a change takes effect
// immediately, no app restart - and persist through RepositoryProvider
// so it survives a relaunch too.

import 'dart:math' show sin, pi, Random;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../features/linking/linking_controller.dart';
import '../services/repository_provider.dart';
import '../services/theme_service.dart';
import '../services/discovery_service.dart';

class SettingsScreen extends StatefulWidget {
  // 2026-08-30: real device feedback - "the yellow warning label is
  // needed at top, as dumping user in settings needs the info." Auto-
  // navigating straight here (linking_screen.dart's _onKeyPairingSettled,
  // replacing the old tap-a-SnackBar step) removed the one place that
  // explained WHY the user landed here - this restores that explanation,
  // as a real banner on this screen instead of a since-dismissed SnackBar
  // on the previous one.
  final bool neededForPairing;
  const SettingsScreen({super.key, this.neededForPairing = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  static final _ipPattern =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  late final TextEditingController _userCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _pathCtrl;
  String? _userError;
  String? _ipError;
  String? _pathError;

  // 2026-08-21: auto-discovery interest capture - see database_service.
  // dart's getAutoDiscoveryInterest for why this is local-only, not a
  // live pricing test. Loaded once so the card can show which price (if
  // any) was already tapped, rather than always looking untapped.
  String? _interestSelected;

  // 2026-08-21: real auto-discovery, item 2 of the IAP build order -
  // scoped to the IP field only, see discovery_service.dart's header
  // for why. Unrestricted/free for now, same "build first, wire in
  // the purchase gate later" split already applied to skins and the
  // conflict picker.
  final _discovery = DiscoveryService();
  bool _discovering = false;

  // 2026-08-28: real feedback, live - "Use suggested path" auto_awesome
  // icon read as a static glyph, not the "sparkle" it's meant to imply -
  // same sine-wave twinkle ShreddingPasswordField already uses for its
  // password-field prefix icons, just a single icon here instead of a
  // two-star cluster.
  //
  // 2026-08-30: real device feedback - "glowing stars... change to
  // twinkling," and separately the satellite icon's "alternating stars"
  // - both were ONE controller (this one, one period, one phase),
  // exactly the "seesaw, not independent twinkling" pattern
  // ShreddingPasswordField's own 2026-08-26 comment already diagnosed
  // and fixed there (two controllers, different non-integer-ratio
  // periods, random per-instance phase seeds - a single shared phase
  // reads as smooth/regular breathing, not irregular sparkle). This
  // screen never got that same fix. Same two-controller technique now,
  // reused directly rather than re-solving an already-solved problem.
  final _sparkleRand = Random();
  late final AnimationController _sparkleCtrl1;
  late final AnimationController _sparkleCtrl2;
  late final double _sparklePhase1;
  late final double _sparklePhase2;
  late final double _sparklePhase3;
  late final double _sparklePhase4;

  double _twinkle(AnimationController ctrl, double phaseSeed) {
    final phase = (ctrl.value + phaseSeed) % 1.0;
    return sin(phase * pi * 2) * 0.35 + 0.65;
  }

  // 2026-08-28: real feedback, live - "might tier0 users need a folder
  // to store multiple git files in or just the one?" Real gap the
  // question surfaced: this button always suggested the exact same
  // path, so a second linked folder/vault would collide with the
  // first - RepositoryProvider's own dedup check keys on remote
  // identity and silently no-ops a second repo pointed at a bare repo
  // already in use, with zero user-facing error (see
  // linking_screen.dart's _saveRepository()). Counts taps this Settings
  // visit so each suggestion is genuinely distinct - "sync.git" first,
  // "sync-2.git" next, etc.
  int _suggestCount = 0;

  // 2026-08-30: extracted from the old "Use suggested path" text link's
  // inline onTap so the big laptop icon above the field can trigger the
  // exact same autofill - one shared handler, two tap targets.
  void _useSuggestedPath() {
    final user = _userCtrl.text.trim();
    if (user.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSurface,
          content: Text('Fill in Desktop username above first',
              style: TextStyle(color: kStar, fontSize: 14)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      // 2026-08-28: real feedback, live - "why did you make a weird
      // default path name?" Dropped the /LocalSync/sync.git subfolder
      // split in favour of matching this repo's own real naming
      // convention (lowercase, flat) - and counts taps so a second/
      // third suggestion this Settings visit doesn't collide with the
      // first (see _suggestCount's own comment for why that collision
      // is a real, not hypothetical, gap). Was
      // '/home/$user/Documents/Git/LocalSync/sync.git' (and vault.git
      // before that).
      _suggestCount++;
      final suffix = _suggestCount == 1 ? '' : '-$_suggestCount';
      _pathCtrl.text = '/home/$user/Documents/Git/localsync$suffix.git';
      _pathError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<LinkingController>();
    _userCtrl = TextEditingController(text: ctrl.desktopUser);
    _ipCtrl = TextEditingController(text: ctrl.desktopIp);
    _pathCtrl = TextEditingController(text: ctrl.bareRepoPath);
    _sparklePhase1 = _sparkleRand.nextDouble();
    _sparklePhase2 = _sparkleRand.nextDouble();
    _sparklePhase3 = _sparkleRand.nextDouble();
    _sparklePhase4 = _sparkleRand.nextDouble();
    _sparkleCtrl1 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat();
    _sparkleCtrl2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1900))
      ..repeat();
    context.read<RepositoryProvider>().getAutoDiscoveryInterest().then((v) {
      if (mounted) setState(() => _interestSelected = v);
    });
  }

  // 2026-08-21: real feedback, live - "there needs to be user help...
  // commands that are most optimised to human readable output, so the
  // user can smoothly step through the setup." Neither value can be
  // auto-filled without real auto-discovery (see the card below), so
  // this is the cheap tier: the exact command to run on the desktop.
  //
  // 2026-08-21, same day, round 2 - two real fixes from live feedback:
  // (1) "the text wrap makes the user wonder if there's a space or no
  // space after name" - a long shell command soft-wrapping mid-token is
  // genuinely ambiguous about whitespace. Wrapped in a horizontal-
  // scrolling SingleChildScrollView with softWrap:false so it always
  // renders as the exact one-line string, scroll instead of wrap.
  // (2) "this block is verbose... maybe in point form or with progress
  // arrows" - the explanatory paragraph became a short bulleted list
  // (chevron + short phrase per line) instead of one dense sentence.
  //
  // 2026-08-21, round 3: "note bullet points and indents" - the two
  // network-interface lines are genuinely sub-items of "run this
  // command," not siblings of it, so points now carry an indent flag
  // (record: (text, indented)) rather than one flat list.
  void _showHelp(String title, String command, List<(String, bool)> points) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(title, style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-08-21: real feedback, live - "an easy copy to the
            // command, which is confusing to type out... if UX can be
            // made easier, great." Long-press-to-select already worked
            // via SelectableText, but that's not discoverable - a
            // one-tap copy button is the obvious affordance. Doesn't
            // solve pasting into the desktop terminal itself (no shared
            // clipboard between phone and desktop), but removes any
            // need to type the command out by hand somewhere it CAN be
            // pasted (a notes app, an SSH client, etc).
            //
            // 2026-08-28: real feedback, live - "be clearer like:
            // Command for your desktop terminal:" - the box below had
            // no label at all explaining what it was or where it's
            // meant to be run, just an unmarked monospace string.
            Text('Command for your desktop terminal:',
                style: TextStyle(color: kTextMid, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
              decoration: BoxDecoration(
                  color: kVoid, border: Border.all(color: kBorder)),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(command,
                          maxLines: 1,
                          style: TextStyle(
                              color: kGreen,
                              fontFamily: 'monospace',
                              fontSize: 13)),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, color: kTextMid, size: 18),
                    tooltip: 'Copy command',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: command));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: kSurface,
                          content: Text('Command copied',
                              style: TextStyle(color: kStar, fontSize: 14)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final (text, indented) in points)
              Padding(
                padding: EdgeInsets.only(bottom: 6, left: indented ? 20 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2026-08-21: real feedback, live - "still have
                    // greater than signs, use bullet point dots."
                    // Icons.chevron_right renders as a ">" shape - that
                    // was the actual complaint, not the arrow text
                    // fixed last round. Plain "•" text for both levels,
                    // no icon glyph that can be misread as an arrow.
                    SizedBox(
                      width: 16,
                      child: Text('•',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: kTextMid,
                              fontSize: indented ? 12 : 15,
                              height: 1.35)),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(
                              color: kTextMid, fontSize: 13, height: 1.35)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it', style: TextStyle(color: kGreen)),
          ),
        ],
      ),
    );
  }

  Future<void> _setInterest(String price) async {
    setState(() => _interestSelected = price);
    await context.read<RepositoryProvider>().setAutoDiscoveryInterest(price);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSurface,
          content: Text(
            price == 'no'
                ? 'Noted - thanks for the honest answer.'
                : 'Noted - $price signal saved.',
            style: TextStyle(color: kStar, fontSize: 14),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _ipCtrl.dispose();
    _pathCtrl.dispose();
    _sparkleCtrl1.dispose();
    _sparkleCtrl2.dispose();
    super.dispose();
  }

  Future<void> _findDesktop() async {
    setState(() => _discovering = true);
    final ip = await _discovery.findDesktopIp();
    if (!mounted) return;
    setState(() => _discovering = false);
    if (ip != null) {
      _ipCtrl.text = ip;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSurface,
          content: Text('Found desktop at $ip',
              style: TextStyle(color: kStar, fontSize: 14)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kSurface,
        content: Text(
          // 2026-08-28: real feedback, live - "the satellite is only
          // for wireless, but my phone is connected via USB, so I just
          // sat there waiting forever." Auto-discovery is mDNS-based
          // and works over Wi-Fi hotspot reliably; USB tether is real
          // but genuinely less reliable for multicast on iOS. The old
          // message never mentioned USB at all, leaving a USB-connected
          // tester with no idea to fall back to the manual command
          // instead of retrying the same search.
          'No desktop found on Wi-Fi. On USB tether, use the (i) '
          'button below instead for the manual command.',
          style: TextStyle(color: kStar, fontSize: 14),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _save() async {
    final user = _userCtrl.text.trim();
    // 2026-08-28: real feedback, live - "the keyboard has no means to
    // type in 172.20.10.11/28" - `ip addr show` (this app's own help
    // dialog tells the user to run it) prints addresses in CIDR form,
    // and a pasted value carries the /28 straight through even though
    // the numeric keyboard itself has no slash key to type one by hand.
    // Stripped before validating rather than rejected outright - the
    // prefix length was never meaningful here, just noise from the
    // source command's output format.
    final ip = _ipCtrl.text.trim().split('/').first;
    _ipCtrl.text = ip;
    final path = _pathCtrl.text.trim();
    setState(() {
      // 2026-08-28: same "can't be empty" validation as the bare repo
      // path below - an empty desktopUser would mean every SSH
      // connection tries to log in as no one at all.
      _userError = user.isEmpty ? 'Can\'t be empty' : null;
      _ipError = _ipPattern.hasMatch(ip) ? null : 'Not a valid IP address';
      _pathError = path.isEmpty ? 'Can\'t be empty' : null;
    });

    // 2026-08-28: real bug, live - "Same error: Desktop username and IP
    // address have not been set yet" after a save attempt that DID
    // include a real username. Root cause: this used to gate all three
    // fields behind one combined `if (anyError) return` - one invalid
    // field (the IP, mistyped with a CIDR suffix) silently discarded
    // two other perfectly valid fields instead of saving what it could.
    // Each field now saves independently; only the screen's own close
    // waits for every field to be valid, so a user fixing one bad field
    // doesn't lose what they already got right.
    final linkingCtrl = context.read<LinkingController>();
    final provider = context.read<RepositoryProvider>();
    if (_userError == null) {
      await provider.setDesktopUser(user);
      linkingCtrl.updateDesktopUser(user);
    }
    if (_ipError == null) {
      await provider.setDesktopIp(ip);
      linkingCtrl.updateDesktopIp(ip);
    }
    if (_pathError == null) {
      await provider.setBareRepoPath(path);
      linkingCtrl.updateBareRepoPath(path);
    }
    if (_userError != null || _ipError != null || _pathError != null) return;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 2026-08-22: was explicit `kVoid` here, same as the theme
      // default anyway - but an explicit value on THIS Scaffold
      // overrides ThemeData.scaffoldBackgroundColor, which is now
      // transparent so main.dart's global FlagBackdrop (void fill +
      // bold skins' tiled mini-flags) can show through underneath
      // every screen. Removed so this screen isn't a hole in that.
      appBar: AppBar(
        backgroundColor: kVoid,
        title: Text('Settings', style: TextStyle(color: kStar)),
      ),
      // 2026-08-30: real device feedback - "the yellow info bit pushes
      // down the Save button under the apple number keyboard, so there's
      // no obvious progress for the user, the user now has to scroll up
      // and find the Save button." Save used to sit mid-scroll, between
      // the 3 fields and the Skins card below - any extra content above
      // it (the new banner, a focused field's own error text, the
      // keyboard itself) pushed it further out of view with nothing
      // fixed on screen to reach it. Moved to bottomNavigationBar - but
      // that alone genuinely does NOT avoid the keyboard on its own
      // (verified with a real golden-test measurement: still landed
      // fully behind a simulated keyboard, "still can't access Save"
      // confirmed the same on a real device). SafeArea only accounts for
      // the device's own safe-area insets (home indicator etc.), not
      // MediaQuery.viewInsets (the keyboard) - explicit bottom padding
      // matching the live keyboard height is what actually pushes this
      // above it.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.neededForPairing) ...[
              // 2026-08-30: real device feedback - "the yellow warning
              // label is needed at top, as dumping user in settings
              // needs the info." Same amber treatment the old SnackBar
              // used, now living on the screen it's actually explaining
              // instead of a message that could be missed/mis-tapped
              // before this screen even opened.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  // 2026-08-30: real device feedback - "too complicated
                  // for a new user and wrong order" (naming all 3 fields
                  // inline read as a checklist to parse, not a plain
                  // instruction). The 3 fields below now carry their own
                  // numbered headers (1/2/3), so this just needs to say
                  // why they're here, not repeat what they are.
                  'Pairing to desktop, needs below filled in to connect.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kVoid, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 20),
            ],
            // 2026-08-28: real feedback, live - found while checking an
            // unrelated UX question: desktopUser was hardcoded in
            // main.dart with no Settings field at all, meaning a real
            // customer whose desktop login isn't 'rapi5' would have
            // every SSH connection fail immediately, with no way to fix
            // it on-device. New first field, alphabetically ahead of
            // "Git bare repo path" per the 2026-08-21 ordering decision
            // below.
            //
            // 2026-08-30: real device feedback - "add 1/2/3 to the
            // headers, same theme as the FILE SYNC SETUP page." Exact
            // same style as that screen's own "1. PAIR YOUR DEVICE" step
            // headers (linking_screen.dart) - visual consistency only,
            // not the sequential locking that screen also does (flagged
            // separately - this page is also used to edit one already-
            // configured field later, which a hard lock would break).
            Text('1. DESKTOP USERNAME',
                style: TextStyle(
                    color: kGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  // 2026-08-30: real device feedback - "the 3 icons
                  // aren't consistent... I prefer the green." Was
                  // kTextMid (a muted grey), inconsistent with the git
                  // bare repo path field's own accent-colored icon.
                  child: Icon(Icons.person_outline, color: kGreen, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _userCtrl,
                    style: TextStyle(color: kStar, fontSize: 16),
                    decoration: InputDecoration(
                      // 2026-08-30: real device feedback - "3 headers in
                      // green are good, this means the other headers are
                      // doubling up and can be removed." This field's own
                      // "Desktop username" label duplicated the new
                      // "1. DESKTOP USERNAME" step header above it -
                      // removed (with the styling it needed to read as a
                      // header, now unused). hintText/helperText stay,
                      // they carry different information.
                      helperText: 'The login username on your desktop - '
                          'what you\'d type to sign in there',
                      helperMaxLines: 2,
                      helperStyle: TextStyle(color: kTextMid, fontSize: 13),
                      hintText: 'e.g. rapi5',
                      errorText: _userError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Divider(color: kBorder, height: 1),
            const SizedBox(height: 28),
            // 2026-08-20: real feedback, live - "looks complicated, less
            // verbose is better." Both labels cut to one short line,
            // same trim already applied elsewhere in this app for the
            // same complaint.
            // 2026-08-20: real bug, live - label/helper text rendered
            // smaller than the input text itself (Material's default
            // InputDecoration sizing), backwards from what's readable.
            // Explicit styles here match this app's established
            // kStar/kTextMid readability fixes rather than trusting
            // the theme's small defaults for these two roles.
            // 2026-08-21: real feedback, live - labels still read as
            // body text next to a full-screen field, not as section
            // headers. Bumped to the 18px/w700 size already used for
            // section headers elsewhere (see home_screen.dart's
            // _SectionTitle-equivalent header text). Renamed "Desktop
            // IP" -> "IP address - desktop" (matches user's own
            // requested wording, applied everywhere this string
            // appears - see home_screen.dart's Settings menu subtitle).
            // "Bare repo path" -> "Git bare repo path" - user's own
            // notes (Knowledge_base_Raspberry_Pi.md, Knowledge_base_
            // obsidian.md) consistently say "Git bare repo", never
            // "bare repository", confirmed by grep before renaming
            // rather than guessed. Icons are built-in Material glyphs,
            // not custom SVG - same tradeoff already decided with the
            // user on 2026-08-18 for the Conflicts screen's icon row
            // (real risk of an invisible SVG rendering bug with no way
            // to preview before a sideload) - ask if genuine custom
            // icon art is wanted instead, budget the same iteration
            // cost as the pairing-screen SVGs took.
            // 2026-08-21: real feedback, live - "alphabetical" ordering
            // requested for both this screen's field order and the
            // kebab menu's Settings subtitle (see home_screen.dart) -
            // Git bare repo path now comes before IP address - desktop.
            //
            // 2026-08-30: real device feedback - "space above 2 is too
            // much, needs to be consistent with space above 3." The
            // extra SizedBox(24) added for this header on top of the
            // existing 28+divider+28 above was the mismatch - "3." below
            // uses that same 28+divider+28 with nothing extra added.
            // Removed to match.
            Text('2. GIT BARE REPO PATH',
                style: TextStyle(
                    color: kGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2026-08-29: real feedback, live - "git logo in wrong
                // place... leave header with just text, have the left
                // image as the git logo." Moved from the label into
                // this leading-icon slot, replacing the generic
                // Material glyph - the official Git icon mark
                // (git-scm.com/downloads/logos, CC BY 3.0), tinted to
                // kStar via colorFilter rather than baking a fixed
                // white into the asset, so it stays correct under any
                // skin.
                //
                // 2026-08-30: real device feedback - "too much confusion
                // with phone and desktop sides... user just sees desktop
                // or desktop git image and taps auto fill." Swapped the
                // small git mark for the same laptop glyph the pairing
                // screen already uses for "this is the desktop side"
                // (pairing_laptop_plain.svg) - bigger, and now the tap
                // target for the suggested-path autofill itself (see
                // _useSuggestedPath below), not just decoration.
                GestureDetector(
                  onTap: _useSuggestedPath,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 10),
                    // 2026-08-30: real device feedback, two rounds - the
                    // SVG fix (removing colorFilter) genuinely fixed the
                    // white-square bug, but then couldn't be made
                    // consistent with the other two fields' green icons
                    // without reintroducing it (srcIn on this multi-color
                    // asset flattens it back to one block, just green
                    // instead of white). Switched to a plain Material
                    // glyph, same tradeoff already decided with the user
                    // 2026-08-18 for the Conflicts screen icon row (see
                    // this Row's own 2026-08-21 comment below) - same
                    // size/color as Desktop username and IP address now.
                    //
                    // 2026-08-30, follow-up - "needs a git logo in the
                    // desktop screen." git-icon.svg (the official Git
                    // mark, unused since this field's icon changed a few
                    // rounds ago - a real, findable asset, not lost) -
                    // small, centered over where Icons.computer draws its
                    // screen area.
                    //
                    // 2026-08-30, real device bug round 2 - "black colour
                    // on top middle" (kVoid tint, invisible against the
                    // dark background), then round 3 - "reverse the git
                    // logo colour, black branching on white should be
                    // white branching on black." Two rounds of guessing
                    // which flat tint would read correctly against
                    // whatever's visually behind the overlay was the
                    // actual problem - a tiny logo sitting directly on
                    // top of another icon has no guaranteed background,
                    // so any single tint color is a guess. A small badge
                    // with its OWN fixed background removes that
                    // ambiguity entirely: the git mark now renders in its
                    // real, unambiguous brand color (#f03c2e, no tint at
                    // all) inside a small kVoid circle - always reads the
                    // same regardless of what's under the computer icon.
                    child: SizedBox(
                      width: 26,
                      height: 22,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(Icons.computer, color: kGreen, size: 22),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: kVoid,
                                shape: BoxShape.circle,
                                border: Border.all(color: kGreen, width: 1),
                              ),
                              padding: const EdgeInsets.all(2.5),
                              child: SvgPicture.asset(
                                'assets/logos/git-icon.svg',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _pathCtrl,
                    style: TextStyle(color: kStar, fontSize: 14),
                    decoration: InputDecoration(
                      // 2026-08-28: real feedback, live - "Git bare repo
                      // path... big word for newbies, need to add
                      // something basic." Kept the real technical name
                      // (still matches docs/desktop-setup.md and what a
                      // desktop terminal command would reference) but
                      // added the plain-language version alongside it
                      // rather than replacing it outright.
                      // 2026-08-29: real feedback, live - "make the
                      // headers larger... this text in brackets doesn't
                      // need to be enlarged." labelText can only take a
                      // single style for the whole string - switched to
                      // label: with a RichText so "Git bare repo path"
                      // can go to 17 while the parenthetical stays at
                      // the original 15.
                      // 2026-08-29: real feedback, live - "add git
                      // logo... same colour as other logos, white, not
                      // the standard git logo colour orange." Official
                      // Git icon mark (git-scm.com/downloads/logos, CC
                      // BY 3.0) moved to the field's leading icon slot
                      // instead (see Icon.account_tree replaced above) -
                      // "leave header with just text, have the left
                      // image as the git logo."
                      // 2026-08-30: real device feedback - "too much
                      // confusion with phone and desktop sides... any
                      // text can be under or in an info tip." The
                      // "(folder sharing to your phone)" parenthetical
                      // and the helperText below both moved into the (i)
                      // dialog instead of sitting always-visible - the
                      // big laptop icon now carries the "this is the
                      // desktop side" meaning on its own, verbosely
                      // spelling it out next to the label was the thing
                      // adding to the confusion, not resolving it.
                      // 2026-08-30: real device feedback - label removed,
                      // duplicated the new "2. GIT BARE REPO PATH" step
                      // header above it (same reasoning as Desktop
                      // username below).
                      hintText: '/home/user/Documents/Git/localsync.git',
                      errorText: _pathError,
                      // 2026-08-21: real feedback, live - "circle with
                      // i" instead of a "?" - Icons.info_outline reads
                      // as reference info, Icons.help_outline reads as
                      // "something's wrong, ask for help." This is
                      // neither - it's a lookup command, not a support
                      // request.
                      suffixIcon: IconButton(
                        icon:
                            Icon(Icons.info_outline, color: kTextDim, size: 20),
                        tooltip: 'How do I find this?',
                        // 2026-08-21: real question, live - "is this
                        // live if the user has a different git bare
                        // repo or is this hard coded text?" It WAS
                        // hardcoded to this developer's own repo name
                        // (Md_files_bare.git) - wrong for any other
                        // real vault. Now reads the field's own live
                        // text at the moment the dialog opens instead.
                        // 2026-08-28: real feedback, live - "how do I
                        // create a new LocalSync git folder? Can the app
                        // walk me through?" This help dialog only ever
                        // covered finding an EXISTING bare repo - no
                        // help at all for the much more common first-
                        // time case, someone with nothing to find yet.
                        // Since git_service.dart's _ensureBareRepoExists()
                        // (2026-08-28) creates the path automatically on
                        // first pairing, that's now the actual answer -
                        // leads with it instead of assuming a repo
                        // already exists.
                        onPressed: () => _showHelp(
                          'Setting the Git bare repo path',
                          "find ~/Documents/Git -maxdepth 3 -name '*.git' -type d",
                          [
                            // 2026-08-30: moved here from always-visible
                            // label text and helperText - both explained
                            // this same field, just repeated at a glance
                            // instead of on demand.
                            (
                              'Desktop side - a folder path '
                                  'on your desktop computer, shared to '
                                  'your phone',
                              false
                            ),
                            (
                              'New setup? Just type any path here, e.g. '
                                  '~/Documents/Git/localsync.git - '
                                  'it gets created automatically the '
                                  'first time you pair, nothing to run '
                                  'yourself',
                              false
                            ),
                            (
                              'Applies to a new folder you link - '
                                  'existing links are unaffected',
                              false
                            ),
                            (
                              'Already have one and want to reuse it? Run '
                                  'this on the desktop terminal instead',
                              false
                            ),
                            ('Lists every Git bare repo on the desktop', true),
                            if (_pathCtrl.text.trim().isNotEmpty)
                              (
                                'Currently set to: ${_pathCtrl.text.trim()}',
                                false
                              )
                            else
                              (
                                'Your real folder is usually the one you '
                                    'set up first',
                                false
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 2026-08-28: real feedback, live - "as simple as suggesting
            // a path... handhold the new customer." Now that
            // desktopUser is a real Settings field (not hardcoded), a
            // real suggestion can be built from it instead of asking the
            // user to type an absolute path from scratch. Linux
            // convention (/home/<user>/...) since that's this app's
            // primary documented platform - macOS users (~/Users/...
            // instead) still need to adjust it themselves, noted in the
            // snackbar-free case below rather than guessing the OS.
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: GestureDetector(
                // 2026-08-30: now shared with the big laptop icon above
                // (_useSuggestedPath) - same action, two tap targets.
                onTap: _useSuggestedPath,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 2026-08-28: real feedback, live - "stars aren't
                    // twinkling" - was a static Icon, same sine-wave
                    // opacity twinkle as ShreddingPasswordField's
                    // prefixIcon cluster, just one icon here.
                    //
                    // 2026-08-30: real device feedback - "glowing,
                    // change to twinkling." One controller/one phase
                    // reads as smooth breathing, not sparkle - averaging
                    // two independently-drifting controllers gives this
                    // single icon its own irregular beat pattern instead
                    // (a lone point needs that combination to read as
                    // twinkle at all; two separate points, like the
                    // satellite icon below, can each stay a plain single
                    // sine and still twinkle relative to each other).
                    AnimatedBuilder(
                      animation:
                          Listenable.merge([_sparkleCtrl1, _sparkleCtrl2]),
                      builder: (_, __) => Icon(Icons.auto_awesome,
                          color: kGreen.withValues(
                              alpha: (_twinkle(_sparkleCtrl1, _sparklePhase1) +
                                      _twinkle(_sparkleCtrl2, _sparklePhase2)) /
                                  2),
                          size: 15),
                    ),
                    const SizedBox(width: 5),
                    Text('Use suggested path',
                        style: TextStyle(
                            color: kGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            // 2026-08-21: real feedback, live - "add a line space above
            // to separate more from the above text, as all the
            // information looks like 1, rather than 2 controls." A
            // plain SizedBox gap alone wasn't enough separation - added
            // a visible divider line, same kBorder used for every other
            // section rule in this app, not just more whitespace.
            const SizedBox(height: 28),
            Divider(color: kBorder, height: 1),
            const SizedBox(height: 28),
            Text('3. IP ADDRESS - DESKTOP',
                style: TextStyle(
                    color: kGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2026-08-21: real feedback, live - a Wi-Fi glyph
                // implies wireless only, but this address can equally
                // come from USB tethering (wired) - Icons.lan is
                // connection-medium-neutral (a small network diagram,
                // not a radio-wave glyph), correct for either case.
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  // 2026-08-30: real device feedback - icon color
                  // consistency across all 3 fields, green preferred.
                  child: Icon(Icons.lan, color: kGreen, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: kStar, fontSize: 16),
                    decoration: InputDecoration(
                      // 2026-08-30: real device feedback - label removed,
                      // duplicated the new "3. IP ADDRESS - DESKTOP" step
                      // header above it (same reasoning as the two fields
                      // above).
                      // 2026-08-21: real feedback, live, two rounds.
                      // First round just reworded "Changes with Tether/
                      // Hotspot" without fixing the real bug - helperText
                      // truncates to one line with no wrap unless
                      // helperMaxLines is set explicitly (Flutter's
                      // default), which is why it showed "...". Fixed
                      // with helperMaxLines below. Second round: "why
                      // say Changes... reads like the app auto-corrects
                      // this, but it's manually entered" - reworded to
                      // an imperative ("Update this") instead of a
                      // passive "Changes", which implied automatic
                      // behavior that doesn't exist.
                      // 2026-08-28: real feedback, live - "this must be
                      // clear, it's a small ambiguity amongst many." The
                      // /28-suffix clarification only lived behind the
                      // (i) help dialog - not good enough on its own,
                      // needed to be visible with zero taps, right at
                      // the field itself, every time.
                      helperText: 'Just the 4 numbers, e.g. 172.20.10.11 - '
                          'no /28 suffix. Update manually after switching '
                          'Tether or Hotspot.',
                      helperMaxLines: 3,
                      helperStyle: TextStyle(color: kTextMid, fontSize: 13),
                      hintText: 'e.g. 172.20.10.2',
                      errorText: _ipError,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 2026-08-21: real auto-discovery - see
                          // discovery_service.dart. Free/unrestricted
                          // for now, scoped to just this field (the
                          // Git bare repo path doesn't drift the same
                          // way an IP does, so it stays manual).
                          IconButton(
                            // 2026-08-29: real feedback, live -
                            // "Satellite needs a little magic stars to
                            // hint its active" -> follow-up, live again,
                            // "needs more twinkly stars." One small
                            // badge read as too subtle - two stars at
                            // different sizes/positions/phases (same
                            // "cluster reads as sparkle, not one static
                            // glyph" precedent as the password fields'
                            // own prefixIcon), a fixed phase offset on
                            // the second star so they don't move in
                            // lockstep. Only while idle - the spinner
                            // already signals "active" once tapped.
                            icon: _discovering
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kGreen),
                                  )
                                : Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Icon(Icons.satellite_alt,
                                          color: kGreen, size: 20),
                                      // 2026-08-30: real device feedback -
                                      // "alternating stars, change to
                                      // twinkling." Both stars shared one
                                      // controller with a fixed 0.5 phase
                                      // offset - a perfectly predictable
                                      // seesaw (one bright exactly when
                                      // the other's dim), which is what
                                      // "alternating" actually described.
                                      // Each star now gets its own
                                      // controller/phase (same fix
                                      // ShreddingPasswordField already
                                      // has for its own two-star
                                      // cluster) - independent drift,
                                      // not a synced seesaw.
                                      Positioned(
                                        top: -4,
                                        right: -4,
                                        child: AnimatedBuilder(
                                          animation: _sparkleCtrl1,
                                          builder: (_, __) => Icon(
                                              Icons.auto_awesome,
                                              color: kGreen.withValues(
                                                  alpha: _twinkle(_sparkleCtrl1,
                                                      _sparklePhase3)),
                                              size: 13),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: -2,
                                        left: -6,
                                        child: AnimatedBuilder(
                                          animation: _sparkleCtrl2,
                                          builder: (_, __) => Icon(
                                              Icons.auto_awesome,
                                              color: kGreen.withValues(
                                                  alpha: _twinkle(_sparkleCtrl2,
                                                      _sparklePhase4)),
                                              size: 8),
                                        ),
                                      ),
                                    ],
                                  ),
                            tooltip: 'Find automatically (Wi-Fi only)',
                            onPressed: _discovering ? null : _findDesktop,
                          ),
                          IconButton(
                            icon: Icon(Icons.info_outline,
                                color: kTextDim, size: 20),
                            tooltip: 'How do I find this?',
                            // 2026-08-21: real feedback, live - reordered
                            // (Hotspot before USB tether, matching how the
                            // user listed it) and indented as sub-items of
                            // "run this command," not flat siblings of it.
                            onPressed: () => _showHelp(
                              'Finding the desktop IP address',
                              'ip -4 addr show',
                              const [
                                ('Run this on the desktop terminal', false),
                                // 2026-08-21: real bug, live - "they have
                                // greater than signs" - the unicode arrow
                                // (→) substituted for the plain "->" the
                                // user originally typed didn't render
                                // correctly on-device. Reverted to the
                                // exact ASCII form asked for the first time.
                                ('Hotspot Wi-Fi -> look for wlan0', true),
                                ('USB tether -> look for eth1 or usb0', true),
                                // 2026-08-28: real feedback, live - "the
                                // keyboard has no means to type in
                                // 172.20.10.11/28." This command's
                                // output includes a /prefix like that -
                                // the field strips it automatically now,
                                // but a clear note here means no one
                                // second-guesses it before saving.
                                (
                                  'Ignore the /28 (or similar) after the '
                                      'address - only the 4 numbers matter',
                                  true
                                ),
                                (
                                  'IP address changes every switch - re-run '
                                      'the command',
                                  false
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 2026-08-30: real device feedback - "Skins needs to be
            // better separated from the 3 steps, which will add
            // confusion to new users setting up pairing." Both cards
            // below are unrelated to pairing - simplest real fix is not
            // showing them at all in that specific context, rather than
            // just adding a stronger visual break that a new user would
            // still have to scroll past and wonder about. A normal
            // Settings visit (neededForPairing false) still sees both.
            if (!widget.neededForPairing) ...[
              const SizedBox(height: 32),
              _buildSkinsCard(),
              const SizedBox(height: 28),
              // 2026-08-29: real feedback, live - "this IAP would appear
              // in the Conflicts page when there's a conflict... move
              // this to Conflicts." Moved to conflicts_screen.dart, shown
              // only when there's a real conflict to resolve - see its
              // own comment there. This was only ever meant to sit here
              // temporarily (see the original 2026-08-21 note, removed),
              // while there was no purchasable Test Store product yet.
              _buildAutoDiscoveryCard(),
            ],
          ],
        ),
      ),
    );
  }

  // 2026-08-21: "skins" IAP, build phase - "build, if skins is
  // easiest, do first, then the rest." Unrestricted selection for
  // now, deliberately - the monetization gate (only terminalGreenPalette
  // free, the rest behind a purchase) is the "wire in" step the user
  // asked for separately, once there's a real product ID to gate
  // against. Right now every palette is freely selectable, so this is
  // actually testable today rather than sitting inert like
  // purchase_service.dart/ConflictPickerUpsell.
  Widget _buildSkinsCard() {
    final themeService = context.watch<ThemeService>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: kSurface, border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: kTextMid, size: 18),
              const SizedBox(width: 8),
              Text('SKINS',
                  style: TextStyle(
                      color: kTextMid,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 12),
          // 2026-08-21: was a single Expanded-in-a-Row (fine for 3
          // skins, cramped and overflow-prone once the national-flag
          // skins brought the count to 7) - Wrap with a fixed swatch
          // width lets it flow onto multiple lines cleanly instead.
          // 2026-08-29: real feedback, live, TWO rounds - "left
          // aligned, leaving a nasty right space" fixed with
          // WrapAlignment.center first, confirmed on-device it did
          // NOTHING. Real cause found on the second pass: the parent
          // Column uses CrossAxisAlignment.start, which never stretches
          // its children to the container's full width in the first
          // place - Wrap was shrink-wrapping to fit its own content, so
          // there was no extra space inside it for WrapAlignment.center
          // to center within. SizedBox(width: double.infinity) forces
          // the Wrap itself to actually span the full width first, so
          // centering has real room to do something.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final palette in allPalettes) ...[
                  // 2026-08-29: real feedback, live - "add a Customise
                  // button, left of the us skin... user sends me a text
                  // or image, I read it and design it (or have Claude AI
                  // design it)." Placed inline in the same grid, right
                  // before the first flag skin, rather than a separate
                  // section - reads as one more skin choice, not a
                  // different kind of thing bolted on.
                  if (palette.id == 'us')
                    const SizedBox(width: 84, child: _CustomiseSkinTile()),
                  SizedBox(
                    width: 84,
                    child: _SkinSwatch(
                      palette: palette,
                      selected: themeService.palette.id == palette.id,
                      onTap: () => themeService.select(palette),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2026-08-21: real feedback, live - "3 boxes with iap prices... would
  // love real auto-discovery." NOT the real mDNS/subnet-scan feature
  // (explicitly scoped out 2026-08-20, still unbuilt) - this is a cheap
  // local signal-capture placeholder for when there IS a real user base
  // to read it from. Framed honestly as in-development, not live pricing.
  Widget _buildAutoDiscoveryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, color: kTextMid, size: 18),
              const SizedBox(width: 8),
              Text('IN DEVELOPMENT',
                  style: TextStyle(
                      color: kTextMid,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 10),
          // 2026-08-29: real feedback, live - "Real auto-discovery"
          // implied the existing Wi-Fi discovery (the satellite search
          // button, already free and working) isn't real, which isn't
          // true. Reworded around the actual gap this would close -
          // USB tether reliability - instead of a vague "real" claim.
          Text(
            'Even better auto-discovery: reliable over USB too, not just '
            'Wi-Fi - no typing an IP or a repo path by hand, ever. Not '
            'built yet - would you pay for it, and how much?',
            style: TextStyle(color: kStar, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _priceBox('1', r'$1'),
              const SizedBox(width: 10),
              _priceBox('19.99', r'$19.99'),
              const SizedBox(width: 10),
              _priceBox('99', r'$99'),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => _setInterest('no'),
              child: Text(
                _interestSelected == 'no'
                    ? 'Noted - not for you'
                    : 'Not for me',
                style: TextStyle(color: kTextDim, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceBox(String value, String label) {
    final selected = _interestSelected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setInterest(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? kGreen.withValues(alpha: 0.12) : kVoid,
            border: Border.all(color: selected ? kGreen : kBorder, width: 1.5),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      color: selected ? kGreen : kStar,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              if (selected) ...[
                const SizedBox(height: 4),
                Icon(Icons.check, color: kGreen, size: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 2026-08-21: "skins" IAP - one tappable preview card per palette.
// Shows the palette's own void/surface/accent colors directly (not a
// generic swatch style borrowed from the currently-active theme), so
// a user can see what each skin actually looks like before picking
// it, not just its name.
class _SkinSwatch extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _SkinSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.void_,
              border: Border.all(
                  color: selected ? palette.accent : kBorder, width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border.all(color: palette.border),
                  ),
                  // 2026-08-22: where a real flag SVG has actually
                  // been sourced (palette.flagAsset), show it here at
                  // full size, nothing clipped - the one place in the
                  // app real flag fidelity genuinely shows (unlike
                  // the border frame, see AppPalette.flagAsset's doc
                  // comment). Falls back to the plain accent dot for
                  // every palette without one yet.
                  child: palette.flagAsset != null
                      ? SvgPicture.asset(palette.flagAsset!, fit: BoxFit.cover)
                      : Center(
                          child: Icon(Icons.circle,
                              color: palette.accent, size: 10),
                        ),
                ),
                const SizedBox(height: 8),
                // 2026-08-25: real bug - "Monochrome" showed as
                // "Monochrom", the longest label in a fixed 84px-wide
                // swatch (see the Wrap below) clipping by a hair rather
                // than wrapping or shrinking. FittedBox scales the text
                // down to fit instead of letting it clip.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(palette.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: selected ? palette.accent : palette.star,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                if (selected) ...[
                  const SizedBox(height: 3),
                  Icon(Icons.check, color: palette.accent, size: 12),
                ] else if (!palette.free) ...[
                  const SizedBox(height: 3),
                  // 2026-08-21: "make the paid skins now" - a visible
                  // preview of the eventual gate, even though every
                  // skin is still freely selectable right now (no
                  // purchase check wired in yet). Same "PRO" wording
                  // as the fair-value framing already used for the
                  // conflict-picker upsell - not a lock icon, no price
                  // guessed here since none is set yet.
                  Text('PRO',
                      style: TextStyle(
                          color: palette.textDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 2026-08-29: real feedback, live - "add a Customise button, left of
// the us skin... 3x price of most expensive skin... user sends me a
// text or image, app auto populates or I can read and have Claude AI
// design it." No skin has an actual price anywhere yet (every "PRO"
// badge above is a preview of the eventual gate, per _SkinSwatch's own
// 2026-08-21 comment) - "3x the most expensive skin" has no real
// number to multiply, so the price shown here is a placeholder until a
// real one exists. Submission itself reuses the same Codeberg issues
// channel the website already points contact requests to - text and
// image attachments both work there natively, no new backend needed
// for what's described as a manually-designed, not auto-generated,
// skin.
class _CustomiseSkinTile extends StatelessWidget {
  const _CustomiseSkinTile();

  static const _requestUrl = 'https://codeberg.org/kworld/contact/issues/new';

  Future<void> _showInfo(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Customise your own skin',
            style: TextStyle(color: kStar, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send a short description or an image of the look you '
              'want, and it gets designed as a real skin for you.',
              style: TextStyle(color: kTextMid, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 10),
            // Placeholder - see this class's own header comment for why.
            Text('Price: TBD (placeholder)',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              launchUrl(Uri.parse(_requestUrl),
                  mode: LaunchMode.externalApplication);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            child: Text('Request a skin →',
                style: TextStyle(color: kVoid, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showInfo(context),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kVoid,
          border: Border.all(color: kBorder, width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              height: 24,
              decoration: BoxDecoration(
                  color: kSurface, border: Border.all(color: kBorder)),
              child: Center(
                  child: Icon(Icons.brush_outlined, color: kGreen, size: 14)),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Customise',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: kStar, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 3),
            Text('PRO',
                style: TextStyle(
                    color: kTextDim,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
