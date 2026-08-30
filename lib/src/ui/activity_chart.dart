import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../model/steward_stats.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// The time window the "Activity" card's line chart is bucketed by.
enum ActivityRange {
  week('Week'),
  month('Month'),
  year('1y'),
  all('All');

  const ActivityRange(this.label);

  final String label;
}

/// One point on the chart: how many trails were touched in that bucket, how
/// many active days it covers, what to print under it on the axis, and what
/// the tooltip calls it.
class _Bucket {
  const _Bucket({
    required this.trails,
    required this.activeDays,
    required this.axisLabel,
    required this.tooltipLabel,
    this.isFuture = false,
  });

  /// The plotted value — elements touched, which is what "trails touched"
  /// counts on the tile above.
  final int trails;

  /// Days in this bucket the rider opened a changeset on. Counted from the
  /// day keys rather than from [trails] being non-zero, so a day whose edits
  /// happened to touch nothing still reads as active.
  final int activeDays;

  /// A bucket the rider hasn't lived through yet — the tail of the current
  /// week. It keeps its slot on the axis (the week still reads Mon–Sun) but
  /// contributes no point, so the line stops at today instead of diving to
  /// zero on days that haven't happened.
  final bool isFuture;

  final String axisLabel;
  final String tooltipLabel;
}

/// The "Activity" card: a Week/Month/1y/All toggle over a line chart of
/// changesets per bucket, with a real y-axis and a tooltip on touch.
///
/// Bucketed from [StewardStats.dailyTrails] alone — Steward only ever fetches
/// a rider's most recent changesets (see `OsmApi.fetchChangesets`), so every
/// range is a different zoom level on that one window rather than a fresh
/// fetch.
class ActivitySection extends StatefulWidget {
  const ActivitySection({super.key, required this.stats});

  final StewardStats stats;

  @override
  State<ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<ActivitySection> {
  ActivityRange _range = ActivityRange.week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = _bucketsFor(widget.stats, _range);
    final activeBuckets = buckets.where((b) => b.activeDays > 0).length;
    final total = buckets.fold<int>(0, (sum, b) => sum + b.trails);

    final maxTrails = buckets.fold<int>(0, (m, b) => math.max(m, b.trails));
    final axis = _NiceAxis.forMax(maxTrails);

    return SlabSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Activity', style: theme.textTheme.titleMedium),
              ),
              _RangeToggle(
                selected: _range,
                onChanged: (range) => setState(() => _range = range),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$total trail${total == 1 ? '' : 's'} touched in this window',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 140,
            child: LineChart(
              _chartData(buckets: buckets, axis: axis),
              duration: const Duration(milliseconds: 180),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _captionFor(_range, activeBuckets),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A y-axis that lands on whole trails, on round numbers. Trails touched runs
/// an order of magnitude above changesets, so the naive `max / 4` gives ticks
/// like 23/46/69 — countable, but nothing a reader can hold in their head.
class _NiceAxis {
  const _NiceAxis({required this.max, required this.interval});

  final double max;
  final double interval;

  /// Roughly four gridlines, with the interval snapped up to the nearest
  /// 1/2/5×10ⁿ so the labels read 20/40/60, not 23/46/69.
  factory _NiceAxis.forMax(int maxValue) {
    // An empty window still needs a scale to draw against, and 0..4 reads as
    // "room for four" rather than as a broken axis.
    if (maxValue <= 4) return const _NiceAxis(max: 4, interval: 1);

    final rough = maxValue / 4;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor())
        .toDouble();
    final interval = [1.0, 2.0, 5.0, 10.0]
        .map((step) => step * magnitude)
        .firstWhere((candidate) => candidate >= rough);

    return _NiceAxis(
      max: (maxValue / interval).ceil() * interval,
      interval: interval,
    );
  }
}

LineChartData _chartData({
  required List<_Bucket> buckets,
  required _NiceAxis axis,
}) {
  // Dots stop being legible once the points are packed tighter than a
  // fingertip, so the 30-day view draws a bare line instead.
  final showDots = buckets.length <= 14;
  final labelEvery = math.max(1, (buckets.length / 7).ceil());

  return LineChartData(
    minX: 0,
    maxX: (buckets.length - 1).toDouble(),
    minY: 0,
    maxY: axis.max,
    clipData: const FlClipData.all(),
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: axis.interval,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: SlabColors.line, strokeWidth: 1),
    ),
    borderData: FlBorderData(show: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: axis.interval,
          reservedSize: 34,
          getTitlesWidget: (value, meta) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              value.toInt().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: SlabColors.sageDim),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 22,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
            // Always label the newest bucket — "where am I now" is the one
            // question this axis has to answer.
            final isLast = i == buckets.length - 1;
            if (!isLast && i % labelEvery != 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                buckets[i].axisLabel,
                style: const TextStyle(fontSize: 10, color: SlabColors.sageDim),
              ),
            );
          },
        ),
      ),
    ),
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => SlabColors.ink900,
        tooltipBorder: const BorderSide(color: SlabColors.line),
        tooltipBorderRadius: BorderRadius.circular(SlabRadii.control),
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItems: (spots) => [
          for (final spot in spots)
            LineTooltipItem(
              '${buckets[spot.x.round()].tooltipLabel}\n',
              const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: SlabColors.sage,
              ),
              children: [
                TextSpan(
                  text: _countLabel(spot.y.round()),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SlabColors.cream,
                  ),
                ),
              ],
            ),
        ],
      ),
      getTouchedSpotIndicator: (barData, indexes) => [
        for (final _ in indexes)
          TouchedSpotIndicatorData(
            const FlLine(color: SlabColors.goldDim, strokeWidth: 1),
            FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4,
                color: SlabColors.gold,
                strokeWidth: 2,
                strokeColor: SlabColors.ink800,
              ),
            ),
          ),
      ],
    ),
    lineBarsData: [
      LineChartBarData(
        spots: [
          for (var i = 0; i < buckets.length; i++)
            if (!buckets[i].isFuture)
              FlSpot(i.toDouble(), buckets[i].trails.toDouble()),
        ],
        isCurved: false,
        color: SlabColors.gold,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: showDots,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 3,
            color: SlabColors.gold,
            strokeWidth: 0,
            strokeColor: Colors.transparent,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              SlabColors.gold.withValues(alpha: 0.28),
              SlabColors.gold.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    ],
  );
}

