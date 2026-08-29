import 'package:flutter/material.dart';

import '../model/lens.dart';
import '../model/trail_filters.dart';
import '../state/steward_state.dart';
import 'legend.dart';
import 'slab_theme.dart';

/// What the map draws, what the colours mean, and the legend that reads them
/// back — the sidebar's Map pane.
///
/// Three independent questions, in the order a rider asks them:
///
///  1. '''Who is this for?''' Travel modes, multi-select. The access question.
///  2. '''What counts as a trail?''' Kinds, multi-select. The shape question:
///     doubletrack, pavement, sidewalks, unsanctioned lines.
///  3. '''What am I looking for?''' Lenses. The gap-finding question.
///
/// It used to be one three-way switch — all / mountain biking / hiking — which
/// answered the first question badly and never asked the second at all: a
/// steward zooming into a town watched their trail network disappear under
/// sidewalks and driveways, with no control that could say so.
class MapControlsPanel extends StatelessWidget {
  const MapControlsPanel({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    // "Unknown access" is meaningless without a mode to ask about.
    final lenses = Lens.values
        .where((l) => l != Lens.access || state.modes.isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        const _SectionLabel('Access'),
        const _SectionHint(
          'Trails closed to everyone ticked here are faded',
        ),
        for (final mode in TravelMode.values)
          _ToggleRow(
            label: mode.label,
            value: state.modes.contains(mode),
            onChanged: (on) => state.setModeEnabled(mode, on),
          ),
        const SizedBox(height: 20),
        const _SectionLabel('Include'),
        const _SectionHint(
          'Select trail types to show.',
        ),
        for (final kind in TrailKind.values)
          _ToggleRow(
            label: kind.label,
            description: kind.description,
            value: state.kinds.contains(kind),
            onChanged: (on) => state.setKindEnabled(kind, on),
          ),
        const SizedBox(height: 20),
        const _SectionLabel('Highlight'),
        const _SectionHint(
          'Rules stack: a trail has to answer every one you tick before it '
          'counts as done. Tick none for the plain map.',
        ),
        for (final lens in lenses)
          _ToggleRow(
            label: lens.label,
            value: state.lenses.contains(lens),
            onChanged: (on) => state.setLensEnabled(lens, on),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: state.lenses.isEmpty
                ? null
                : () => state.setLenses(const {}),
            child: const Text('Clear all'),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Legend'),
        const SizedBox(height: 10),
        Legend(state: state),
      ],
    );
  }
}

/// One toggle in the pane: the box, what it's called, and — where the name
/// alone doesn't say which trails it covers — a line that does.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(SlabRadii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: value, onChanged: (on) => onChanged(on ?? false)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: value ? SlabColors.cream : SlabColors.sage,
                      ),
                    ),
                  ),
                  if (description case final description?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall);
}

class _SectionHint extends StatelessWidget {
  const _SectionHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
