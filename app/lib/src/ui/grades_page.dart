import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../parsing/grades.dart';
import 'app_controller.dart';

/// 「查詢各式成績」（`GRD5010`）。
///
/// **這一頁大部分時候沒有分數可以看。** 學期剛開始時每一門都是「成績未到」，
/// 轉學生整份是「抵免」。畫面要把那件事講成一句話，不然使用者看到一整排
/// 沒有數字的課，只會覺得 App 沒抓到資料。
class GradesPage extends StatefulWidget {
  const GradesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  GradeReport? _report;
  String? _error;
  String? _notice;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _report = null;
    });
    try {
      _report = await widget.controller.repository.openGrades();
    } on AisMessage catch (e) {
      // 學校說現在不開放 —— 那不是錯誤，別配紅色圖示和重試鈕。
      _notice = e.message;
    } on AisException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '發生未預期的錯誤（${e.runtimeType}）。';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('成績'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '重新整理',
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_notice != null) return _message(context, _notice!, Icons.info_outline);
    if (_error != null) {
      return _message(context, _error!, Icons.error_outline, retry: true);
    }

    final r = _report;
    if (r == null || r.isEmpty) {
      return _message(
        context,
        '這裡還沒有任何成績紀錄。',
        Icons.inbox_outlined,
        retry: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _StatusLine(report: r),
        if (r.totals.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TotalsCard(totals: r.totals),
        ],
        for (final term in r.terms) ...[
          const SizedBox(height: 20),
          _TermSection(term: term, courses: r.inTerm(term)),
        ],
      ],
    );
  }

  Widget _message(BuildContext context, String text, IconData icon,
      {bool retry = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _load, child: const Text('重試')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 最上面那一句：**現在到底有沒有分數可以看**。
///
/// 沒有這一句的話，一整排沒有數字的課看起來就像 App 壞了。
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.report});

  final GradeReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scored = report.courses.where((c) => c.mark.score != null).length;
    final pending = report.courses.where((c) => c.mark.isPending).length;
    final transferred =
        report.courses.where((c) => c.mark.isTransferred).length;

    final parts = <String>[
      if (scored > 0) '$scored 門有成績',
      if (pending > 0) '$pending 門還沒登記',
      if (transferred > 0) '$transferred 門抵免',
    ];

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.assignment_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                parts.isEmpty ? '共 ${report.courses.length} 門' : parts.join('、'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 上面那排統計。**只有學校真的填了的才會到這裡**（見 `parseGrades`）。
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final Map<String, String> totals;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in entries) ...[
              Row(
                children: [
                  Expanded(child: Text(e.key)),
                  Text(e.value,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              if (e != entries.last) const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _TermSection extends StatelessWidget {
  const _TermSection({required this.term, required this.courses});

  final String term;
  final List<CourseGrade> courses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  termLabel(term),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              Text(
                '${courses.length} 門',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final c in courses) _CourseTile(course: c),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

/// `1151` -> `115 學年 上學期`。格式是「學年 3 碼 + 學期 1 碼」。
///
/// **不要順手把民國年轉成西元。** 學校整套系統、課表、行事曆講的都是民國年，
/// 只有這一頁轉的話，使用者要自己換算回去才能跟其他頁面對得起來。
///
/// 認不得的學期碼**照原樣顯示**，不要猜 —— 編一個「下學期」出來，
/// 畫面上看起來完全正常，但那是假的。
String termLabel(String term) {
  if (term.length != 4) return term; // 認不得就照原樣，不要猜
  final year = term.substring(0, 3);
  final sms = term.substring(3);
  final name = switch (sms) {
    '1' => '上學期',
    '2' => '下學期',
    '3' => '暑修',
    _ => null,
  };
  return name == null ? term : '$year 學年 $name';
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});

  final CourseGrade course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = course;
    final sub = [
      if (c.kind.isNotEmpty) c.kind,
      // **0 學分不寫「0 學分」。** 體育就是 0 —— 那種課是「要通過」不是
      // 「拿學分」，寫成 0 學分看起來像不重要的東西。
      if (c.credits != null && c.credits != 0) '${c.credits} 學分',
      if (c.teacher.isNotEmpty) c.teacher,
    ].join('・');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _MarkChip(mark: c.mark),
        ],
      ),
    );
  }
}

/// 成績那一格。
///
/// **記號要用字講出來。** 學校在那一欄寫的是 `+`、`抵`、`*` —— 照搬的話
/// 畫面上是一個沒有任何說明的符號，使用者不知道那是「還沒登記」還是「零分」。
class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.mark});

  final GradeMark mark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 有分數就以分數為主角，記號（不及格）退成旁邊那行小字。
    if (mark.score != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            mark.score!,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: mark.isFailed ? scheme.error : null,
            ),
          ),
          if (mark.note != null)
            Text(
              mark.note!,
              style: TextStyle(fontSize: 11, color: scheme.error),
            ),
        ],
      );
    }

    // 沒有分數：認得的記號講人話，認不得的照原樣顯示（**不要自己編說法**）。
    final text = mark.note ?? mark.raw;
    if (text.isEmpty) return const SizedBox.shrink();

    final color = mark.isTransferred
        ? scheme.tertiary
        : mark.isWithdrawn
            ? scheme.outline
            : scheme.onSurfaceVariant;

    return Text(text, style: TextStyle(fontSize: 12, color: color));
  }
}
