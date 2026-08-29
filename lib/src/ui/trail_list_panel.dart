import 'package:flutter/material.dart';

import '../model/difficulty.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// Every trail the map is currently drawing, as a list.
///
/// Two jobs, per product description §4. It's a discovery surface — the same
/// completeness questions the lenses ask, but as a working list you can go down
/// one row at a time — and it's the selection surface for a bulk edit, because
/// "tick the twelve trails missing a rating" is a thing you can do in a list
/// and cannot sanely do by clicking twelve lines on a map.
///
/// The list is the viewport: it's re-read whenever the camera settles, and it
/// inherits the travel-mode and lens filters the map is already applying — it
/// shows exactly what the map shows, and narrows nothing further on its own.
class TrailListPanel extends StatelessWidget {
  const TrailListPanel({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trails = state.visibleTrails;

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
            PanelHeader(
              title: 'Trails in view',
              closeTooltip: 'Close the list',
              onClose: () => state.setTrailListOpen(false),
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
        child: Text(
          state.hasListedVisibleTrails
              ? 'No trails in view. Pan or zoom in until some appear.'
              : 'Reading the map…',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: trails.length,
      itemBuilder: (context, i) => _TrailRow(
        key: ValueKey(trails[i].osmWayId),
        trail: trails[i],
        state: state,
      ),
    );
  }
}

/// Tick every trail the list is currently showing — the whole point of the
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
      child: Container(
        color: SlabColors.ink900,
        padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: SlabColors.gold,
                  fontWeight: FontWeight.w600,
                ),
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
        // A ticked row wears the gold wash the design system puts behind any
        // active control.
        color: state.isSelected(trail.osmWayId) ? SlabColors.goldSoft : null,
        border: const Border(bottom: BorderSide(color: SlabColors.line)),
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
              width: 158,
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
    final isOpen = state.isTrailListOpen;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: isOpen ? SlabColors.goldSoft : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SlabRadii.panel),
        side: BorderSide(color: isOpen ? SlabColors.gold : SlabColors.line),
      ),
      child: InkWell(
        onTap: state.toggleTrailList,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.format_list_bulleted,
                size: 20,
                color: isOpen ? SlabColors.gold : SlabColors.sage,
              ),
              const SizedBox(width: 12),
              Text(
                isOpen ? 'Hide the trail list' : 'List trails in view',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isOpen ? SlabColors.gold : SlabColors.cream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
