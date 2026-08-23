import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/difficulty.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';

/// Details for the selected trail, and the guided editor for the attributes
/// Steward can change.
///
/// Editable attributes carry a pencil; tapping it swaps the value for a picker
/// with a check (stage it) and an X (discard it). Nothing here reaches
/// OpenStreetMap — staged edits collect in [StewardState] and go out together
/// as one changeset from the staged-changes review.
///
/// One trail only. Several selected trails get [SelectionPanel] instead, which
/// applies one value across all of them.
class TrailPanel extends StatelessWidget {
  const TrailPanel({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final trail = state.selected;
    if (trail == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final error = state.readErrorFor(trail.osmWayId);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        trail.name ?? 'Unnamed trail',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear selection',
                      onPressed: state.clearSelection,
                    ),
                  ],
                ),
                _SourceLine(trail: trail, state: state),
                const SizedBox(height: 16),
                DifficultyField(trail: trail, state: state),
                const SizedBox(height: 12),
                _SurfaceRow(trail: trail),
                if (trail.isInformal) ...[
                  const SizedBox(height: 12),
                  const _Chip(
                    icon: Icons.report_gmailerrorred_outlined,
                    label: 'Tagged informal in OpenStreetMap',
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // The additive gesture is invisible until someone tells you
                // about it, and this panel is where a rider already is when
                // the thought "I want to do this to the next one too" occurs.
                _Chip(
                  icon: Icons.done_all,
                  label: '$multiSelectModifier-click another trail to edit '
                      'several at once',
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text('Way ${trail.osmWayId} on osm.org'),
                    onPressed: () => launchUrl(Uri.parse(trail.osmUrl)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says out loud whether these values are authoritative yet. The editor can't
/// safely submit against tile data, so it's worth being visible about which
/// one the panel is showing.
class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.trail, required this.state});

  final Trail trail;
  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, text) = switch (trail) {
      _ when state.isLoadingDetails(trail.osmWayId) => (
        Icons.sync,
        'Checking OpenStreetMap for the latest tags…',
      ),
      _ when trail.isAuthoritative => (
        Icons.check_circle_outline,
        'Live from OpenStreetMap, version ${trail.version}',
      ),
      _ => (Icons.layers_outlined, 'From map tiles — may be a few hours old'),
    };
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

/// Difficulty for one trail, read-only until the pencil is tapped.
///
/// Public because the in-view list reuses nothing of its chrome but the bulk
/// editor and this panel both need the same commit rules — those live in
/// [StewardState.applyDifficulty], which this calls with a list of one.
class DifficultyField extends StatefulWidget {
  const DifficultyField({
    super.key,
    required this.trail,
    required this.state,
  });

  final Trail trail;
  final StewardState state;

  @override
  State<DifficultyField> createState() => _DifficultyFieldState();
}

class _DifficultyFieldState extends State<DifficultyField> {
  bool _isEditing = false;
  Difficulty? _draft;

  @override
  void didUpdateWidget(DifficultyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A half-finished edit belongs to the trail it was started on.
    if (oldWidget.trail.osmWayId != widget.trail.osmWayId) _cancel();
  }

  StagedEdit? get _staged => widget.state.stagedEditFor(
    widget.trail.osmWayId,
    TrailAttribute.difficulty,
  );

  /// What the panel shows: the pending value when there is one, so the rider
  /// sees the trail as they've just described it.
  Difficulty get _shown => _staged?.difficulty ?? widget.trail.difficulty;

  /// Editing is gated on authoritative tags. A changeset composed against tile
  /// data is built on a version that may already be stale.
  bool get _canEdit => widget.trail.isAuthoritative;

  void _startEditing() => setState(() {
    _isEditing = true;
    _draft = widget.trail.hasDifficulty || _staged != null ? _shown : null;
  });

  void _cancel() => setState(() {
    _isEditing = false;
    _draft = null;
  });

  void _commit() {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _isEditing = false;
      _draft = null;
    });
    // A list of one: picking the value OSM already holds isn't an edit, and is
    // how a rider walks back a pending change — the same rule the bulk editor
    // applies across a hundred trails.
    widget.state.applyDifficulty([widget.trail], draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staged = _staged;

    return Field(
      label: 'Difficulty',
      isMissing: !widget.trail.hasDifficulty && staged == null,
      isStaged: staged != null,
      trailing: _isEditing
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (staged != null)
                  IconAction(
                    icon: Icons.undo,
                    tooltip: 'Discard this staged change',
                    onPressed: () => widget.state.unstageEdit(
                      widget.trail.osmWayId,
                      TrailAttribute.difficulty,
                    ),
                  ),
                IconAction(
                  icon: Icons.edit_outlined,
                  tooltip: _canEdit
                      ? 'Edit difficulty'
                      : 'Waiting for the latest tags from OpenStreetMap',
                  onPressed: _canEdit ? _startEditing : null,
                ),
              ],
            ),
      child: _isEditing ? _buildEditor(theme) : _buildValue(theme, staged),
    );
  }

  Widget _buildValue(ThemeData theme, StagedEdit? staged) {
    final hasValue = widget.trail.hasDifficulty || staged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DifficultyIcon(_shown),
            const SizedBox(width: 10),
            Text(hasValue ? _shown.label : 'Not rated yet'),
          ],
        ),
        if (staged != null) ...[
          const SizedBox(height: 4),
          Text(
            'Was ${staged.fromLabel.toLowerCase()}',
            style: theme.textTheme.bodySmall,
          ),
          if (staged.note case final note?) ...[
            const SizedBox(height: 4),
            Text(note, style: theme.textTheme.bodySmall),
          ],
        ],
      ],
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DifficultyDropdown(
                value: _draft,
                onChanged: (d) => setState(() => _draft = d),
              ),
            ),
            const SizedBox(width: 2),
            IconAction(
              icon: Icons.check,
              tooltip: 'Stage this change',
              onPressed: _draft == null ? null : _commit,
              emphasised: true,
            ),
            IconAction(
              icon: Icons.close,
              tooltip: 'Discard',
              onPressed: _cancel,
            ),
          ],
        ),
        if (_draft?.isCommonsOnly ?? false) ...[
          const SizedBox(height: 6),
          Text(Difficulty.commonsOnlyNote, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  const _SurfaceRow({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    final surface = trail.surface;
    final label = switch (surface) {
      final s? => s.label,
      // A real OSM value SLAB's picker can't express — show it plainly rather
      // than calling it missing.
      null when trail.hasUnmappedSurface => trail.rawSurface!,
      _ => 'Not recorded yet',
    };
    return Field(
      label: 'Surface',
      isMissing: trail.rawSurface == null,
      child: Text(label),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