String _countLabel(int trails) => '$trails trail${trails == 1 ? '' : 's'}';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

/// The lower bound on "All" — a line needs somewhere to go, and a rider who
/// started this month should still see the shape of a chart rather than one
/// lonely dot.
const _minAllMonths = 6;

List<_Bucket> _bucketsFor(StewardStats stats, ActivityRange range) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (range) {
    case ActivityRange.week:
      // Day arithmetic through the DateTime constructor rather than
      // Duration(days:) — adding 24h across a DST boundary lands at 23:00 the
      // day before, which would never match a midnight-keyed bucket.
      final monday = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1),
      );
      return [
        for (var i = 0; i < 7; i++)
          () {
            final day = DateTime(monday.year, monday.month, monday.day + i);
            return _dayBucket(
              stats,
              day,
              axisLabel: _weekdayLabels[i],
              isFuture: day.isAfter(today),
            );
          }(),
      ];

    case ActivityRange.month:
      final start = DateTime(today.year, today.month, today.day - 29);
      return [
        for (var i = 0; i < 30; i++)
          () {
            final day = DateTime(start.year, start.month, start.day + i);
            return _dayBucket(stats, day, axisLabel: '${day.day}');
          }(),
      ];

    case ActivityRange.year:
      return [
        for (var i = 11; i >= 0; i--)
          _monthBucket(stats, DateTime(today.year, today.month - i)),
      ];

    case ActivityRange.all:
      final first = (stats.firstEditAt ?? today).toLocal();
      final elapsed =
          (today.year - first.year) * 12 + (today.month - first.month) + 1;
      final span = elapsed.clamp(_minAllMonths, 24);
      return [
        for (var i = span - 1; i >= 0; i--)
          _monthBucket(stats, DateTime(today.year, today.month - i)),
      ];
  }
}

_Bucket _dayBucket(
  StewardStats stats,
  DateTime day, {
  required String axisLabel,
  bool isFuture = false,
}) => _Bucket(
  trails: stats.dailyTrails[day] ?? 0,
  activeDays: stats.dailyTrails.containsKey(day) ? 1 : 0,
  axisLabel: axisLabel,
  tooltipLabel: '${_monthLabels[day.month - 1]} ${day.day}',
  isFuture: isFuture,
);

_Bucket _monthBucket(StewardStats stats, DateTime month) {
  final inMonth = stats.dailyTrails.entries.where(
    (e) => e.key.year == month.year && e.key.month == month.month,
  );
  return _Bucket(
    trails: inMonth.fold<int>(0, (sum, e) => sum + e.value),
    activeDays: inMonth.length,
    axisLabel: _monthLabels[month.month - 1],
    tooltipLabel: '${_monthLabels[month.month - 1]} ${month.year}',
  );
}

String _captionFor(ActivityRange range, int activeBuckets) {
  String days(int n) => '$n active day${n == 1 ? '' : 's'}';
  String months(int n) => '$n active month${n == 1 ? '' : 's'}';
  return switch (range) {
    ActivityRange.week => '${days(activeBuckets)} this week',
    ActivityRange.month => '${days(activeBuckets)} in the last 30 days',
    ActivityRange.year => '${months(activeBuckets)} in the last 12 months',
    ActivityRange.all => '${months(activeBuckets)} overall',
  };
}

/// A compact Week/Month/1y/All switcher, hand-rolled rather than
/// [SegmentedButton] — that widget's minimum tap targets don't fit four
/// segments in the sidebar's width without overflowing.
class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.selected, required this.onChanged});

  final ActivityRange selected;
  final ValueChanged<ActivityRange> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: SlabColors.ink900,
      borderRadius: BorderRadius.circular(SlabRadii.pill),
      border: Border.all(color: SlabColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final range in ActivityRange.values)
          _RangeChip(
            range: range,
            selected: range == selected,
            onTap: () => onChanged(range),
          ),
      ],
    ),
  );
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.range,
    required this.selected,
    required this.onTap,
  });

  final ActivityRange range;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(SlabRadii.pill),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? SlabColors.goldSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(SlabRadii.pill),
      ),
      child: Text(
        range.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? SlabColors.gold : SlabColors.sage,
        ),
      ),
    ),
  );
}
