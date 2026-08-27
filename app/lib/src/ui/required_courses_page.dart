import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../ais/form_schema.dart';
import '../data/function_view.dart';
import '../parsing/required_courses.dart';
import 'app_controller.dart';

/// 畢業必修 —— 你這個系四年要修哪些課、門檻是多少。
///
/// 查詢條件（入學年度、部別、系所、入學身分）**沒有寫死在這裡**，
/// 是從學校那一頁自己的宣告讀出來的，跟通用功能頁同一套。
/// 學校加一個條件，這裡自動就多一個下拉。
class RequiredCoursesPage extends StatefulWidget {
  const RequiredCoursesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RequiredCoursesPage> createState() => _RequiredCoursesPageState();
}

class _RequiredCoursesPageState extends State<RequiredCoursesPage> {
  FunctionView? _view;
  RequiredCourses? _result;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.openRequiredCourses();
    });
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on AisException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '發生未預期的錯誤（${e.runtimeType}）。';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setField(String name, String value) async {
    final view = _view;
    if (view == null) return;

    // 部別是連動欄位：改了要重送整張表單，伺服器才會把系所的選項換掉。
    if (view.needsCascade(name)) {
      setState(() {
        _busy = true;
        _error = null;
      });
      await _guard(() async {
        _view = await widget.controller.repository.cascade(view, name, value);
      });
      return;
    }
    setState(() {
      _view = view.copyWith(values: {...view.values, name: value});
    });
  }

  Future<void> _query() async {
    final view = _view;
    if (view == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.runQuery(view, 'QUERY_BTN1');
      _result = parseRequiredCourses(_view!.page.html);
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      appBar: AppBar(
        title: const Text('畢業必修'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: view == null && _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (_error != null) _ErrorBanner(_error!, onRetry: _open),
                if (view != null) ...[
                  ..._buildForm(view),
                  const Divider(height: 32),
                  ..._buildResult(),
                ],
              ],
            ),
    );
  }

  List<Widget> _buildForm(FunctionView view) => [
        for (final f in view.schema.visibleFields)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _FieldInput(
              field: f,
              value: view.values[f.name] ?? f.value,
              enabled: !_busy,
              onChanged: (v) => _setField(f.name, v),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: FilledButton(
            onPressed: _busy ? null : _query,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('查詢'),
          ),
        ),
      ];

  List<Widget> _buildResult() {
    final r = _result;
    if (r == null) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('選好條件後按查詢。入學年度和系所要跟你自己的一致，'
              '不然看到的會是別人的必修表。'),
        ),
      ];
    }
    if (r.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('這組條件查不到必修科目表。確認一下入學年度、系所和入學身分。'),
        ),
      ];
    }

    return [
      _Thresholds(r),
      for (var term = 0; term < 10; term++)
        ..._termSection(r, term),
      ..._unscheduledSection(r),
      if (r.notes.isNotEmpty) _Notes(r.notes),
    ];
  }

  /// 某一個學期要修的課。一門課跨兩個學期（微積分上下各 3 學分）
  /// 會在兩個學期都出現 —— 那是對的，兩學期都要修。
  List<Widget> _termSection(RequiredCourses r, int term) {
    final courses =
        r.courses.where((c) => c.byTerm.containsKey(term)).toList();
    if (courses.isEmpty) return const [];
    return [
      _SectionHeader('${termLabel(term)}　${_creditSummary(courses, term)}'),
      for (final c in courses) _CourseRow(course: c, term: term),
    ];
  }

  /// 沒有標建議學期的（畢業門檻那種）。**不要塞進某個學期** ——
  /// 那會讓人以為那學期非修不可。
  List<Widget> _unscheduledSection(RequiredCourses r) {
    final rest = r.courses.where((c) => c.byTerm.isEmpty).toList();
    if (rest.isEmpty) return const [];
    return [
      const _SectionHeader('沒有指定學期'),
      for (final c in rest) _CourseRow(course: c, term: null),
    ];
  }

  static String _creditSummary(List<RequiredCourse> courses, int term) {
    var total = 0.0;
    for (final c in courses) {
      // 那一格寫的才是這學期的學分，不是整門課的總學分
      // （微積分 6 學分是上下加起來的，一上只有 3）。
      final cell = c.byTerm[term] ?? '';
      for (final part in cell.split(RegExp(r'[,、]'))) {
        total += double.tryParse(part.trim()) ?? 0;
      }
    }
    return '共 ${_fmt(total)} 學分';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Thresholds extends StatelessWidget {
  const _Thresholds(this.r);

  final RequiredCourses r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, double? value, {bool strong = false}) => Expanded(
          child: Column(
            children: [
              Text(
                value == null
                    ? '—'
                    : _RequiredCoursesPageState._fmt(value),
                style: (strong
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.titleLarge)
                    ?.copyWith(
                  color: strong ? theme.colorScheme.primary : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            cell('必修', r.requiredCredits),
            cell('選修最低', r.electiveMinimum),
            cell('畢業最低', r.graduationMinimum, strong: true),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.term});

  final RequiredCourse course;
  final int? term;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cell = term == null ? '' : (course.byTerm[term] ?? '');

    return ListTile(
      dense: true,
      leading: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          cell.isEmpty ? '—' : cell,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
      title: Text(course.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              course.category,
              if (course.codes.isNotEmpty) course.codes.join('、'),
              // 沒有課號的是「這個領域修滿學分即可」，不是指定某一門課 ——
              // 這件事一定要講，不然使用者會去找一門叫「11-博雅課程」的課。
              if (course.codes.isEmpty) '修滿學分即可，不限課號',
            ].join('　'),
            style: theme.textTheme.bodySmall,
          ),
          if (course.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                course.note,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
      isThreeLine: course.note.isNotEmpty,
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes(this.notes);

  final List<String> notes;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('說明', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // 照原文顯示 —— 這些是規則，摘要或改寫都可能失真。
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(n, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      );
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({
    required this.field,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final SchemaField field;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.kind != FieldKind.select || field.needsCascade) {
      return TextField(
        enabled: false,
        decoration: InputDecoration(
          labelText: field.label,
          border: const OutlineInputBorder(),
          helperText: field.needsCascade ? '要先選上面的條件' : null,
        ),
      );
    }
    final values = field.options.map((o) => o.value).toList();
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : values.firstOrNull,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final o in field.options)
          DropdownMenuItem(
            value: o.value,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? (v) => onChanged(v ?? '') : null,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message, {required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('重試')),
        ],
      ),
    );
  }
}
