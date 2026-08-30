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
    required this.dailyTrails,
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

  /// Trails touched per calendar day, keyed by local midnight of that day
  /// (the same day-bucketing [currentStreakDays] uses). Feeds the activity
  /// chart and the contribution heatmap, which re-bucket it over a wider
  /// window.
  ///
  /// Every day the rider opened a changeset has a key here, so the keys are
  /// exactly the active days — a day whose changesets happened to touch
  /// nothing still counts as active, and maps to 0.
  final Map<DateTime, int> dailyTrails;

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
        dailyTrails: {},
      );
    }

    var elementsChanged = 0;
    var firstEditAt = changesets.first.createdAt;
    var lastEditAt = changesets.first.createdAt;
    final dailyTrails = <DateTime, int>{};
    for (final changeset in changesets) {
      elementsChanged += changeset.changesCount;
      if (changeset.createdAt.isBefore(firstEditAt)) {
        firstEditAt = changeset.createdAt;
      }
      if (changeset.createdAt.isAfter(lastEditAt)) {
        lastEditAt = changeset.createdAt;
      }
      // Local, not UTC. OSM hands back `created_at` in UTC, and an evening
      // edit anywhere west of Greenwich is already "tomorrow" there — bucket
      // that by its UTC date and the rider's own streak reads zero on the day
      // they just edited, and every window ending "today" misses the edit.
      final created = changeset.createdAt.toLocal();
      final day = DateTime(created.year, created.month, created.day);
      dailyTrails[day] = (dailyTrails[day] ?? 0) + changeset.changesCount;
    }

    return StewardStats(
      changesetCount: changesets.length,
      elementsChanged: elementsChanged,
      daysActive: dailyTrails.length,
      currentStreakDays: _streakFrom(dailyTrails.keys.toSet()),
      firstEditAt: firstEditAt,
      lastEditAt: lastEditAt,
      dailyTrails: dailyTrails,
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
