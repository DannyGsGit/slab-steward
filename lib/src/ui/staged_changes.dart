import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/staged_edit.dart';
import '../osm/oauth_popup.dart' show OAuthPopupCancelled;
import '../osm/osm_environment.dart';
import '../analytics/steward_events.dart';
import '../osm/submission_gate.dart';
import '../state/steward_state.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

String _countLabel(int count) => count == 1 ? '1 change' : '$count changes';

/// Review, prune, and submit the staged edits — the sidebar's Staged changes
/// pane.
///
/// The changeset comment is mandatory here for the same reason OSM asks for
/// one: an unexplained edit is the kind other mappers revert. Submitting
/// doesn't write to OSM from this pane — it hands off to [SubmissionGateDialog],
/// a compliance gate that checks the comment, appends the campaign hashtag if
/// it's missing, re-reads every staged trail, and checks for edits made since
/// staging before anything is finalized. See
/// docs/specs/slab-steward-osm-changeset-spec.md.
class StagedChangesPanel extends StatefulWidget {
  const StagedChangesPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<StagedChangesPanel> createState() => _StagedChangesPanelState();
}

class _StagedChangesPanelState extends State<StagedChangesPanel> {
  final _comment = TextEditingController();
  bool _requestReview = false;

  /// An error from the most recent sign-in attempt, shown next to the
  /// sign-in button. Cleared on the next attempt.
  String? _authError;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// The point of no return lives behind this: the gate dialog runs the
  /// checks and, if they all pass, submits.
  Future<void> _submit() async {
    final comment = _comment.text.trim();
    if (comment.isEmpty) return;
    trackSubmitOpened(trailCount: widget.state.stagedTrails.length);
    await showDialog<void>(
      context: context,
      builder: (_) => SubmissionGateDialog(
        state: widget.state,
        comment: comment,
        requestReview: _requestReview,
      ),
    );
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

  Future<void> _discardAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => PointerInterceptor(
        child: AlertDialog(
          title: const Text('Discard all staged changes?'),
          content: Text(
            '${_countLabel(widget.state.stagedEditCount)} will be thrown '
            'away. Nothing has been submitted, so nothing on OpenStreetMap '
            'changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep them'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SlabColors.rust,
                foregroundColor: SlabColors.cream,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard all'),
            ),
          ],
        ),
      ),
    );
    if (confirmed ?? false) widget.state.clearStagedEdits();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byTrail = widget.state.stagedEditsByTrail;

    if (byTrail.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Text('Nothing staged. Pick a trail and edit an attribute.'),
      );
    }

    final submit = _SubmitSection(
      comment: _comment,
      requestReview: _requestReview,
      onRequestReviewChanged: (value) => setState(() => _requestReview = value),
      onSubmit: _submit,
      onSignIn: _signIn,
      authError: _authError,
      state: widget.state,
    );
    final groups = [
      for (final entry in byTrail.entries)
        _TrailGroup(
          osmWayId: entry.key,
          edits: entry.value,
          state: widget.state,
        ),
    ];
    final discardAll = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Discard all'),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: _discardAll,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Pinning the comment and the Submit button above a scrolling list is
        // the right shape while there is room for both: a rider pruning a long
        // list can still see what they are about to send. Below that — a phone's
        // band above the bottom bar, or a short window — the form alone is
        // taller than the pane, and pinning it would push the list off the
        // bottom edge. There, everything scrolls together.
        if (constraints.maxHeight < _pinnedFormNeeds) {
          return ListView(
            children: [
              submit,
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: groups,
                ),
              ),
              const Divider(height: 1),
              discardAll,
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            submit,
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                children: groups,
              ),
            ),
            const Divider(height: 1),
            discardAll,
          ],
        );
      },
    );
  }
}

/// How much height the pinned comment form wants before it stops being worth
/// pinning: the field and its helper text, the review checkbox, the submit
/// button, and enough of the list under them to be a list.
const _pinnedFormNeeds = 420.0;

/// The pre-flight checks, and — if they all pass — the submission itself.
///
/// A dialog rather than a pane: this is the one moment in Steward that is not
/// reversible, and it deserves the whole window's attention rather than a
/// column beside a map the rider could keep panning.
class SubmissionGateDialog extends StatefulWidget {
  const SubmissionGateDialog({
    super.key,
    required this.state,
    required this.comment,
    required this.requestReview,
  });

  final StewardState state;

  /// Already trimmed and non-empty — the pane's Submit button enforces that.
  final String comment;
  final bool requestReview;

  @override
  State<SubmissionGateDialog> createState() => _SubmissionGateDialogState();
}

class _SubmissionGateDialogState extends State<SubmissionGateDialog> {
  late final SubmissionGate _gate = widget.state.createSubmissionGate();

  /// Set once a passed gate has actually submitted, so the checklist can
  /// report success and wait for the rider to close it rather than closing
  /// out from under them.
  int? _finalizedCount;

