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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../features/linking/linking_controller.dart';
import '../services/repository_provider.dart';
import '../services/theme_service.dart';
import '../services/discovery_service.dart';
import '../services/purchase_service.dart';
import '../widgets/conflict_picker_upsell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _ipPattern =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  late final TextEditingController _ipCtrl;
  late final TextEditingController _pathCtrl;
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

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<LinkingController>();
    _ipCtrl = TextEditingController(text: ctrl.desktopIp);
    _pathCtrl = TextEditingController(text: ctrl.bareRepoPath);
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
    _ipCtrl.dispose();
    _pathCtrl.dispose();
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
          'No desktop found - make sure it\'s advertising (see Settings help) '
          'and on the same network',
          style: TextStyle(color: kStar, fontSize: 14),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _save() async {
    final ip = _ipCtrl.text.trim();
    final path = _pathCtrl.text.trim();
    setState(() {
      _ipError = _ipPattern.hasMatch(ip) ? null : 'Not a valid IP address';
      _pathError = path.isEmpty ? 'Can\'t be empty' : null;
    });
    if (_ipError != null || _pathError != null) return;

    final linkingCtrl = context.read<LinkingController>();
    final provider = context.read<RepositoryProvider>();
    await provider.setDesktopIp(ip);
    linkingCtrl.updateDesktopIp(ip);
    await provider.setBareRepoPath(path);
    linkingCtrl.updateBareRepoPath(path);
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
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Icon(Icons.account_tree, color: kTextMid, size: 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _pathCtrl,
                    style: TextStyle(color: kStar, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Git bare repo path',
                      labelStyle: TextStyle(
                          color: kStar, fontSize: 18, fontWeight: FontWeight.w700),
                      // 2026-08-21: floatingLabelStyle fix - "text must
                      // be larger than /home/rapi5/Documents/Git/pi5-
                      // obsidia..." - see the field below for why this
                      // is needed even though labelStyle already says 18.
                      floatingLabelStyle: TextStyle(
                          color: kStar, fontSize: 19, fontWeight: FontWeight.w700),
                      // 2026-08-21: real feedback, live - "what does
                      // this even mean, make it clearer" on "For the
                      // next vault you link". Spells out the actual
                      // scope (only future links, not existing ones) -
                      // see RepositoryProvider's own comment on
                      // setBareRepoPath for the same explanation.
                      helperText: 'Applies to the next vault you link - '
                          'existing links are unaffected',
                      helperMaxLines: 2,
                      helperStyle: TextStyle(color: kTextMid, fontSize: 13),
                      hintText: '/home/user/Git_bare_repo/name.git',
                      errorText: _pathError,
                      // 2026-08-21: real feedback, live - "circle with
                      // i" instead of a "?" - Icons.info_outline reads
                      // as reference info, Icons.help_outline reads as
                      // "something's wrong, ask for help." This is
                      // neither - it's a lookup command, not a support
                      // request.
                      suffixIcon: IconButton(
                        icon: Icon(Icons.info_outline,
                            color: kTextDim, size: 20),
                        tooltip: 'How do I find this?',
                        // 2026-08-21: real question, live - "is this
                        // live if the user has a different git bare
                        // repo or is this hard coded text?" It WAS
                        // hardcoded to this developer's own repo name
                        // (Md_files_bare.git) - wrong for any other
                        // real vault. Now reads the field's own live
                        // text at the moment the dialog opens instead.
                        onPressed: () => _showHelp(
                          'Finding the Git bare repo path',
                          "find ~/Documents/Git -maxdepth 3 -name '*.git' -type d",
                          [
                            ('Run this on the desktop terminal', false),
                            ('Lists every Git bare repo on the desktop', false),
                            if (_pathCtrl.text.trim().isNotEmpty)
                              ('Currently set to: ${_pathCtrl.text.trim()}', false)
                            else
                              ('Your real vault is usually the one you '
                                      'set up first',
                                  false),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
                      labelStyle: TextStyle(
                          color: kStar, fontSize: 18, fontWeight: FontWeight.w700),
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
                          color: kStar, fontSize: 19, fontWeight: FontWeight.w700),
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
                      helperText:
                          'Update this manually after switching Tether or Hotspot',
                      helperMaxLines: 2,
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
                            icon: _discovering
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kGreen),
                                  )
                                : Icon(Icons.satellite_alt,
                                    color: kGreen, size: 20),
                            tooltip: 'Find automatically',
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
                                ('IP address changes every switch - re-run '
                                        'the command',
                                    false),
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
            // 2026-08-21: real dashboard setup finally done (RevenueCat
            // Test Store: conflict_picker_unlock product, conflict_picker
            // entitlement, both attached, "default" offering has a real
            // Custom package wrapping the product) - "can I see a tap
            // this for a price and it runs?" Placed here in Settings,
            // not the real Conflicts screen, so testing the actual free
            // conflict-picker flow stays completely unaffected. This is
            // the first place in the whole app a real purchase can
            // genuinely be attempted (Test Store, not a live App Store
            // charge - no funded Apple Developer account yet).
            ConflictPickerUpsell(purchases: context.watch<PurchaseService>()),
            const SizedBox(height: 28),
            _buildAutoDiscoveryCard(),
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
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder)),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final palette in allPalettes)
                SizedBox(
                  width: 84,
                  child: _SkinSwatch(
                    palette: palette,
                    selected: themeService.palette.id == palette.id,
                    onTap: () => themeService.select(palette),
                  ),
                ),
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
          Text(
            'Real auto-discovery: LocalSync finds your desktop on its own, '
            'no typing an IP or a repo path by hand. Not built yet - would '
            'you pay for it, and how much?',
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
                _interestSelected == 'no' ? 'Noted - not for you' : 'Not for me',
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
                          child: Icon(Icons.circle, color: palette.accent, size: 10),
                        ),
                ),
                const SizedBox(height: 8),
                Text(palette.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: selected ? palette.accent : palette.star,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
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
