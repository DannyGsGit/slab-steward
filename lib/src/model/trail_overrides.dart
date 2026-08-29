import 'dart:convert';

import '../osm/oauth_storage.dart';

/// Trail tags Steward knows to be newer than the tileset it draws.
///
/// The map's colours come from `tiles.openstreetmap.us`, a periodic planet
/// build — its TileJSON routinely reports a timestamp several days old. So
/// between rating a trail and the next tile build, the lens keeps drawing that
/// trail as unrated: the work looks undone the moment it lands. Reading the
/// trail again doesn't help, because the panel and the map are fed by
/// different sources.
///
/// This is the reconciliation. Two things put an entry here, and both are
/// simply "the API told us something the tiles don't know yet":
///
///  1. **What we submitted.** A trail's tags as of the changeset that closed.
///  2. **What we read.** Every authoritative read on click, which carries
///     whatever anyone else has changed since the tiles were cut — so trails
///     other people have already fixed stop being advertised as work.
///
/// Entries are keyed by OSM way id, since that is what the style expressions
/// match on: the tileset carries the same ids the API answers for.
class TrailOverrides {
  TrailOverrides({this.onChanged});

  /// Called whenever the set changes, so the map can restyle.
  final void Function()? onChanged;

  static const _storageKey = 'steward_trail_overrides';
  static const _formatVersion = 1;

  /// Enough for a long session over a big trail network, and small enough that
  /// the serialised form stays well inside a browser storage quota. Evicting
  /// the oldest is the right call: the newest observations are the ones the
  /// tiles are least likely to have caught up with.
  static const _maxEntries = 2000;

  final Map<int, TrailOverride> _byTileId = {};

  /// The tags to render each known trail with, ready for [TagSource].
  Map<int, Map<String, String>> get byTileId => {
    for (final entry in _byTileId.entries) entry.key: entry.value.tags,
  };

  bool get isEmpty => _byTileId.isEmpty;

  int get length => _byTileId.length;

  TrailOverride? operator [](int tileId) => _byTileId[tileId];

  /// Records what the API says [tileId]'s tags are, as of [observedAt].
  ///
  /// A later observation always wins over an earlier one, whichever source it
  /// came from — a read after someone else's edit should supersede our own
  /// submission, not lose to it.
  void record(
    int tileId,
    Map<String, String> tags, {
    required OverrideSource source,
    DateTime? observedAt,
  }) {
    final at = (observedAt ?? DateTime.now()).toUtc();
    final existing = _byTileId[tileId];
    if (existing != null && existing.observedAt.isAfter(at)) return;
    if (existing != null && existing.tags.length == tags.length) {
      final same = tags.entries.every((e) => existing.tags[e.key] == e.value);
      // Re-clicking a trail shouldn't restyle the map for no reason.
      if (same) return;
    }
    _byTileId[tileId] = TrailOverride(
      tags: Map.unmodifiable(tags),
      observedAt: at,
      source: source,
    );
    _evictOldest();
    _persist();
    onChanged?.call();
  }

  /// Forgets everything observed before [tilesetBuiltAt] — the tiles have
  /// caught up, so the override would only be repeating what they now say.
  void pruneObservedBefore(DateTime tilesetBuiltAt) {
    final before = _byTileId.length;
    _byTileId.removeWhere((_, o) => o.observedAt.isBefore(tilesetBuiltAt));
    if (_byTileId.length == before) return;
    _persist();
    onChanged?.call();
  }

  /// Forgets everything, in memory and in storage.
  ///
  /// Unconditional about the stored copy: an instance that never loaded still
  /// has to be able to throw away what a previous one wrote.
  void clear() {
    removeStorage(_storageKey);
    if (_byTileId.isEmpty) return;
    _byTileId.clear();
    onChanged?.call();
  }

  void _evictOldest() {
    if (_byTileId.length <= _maxEntries) return;
    final oldest = _byTileId.entries.toList()
      ..sort((a, b) => a.value.observedAt.compareTo(b.value.observedAt));
    for (final entry in oldest.take(_byTileId.length - _maxEntries)) {
      _byTileId.remove(entry.key);
    }
  }

  // -------------------------------------------------------------------------
  // Persistence. Surviving a reload is the whole point of the complaint this
  // exists to answer — "I submitted it, refreshed, and it's still magenta".
  // -------------------------------------------------------------------------

  void load() {
    final raw = readStorage(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      if (decoded['v'] != _formatVersion) return;
      final entries = decoded['entries'] as Map<String, Object?>;
      for (final entry in entries.entries) {
        final value = entry.value as Map<String, Object?>;
        _byTileId[int.parse(entry.key)] = TrailOverride(
          tags: Map.unmodifiable(
            (value['tags'] as Map<String, Object?>).map(
              (k, v) => MapEntry(k, '$v'),
            ),
          ),
          observedAt: DateTime.parse(value['at'] as String).toUtc(),
          source: OverrideSource.values.firstWhere(
            (s) => s.name == value['source'],
            orElse: () => OverrideSource.read,
          ),
        );
      }
    } catch (_) {
      // A cache that won't parse is a cache worth throwing away; the map
      // simply falls back to what the tiles say, which is never wrong, only
      // stale.
      _byTileId.clear();
      removeStorage(_storageKey);
    }
  }

  void _persist() {
    writeStorage(
      _storageKey,
      jsonEncode({
        'v': _formatVersion,
        'entries': {
          for (final entry in _byTileId.entries)
            '${entry.key}': {
              'at': entry.value.observedAt.toIso8601String(),
              'source': entry.value.source.name,
              'tags': entry.value.tags,
            },
        },
      }),
    );
  }
}

/// Where an override came from. Kept because the two ages mean different
/// things: our own submission is as fresh as OSM itself, while a read is only
/// as fresh as the moment we happened to look.
enum OverrideSource { submitted, read }

class TrailOverride {
  const TrailOverride({
    required this.tags,
    required this.observedAt,
    required this.source,
  });

  final Map<String, String> tags;
  final DateTime observedAt;
  final OverrideSource source;
}
