import 'package:flutter/material.dart';

import '../model/difficulty.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';

/// Every trail the map is currently drawing, as a list.
///
/// Two jobs, per product description §4. It's a discovery surface — the same
/// completeness questions the lenses ask, but as a working list you can go down
/// one row at a time — and it's the selection surface for a bulk edit, because
/// "tick the twelve trails missing a rating" is a thing you can do in a list
/// and cannot sanely do by clicking twelve lines on a map.
///
/// The list is the viewport: it's re-read whenever the camera settles, and it
/// inherits the travel-mode and lens filters the map is already applying.
class TrailListPanel extends StatefulWidget {
  const TrailListPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<TrailListPanel> createState() => _TrailListPanelState();
}

/// The completeness questions the list can be narrowed by — the lens
/// vocabulary, asked of a list instead of a colour ramp.
enum _ListFilter {
  all('All'),
  missingDifficulty('No rating'),
  missingSurface('No surface'),
  missingElectricBicycle('No e-bike rule');

  const _ListFilter(this.label);

  final String label;

  bool matches(Trail trail) => switch (this) {
    _ListFilter.all => true,
    _ListFilter.missingDifficulty => !trail.hasDifficulty,
    _ListFilter.missingSurface => trail.rawSurface == null,
    _ListFilter.missingElectricBicycle => !trail.hasElectricBicycle,
  };
}

class _TrailListPanelState extends State<TrailListPanel> {
  _ListFilter _filter = _ListFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final trails = [
      for (final trail in state.visibleTrails)
        if (_filter.matches(trail)) trail,
    ];

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        // Wide enough to carry a name, its answer, and a live picker on one
        // line. See [_TrailRow].
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Trails in view',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close the list',
                    onPressed: () => state.setTrailListOpen(false),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final filter in _ListFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _SelectAllRow(state: state, trails: trails),
            const Divider(height: 1),
            Flexible(child: _buildList(theme, trails)),
            if (state.visibleTrailsTruncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Showing the first ${StewardState.maxVisibleTrails} trails. '
                  'Zoom in to narrow this down.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, List<Trail> trails) {
    if (trails.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Text(switch ((widget.state.hasListedVisibleTrails, _filter)) {
          (false, _) => 'Reading the map…',
          (_, _ListFilter.all) =>
            'No trails in view. Pan or zoom in until some appear.',
          _ => 'Every trail in view already answers that question.',
        }, style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: trails.length,
      itemBuilder: (context, i) => _TrailRow(
        key: ValueKey(trails[i].osmWayId),
        trail: trails[i],
        state: widget.state,
      ),
    );
  }
}

/// Tick every trail the filter is currently showing — the whole point of the
/// list as a bulk-selection surface. Selections made elsewhere, or scrolled out
/// of view, are left alone either way.
class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({required this.state, required this.trails});

  final StewardState state;
  final List<Trail> trails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listed = {for (final trail in trails) trail.osmWayId};
    final selectedHere = listed.where(state.isSelected).length;
    final value = switch (selectedHere) {
      0 => false,
      _ when selectedHere == listed.length => true,
      _ => null,
    };

    void toggle() {
      final selection = {
        for (final trail in state.selectedTrails) trail.osmWayId,
      };
      state.setSelection(
        value == true ? selection.difference(listed) : selection.union(listed),
      );
    }