  /// Conflicts the rider has already acted on this run, tracked by identity
  /// so the list can shrink live without waiting on a re-check.
  final Set<FieldConflict> _dismissedConflicts = {};
  final Set<int> _dismissedUnreadable = {};

  @override
  void initState() {
    super.initState();
    _runGate();
  }

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  Future<void> _runGate() async {
    _dismissedConflicts.clear();
    _dismissedUnreadable.clear();
    final passed = await _gate.run(
      comment: widget.comment,
      trails: widget.state.stagedTrails,
    );
    if (!mounted) return;
    if (!passed) {
      // Which step stopped it, not merely that something did. A retry emits
      // again on purpose: a rider who fails the comment check three times is
      // a different story from one who fails it once.
      final failed = _gate.checks
          .where((c) => c.status == CheckStatus.failed)
          .firstOrNull;
      if (failed != null) trackGateFailed(check: failed.id);
    }
    if (passed) await _submit();
  }

  /// The point of no return: on a `live` build this writes to OpenStreetMap,
  /// and a closed changeset can't be un-submitted. Only reachable once the
  /// gate has passed every pre-flight check and the rider is signed in, which
  /// the pane's Submit button already enforces.
  ///
  /// Nothing here branches on the configuration — a dry run reports success
  /// the same way, and this folds the result into the override cache and
  /// empties staging just as it would after a real write.
  Future<void> _submit() async {
    final token = widget.state.auth.bearerToken;
    if (token == null) return;
    final count = widget.state.stagedEditCount;
    final trailCount = widget.state.stagedTrails.length;
    final ok = await _gate.submit(
      bearerToken: token,
      requestReview: widget.requestReview,
    );
    if (!mounted) return;
    if (ok) {
      // Folds what just went out into the override cache before emptying the
      // staging area, so the trail keeps rendering as edited instead of
      // reverting to whatever the tileset last knew.
      // Counted before applySubmitted empties staging.
      trackSubmitSucceeded(
        trailCount: trailCount,
        changesetId: _gate.changesetId,
      );
      widget.state.applySubmitted();
      // Stays open on purpose — the rider closes it once they've read the
      // result, rather than it vanishing the moment the last check passes.
      setState(() => _finalizedCount = count);
    } else {
      // A rejected token can't be retried as-is; drop it so the pane offers
      // sign-in again rather than a Submit button that can't work.
      if (_gate.tokenRejected) widget.state.auth.clearOnUnauthorized();
      setState(() {}); // the failure itself is already on gate.checks
    }
  }

  void _keepMine(FieldConflict conflict) {
    final live = _gate.freshWays[conflict.osmWayId];
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

  @override
  Widget build(BuildContext context) {
    // On web the map underneath is a platform view, and the browser delivers
    // scrolls and clicks to it directly regardless of what Flutter paints on
    // top — see the matching note in StewardMapView. PointerInterceptor stops
    // them at the DOM before they reach it.
    return PointerInterceptor(
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
          child: ListenableBuilder(
            listenable: Listenable.merge([widget.state, _gate]),
            builder: (context, _) => _buildGateStep(context),
          ),
        ),
      ),
    );
  }

  Widget _buildGateStep(BuildContext context) {
    final theme = Theme.of(context);
    final gate = _gate;
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
        PanelHeader(
          title: 'Submission checks',
          large: true,
          closeTooltip: 'Close',
          onClose: () => Navigator.of(context).pop(),
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
                    const Icon(
                      Icons.check_circle,
                      color: SlabColors.diffEasy,
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
                                  color: SlabColors.gold,
                                  decoration: TextDecoration.underline,
                                  decorationColor: SlabColors.gold,
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
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
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
                    onKeepMine: () => _keepMine(conflict),
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
            child: Align(
              alignment: _finalizedCount != null
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: _finalizedCount != null
                  ? FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    )
                  : TextButton(
                      onPressed: () => Navigator.of(context).pop(),
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
    CheckStatus.open => const Icon(
      Icons.radio_button_unchecked,
      size: 20,
      color: SlabColors.sageDim,
    ),
    CheckStatus.running => const Padding(
      padding: EdgeInsets.all(2),
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    CheckStatus.passed => const Icon(
      Icons.check_circle,
      size: 20,
      color: SlabColors.diffEasy,
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
      child: SlabSurface(
        color: SlabColors.rustSoft,
        borderColor: SlabColors.rust,
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
                        OutlinedButton(
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
            builder: (context, _) => SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.upload_outlined, size: 17),
                label: Text('Submit ${_countLabel(state.stagedEditCount)}'),
                onPressed: comment.text.trim().isEmpty || !state.auth.isSignedIn
                    ? null
                    : onSubmit,
              ),
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
            child: Icon(
              Icons.subdirectory_arrow_right,
              size: 15,
              color: SlabColors.sageDim,
            ),
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
