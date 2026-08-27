import 'package:flutter/material.dart';

import '../parsing/models.dart';
import '../parsing/timetable.dart';
import 'theme.dart';

/// 課表格子。
///
/// 只畫**解析得出時段**的課。沒有時段的課不會被吞掉 —— 它們在下面的清單裡，
/// 而且清單永遠會顯示全部。這是刻意的取捨：與其把一堂課猜到錯的格子，
/// 不如讓它出現在清單而不出現在格子裡。使用者看得出「這堂課沒排進去」，
/// 但看不出「這堂課排錯了」。
///
/// **為什麼不用 DataTable**：它一格是一格，連堂的課（`102 103 104`）會被畫成
/// 三個各自獨立的儲存格、課名重複三次，看起來像三門不同的課。這裡改成
/// 疊在格線上的方塊，連著的節次合成一塊。
class TimetableGrid extends StatelessWidget {
  const TimetableGrid({super.key, required this.courses, this.today});

  final List<Course> courses;

  /// 今天是星期幾（0 = 週一）。給測試用；正式執行時預設是今天。
  final int? today;

  /// 一節多高。要放得下兩行課名加一行教室。
  static const double _rowHeight = 56;

  /// 最左邊那一欄（節次）。
  static const double _periodWidth = 32;

  /// 一天最少要多寬。比這個窄的話課名一個字都放不下，寧可橫向捲動。
  static const double _minDayWidth = 64;

  /// 一門課的顏色。
  ///
  /// 用**課號**決定，不是清單順序 —— 換一個學期、多加一門課，同一門課的
  /// 顏色才不會跟著換。自己算雜湊而不用 `String.hashCode`：後者不保證
  /// 跨版本穩定，那會讓顏色在某次更新後莫名其妙全部重排。
  static Color colorFor(String key) {
    var h = 0;
    for (final unit in key.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return NtouTheme.moduleColor(h % NtouTheme.moduleColors.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheduled = courses.where((c) => c.slots.isNotEmpty).toList();
    if (scheduled.isEmpty) return const SizedBox.shrink();

    // 星期範圍：至少一到五，有週末的課才多畫。
    var days = 5;
    var minPeriod = 99;
    var maxPeriod = 0;
    for (final c in scheduled) {
      for (final s in c.slots) {
        if (s.weekday + 1 > days) days = s.weekday + 1;
        if (s.period < minPeriod) minPeriod = s.period;
        if (s.period > maxPeriod) maxPeriod = s.period;
      }
    }

    final blocks = _blocks(scheduled);
    final rows = maxPeriod - minPeriod + 1;
    final todayIndex = today ?? (DateTime.now().weekday - 1);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - _periodWidth;
          final dayWidth =
              (available / days).clamp(_minDayWidth, double.infinity);
          final total = _periodWidth + dayWidth * days;

          final grid = SizedBox(
            width: total,
            height: _rowHeight * (rows + 1), // +1 是星期那一列
            child: _Grid(
              days: days,
              rows: rows,
              minPeriod: minPeriod,
              dayWidth: dayWidth,
              rowHeight: _rowHeight,
              periodWidth: _periodWidth,
              today: todayIndex,
              blocks: blocks,
            ),
          );

          // 一到五塞得下就不要捲；有週末課才可能超出去。
          return total <= constraints.maxWidth
              ? grid
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: grid);
        },
      ),
    );
  }

  /// 把每門課的時段切成「連著的幾節」。
  ///
  /// `102 103 104` 是同一堂課上三節，不是三堂課 —— 要合成一塊，
  /// 課名才不會重複三次。中間斷開的（`102` 和 `105`）各自一塊。
  static List<_Block> _blocks(List<Course> courses) {
    final out = <_Block>[];
    for (final c in courses) {
      final byDay = <int, List<int>>{};
      for (final s in c.slots) {
        (byDay[s.weekday] ??= []).add(s.period);
      }
      byDay.forEach((weekday, periods) {
        periods.sort();
        var start = periods.first;
        var prev = periods.first;
        for (final p in periods.skip(1)) {
          if (p == prev + 1) {
            prev = p;
            continue;
          }
          out.add(_Block(c, weekday, start, prev - start + 1));
          start = p;
          prev = p;
        }
        out.add(_Block(c, weekday, start, prev - start + 1));
      });
    }
    return out;
  }
}

class _Block {
  const _Block(this.course, this.weekday, this.start, this.length);

  final Course course;
  final int weekday;
  final int start;
  final int length;

  Color get color => TimetableGrid.colorFor(
      course.code.isNotEmpty ? course.code : course.name);
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.days,
    required this.rows,
    required this.minPeriod,
    required this.dayWidth,
    required this.rowHeight,
    required this.periodWidth,
    required this.today,
    required this.blocks,
  });

  final int days;
  final int rows;
  final int minPeriod;
  final double dayWidth;
  final double rowHeight;
  final double periodWidth;
  final int today;
  final List<_Block> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      children: [
        // 今天那一欄先鋪一層淡底
        if (today >= 0 && today < days)
          Positioned(
            left: periodWidth + dayWidth * today,
            top: 0,
            width: dayWidth,
            height: rowHeight * (rows + 1),
            child: ColoredBox(color: scheme.primary.withValues(alpha: 0.05)),
          ),

        // 星期
        for (var d = 0; d < days; d++)
          Positioned(
            left: periodWidth + dayWidth * d,
            top: 0,
            width: dayWidth,
            height: rowHeight,
            child: Center(
              child: Text(
                kWeekdays[d],
                style: theme.textTheme.labelLarge?.copyWith(
                  color: d == today ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: d == today ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),

        // 節次
        for (var r = 0; r < rows; r++)
          Positioned(
            left: 0,
            top: rowHeight * (r + 1),
            width: periodWidth,
            height: rowHeight,
            child: Center(
              child: Text(
                '${minPeriod + r}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),

        // 橫格線
        for (var r = 0; r <= rows; r++)
          Positioned(
            left: 0,
            top: rowHeight * (r + 1),
            width: periodWidth + dayWidth * days,
            height: 1,
            child: ColoredBox(color: scheme.outlineVariant),
          ),

        // 課
        for (final b in blocks)
          Positioned(
            left: periodWidth + dayWidth * b.weekday + 2,
            top: rowHeight * (b.start - minPeriod + 1) + 2,
            width: dayWidth - 4,
            height: rowHeight * b.length - 4,
            child: _CourseBlock(block: b),
          ),
      ],
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.block});

  final _Block block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = block.course;
    final color = block.color;

    final last = block.start + block.length - 1;
    final when = block.length == 1
        ? '第 ${block.start} 節'
        : '第 ${block.start} 到 $last 節';

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [
        '星期${kWeekdays[block.weekday.clamp(0, 6)]}$when',
        c.name,
        if (c.room.isNotEmpty) c.room,
      ].join('，'),
      child: Container(
        decoration: BoxDecoration(
          // 顏色只做底色和左邊那條 —— **文字一律用 onSurface**。
          // 色盤裡的琥珀 #F9A825、黃綠 #7CB342 在白底上當文字色只有 2:1 上下，
          // 那是讀不了的。
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(NtouTheme.radiusSm),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                c.name,
                maxLines: block.length > 1 ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
            if (c.room.isNotEmpty)
              Text(
                c.room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
