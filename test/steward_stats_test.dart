import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/steward_stats.dart';
import 'package:slab_steward/src/osm/osm_api.dart';

OsmChangeset _changeset(DateTime createdAt, {int changesCount = 1}) =>
    OsmChangeset(
      id: createdAt.millisecondsSinceEpoch,
      createdAt: createdAt,
      changesCount: changesCount,
    );

void main() {
  final now = DateTime.now();
  DateTime daysAgo(int n) => now.subtract(Duration(days: n));

  test('no changesets is the empty stats, not a crash', () {
    final stats = StewardStats.from(const []);
    expect(stats.isEmpty, isTrue);
    expect(stats.changesetCount, 0);
    expect(stats.currentStreakDays, 0);
    expect(stats.firstEditAt, isNull);
  });

  test('sums changes and dates across changesets', () {
    final stats = StewardStats.from([
      _changeset(daysAgo(5), changesCount: 3),
      _changeset(daysAgo(1), changesCount: 2),
    ]);
    expect(stats.changesetCount, 2);
    expect(stats.elementsChanged, 5);
    expect(stats.daysActive, 2);
    expect(stats.firstEditAt, daysAgo(5));
    expect(stats.lastEditAt, daysAgo(1));
  });

  test('same-day changesets count as one active day', () {
    final stats = StewardStats.from([
      _changeset(daysAgo(0)),
      _changeset(daysAgo(0)),
    ]);
    expect(stats.daysActive, 1);
  });

  test('a streak run through today counts every day in it', () {
    final stats = StewardStats.from([
      _changeset(daysAgo(2)),
      _changeset(daysAgo(1)),
      _changeset(daysAgo(0)),
    ]);
    expect(stats.currentStreakDays, 3);
  });

  test('an edit yesterday still counts as an unbroken streak, even with '
      'nothing today yet', () {
    final stats = StewardStats.from([
      _changeset(daysAgo(2)),
      _changeset(daysAgo(1)),
    ]);
    expect(stats.currentStreakDays, 2);
  });

  test('a gap ends the streak at the break, not the total active days', () {
    final stats = StewardStats.from([
      _changeset(daysAgo(10)),
      _changeset(daysAgo(1)),
      _changeset(daysAgo(0)),
    ]);
    expect(stats.currentStreakDays, 2);
    expect(stats.daysActive, 3);
  });

  test('nothing since the day before yesterday breaks the streak to zero', () {
    final stats = StewardStats.from([_changeset(daysAgo(2))]);
    expect(stats.currentStreakDays, 0);
  });

  // OSM hands back `created_at` in UTC, which is a different calendar date
  // from the rider's own for part of every day: an evening edit west of
  // Greenwich is already tomorrow in UTC, an early-morning one east of it is
  // still yesterday. Bucketing on the UTC date put the edit in a day the
  // rider hasn't lived through, which zeroed the streak on a day they'd just
  // edited and dropped the edit out of every window ending "today".
  test('an edit is counted on the rider\'s calendar day, not UTC\'s', () {
    final today = DateTime(now.year, now.month, now.day);
    // Both ends of the local day; in any non-zero UTC offset at least one of
    // these falls on a different UTC date.
    final earlyLocal = today.add(const Duration(hours: 0, minutes: 30));
    final lateLocal = today.add(const Duration(hours: 23, minutes: 30));

    for (final localTime in [earlyLocal, lateLocal]) {
      final stats = StewardStats.from([_changeset(localTime.toUtc())]);
      expect(
        stats.dailyTrails.keys.single,
        today,
        reason: 'an edit at local $localTime belongs to $today',
      );
      expect(stats.daysActive, 1);
      expect(stats.currentStreakDays, 1, reason: 'edited today, so on a streak');
    }
  });
}
