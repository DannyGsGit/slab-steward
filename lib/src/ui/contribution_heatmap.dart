import 'package:flutter/material.dart';

import '../model/steward_stats.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// How many weeks of history the grid shows. Columns are weeks and rows are
/// weekdays, so the window is always a whole number of weeks.
const _weeks = 10;

const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Which weekday rows get a label down the left edge. Labelling all seven in
/// a sidebar this narrow just makes a column of noise.
const _labelledRows = {0, 2, 4};

/// The "Contribution activity" card: a GitHub-style grid of the last
/// [_weeks] weeks, one column per week and one row per weekday, each cell
/// shaded by how many trails were touched that day.
class ContributionHeatmap extends StatelessWidget {
  const ContributionHeatmap({super.key, required this.stats});

  final StewardStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Anchor on the Monday of this week so the last column is the current,
    // partly-finished week and every row is a consistent weekday.
    final thisMonday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final firstMonday = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day - (_weeks - 1) * 7,
    );

    final busiestDay = stats.dailyTrails.values.isEmpty
        ? 0
        : stats.dailyTrails.values.reduce((a, b) => a > b ? a : b);

    return SlabSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contribution activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 3.0;
              const labelWidth = 14.0;
              final cell =
                  (constraints.maxWidth - labelWidth - gap * _weeks) / _weeks;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      children: [
                        for (var row = 0; row < 7; row++)
                          SizedBox(
                            height: cell + gap,
                            child: _labelledRows.contains(row)
                                ? Text(
                                    _weekdayInitials[row],
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: SlabColors.sageDim,
                                    ),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                  for (var week = 0; week < _weeks; week++) ...[
                    Column(
                      children: [
                        for (var row = 0; row < 7; row++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: _HeatmapCell(
                              size: cell,
                              day: DateTime(
                                firstMonday.year,
                                firstMonday.month,
                                firstMonday.day + week * 7 + row,
                              ),
                              today: today,
                              trailsByDay: stats.dailyTrails,
                              busiestDay: busiestDay,
                            ),
                          ),
                      ],
                    ),
                    if (week < _weeks - 1) const SizedBox(width: gap),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _captionFor(stats, today),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              const _IntensityLegend(),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.size,
    required this.day,
    required this.today,
    required this.trailsByDay,
    required this.busiestDay,
  });

  final double size;
  final DateTime day;
  final DateTime today;
  final Map<DateTime, int> trailsByDay;

  /// Trails touched on the rider's busiest day, which the shading ramp is
  /// scaled against.
  final int busiestDay;

  @override
  Widget build(BuildContext context) {
    // Days after today are drawn as holes rather than as empty squares — a
    // filled square for next Thursday reads as "nothing done" on a day that
    // hasn't happened.
    if (day.isAfter(today)) {
      return SizedBox(width: size, height: size);
    }

    final trails = trailsByDay[day] ?? 0;
    final cell = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _shadeFor(trails, busiestDay),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: trails == 0 ? SlabColors.line : Colors.transparent,
        ),
      ),
    );

    return Tooltip(
      message:
          '${_monthLabels[day.month - 1]} ${day.day}: '
          '$trails trail${trails == 1 ? '' : 's'}',
      waitDuration: const Duration(milliseconds: 200),
      child: cell,
    );
  }
}

/// Empty days sit a step *below* the card they're on rather than level with
/// it — an empty cell in the card's own [SlabColors.ink700] is invisible.
Color _shadeFor(int trails, int busiestDay) {
  if (trails == 0) return SlabColors.ink900;
  if (busiestDay <= 1) return SlabColors.gold;
  // Four steps, so a busy day is plainly brighter than a quiet one instead of
  // every active day looking identical.
  final step = (trails / busiestDay * 4).ceil().clamp(1, 4);
  return SlabColors.gold.withValues(alpha: 0.25 + 0.25 * (step - 1));
}

class _IntensityLegend extends StatelessWidget {
  const _IntensityLegend();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Less',
        style: TextStyle(fontSize: 9, color: SlabColors.sageDim),
      ),
      const SizedBox(width: 4),
      for (var step = 0; step <= 4; step++) ...[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: step == 0
                ? SlabColors.ink900
                : SlabColors.gold.withValues(alpha: 0.25 + 0.25 * (step - 1)),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: step == 0 ? SlabColors.line : Colors.transparent,
            ),
          ),
        ),
        const SizedBox(width: 2),
      ],
      const SizedBox(width: 2),
      const Text(
        'More',
        style: TextStyle(fontSize: 9, color: SlabColors.sageDim),
      ),
    ],
  );
}

const _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _captionFor(StewardStats stats, DateTime today) {
  final weeks = '$_weeks weeks';
  if (stats.currentStreakDays > 0) {
    return 'Last $weeks · ${stats.currentStreakDays}-day streak going';
  }
  if (stats.dailyTrails.containsKey(today)) {
    return 'Last $weeks · nice work today';
  }
  return 'Last $weeks · edit today to start a streak';
}
