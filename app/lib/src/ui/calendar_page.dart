import 'package:flutter/material.dart';

import '../parsing/academic_calendar.dart';

/// 整學年的行事曆。首頁只列接下來 4 筆，這裡列全部 —— 都是抓官網那一頁時
/// 一起 parse 好的，開這一頁不會再打一次伺服器。
///
/// **接下來的排在上面，已過去的收進底部摺疊區。** 過去的事件（開學日、
/// 加退選截止）常常是要回頭查的參考點，藏掉不方便、但也不該擋在最前面 ——
/// 進到這一頁最想看的是「接下來」。
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key, required this.events, required this.now});

  final List<CalendarEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);

    // 照開始日排。學校給的順序不保證是時間序 —— 一頁行事曆上按鈕的排列
    // 是照版面，不是照日期。
    final sorted = [...events]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });

    final upcoming = [for (final e in sorted) if (!e.end.isBefore(today)) e];
    final past = [for (final e in sorted) if (e.end.isBefore(today)) e];

    return Scaffold(
      appBar: AppBar(title: const Text('校園行事曆')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ..._grouped(context, upcoming, today, dim: false),
          if (past.isNotEmpty)
            Theme(
              // ExpansionTile 預設會在展開時把上下畫一條線，跟月標混在一起
              // 有點雜 —— 拿掉那個 divider。
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.history, size: 20),
                title: Text('已過去的 ${past.length} 筆'),
                childrenPadding: EdgeInsets.zero,
                children: _grouped(context, past, today, dim: true),
              ),
            ),
        ],
      ),
    );
  }

  /// 一串事件按月分組，前面插月標。
  ///
  /// 月份的鍵用 (年, 月)：跨年的行事曆只比月份的話，1 月會跟去年 1 月併在一起。
  List<Widget> _grouped(
    BuildContext context,
    List<CalendarEvent> list,
    DateTime today, {
    required bool dim,
  }) {
    final out = <Widget>[];
    var lastKey = '';
    for (final e in list) {
      final key = '${e.start.year}-${e.start.month}';
      if (key != lastKey) {
        out.add(_MonthHeader(year: e.start.year, month: e.start.month));
        lastKey = key;
      }
      out.add(_EventRow(event: e, past: dim, ongoing: e.covers(today)));
    }
    return out;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        '$year 年 $month 月',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: scheme.primary),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.past,
    required this.ongoing,
  });

  final CalendarEvent event;
  final bool past;
  final bool ongoing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 進行中的用醒目色 —— 一件開始日在上禮拜的事，光看日期會被當成已經過去了。
    final dateColor = ongoing
        ? scheme.primary
        : past
            ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
            : scheme.onSurface;
    final titleColor = past ? scheme.onSurfaceVariant : scheme.onSurface;

    final note = [
      if (!event.isSingleDay) '到 ${event.end.month}/${event.end.day}',
      if (ongoing) '進行中',
    ].join(' · ');

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 44,
        child: Center(
          child: Text(
            '${event.start.month}/${event.start.day}',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: dateColor, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      title: Text(event.title,
          style: theme.textTheme.bodyMedium?.copyWith(color: titleColor)),
      subtitle: note.isEmpty
          ? null
          : Text(note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ongoing ? scheme.primary : scheme.onSurfaceVariant,
              )),
    );
  }
}
