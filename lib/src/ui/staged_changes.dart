import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/staged_edit.dart';
import '../osm/oauth_popup.dart' show OAuthPopupCancelled;
import '../osm/osm_environment.dart';
import '../osm/submission_gate.dart';
import '../state/steward_state.dart';

/// The map-level indicator that edits are waiting to be submitted.
///
/// Carries a count badge — the pending work has to be visible from the map,
/// because that's where the rider is while they build a changeset up one trail
/// at a time. Renders nothing when there is nothing staged.
class StagedChangesButton extends StatelessWidget {
  const StagedChangesButton({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final count = state.stagedEditCount;
    if (count == 0) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showStagedChangesDialog(context, state),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge.count(
                count: count,
                child: const Padding(
                  padding: EdgeInsets.only(right: 2, top: 2),
                  child: Icon(Icons.edit_note, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Text('Review ${_countLabel(count)}'),
            ],
          ),
        ),
      ),
    );
  }
}

String _countLabel(int count) => count == 1 ? '1 change' : '$count changes';

Future<void> showStagedChangesDialog(BuildContext context, StewardState state) {
  return showDialog<void>(
    context: context,
    builder: (_) => StagedChangesDialog(state: state),
  );
}

/// Review, prune, and submit the staged edits.
///
/// The changeset comment is mandatory here for the same reason OSM asks for
/// one: an unexplained edit is the kind other mappers revert. Clicking
/// submit doesn't write to OSM directly — it hands off to a compliance gate
/// that checks the comment, appends the campaign hashtag if it's missing,
/// re-reads every staged trail, and checks for edits made since staging
/// before anything is finalized. See docs/slab-steward-osm-changeset-spec.md.
class StagedChangesDialog extends StatefulWidget {
  const StagedChangesDialog({super.key, required this.state});

  final StewardState state;

  @override
  State<StagedChangesDialog> createState() => _StagedChangesDialogState();
}

enum _Step { review, gate }

class _StagedChangesDialogState extends State<StagedChangesDialog> {
  final _comment = TextEditingController();
  bool _requestReview = false;
  _Step _step = _Step.review;
  SubmissionGate? _gate;

  /// Set once a passed gate has actually submitted, so the checklist can
  /// report success and wait for the rider to close it rather than closing
  /// out from under them.
  int? _finalizedCount;

  /// An error from the most recent sign-in attempt, shown next to the
  /// sign-in button. Cleared on the next attempt.
  String? _authError;

  /// Conflicts the rider has already acted on this run, tracked by identity
  /// so the list can shrink live without waiting on a re-check.
  final Set<FieldConflict> _dismissedConflicts = {};
  final Set<int> _dismissedUnreadable = {};

  @override
  void dispose() {
    _comment.dispose();
    _gate?.dispose();
    super.dispose();
  }

  Future<void> _runGate() async {
    final comment = _comment.text.trim();
    if (comment.isEmpty) return;
    _dismissedConflicts.clear();
    _dismissedUnreadable.clear();
    final gate = _gate ??= widget.state.createSubmissionGate();
    setState(() => _step = _Step.gate);

    final passed = await gate.run(
      comment: comment,
      trails: widget.state.stagedTrails,
    );
    if (!mounted) return;
    if (passed) await _submit(gate);
  }

  /// The point of no return: on a `live` build this writes to OpenStreetMap,
  /// and a closed changeset can't be un-submitted. Only reachable once [gate]
  /// has passed every pre-flight check and the rider is signed in, which the
  /// review step's Submit button already enforces.
  ///
  /// Nothing here branches on the configuration — a dry run reports success
  /// the same way, and this folds the result into the override cache and
  /// empties staging just as it would after a real write.
  Future<void> _submit(SubmissionGate gate) async {
    final token = widget.state.auth.bearerToken;
    if (token == null) return;
    final count = widget.state.stagedEditCount;
    final ok = await gate.submit(
      bearerToken: token,
      requestReview: _requestReview,
    );
    if (!mounted) return;
    if (ok) {
      // Folds what just went out into the override cache before emptying the
      // staging area, so the trail keeps rendering as edited instead of
      // reverting to whatever the tileset last knew.
      widget.state.applySubmitted();
      // Stays open on purpose — the rider closes it once they've read the
      // result, rather than it vanishing the moment the last check passes.
      setState(() => _finalizedCount = count);
    } else {
      // A rejected token can't be retried as-is; drop it so the review step
      // offers sign-in again rather than a Submit button that can't work.
      if (gate.tokenRejected) widget.state.auth.clearOnUnauthorized();
      setState(() {}); // the failure itself is already on gate.checks
    }
  }

  Future<void> _signIn() async {
    setState(() => _authError = null);
    try {
      await widget.state.auth.signIn();
    } on OAuthPopupCancelled {
      // The rider closed the popup themselves — not an error worth showing.
    } catch (e) {
      if (!mounted) return;
      setState(() => _authError = '$e');
    }
  }

