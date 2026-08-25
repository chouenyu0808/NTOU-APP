import 'package:flutter/material.dart';

import '../parsing/models.dart';
import '../parsing/timetable.dart';

/// 課表格子。
///
/// 只畫**解析得出時段**的課。沒有時段的課不會被吞掉 —— 它們在下面的清單裡，
/// 而且清單永遠會顯示全部。這是刻意的取捨：與其把一堂課猜到錯的格子，
/// 不如讓它出現在清單而不出現在格子裡。使用者看得出「這堂課沒排進去」，
/// 但看不出「這堂課排錯了」。
class TimetableGrid extends StatelessWidget {
  const TimetableGrid({super.key, required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    final scheduled = courses.where((c) => c.slots.isNotEmpty).toList();
    if (scheduled.isEmpty) return const SizedBox.shrink();

    // 星期範圍：至少一到五，有週末的課才多畫。
    var maxWeekday = 4;
    var minPeriod = 99;
    var maxPeriod = 0;
    for (final c in scheduled) {
      for (final s in c.slots) {
        if (s.weekday > maxWeekday) maxWeekday = s.weekday;
        if (s.period < minPeriod) minPeriod = s.period;
        if (s.period > maxPeriod) maxPeriod = s.period;
      }
    }

    // 每一格放哪堂課
    final cells = <int, Map<int, Course>>{};
    for (final c in scheduled) {
      for (final s in c.slots) {
        (cells[s.period] ??= {})[s.weekday] = c;
      }
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTableTheme(
          data: const DataTableThemeData(
            headingRowHeight: 36,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 68,
            columnSpacing: 8,
            horizontalMargin: 8,
          ),
          child: DataTable(
            columns: [
              const DataColumn(label: Text('節')),
              for (var wd = 0; wd <= maxWeekday; wd++)
                DataColumn(label: Text(kWeekdays[wd])),
            ],
            rows: [
              for (var p = minPeriod; p <= maxPeriod; p++)
                DataRow(
                  cells: [
                    DataCell(Text('$p', style: theme.textTheme.labelMedium)),
                    for (var wd = 0; wd <= maxWeekday; wd++)
                      DataCell(_cell(context, cells[p]?[wd], scheme)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, Course? course, ColorScheme scheme) {
    if (course == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (course.room.isNotEmpty)
            Text(
              course.room,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }
}
