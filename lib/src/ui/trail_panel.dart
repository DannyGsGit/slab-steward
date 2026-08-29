import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/difficulty.dart';
import '../model/electric_bicycle.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';

/// Details for the selected trail, and the guided editor for the attributes
/// Steward can change.
///
/// Every editable attribute is a picker, always live: choosing a value stages
/// it, the way the bulk editor works. There is no pencil to press first and no
/// check to press after — an edit-mode toggle in front of a three-option
/// dropdown is two clicks of ceremony around one decision, and nothing here
/// reaches OpenStreetMap anyway. Staged edits collect in [StewardState], show
/// as STAGED with an undo beside them, and go out together as one changeset
/// from the staged-changes review.
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
                ElectricBicycleField(trail: trail, state: state),
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
                  label:
                      '$multiSelectModifier-click another trail — or '
                      '$multiSelectModifier-drag a box — to edit several '
                      'at once',
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

/// Difficulty for one trail: a live picker, not a value with an edit button.
///
/// Public because the bulk editor and this panel both need the same commit
/// rules — those live in [StewardState.applyDifficulty], which this calls with
/// a list of one.
class DifficultyField extends StatelessWidget {
  const DifficultyField({super.key, required this.trail, required this.state});

  final Trail trail;
  final StewardState state;

  StagedEdit? get _staged =>
      state.stagedEditFor(trail.osmWayId, TrailAttribute.difficulty);

  /// What the picker shows: the pending value when there is one, so the rider
  /// sees the trail as they've just described it. Null when nobody has rated
  /// it, which is what puts the hint in the picker.
  ///
  /// Also null when OSM holds something outside the 0–4 scale — `imba=7` is
  /// not a rating, and handing the picker a value it doesn't offer is an
  /// assertion, not a display.
  Difficulty? get _shown => switch (_staged?.difficulty) {
    final staged? => staged,
    null when trail.hasDifficulty && trail.difficulty != Difficulty.unrated =>
      trail.difficulty,
    _ => null,
  };

  /// True when OSM has a `mtb:scale:imba` value that isn't one of the five.
  bool get _hasUnreadableRating =>
      trail.hasDifficulty && trail.difficulty == Difficulty.unrated;

  /// Editing is gated on authoritative tags. A changeset composed against tile
  /// data is built on a version that may already be stale.
  bool get _canEdit => trail.isAuthoritative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staged = _staged;
    final shown = _shown;

    return Field(
      label: 'Difficulty',
      isMissing: !trail.hasDifficulty && staged == null,
      isStaged: staged != null,
      trailing: staged == null
          ? null
          : IconAction(
              icon: Icons.undo,
              tooltip: 'Discard this staged change',
              onPressed: () =>
                  state.unstageEdit(trail.osmWayId, TrailAttribute.difficulty),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WhileReading(
            isEditable: _canEdit,
            child: DifficultyDropdown(
              value: shown,
              // A list of one: picking the value OSM already holds isn't an
              // edit, and is how a rider walks back a pending change — the
              // same rule the bulk editor applies across a hundred trails.
              onChanged: _canEdit
                  ? (value) {
                      if (value != null) state.applyDifficulty([trail], value);
                    }
                  : null,
            ),
          ),
          if (staged != null) ...[
            const SizedBox(height: 6),
            Text(
              'Was ${staged.fromLabel.toLowerCase()}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (shown?.isCommonsOnly ?? false) ...[
            const SizedBox(height: 6),
            Text(Difficulty.commonsOnlyNote, style: theme.textTheme.bodySmall),
          ],
          if (staged == null && _hasUnreadableRating) ...[
            const SizedBox(height: 6),
            Text(
              'OpenStreetMap holds “${trail.tags[Difficulty.osmKey]}” here, '
              'which is not a rating on the 0–4 scale. Picking one replaces '
              'it.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// E-bike permission for one trail, on the same terms as [DifficultyField],
/// with one of its own.
///
/// A trail already answering with a value outside Steward's two options —
/// `designated`, `permissive`, anything else in the access vocabulary — is
/// shown read-only. `electric_bicycle` is a single key, so a pick would
/// *replace* that answer rather than add to it, and `designated` says
/// everything "allowed" says and more. Steward is not the tool that quietly
/// throws that away; the note points at an editor that can change it
/// deliberately.
class ElectricBicycleField extends StatelessWidget {
  const ElectricBicycleField({
    super.key,
    required this.trail,
    required this.state,
  });

  final Trail trail;
  final StewardState state;

  StagedEdit? get _staged =>
      state.stagedEditFor(trail.osmWayId, TrailAttribute.electricBicycle);

  EbikeAccess? get _shown => _staged?.electricBicycle ?? trail.electricBicycle;

  /// See the class doc: a value the picker can't express is not a gap to fill,
  /// it's an answer to leave alone.
  bool get _isProtected => trail.hasUnmappedElectricBicycle;

  bool get _canEdit => trail.isAuthoritative && !_isProtected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staged = _staged;
    final shown = _shown;
    // What the current answer actually claims, in the same words the picker
    // used to offer it: "allowed" and "e-bike trail" are a distinction that
    // has to survive the menu closing. An empty field says nothing — the
    // picker's own hint is the whole story there.
    final note = switch ((shown, _isProtected)) {
      (final access?, _) => access.description,
      (null, true) =>
        'OpenStreetMap already answers this with '
            '“${trail.rawElectricBicycle}”, which says more than either '
            'of Steward\'s options. Steward leaves it alone rather than '
            'replacing it — change it in a full editor if it\'s wrong.',
      _ => null,
    };

    return Field(
      label: 'E-bike access',
      isMissing: !trail.hasElectricBicycle && staged == null,
      isStaged: staged != null,
      trailing: staged == null
          ? null
          : IconAction(
              icon: Icons.undo,
              tooltip: 'Discard this staged change',
              onPressed: () => state.unstageEdit(
                trail.osmWayId,
                TrailAttribute.electricBicycle,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isProtected)
            // Not a disabled picker: there is nothing here for a rider to do,
            // and a greyed-out dropdown reads as "wait" rather than "this one
            // is already answered".
            Row(
              children: [
                const EbikeIcon(null),
                const SizedBox(width: 8),
                Expanded(child: Text(trail.rawElectricBicycle!)),
              ],
            )
          else
            _WhileReading(
              isEditable: _canEdit,
              child: ElectricBicycleDropdown(
                value: shown,
                hint: 'Not recorded',
                onChanged: _canEdit
                    ? (value) {
                        if (value != null) {
                          state.applyElectricBicycle([trail], value);
                        }
                      }
                    : null,
              ),
            ),
          if (staged != null) ...[
            const SizedBox(height: 6),
            Text(
              'Was ${staged.fromLabel.toLowerCase()}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Says why a picker is disabled, and gets out of the way once it isn't.
///
/// Every field is gated on the same thing — authoritative tags — so the
/// explanation is one sentence written in one place rather than per field.
class _WhileReading extends StatelessWidget {
  const _WhileReading({required this.isEditable, required this.child});

  final bool isEditable;
  final Widget child;

  @override
  Widget build(BuildContext context) => isEditable
      ? child
      : Tooltip(
          message: 'Waiting for the latest tags from OpenStreetMap',
          child: child,
        );
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
