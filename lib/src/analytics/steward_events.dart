/// Every event Steward sends, in one place.
///
/// Call sites use these rather than `captureEvent` directly so the names and
/// property keys are declared once and checked by the compiler — a funnel
/// breaks silently and permanently if one call site sends `submit_succeded`,
/// and nothing about the dashboard would say so.
///
/// The funnel these compose is docs/specs/analytics.md §1:
///
///     app_opened → trail_selected → edit_staged → auth_completed
///                → submit_opened → submit_succeeded
///
/// Everything else exists to explain a drop between two of those.
library;

import '../model/staged_edit.dart';
import 'analytics.dart';

void trackAppOpened() => captureEvent('app_opened');

/// [count] is how many trails the gesture named — one for a click, however
/// many a box or a "select all" caught.
void trackTrailSelected({required bool bulk, required int count}) =>
    captureEvent('trail_selected', {'bulk': bulk, 'count': count});

void trackEditStaged({
  required TrailAttribute attribute,
  required int trailCount,
}) => captureEvent('edit_staged', {
  'attribute': attribute.name,
  'trail_count': trailCount,
});

void trackAuthStarted() => captureEvent('auth_started');

void trackAuthCompleted() => captureEvent('auth_completed');

/// The rider closed the OSM popup themselves. Deliberately *not* an
/// `auth_failed`: both UI layers already treat it as a non-error, and lumping
/// the two together would make a wall of "failures" out of people who simply
/// changed their mind.
void trackAuthCancelled() => captureEvent('auth_cancelled');

/// [reason] is the exception's *type name*, never its message. Messages from
/// the token exchange can carry fragments of an OAuth response, and none of
/// that belongs in an analytics payload.
void trackAuthFailed(String reason) =>
    captureEvent('auth_failed', {'reason': reason});

void trackSubmitOpened({required int trailCount}) =>
    captureEvent('submit_opened', {'trail_count': trailCount});

/// [check] is the id of the gate step that stopped the submission —
/// `comment`, `fetch`, or `conflicts`. The highest-value property in the
/// whole schema: where riders give up inside the compliance gate is available
/// from no other source, least of all from OpenStreetMap.
void trackGateFailed({required String check}) =>
    captureEvent('gate_failed', {'check': check});

/// [changesetId] is null on a dry-run build, where the gate reports success
/// without ever opening a changeset. The `writes_to_osm` super-property is
/// what separates those two populations; this just doesn't invent an id.
void trackSubmitSucceeded({required int trailCount, int? changesetId}) =>
    captureEvent('submit_succeeded', {
      'trail_count': trailCount,
      'changeset_id': ?changesetId,
    });
