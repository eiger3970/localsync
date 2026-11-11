import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/conflict_scanner.dart';

// The phone's merged Nov 10th note (real shape): two wordings of 0803, three untimed lines between.
const note = '0803 backpack missing selfie stick.\n\n'
    'I left back pack in 31C.\nI brushed my teeth.\n\n'
    '0803 unpacking backpack and the selfie stick has been stolen.\n\n'
    '1400 I collected 2 letters from Riponne.\n\n'
    '2030 old thug pushed in.\n';

void main() {
  test('same time, different wording is listed; text between is kept either way', () {
    final found = sameTimeEntries('Journal/Nov 10th.md', note, {});
    expect(found.length, 1);
    final e = found.single;
    expect(e.versions[0].body.contains('backpack missing'), isTrue);
    expect(e.versions[0].body.contains('unpacking'), isFalse);
    expect(e.versions[1].body.contains('unpacking'), isTrue);
    expect(e.versions[1].body.contains('backpack missing'), isFalse);
    for (final v in e.versions) {
      expect(v.body.contains('I left back pack in 31C.'), isTrue);
    }
    for (final i in [0, 1]) {
      final out = applyResolution(note, e, e.versions[i].body);
      expect(RegExp(r'^0803', multiLine: true).allMatches(out).length, 1);
      for (final keep in ['I brushed my teeth.', '1400 I collected', '2030 old thug']) {
        expect(out.contains(keep), isTrue, reason: keep);
      }
    }
  });

  test('Keep both leaves the note unchanged', () {
    final e = sameTimeEntries('Journal/Nov 10th.md', note, {}).single;
    expect(applyKeepBoth(note, e).content, note);
  });

  test('settled pair is not listed again; plain duplicates and distinct times are ignored', () {
    final e = sameTimeEntries('a.md', note, {}).single;
    expect(sameTimeEntries('a.md', note, {e.sameTimeSig!}), isEmpty);
    expect(sameTimeEntries('a.md', '1400 same text\n\n1400 same text\n', {}), isEmpty);
    expect(sameTimeEntries('a.md', '1400 one\n\n1401 two\n', {}), isEmpty);
  });
}
