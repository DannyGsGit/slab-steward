import '../osm/osm_api.dart' show OsmChangeset;

/// What a rider has done through Steward, summarised from their `#slabsteward`
/// changesets — the numbers the stats pane shows to make that work visible.
class StewardStats {
  const StewardStats({
    required this.changesetCount,
    required this.elementsChanged,
    required this.daysActive,
    required this.currentStreakDays,
    required this.firstEditAt,
    required this.lastEditAt,
  });

  /// Changesets submitted through Steward.
  final int changesetCount;

  /// Total elements touched across every changeset — the closest thing to
  /// "trails edited" without re-deriving it from each changeset's diff.
  final int elementsChanged;

  /// Distinct calendar days on which at least one changeset was opened.
  final int daysActive;

  /// Consecutive active days, counting backward from today, that were still
  /// unbroken as of yesterday — an edit made earlier today still counts, one
  /// made only yesterday hasn't lapsed yet either.
  final int currentStreakDays;

  final DateTime? firstEditAt;
  final DateTime? lastEditAt;

  bool get isEmpty => changesetCount == 0;

  factory StewardStats.from(List<OsmChangeset> changesets) {
    if (changesets.isEmpty) {
      return const StewardStats(
        changesetCount: 0,
        elementsChanged: 0,
        daysActive: 0,
        currentStreakDays: 0,
        firstEditAt: null,
        lastEditAt: null,
      );
    }

    var elementsChanged = 0;
    var firstEditAt = changesets.first.createdAt;
    var lastEditAt = changesets.first.createdAt;
    final activeDays = <DateTime>{};
    for (final changeset in changesets) {
      elementsChanged += changeset.changesCount;
      if (changeset.createdAt.isBefore(firstEditAt)) {
        firstEditAt = changeset.createdAt;
      }
      if (changeset.createdAt.isAfter(lastEditAt)) {
        lastEditAt = changeset.createdAt;
      }
      final day = changeset.createdAt;
      activeDays.add(DateTime(day.year, day.month, day.day));
    }

    return StewardStats(
      changesetCount: changesets.length,
      elementsChanged: elementsChanged,
      daysActive: activeDays.length,
      currentStreakDays: _streakFrom(activeDays),
      firstEditAt: firstEditAt,
      lastEditAt: lastEditAt,
    );
  }

  static int _streakFrom(Set<DateTime> activeDays) {
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    // A streak that hasn't been broken yet: today may not have an edit on it
    // without ending the streak, but yesterday must.
    if (!activeDays.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (activeDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
