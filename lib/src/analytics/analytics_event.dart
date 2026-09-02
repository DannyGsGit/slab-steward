/// One captured event, as the test recorder keeps it.
///
/// Shared by both platform implementations rather than living in either, so
/// the type is the same one whichever side of the conditional export is in
/// play.
class AnalyticsEvent {
  const AnalyticsEvent(this.name, this.properties);

  final String name;
  final Map<String, Object?> properties;

  @override
  String toString() => properties.isEmpty ? name : '$name $properties';
}
