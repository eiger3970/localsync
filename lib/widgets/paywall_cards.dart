// widgets/paywall_cards.dart
//
// 2026-09-29: user - price screen as 3 swipeable picture cards (approved
// from the HTML preview), "to increase sales by maximising the intro".
// Order by what sells most: Notes, Conflicts, Backups. Each card: main noun
// first in the heading, facts alphabetical, noun first ("Cloud: none").
// The price button stays below the cards, visible on every card.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/rescue_screen.dart' show RedButtonPainter;

class PaywallCards extends StatefulWidget {
  final Color accent;
  final Color ink;
  final Color inkDim;
  const PaywallCards(
      {super.key,
      required this.accent,
      required this.ink,
      required this.inkDim});

  @override
  State<PaywallCards> createState() => _PaywallCardsState();
}

class _PaywallCardsState extends State<PaywallCards> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = [_notes(), _conflicts(), _backups(), _rescue()];
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final c in cards)
                SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cards.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _page
                      ? widget.accent
                      : widget.inkDim.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _heading(String noun, String rest, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: noun, style: TextStyle(color: widget.accent)),
            TextSpan(text: ': $rest', style: TextStyle(color: widget.ink)),
          ]),
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 14, color: widget.inkDim)),
          const SizedBox(height: 14),
        ],
      );

  Widget _fact(String noun, String text, {Widget? trailing}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: widget.inkDim.withValues(alpha: 0.2)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_rounded, color: widget.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: noun,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: widget.ink)),
                  TextSpan(text: ': $text'),
                  if (trailing != null)
                    WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: trailing),
                ]),
                style: TextStyle(fontSize: 14, color: widget.inkDim),
              ),
            ),
          ],
        ),
      );

  // ── Card 1: Notes ───────────────────────────────────────────────────
  // 2026-09-29: user - "arrow phone to desktop and also desktop to phone.
  // This is 2 way transmissions." Wi-Fi: "state secure Wi-Fi, or have a
  // tip" - sync is SSH (encrypted) on any network; the tip links to the
  // help page's Wi-Fi, securing entry.
  Widget _notes() {
    Widget arrow(IconData icon) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 4; i++)
            Container(
                width: 8,
                height: 2.5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: widget.accent),
          Icon(icon, color: widget.accent, size: 18),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Notes', 'yours only',
            'Phone and your own desktop, both ways. No cloud in between.'),
        SizedBox(
          height: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Icon(Icons.smartphone_rounded, size: 64, color: widget.ink),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 26, color: Colors.redAccent),
                  const SizedBox(height: 6),
                  arrow(Icons.arrow_forward_rounded),
                  const SizedBox(height: 6),
                  Transform.flip(
                      flipX: true, child: arrow(Icons.arrow_forward_rounded)),
                ],
              ),
              Icon(Icons.desktop_windows_rounded,
                  size: 64, color: widget.ink),
            ],
          ),
        ),
        _fact('Account', 'none needed'),
        _fact('Cloud', 'none, your notes never leave your devices'),
        _fact('Privacy', 'yours, no company holds your data'),
        _fact('Sync',
            'automatic, both ways, encrypted, over cable or your password-protected Wi-Fi ',
            trailing: GestureDetector(
              onTap: () => launchUrl(
                  Uri.parse(
                      'https://kworld.space/localsync/help#wifi-securing'),
                  mode: LaunchMode.externalApplication),
              child: Text('(Wi-Fi tips)',
                  style: TextStyle(
                      fontSize: 14,
                      color: widget.accent,
                      decoration: TextDecoration.underline)),
            )),
      ],
    );
  }

  // ── Card 2: Conflicts ───────────────────────────────────────────────
  // A real-looking example: shared lines, timed and untimed lines on each
  // side, and the one-tap result (repeat kept once, times in order).
  // Colour key on screen, never in a dialog.
  static const _phoneBg = Color(0xFFD6ECFF);
  static const _deskBg = Color(0xFFFFEFC2);

  Widget _line(String t, [Color? bg]) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(3)),
        child: Text(t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 12, color: widget.ink)),
      );

  Widget _note(String label, List<Widget> lines, {Color? border}) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          border: Border.all(
              color: border ?? widget.inkDim.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: border ?? widget.inkDim)),
            const SizedBox(height: 4),
            ...lines,
          ],
        ),
      );

  Widget _key(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: c,
                border: Border.all(color: widget.inkDim.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 11.5, color: widget.inkDim)),
        const SizedBox(width: 12),
      ]);

  Widget _conflicts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Conflicts', 'nothing lost',
              'Same note changed on both. One tap keeps it all, tidy.'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _note('PHONE', [
                _line('Journal 29 Sep'),
                _line('09:30 Gym', _phoneBg),
                _line('08:10 Coffee'),
                _line('Call Mum', _phoneBg),
              ])),
              const SizedBox(width: 8),
              Expanded(
                  child: _note('DESKTOP', [
                _line('Journal 29 Sep'),
                _line('08:10 Coffee'),
                _line('07:45 Walk dog', _deskBg),
                _line('Buy milk', _deskBg),
              ])),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: Text('KEEP BOTH & CLEAN UP',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: widget.accent)),
            ),
          ),
          _note(
              'SAVED, BOTH SIDES',
              [
                _line('Journal 29 Sep'),
                _line('07:45 Walk dog', _deskBg),
                _line('08:10 Coffee'),
                _line('09:30 Gym', _phoneBg),
                _line('Buy milk', _deskBg),
                _line('Call Mum', _phoneBg),
              ],
              border: widget.accent),
          const SizedBox(height: 6),
          Row(children: [
            _key(Colors.white, 'Both'),
            _key(_deskBg, 'Desktop'),
            _key(_phoneBg, 'Phone'),
          ]),
          const SizedBox(height: 6),
          _fact('Repeats', 'kept once (08:10 Coffee)'),
          _fact('Times', 'put in order'),
        ],
      );

  // ── Card 3: Backups ─────────────────────────────────────────────────
  // 2026-09-29: user - "Cutting edge tech is true, but specifics not
  // needed ... not a 1 night vibe coder amateur, nor a major corporation
  // holding control of your valuable privacy and data sovereignty."
  Widget _backups() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Backups', 'automatic',
              'On your own devices. No cloud subscription.'),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.file_copy_outlined, size: 44, color: widget.inkDim),
                Icon(Icons.verified_user_rounded,
                    size: 88, color: widget.accent),
                Icon(Icons.history_rounded, size: 44, color: widget.inkDim),
              ],
            ),
          ),
          // 2026-09-29: user - "as a noob, what exactly is a deletion?"
          // Plain words: notes that are gone, even ones removed by mistake.
          _fact('Copies', 'full copy on both sides before the first sync'),
          _fact('Engineering',
              'security-first, cutting-edge sync. Not a weekend app, not a data company.'),
          _fact('Lost notes', 'brought back, even ones removed by mistake'),
          _fact('Versions', 'every sync saved on your desktop'),
        ],
      );

  // ── Card 4: Rescue ──────────────────────────────────────────────────
  // 2026-09-29: user - "Rescue is a big feature, users will value that."
  // A separate emergency product, shown here so people know it exists
  // before they ever need it. No second buy button: it's bought from
  // LocalSync -> ⋮ -> Rescue, only if ever needed.
  Widget _rescue() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Rescue', 'one tap if things go wrong',
              'Notes lost or messed up? One red button puts them back.'),
          Center(
            child: SizedBox(
              width: 130,
              height: 130,
              child: CustomPaint(
                painter: RedButtonPainter(glow: 0.6),
                child: const Center(
                  child: Text('RESCUE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _fact('Available', 'any time: LocalSync -> ⋮ -> Rescue'),
          _fact('Conflicts', 'every one kept and cleaned up'),
          _fact('Lost notes', 'all brought back, even ones removed by mistake'),
          _fact('Price', 'separate, one payment, only if you ever need it'),
        ],
      );
}