  void _backToReview() {
    setState(() => _step = _Step.review);
  }

  void _keepMine(SubmissionGate gate, FieldConflict conflict) {
    final live = gate.freshWays[conflict.osmWayId];
    if (live == null) return;
    widget.state.rebaseEditOnLive(conflict.osmWayId, conflict.attribute, live);
    setState(() => _dismissedConflicts.add(conflict));
  }

  void _discardMine(FieldConflict conflict) {
    widget.state.unstageEdit(conflict.osmWayId, conflict.attribute);
    setState(() => _dismissedConflicts.add(conflict));
  }

  void _discardUnreadable(UnreadableTrail trail) {
    widget.state.unstageTrail(trail.osmWayId);
    setState(() => _dismissedUnreadable.add(trail.osmWayId));
  }

  Future<void> _discardAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard all staged changes?'),
        content: Text(
          '${_countLabel(widget.state.stagedEditCount)} will be thrown away. '
          'Nothing has been submitted, so nothing on OpenStreetMap changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard all'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.state.clearStagedEdits();
  }

  @override
  Widget build(BuildContext context) {
    // On web the map underneath is a platform view, and the browser delivers
    // scrolls and clicks to it directly regardless of what Flutter paints on
    // top — see the matching note in StewardMapView. PointerInterceptor stops
    // them at the DOM before they reach it.
    final gate = _gate;
    return PointerInterceptor(
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
          child: ListenableBuilder(
            listenable: gate == null
                ? widget.state
                : Listenable.merge([widget.state, gate]),
            builder: (context, _) => _step == _Step.review
                ? _buildReviewStep(context)
                : _buildGateStep(context, gate!),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    final theme = Theme.of(context);
    final byTrail = widget.state.stagedEditsByTrail;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Staged changes',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        if (byTrail.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Text('Nothing staged. Pick a trail and edit an attribute.'),
          )
        else ...[
          _SubmitSection(
            comment: _comment,
            requestReview: _requestReview,
            onRequestReviewChanged: (value) =>
                setState(() => _requestReview = value),
            onSubmit: _runGate,
            onSignIn: _signIn,
            authError: _authError,
            state: widget.state,
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
              shrinkWrap: true,
              children: [
                for (final entry in byTrail.entries)
                  _TrailGroup(
                    osmWayId: entry.key,
                    edits: entry.value,
                    state: widget.state,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Discard all'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: _discardAll,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGateStep(BuildContext context, SubmissionGate gate) {
    final theme = Theme.of(context);
    final remainingConflicts = [
      for (final c in gate.conflicts)
        if (!_dismissedConflicts.contains(c)) c,
    ];
    final remainingUnreadable = [
      for (final t in gate.unreadable)
        if (!_dismissedUnreadable.contains(t.osmWayId)) t,
    ];
    final isRunning = gate.checks.any((c) => c.status == CheckStatus.running);
    final hasFailure = gate.checks.any((c) => c.status == CheckStatus.failed);
    final canRetry =
        hasFailure && remainingConflicts.isEmpty && remainingUnreadable.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Submission checks',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            shrinkWrap: true,
            children: [
              for (final check in gate.checks) _CheckRow(check: check),
              if (_finalizedCount case final count?) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All checks passed',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Submitted ${_countLabel(count)} to $osmLabel.',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (gate.changesetUrl case final url?) ...[
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => launchUrl(Uri.parse(url)),
                              child: Text(
                                url,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (gate.checks.firstWhere((c) => c.id == 'comment').status ==
                  CheckStatus.failed) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _backToReview,
                  child: const Text('Edit comment'),
                ),
              ],
              if (remainingUnreadable.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Some trails could not be re-read',
                  style: theme.textTheme.titleSmall,
                ),
                for (final trail in remainingUnreadable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(trail.trailLabel),
                              Text(
                                trail.message,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _discardUnreadable(trail),
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ),
              ],
              if (remainingConflicts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Someone else edited these fields',
                  style: theme.textTheme.titleSmall,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Choose which value to keep for each. Nothing has been '
                    'submitted, and the rest of your staged changes are safe.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                for (final conflict in remainingConflicts)
                  _ConflictRow(
                    conflict: conflict,
                    onKeepMine: () => _keepMine(gate, conflict),
                    onDiscardMine: () => _discardMine(conflict),
                  ),
              ],
              if (canRetry) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry checks'),
                  onPressed: _runGate,
                ),
              ],
            ],
          ),
        ),
        if (!isRunning)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _finalizedCount != null
                ? Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _backToReview,
                      child: const Text('Back'),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final SubmissionCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: _statusIcon(theme, check.status),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label),
                if (check.detail case final detail?)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: check.status == CheckStatus.failed
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(ThemeData theme, CheckStatus status) => switch (status) {
    CheckStatus.open => Icon(
      Icons.radio_button_unchecked,
      size: 20,
      color: theme.disabledColor,
    ),
    CheckStatus.running => const Padding(
      padding: EdgeInsets.all(2),
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    CheckStatus.passed => Icon(
      Icons.check_circle,
      size: 20,
      color: Colors.green.shade600,
    ),
    CheckStatus.failed => Icon(
      Icons.cancel,
      size: 20,
      color: theme.colorScheme.error,
    ),
  };
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.conflict,
    required this.onKeepMine,
    required this.onDiscardMine,
  });

