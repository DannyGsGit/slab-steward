import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../model/staged_edit.dart';
import 'osm_api.dart';
import 'osm_environment.dart';

enum CheckStatus { open, running, passed, failed }

/// One step in the pre-submit compliance gate, and where it landed.
class SubmissionCheck {
  SubmissionCheck(this.id, this.label);

  final String id;
  final String label;
  CheckStatus status = CheckStatus.open;

  /// Progress or result text shown under the label — "3 of 7 trails", a
  /// failure reason, or why a step passed.
  String? detail;
}

/// A tag that changed on the server between staging and submit in a way that
/// conflicts with what the rider is about to write.
///
/// Per docs/specs/slab-steward-osm-changeset-spec.md §4: this only fires when the
/// live value differs from both what the edit was staged against
/// ([originalValue]) *and* what the rider wants to submit ([desiredValue]).
/// If the live value already matches [desiredValue], someone else made the
/// same change — that's a safe auto-merge, not a conflict.
class FieldConflict {
  const FieldConflict({
    required this.osmWayId,
    required this.trailLabel,
    required this.attribute,
    required this.tagKey,
    required this.originalValue,
    required this.liveValue,
    required this.desiredValue,
  });

  final int osmWayId;
  final String trailLabel;
  final TrailAttribute attribute;
  final String tagKey;

  /// The value this field held when the rider staged the edit.
  final String? originalValue;

  /// The value the field holds right now, fetched immediately before submit.
  final String? liveValue;

  /// The value the rider is trying to write.
  final String? desiredValue;
}

/// A staged trail the gate couldn't re-read from the OSM API.
class UnreadableTrail {
  const UnreadableTrail({
    required this.osmWayId,
    required this.trailLabel,
    required this.message,
    required this.isGone,
  });

  final int osmWayId;
  final String trailLabel;
  final String message;

  /// True when the way was deleted or redacted, as opposed to a transient
  /// read failure worth retrying.
  final bool isGone;
}

/// What one trail should actually write, built from the tags and version the
/// gate fetched immediately before submit — never the staging-time snapshot.
class ResolvedWrite {
  const ResolvedWrite({
    required this.osmWayId,
    required this.trailLabel,
    required this.version,
    required this.nodeIds,
    required this.tags,
  });

  final int osmWayId;
  final String? trailLabel;
  final int version;
  final List<int> nodeIds;
  final Map<String, String> tags;
}

/// Comments the OSM wiki calls out as bad practice — content-free filler
/// that doesn't say what changed or why. See the spec's "Comment templates".
const bannedComments = {
  'update',
  'fix',
  '.',
  'edit',
  'changes',
  'slab steward edit',
};

/// A high bar, per product direction: a comment needs more than one word and
/// can't be one of the generic phrases the community already flags as noise.
bool isMeaningfulComment(String comment) {
  final trimmed = comment.trim();
  if (trimmed.isEmpty) return false;
  if (bannedComments.contains(trimmed.toLowerCase())) return false;
  if (trimmed.length < 10) return false;
  if (!trimmed.contains(' ')) return false;
  return true;
}

/// Appends the campaign hashtag if the rider didn't already include it.
String ensureHashtag(String comment) {
  final trimmed = comment.trim();
  if (trimmed.toLowerCase().contains('#slabsteward')) return trimmed;
  return '$trimmed #slabsteward';
}

/// Runs the pre-submit compliance gate and holds its result.
///
/// A fresh instance is used per submit attempt; [run] can be called again on
/// the same instance to retry. UI listens via [ChangeNotifier] to draw the
/// checklist live as each step moves from open to running to passed/failed.
class SubmissionGate extends ChangeNotifier {
  SubmissionGate({
    required this.osmApi,
    this.maxConcurrentReads = 4,
    this.environment = osmEnvironment,
  });

  final OsmApi osmApi;

  /// How many way reads may be in flight at once — same courtesy limit as
  /// resolving a bulk selection.
  final int maxConcurrentReads;

  /// Whether [submit] commits or stops short of the write. Injectable only so
  /// tests can exercise both configurations in one run; the app always takes
  /// the build's [osmEnvironment].
  final OsmEnvironment environment;

  final List<SubmissionCheck> checks = [
    SubmissionCheck('comment', 'Changeset comment is descriptive'),
    SubmissionCheck('hashtag', 'Campaign hashtag present'),
    SubmissionCheck('fetch', 'Fetching latest data from OpenStreetMap'),
    SubmissionCheck('conflicts', 'Checking for edits made since you started'),
    SubmissionCheck('submit', 'Submitting to $osmLabel'),
  ];

  /// The comment actually going out, hashtag included.
  String finalComment = '';

