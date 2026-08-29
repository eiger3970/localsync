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

import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../features/linking/linking_controller.dart';
import '../services/repository_provider.dart';
import '../services/theme_service.dart';
import '../services/discovery_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
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

  // 2026-08-28: real feedback, live - a genuinely pushed/merged fix
  // still read as "not applied" during device testing, traced to the
  // build number never being bumped (see pubspec.yaml's own comment).
  // Shown here so which build is actually installed is a glance, not
  // a guess.
  String? _versionLabel;

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
  late final AnimationController _pathSparkleCtrl;

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

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<LinkingController>();
    _userCtrl = TextEditingController(text: ctrl.desktopUser);
    _ipCtrl = TextEditingController(text: ctrl.desktopIp);
    _pathCtrl = TextEditingController(text: ctrl.bareRepoPath);
    _pathSparkleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat();
    context.read<RepositoryProvider>().getAutoDiscoveryInterest().then((v) {
      if (mounted) setState(() => _interestSelected = v);
    });
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(
            () => _versionLabel = 'v${info.version} (${info.buildNumber})');
      }
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
    _pathSparkleCtrl.dispose();
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2026-08-28: real feedback, live - found while checking an
            // unrelated UX question: desktopUser was hardcoded in
            // main.dart with no Settings field at all, meaning a real
            // customer whose desktop login isn't 'rapi5' would have
            // every SSH connection fail immediately, with no way to fix
            // it on-device. New first field, alphabetically ahead of
            // "Git bare repo path" per the 2026-08-21 ordering decision
            // below.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Icon(Icons.person_outline, color: kTextMid, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _userCtrl,
                    style: TextStyle(color: kStar, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Desktop username',
                      // 2026-08-28: real feedback, live - "white text,
                      // should be faded grey so I know I'm meant to
                      // type in there... or have the cursor active."
                      // Without this, an empty/unfocused field rests
                      // the bold kStar-colored label INSIDE the box
                      // (Material's default), reading as already-typed
                      // content, not a label - and hintText stays
                      // hidden until the label floats up, which only
                      // happened once tapped. Forcing the label to
                      // always float to the header position means the
                      // grey hint is visible inside the box from the
                      // very first frame, no tap needed first.
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      // 2026-08-28: real feedback, live - "Text is
                      // higher than the lines: Desktop username is
                      // above the text box." This field was new, still
                      // on the original 18/19 sizing while "Git bare
                      // repo path" right below it had already been
                      // reduced to 15/15 for its own longer label text -
                      // matched here for consistency across the whole
                      // screen rather than guessing at the exact
                      // rendering mechanism blind.
                      // 2026-08-29: real feedback, live - "make the
                      // headers larger" - bumped 15 -> 17 on all three
                      // field labels (this one, Git bare repo path, IP
                      // address - desktop).
                      labelStyle: TextStyle(
                          color: kStar,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
                      floatingLabelStyle: TextStyle(
                          color: kStar,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
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
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: SvgPicture.asset(
                    'assets/logos/git-icon.svg',
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(kStar, BlendMode.srcIn),
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
                      label: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                                text: 'Git bare repo path',
                                style: TextStyle(
                                    color: kStar,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            TextSpan(
                                text: ' (folder sharing to your phone)',
                                style: TextStyle(
                                    color: kStar,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      // 2026-08-28: same fix as Desktop username above -
                      // always float, so the grey hint path shows from
                      // the first frame instead of the bold label
                      // sitting inside the box looking like real content.
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      // 2026-08-21: real feedback, live - "what does
                      // this even mean, make it clearer" on "For the
                      // next vault you link". Spells out the actual
                      // scope (only future links, not existing ones) -
                      // see RepositoryProvider's own comment on
                      // setBareRepoPath for the same explanation.
                      // 2026-08-28: real feedback, live - "what's the
                      // difference between a Vault and a Folder... Tier
                      // 0 uses need the word Folder throughout, Vault is
                      // a term for experts" (and a totally different
                      // Bitwarden product to a newbie besides). Settings
                      // isn't mode-scoped - it can't know in advance
                      // whether the next link will be Tier 0 or Obsidian
                      // - so "folder" here, being generically true of an
                      // Obsidian vault too, is the safer plain-language
                      // default rather than "vault" confusing the far
                      // more common Tier 0 case.
                      helperText: 'Applies to a new folder you link - '
                          'existing links are unaffected',
                      helperMaxLines: 2,
                      helperStyle: TextStyle(color: kTextMid, fontSize: 13),
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
                            (
                              'New setup? Just type any path here, e.g. '
                                  '~/Documents/Git/localsync.git - '
                                  'it gets created automatically the '
                                  'first time you pair, nothing to run '
                                  'yourself',
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
                onTap: () {
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
                    // 2026-08-28: real feedback, live - "why did you
                    // make a weird default path name?" Dropped the
                    // /LocalSync/sync.git subfolder split in favour of
                    // matching this repo's own real naming convention
                    // (lowercase, flat) - and counts taps so a second/
                    // third suggestion this Settings visit doesn't
                    // collide with the first (see _suggestCount's own
                    // comment for why that collision is a real, not
                    // hypothetical, gap). Was
                    // '/home/$user/Documents/Git/LocalSync/sync.git'
                    // (and vault.git before that).
                    _suggestCount++;
                    final suffix = _suggestCount == 1 ? '' : '-$_suggestCount';
                    _pathCtrl.text =
                        '/home/$user/Documents/Git/localsync$suffix.git';
                    _pathError = null;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 2026-08-28: real feedback, live - "stars aren't
                    // twinkling" - was a static Icon, same sine-wave
                    // opacity twinkle as ShreddingPasswordField's
                    // prefixIcon cluster, just one icon here.
                    AnimatedBuilder(
                      animation: _pathSparkleCtrl,
                      builder: (_, __) => Icon(Icons.auto_awesome,
                          color: kGreen.withValues(
                              alpha:
                                  sin(_pathSparkleCtrl.value * pi * 2) * 0.35 +
                                      0.65),
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
                  child: Icon(Icons.lan, color: kTextMid, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _ipCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: kStar, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'IP address - desktop',
                      // 2026-08-28: same fix as the two fields above -
                      // always float, so the grey hint IP shows from the
                      // first frame instead of requiring a tap first.
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      // 2026-08-29: real feedback, live - "make the
                      // headers larger" - bumped 15 -> 17, matching
                      // Desktop username and Git bare repo path.
                      labelStyle: TextStyle(
                          color: kStar,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
                      // 2026-08-21: real feedback, live - "text must be
                      // larger than 172.20.10.11." labelStyle alone
                      // only governs the label's un-floated resting
                      // position (before the field has content); once
                      // it floats to the top - which it always does
                      // here, since both fields are pre-filled -
                      // Material silently applies its own ~0.75x shrink
                      // on top of labelStyle unless floatingLabelStyle
                      // is set explicitly. That implicit shrink is why
                      // the label rendered smaller than the 16px value
                      // text despite labelStyle already saying 18px.
                      floatingLabelStyle: TextStyle(
                          color: kStar,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
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
                            // hint its active." Same sine-wave twinkle
                            // as "Use suggested path" above (reusing
                            // _pathSparkleCtrl - same rhythm, one fewer
                            // controller), a small badge at the corner
                            // rather than replacing the satellite glyph
                            // itself. Only while idle - the spinner
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
                                      Positioned(
                                        top: -3,
                                        right: -3,
                                        child: AnimatedBuilder(
                                          animation: _pathSparkleCtrl,
                                          builder: (_, __) => Icon(
                                              Icons.auto_awesome,
                                              color: kGreen.withValues(
                                                  alpha: sin(_pathSparkleCtrl
                                                                  .value *
                                                              pi *
                                                              2) *
                                                          0.35 +
                                                      0.65),
                                              size: 10),
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
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
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
            if (_versionLabel != null) ...[
              const SizedBox(height: 20),
              Center(
                child: Text(_versionLabel!,
                    style: TextStyle(color: kTextDim, fontSize: 11)),
              ),
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
          // 2026-08-29: real feedback, live - "left aligned, leaving a
          // nasty right space" - Wrap defaults to WrapAlignment.start,
          // so a final row that doesn't fill the full width reads as
          // lopsided. Centering each row fixes that regardless of how
          // many swatches fit per line.
          Wrap(
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