  final FieldConflict conflict;
  final VoidCallback onKeepMine;
  final VoidCallback onDiscardMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${conflict.trailLabel} — ${conflict.attribute.label}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text('When you started: ${conflict.originalValue ?? '(not set)'}'),
            Text('On OpenStreetMap now: ${conflict.liveValue ?? '(not set)'}'),
            Text('You are submitting: ${conflict.desiredValue ?? '(remove)'}'),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: onDiscardMine,
                  child: const Text('Discard my change'),
                ),
                FilledButton(
                  onPressed: onKeepMine,
                  child: const Text('Keep my change'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The comment field and the submit button, above the list because the
/// changeset is the thing being reviewed — the edits are its contents.
class _SubmitSection extends StatelessWidget {
  const _SubmitSection({
    required this.comment,
    required this.requestReview,
    required this.onRequestReviewChanged,
    required this.onSubmit,
    required this.onSignIn,
    required this.authError,
    required this.state,
  });

  final TextEditingController comment;
  final bool requestReview;
  final ValueChanged<bool> onRequestReviewChanged;
  final VoidCallback onSubmit;
  final VoidCallback onSignIn;
  final String? authError;
  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: comment,
            autofocus: true,
            maxLength: 200,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(
              labelText: 'Describe your change',
              hintText: 'e.g. Rated difficulty from a ride on <date>',
              helperText: 'Required.',
              border: OutlineInputBorder(),
            ),
          ),
          // const SizedBox(height: 4),
          // // Hashtag discipline on every changeset, single-trail ones included
          // // — product description §5. Appended automatically if missing.
          // Text(
          //   'Submitted with #slabsteward so the OSM community can audit these '
          //   'edits as a group.',
          //   style: theme.textTheme.bodySmall,
          // ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => onRequestReviewChanged(!requestReview),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: requestReview,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) =>
                        onRequestReviewChanged(value ?? false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Request community review — only if you are unsure '
                      'about this edit.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Kept to a single row either way: this sits above the list of
          // staged edits, and every line spent here is a trail the rider
          // can't see while reviewing what they're about to submit.
          ListenableBuilder(
            listenable: state.auth,
            builder: (context, _) {
              final auth = state.auth;
              if (!auth.isSignedIn) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Not signed in — submitting writes to $osmLabel.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: auth.isSigningIn ? null : onSignIn,
                          child: auth.isSigningIn
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                      ],
                    ),
                    if (authError case final error?)
                      Text(
                        error,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                );
              }
              // Signed in is the quiet case: the account button in the app
              // bar already says who you are and offers sign out.
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 4),
          ListenableBuilder(
            listenable: Listenable.merge([comment, state.auth]),
            builder: (context, _) => FilledButton.icon(
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: Text('Submit ${_countLabel(state.stagedEditCount)}'),
              onPressed: comment.text.trim().isEmpty || !state.auth.isSignedIn
                  ? null
                  : onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailGroup extends StatelessWidget {
  const _TrailGroup({
    required this.osmWayId,
    required this.edits,
    required this.state,
  });

  final int osmWayId;
  final List<StagedEdit> edits;
  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  edits.first.trailLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text('way $osmWayId', style: theme.textTheme.bodySmall),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove every change to this trail',
                visualDensity: VisualDensity.compact,
                onPressed: () => state.unstageTrail(osmWayId),
              ),
            ],
          ),
          for (final edit in edits) _EditRow(edit: edit, state: state),
        ],
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({required this.edit, required this.state});

  final StagedEdit edit;
  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3, right: 8),
            child: Icon(Icons.subdirectory_arrow_right, size: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${edit.attribute.label}: ${edit.summary}'),
                const SizedBox(height: 2),
                // The plain-language line above is the review; this is the
                // "for the technically curious" half of the same preview.
                Text(
                  edit.changesOsm
                      ? edit.tagDiffLines.join(', ')
                      : 'No OpenStreetMap tag changes',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (edit.note case final note?)
                  Text(note, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            tooltip: 'Remove this change',
            visualDensity: VisualDensity.compact,
            onPressed: () => state.unstageEdit(edit.osmWayId, edit.attribute),
          ),
        ],
      ),
    );
  }
}
