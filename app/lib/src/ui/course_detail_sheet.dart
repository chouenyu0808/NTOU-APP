import 'package:flutter/material.dart';

import '../config/period_times.dart';
import '../parsing/models.dart';
import '../parsing/timetable.dart';

Future<void> showCourseDetail(
  BuildContext context,
  Course course,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(course.name, style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (course.code.isNotEmpty) SelectableText('課號　${course.code}'),
          if (course.teacher.isNotEmpty) SelectableText('教師　${course.teacher}'),
          SelectableText('教室　${course.room.isEmpty ? "尚未提供" : course.room}'),
          if (course.classLabel.isNotEmpty) Text('班別　${course.classLabel}'),
          if (course.credits != null) Text('學分　${course.credits}'),
          const Divider(height: 28),
          if (course.slots.isEmpty) const Text('尚未提供上課時間'),
          for (final slot in (course.slots.toList()..sort()))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '星期${kWeekdays[slot.weekday]}　第 ${slot.period} 節'
                '${_time(slot.period)}',
              ),
            ),
        ],
      ),
    ),
  ),
);

String _time(int period) {
  final time = PeriodTimes.ntou[period];
  return time == null
      ? ''
      : '　${PeriodTimes.hhmm(time.start)}–${PeriodTimes.hhmm(time.end)}';
}
