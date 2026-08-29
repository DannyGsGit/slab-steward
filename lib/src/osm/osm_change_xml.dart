import 'submission_gate.dart' show ResolvedWrite;

// The XML bodies the changeset write path sends — factored out of OsmApi so
// there is exactly one place that knows the shape of a changeset-create or
// osmChange-upload request. See docs/specs/slab-steward-osm-changeset-spec.md §2
// for why every pre-existing tag and every `<nd>` has to be reproduced, not
// just the ones that changed.

/// `PUT /api/0.6/changeset/create` body.
String changesetCreateXml(Map<String, String> tags) {
  final buffer = StringBuffer()
    ..writeln('<osm>')
    ..writeln('  <changeset>');
  for (final entry in tags.entries) {
    buffer.writeln(
      '    <tag k="${_xmlAttr(entry.key)}" v="${_xmlAttr(entry.value)}"/>',
    );
  }
  buffer
    ..writeln('  </changeset>')
    ..writeln('</osm>');
  return buffer.toString();
}

/// `POST /api/0.6/changeset/{id}/upload` body — a `<modify>` block only,
/// since Steward is metadata-only and never creates or deletes elements.
String osmChangeXml({
  required int changesetId,
  required List<ResolvedWrite> writes,
}) {
  final buffer = StringBuffer()
    ..writeln('<osmChange version="0.6" generator="SLAB Steward">')
    ..writeln('  <modify>');
  for (final write in writes) {
    buffer.writeln(
      '    <way id="${write.osmWayId}" version="${write.version}" '
      'changeset="$changesetId">',
    );
    for (final nodeId in write.nodeIds) {
      buffer.writeln('      <nd ref="$nodeId"/>');
    }
    for (final entry in write.tags.entries) {
      buffer.writeln(
        '      <tag k="${_xmlAttr(entry.key)}" v="${_xmlAttr(entry.value)}"/>',
      );
    }
    buffer.writeln('    </way>');
  }
  buffer
    ..writeln('  </modify>')
    ..writeln('</osmChange>');
  return buffer.toString();
}

String _xmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
