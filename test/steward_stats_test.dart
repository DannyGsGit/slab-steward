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
}
