/// SLAB's simplified surface picker and its mapping onto OSM `surface=*`.
///
/// See the product description §3.2. `fine_gravel` vs `gravel` for
/// "Loose over Hard" is still an open question there; `fine_gravel` is the
/// placeholder until someone looks at how each renders downstream.
///
/// Deliberately unmapped: "root-heavy". OSM has no value for it and forcing a
/// bad mapping is worse than leaving the gap visible.
enum TrailSurface {
  hardpack('Hardpack / Groomed', 'compacted'),
  naturalDirt('Natural Dirt', 'ground'),
  looseOverHard('Loose over Hard', 'fine_gravel'),
  rock('Rock / Rock Garden', 'rock'),
  sand('Sand', 'sand'),
  paved('Paved / Hardsurface', 'paved');

  const TrailSurface(this.label, this.osmValue);

  final String label;
  final String osmValue;

  /// Resolves a raw OSM `surface` value to a SLAB option.
  ///
  /// Returns null for values SLAB's picker cannot express — `dirt`, `mud`,
  /// `woodchips` and friends are all real OSM values. Showing them as "not set"
  /// would be a lie, so the caller displays the raw value read-only instead.
  static TrailSurface? fromOsm(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final v = raw.trim();
    return switch (v) {
      'compacted' => TrailSurface.hardpack,
      'ground' || 'earth' || 'dirt' => TrailSurface.naturalDirt,
      'fine_gravel' || 'gravel' => TrailSurface.looseOverHard,
      'rock' || 'stone' => TrailSurface.rock,
      'sand' => TrailSurface.sand,
      'paved' || 'asphalt' || 'concrete' => TrailSurface.paved,
      _ => null,
    };
  }
}