  List<FieldConflict> conflicts = const [];
  List<UnreadableTrail> unreadable = const [];
  List<ResolvedWrite> resolvedWrites = const [];

  /// Fresh reads keyed by way id, kept around so a conflict can be resolved
  /// by rebasing the edit onto them without a second round trip.
  Map<int, OsmWay> freshWays = const {};

  /// Set once [submit] has actually opened a changeset — the changeset id
  /// and its human-facing permalink, for the "all checks passed" panel to
  /// show. The permalink is a *website* URL, not an API one.
  int? changesetId;
  String? get changesetUrl =>
      changesetId == null ? null : '$osmWebHost/changeset/$changesetId';

  /// True when [submit] failed because OSM rejected the token. The caller
  /// should drop the stored session — a retry with the same token can only
  /// fail the same way.
  bool tokenRejected = false;

  SubmissionCheck _check(String id) => checks.firstWhere((c) => c.id == id);

  /// Runs every check in order, stopping at the first failure. Returns true
  /// only when the whole gate passed and [resolvedWrites] is ready to submit.
  Future<bool> run({
    required String comment,
    required List<StagedTrail> trails,
  }) async {
    for (final c in checks) {
      c.status = CheckStatus.open;
      c.detail = null;
    }
    conflicts = const [];
    unreadable = const [];
    resolvedWrites = const [];
    freshWays = const {};
    tokenRejected = false;
    notifyListeners();

    // 1. Comment quality — synchronous, but still gets its own row so the
    // checklist shows every gate the rider's submission passed through.
    final commentCheck = _check('comment')..status = CheckStatus.running;
    notifyListeners();
    if (!isMeaningfulComment(comment)) {
      commentCheck.status = CheckStatus.failed;
      commentCheck.detail =
          'Say what changed, on what, and why — e.g. "Set surface on 6 '
          'trails from a field visit", not "update".';
      notifyListeners();
      return false;
    }
    commentCheck.status = CheckStatus.passed;
    notifyListeners();

    // 2. Hashtag — always auto-fixed, never blocks submission.
    final hashtagCheck = _check('hashtag')..status = CheckStatus.running;
    notifyListeners();
    final hadHashtag = comment.toLowerCase().contains('#slabsteward');
    finalComment = ensureHashtag(comment);
    hashtagCheck
      ..status = CheckStatus.passed
      ..detail = hadHashtag
          ? 'Already present.'
          : 'Added automatically: "#slabsteward".';
    notifyListeners();

    // Local-only edits (e.g. Pro Line over an already-Expert trail) never
    // touch OSM, so they need neither a fresh read nor a conflict check.
    final onOsm = trails
        .where((t) => t.edits.any((e) => e.changesOsm))
        .toList();
    final fetchCheck = _check('fetch');
    final conflictCheck = _check('conflicts');
    if (onOsm.isEmpty) {
      fetchCheck
        ..status = CheckStatus.passed
        ..detail = 'Nothing staged writes to OpenStreetMap.';
      conflictCheck
        ..status = CheckStatus.passed
        ..detail = 'Nothing to check.';
      notifyListeners();
      return true;
    }

    // 3. Fetch fresh data — re-GET every way immediately before building the
    // diff, per the spec's core rule: never reuse a body cached across the
    // user-interaction boundary.
    fetchCheck
      ..status = CheckStatus.running
      ..detail = '0 of ${onOsm.length} trails';
    notifyListeners();

    final fresh = <int, OsmWay>{};
    final failures = <UnreadableTrail>[];
    final pending = Queue<StagedTrail>.of(onOsm);
    var done = 0;

    Future<void> worker() async {
      while (pending.isNotEmpty) {
        final trail = pending.removeFirst();
        try {
          fresh[trail.osmWayId] = await osmApi.fetchWay(trail.osmWayId);
        } on OsmApiException catch (e) {
          failures.add(
            UnreadableTrail(
              osmWayId: trail.osmWayId,
              trailLabel: trail.trailLabel,
              message: e.isGone
                  ? 'No longer in OpenStreetMap — the map tiles may be out of date.'
                  : e.message,
              isGone: e.isGone,
            ),
          );
        }
        done++;
        fetchCheck.detail = '$done of ${onOsm.length} trails';
        notifyListeners();
      }
    }

    await Future.wait([
      for (var i = 0; i < maxConcurrentReads.clamp(1, onOsm.length); i++)
        worker(),
    ]);

    freshWays = fresh;

    if (failures.isNotEmpty) {
      fetchCheck.status = CheckStatus.failed;
      fetchCheck.detail =
          'Could not re-read ${failures.length} of ${onOsm.length} trails.';
      unreadable = failures;
      notifyListeners();
      return false;
    }
    fetchCheck.status = CheckStatus.passed;
    fetchCheck.detail =
        'Read ${onOsm.length} trail${onOsm.length == 1 ? '' : 's'}.';
    notifyListeners();

    // 4. Conflict check — compare the value each edit was staged against to
    // the value just fetched. Only a mismatch that *also* disagrees with what
    // the rider wants to submit is a real conflict; if the live value already
    // matches, someone else made the same change and the merge is safe.
    conflictCheck.status = CheckStatus.running;
    notifyListeners();

    final foundConflicts = <FieldConflict>[];
    final writes = <ResolvedWrite>[];
    for (final trail in onOsm) {
      final way = fresh[trail.osmWayId]!;
      final tags = Map<String, String>.from(way.tags);
      for (final edit in trail.edits) {
        for (final entry in edit.tagChanges.entries) {
          final key = entry.key;
          final desired = entry.value;
          final original = edit.baseTags[key];
          final live = way.tags[key];
          if (original != live && live != desired) {
            foundConflicts.add(
              FieldConflict(
                osmWayId: trail.osmWayId,
                trailLabel: trail.trailLabel,
                attribute: edit.attribute,
                tagKey: key,
                originalValue: original,
                liveValue: live,
                desiredValue: desired,
              ),
            );
          }
          if (desired == null) {
            tags.remove(key);
          } else {
            tags[key] = desired;
          }
        }
      }
      writes.add(
        ResolvedWrite(
          osmWayId: trail.osmWayId,
          trailLabel: trail.trailLabel,
          version: way.version,
          nodeIds: way.nodeIds,
          tags: tags,
        ),
      );
    }

    if (foundConflicts.isNotEmpty) {
      conflictCheck.status = CheckStatus.failed;
      conflictCheck.detail =
          '${foundConflicts.length} field${foundConflicts.length == 1 ? '' : 's'} '
          'changed on OpenStreetMap since you staged this edit.';
      conflicts = foundConflicts;
      notifyListeners();
      return false;
    }

    conflictCheck
      ..status = CheckStatus.passed
      ..detail = 'No conflicting edits found.';
    resolvedWrites = writes;
    notifyListeners();
    return true;
  }

