// 2026-08-19: "way too convoluted, automate it" - a pull that produced
// a real conflict used to return the same generic SyncOk message as
// any other clean pull, with nothing telling the user a decision was
// needed. This locks in the honest message text for the new
// SyncOkWithConflicts result (see sync_service.dart) that replaced it.

import 'package:flutter_test/flutter_test.dart';
import 'package:localsync/services/sync_service.dart';

void main() {
  test('singular conflict count reads "1 file", not "1 files"', () {
    expect(syncResultMessage(const SyncOkWithConflicts(1)),
        'Merged in changes - 1 file needs your review.');
  });

  test('plural conflict count reads "N files"', () {
    expect(syncResultMessage(const SyncOkWithConflicts(3)),
        'Merged in changes - 3 files need your review.');
  });

  test('a clean pull with no conflicts keeps its original message', () {
    expect(syncResultMessage(const SyncOk('Merged in changes from desktop.')),
        'Merged in changes from desktop.');
  });
}
