import 'package:flutter/material.dart';

import '../model/lens.dart';
import '../state/steward_state.dart';

/// Travel mode and lens pickers — what's drawn, and what question the colours
/// are answering. Both concepts are OpenTrailMap's.
///
/// Collapsible: the pickers are only useful while being adjusted, so they
/// give up screen real estate to the map the rest of the time.
class MapControls extends StatefulWidget {
  const MapControls({super.key, required this.state});

  final StewardState state;

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // "Unknown access" is meaningless without a travel mode to ask about.
    final lenses = Lens.values
        .where((l) => l != Lens.access || state.mode != TravelMode.all)
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0).add(
          EdgeInsets.only(bottom: _expanded ? 0 : 10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Label('Map controls'),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              const _Label('Show'),
              const SizedBox(height: 6),
              SegmentedButton<TravelMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  for (final mode in TravelMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {state.mode},
                onSelectionChanged: (s) => state.setMode(s.first),
              ),
              const SizedBox(height: 16),
              const _Label('Highlight'),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final lens in lenses)
                      ChoiceChip(
                        label: Text(lens.label),
                        selected: state.lens == lens,
                        onSelected: (_) => state.setLens(lens),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(letterSpacing: 0.8),
  );
}