  /// Actually writes [resolvedWrites] to OpenStreetMap — the step after
  /// [run] has passed. Only called once the rider has confirmed the review
  /// screen, since this is the point of no return: a closed changeset is
  /// live and immutable (spec §5).
  ///
  /// Opens a changeset, uploads the diff as one atomic transaction, and
  /// closes it. Local-only edits (nothing in [resolvedWrites]) skip the
  /// network entirely, mirroring how [run] already short-circuits the
  /// fetch/conflict checks in that case. On failure, [checks] records why
  /// and nothing staged is cleared — that's the caller's job, and only once
  /// this returns true.
  ///
  /// Under [OsmEnvironment.dryRun] these three calls are the *only* thing
  /// that doesn't happen: the gate has already run in full against live OSM
  /// data, and this still returns true, so staging clears and the map
  /// recolours exactly as it would have. [changesetId] stays null, because
  /// there is no changeset — which is what keeps the result panel from
  /// linking to one that doesn't exist.
  Future<bool> submit({
    required String bearerToken,
    required bool requestReview,
  }) async {
    final submitCheck = _check('submit')
      ..status = CheckStatus.running
      ..detail = null;
    notifyListeners();

    if (resolvedWrites.isEmpty) {
      submitCheck
        ..status = CheckStatus.passed
        ..detail = 'Nothing to submit to $osmLabel.';
      notifyListeners();
      return true;
    }

    if (!environment.writesToOsm) {
      submitCheck
        ..status = CheckStatus.passed
        ..detail =
            'Dry run — every check ran against live $osmLabel data, and the '
            'changeset was not sent.';
      notifyListeners();
      return true;
    }

    try {
      final tags = {
        'created_by': 'SLAB Steward',
        'comment': finalComment,
        'hashtags': '#slabsteward',
        'host': 'https://slab-steward.web.app',
        'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
        if (requestReview) 'review_requested': 'yes',
      };
      final id = await osmApi.openChangeset(
        tags: tags,
        bearerToken: bearerToken,
      );
      await osmApi.uploadChangeset(
        changesetId: id,
        writes: resolvedWrites,
        bearerToken: bearerToken,
      );
      await osmApi.closeChangeset(changesetId: id, bearerToken: bearerToken);
      changesetId = id;
      submitCheck
        ..status = CheckStatus.passed
        ..detail = 'Changeset $id';
    } on OsmApiException catch (e) {
      tokenRejected = e.isUnauthorized;
      submitCheck
        ..status = CheckStatus.failed
        ..detail = e.isUnauthorized
            ? 'Your OpenStreetMap sign-in is no longer valid. Sign in again '
                  'and retry — nothing was submitted.'
            : e.message;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }
}
