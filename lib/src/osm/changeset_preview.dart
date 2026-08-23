import '../model/staged_edit.dart';
import 'submission_gate.dart';

/// Renders the OSM API calls a submit would make, without making them.
///
/// OSM sign-in isn't wired up yet, so there is no token to open a changeset
/// under. This exists so the shape of that future call — the
/// changeset-create body, and the osmChange upload with its tags and node
/// refs — can be checked by hand before it's wired to a real request.
///
/// [writes] carries the version, node list and resulting tags the submission
/// gate fetched fresh immediately before this is called — never the
/// staging-time snapshot, which may already be stale. See
/// docs/slab-steward-osm-changeset-spec.md §2.
String buildChangesetPreview({
  required String comment,
  required bool requestReview,
  required List<ResolvedWrite> writes,
  required List<StagedTrail> localOnlyTrails,
}) {
  final buffer = StringBuffer()
    ..writeln('SLAB Steward — staged changeset preview')
    ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}')
    ..writeln(
      'Nothing was sent — OSM sign-in is not wired up yet. This is what '
      'would go out once it is.',
    )
    ..writeln('Target API: https://api.openstreetmap.org')
    ..writeln();

  buffer
    ..writeln('--- Request 1: PUT /api/0.6/changeset/create ---')
    ..writeln('Content-Type: text/xml; charset=utf-8')
    ..writeln()
    ..writeln('<osm>')
    ..writeln('  <changeset>')
    ..writeln('    <tag k="created_by" v="SLAB Steward"/>')
    ..writeln('    <tag k="comment" v="${_xmlAttr(comment)}"/>')
    ..writeln('    <tag k="hashtags" v="#slabsteward"/>');
  if (requestReview) {
    buffer.writeln('    <tag k="review_requested" v="yes"/>');
  }
  buffer
    ..writeln('  </changeset>')
    ..writeln('</osm>')
    ..writeln();

  buffer
    ..writeln('--- Request 2: POST /api/0.6/changeset/{changeset_id}/upload ---')
    ..writeln('Content-Type: text/xml; charset=utf-8')
    ..writeln(
      '({changeset_id} is returned by request 1 — unknown until that call '
      'is actually made)',
    )
    ..writeln();

  if (writes.isEmpty) {
    buffer.writeln(
      '(nothing to upload — every staged edit is local-only, see below)',
    );
  } else {
    buffer.writeln('<osmChange version="0.6" generator="SLAB Steward">');
    buffer.writeln('  <modify>');
    for (final write in writes) {
      buffer.writeln(
        '    <way id="${write.osmWayId}" version="${write.version}" '
        'changeset="{changeset_id}">',
      );
      for (final nodeId in write.nodeIds) {
        buffer.writeln('      <nd ref="$nodeId"/>');
      }
      final tags = write.tags;
      for (final key in tags.keys.toList()..sort()) {
        buffer.writeln(
          '      <tag k="${_xmlAttr(key)}" v="${_xmlAttr(tags[key]!)}"/>',
        );
      }
      buffer.writeln('    </way>');
    }
    buffer.writeln('  </modify>');
    buffer.writeln('</osmChange>');
  }
  buffer.writeln();

  buffer
    ..writeln('--- Request 3: PUT /api/0.6/changeset/{changeset_id}/close ---')
    ..writeln('(no body)')
    ..writeln();

  if (localOnlyTrails.isNotEmpty) {
    buffer.writeln('--- Staged but not submitted to OSM ---');
    for (final trail in localOnlyTrails) {
      buffer.writeln(
        '  ${trail.trailLabel} (way ${trail.osmWayId}): '
        '${trail.edits.map((e) => e.summary).join(', ')}',
      );
    }
  }

  return buffer.toString();
}

String _xmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