    return InkWell(
      onTap: listed.isEmpty ? null : toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
        child: Row(
          children: [
            Checkbox(
              tristate: true,
              value: value,
              onChanged: listed.isEmpty ? null : (_) => toggle(),
            ),
            Expanded(
              child: Text(
                'Select all ${listed.length}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (state.selectionCount > 0)
              Text(
                '${state.selectionCount} selected',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// One trail in the list: tick it into the working set, or rate it right here
/// without leaving the list.
///
/// The picker is live, the same as the one in the detail panel — a list is a
/// place to work through twelve trails quickly, and a pencil in front of every
/// row is twelve extra clicks buying nothing.
class _TrailRow extends StatefulWidget {
  const _TrailRow({super.key, required this.trail, required this.state});

  final Trail trail;
  final StewardState state;

  @override
  State<_TrailRow> createState() => _TrailRowState();
}

class _TrailRowState extends State<_TrailRow> {
  /// True while this row's OSM read is in flight.
  bool _isResolving = false;

  StagedEdit? get _staged => widget.state.stagedEditFor(
    widget.trail.osmWayId,
    TrailAttribute.difficulty,
  );

  Difficulty? get _shown {
    final staged = _staged?.difficulty;
    if (staged != null) return staged;
    final trail = widget.state.trailFor(widget.trail.osmWayId) ?? widget.trail;
    return trail.hasDifficulty ? trail.difficulty : null;
  }

  /// The list is built from tile data, so a row usually has no authoritative
  /// tags until someone picks a value on it. Fetching all of them up front
  /// would be one OSM API call per trail on screen; fetching this one, now, is
  /// the same gate the panel applies, just asked at the moment of intent.
  Future<void> _pick(Difficulty value) async {
    setState(() => _isResolving = true);
    await widget.state.setDifficulty(widget.trail.osmWayId, value);
    if (mounted) setState(() => _isResolving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final trail = state.trailFor(widget.trail.osmWayId) ?? widget.trail;
    final staged = _staged;

    return Container(
      decoration: BoxDecoration(
        color: state.isSelected(trail.osmWayId)
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : null,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: Row(
          children: [
            Checkbox(
              value: state.isSelected(trail.osmWayId),
              onChanged: (checked) =>
                  state.setSelected(trail.osmWayId, checked ?? false),
            ),
            Expanded(child: _buildLabel(theme, trail, staged)),
            if (staged != null)
              IconAction(
                icon: Icons.undo,
                tooltip: 'Discard this staged change',
                onPressed: () => state.unstageEdit(
                  trail.osmWayId,
                  TrailAttribute.difficulty,
                ),
              ),
            const SizedBox(width: 4),
            SizedBox(
              width: 150,
              child: DifficultyDropdown(
                value: _shown,
                hint: 'Rate it',
                onChanged: _isResolving
                    ? null
                    : (value) {
                        if (value != null) _pick(value);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(ThemeData theme, Trail trail, StagedEdit? staged) {
    final error = widget.state.readErrorFor(trail.osmWayId);
    final (subtitle, isError) = switch ((_isResolving, error, staged)) {
      (true, _, _) => ('Reading the latest tags from OpenStreetMap…', false),
      (_, final message?, _) => (message, true),
      (_, _, final edit?) => (edit.summary, false),
      _ => (_describe(trail), false),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trail.name ?? 'Unnamed trail',
          style: theme.textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
        Row(
          children: [
            if (staged != null) ...[
              const StatusBadge.staged(),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isError ? theme.colorScheme.error : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _describe(Trail trail) {
    final surface = trail.surface?.label ?? trail.rawSurface;
    return switch ((trail.hasDifficulty, surface)) {
      (false, null) => 'No rating, no surface',
      (false, final s?) => 'No rating · $s',
      (true, null) => '${trail.difficulty.label} · no surface',
      (true, final s?) => '${trail.difficulty.label} · $s',
    };
  }
}

/// The map-level control that opens [TrailListPanel].
///
/// Sits with the other map chrome rather than in the panel, because its job is
/// to answer "what else is around here?" — a question asked of the map, not of
/// any one trail.
class TrailListButton extends StatelessWidget {
  const TrailListButton({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = state.isTrailListOpen;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: isOpen ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: state.toggleTrailList,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.format_list_bulleted, size: 22),
              const SizedBox(width: 12),
              Text(isOpen ? 'Hide the trail list' : 'List trails in view'),
            ],
          ),
        ),
      ),
    );
  }
}
