import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parsing/models.dart';
import '../planner/plan_models.dart';
import '../storage/plan_store.dart';
import '../ui/app_controller.dart';
import 'course_browser_page.dart';
import 'timetable_grid.dart';

/// 預排課表頁。
///
/// 不需要登入也能使用 —— 預排是事前規劃，學校系統不提供時段資訊，
/// 所有時段都由使用者自己填入。
class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, required this.controller, required this.store});

  final AppController controller;
  final PlanStore store;

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  CoursePlan _plan = const CoursePlan(year: '', semester: '', courses: []);
  bool _loading = true;

  // 選好的學年學期
  String _year = '';
  String _semester = '';

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
    _init();
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // 登入後學年學期選項變更時，同步預設值
    if (_year.isEmpty && _c.year != null) {
      setState(() {
        _year = _c.year!;
        _semester = _c.semester ?? '1';
      });
      _loadPlan();
    }
  }

  Future<void> _init() async {
    // 優先用 AppController 已有的學年學期
    _year = _c.year ?? '';
    _semester = _c.semester ?? '1';

    if (_year.isEmpty) {
      // 未登入：用預設值（當前年份、第 1 學期）
      final now = DateTime.now();
      _year = '${now.year - 1911 - 1}'; // 民國年
      _semester = '1';
    }

    await _loadPlan();
  }

  Future<void> _loadPlan() async {
    if (_year.isEmpty) return;
    final saved = await widget.store.read(_year, _semester);
    if (mounted) {
      setState(() {
        _plan = saved ?? CoursePlan(year: _year, semester: _semester);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await widget.store.write(_plan);
  }

  void _updatePlan(CoursePlan plan) {
    setState(() => _plan = plan);
    _save();
  }

  Future<void> _addCourse() async {
    final result = await showDialog<PlannedCourse>(
      context: context,
      builder: (_) => const _AddCourseDialog(),
    );
    if (result != null) _updatePlan(_plan.add(result));
  }

  Future<void> _editSlots(PlannedCourse pc) async {
    final result = await showDialog<List<TimeSlot>>(
      context: context,
      builder: (_) => _EditSlotsDialog(initial: pc.slots),
    );
    if (result != null) {
      _updatePlan(_plan.update(pc.copyWith(slots: result, slotsAreManual: true)));
    }
  }

  void _removeCourse(String key) => _updatePlan(_plan.remove(key));

  Future<void> _changeSemester() async {
    // 簡單的對話框讓使用者選學期
    final years = _c.years.isNotEmpty
        ? _c.years.map((o) => o.value).toList()
        : [_year];
    final semesters = _c.semesters.isNotEmpty
        ? _c.semesters.map((o) => o.value).toList()
        : ['1', '2'];

    String tempYear = _year;
    String tempSem = _semester;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('選擇學期'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: years.contains(tempYear) ? tempYear : years.first,
                decoration: const InputDecoration(labelText: '學年度'),
                items: [for (final y in years) DropdownMenuItem(value: y, child: Text(y))],
                onChanged: (v) => setInner(() => tempYear = v ?? tempYear),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: semesters.contains(tempSem) ? tempSem : semesters.first,
                decoration: const InputDecoration(labelText: '學期'),
                items: [for (final s in semesters) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: (v) => setInner(() => tempSem = v ?? tempSem),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確定')),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        _year = tempYear;
        _semester = tempSem;
        _loading = true;
      });
      await _loadPlan();
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('從學校課程選'),
              subtitle: const Text('用課名或系所搜尋，直接加入'),
              onTap: () {
                Navigator.pop(ctx);
                if (widget.controller.phase != AppPhase.ready) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請先登入才能查詢學校課程')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CourseBrowserPage(
                      controller: widget.controller,
                      planStore: widget.store,
                    ),
                  ),
                ).then((_) => _loadPlan()); // Reload when returning
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('手動輸入'),
              subtitle: const Text('自己打課名和時段'),
              onTap: () {
                Navigator.pop(ctx);
                _addCourse();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conflicts = _plan.conflicts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('預排課表'),
        actions: [
          TextButton.icon(
            onPressed: _changeSemester,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(
              _year.isEmpty ? '選學期' : '$_year-$_semester',
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptions,
        icon: const Icon(Icons.add),
        label: const Text('新增課程'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plan.courses.isEmpty
              ? _EmptyPlanner(onAdd: _addCourse)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    // 衝堂警告
                    if (conflicts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final c in conflicts)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          child: _ConflictBanner(conflict: c),
                        ),
                    ],

                    // 課表格子
                    const SizedBox(height: 8),
                    TimetableGrid(courses: _plan.asCourses()),

                    // 統計
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          _Stat(_plan.courses.length.toString(), '門課'),
                          const SizedBox(width: 20),
                          _Stat(_plan.totalCredits.toStringAsFixed(1), '學分'),
                          if (_plan.missingSlotCount > 0) ...[
                            const SizedBox(width: 20),
                            _Stat(
                              _plan.missingSlotCount.toString(),
                              '堂未填時段',
                              color: scheme.error,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const Divider(height: 24),

                    // 課程清單
                    for (final pc in _plan.courses)
                      _CourseItem(
                        pc: pc,
                        onEditSlots: () => _editSlots(pc),
                        onRemove: () => _removeCourse(pc.key),
                      ),
                  ],
                ),
    );
  }
}

// ─── 空白提示 ────────────────────────────────────────────────────────────────

class _EmptyPlanner extends StatelessWidget {
  const _EmptyPlanner({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_note_outlined, size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 16),
          Text('還沒有預排的課程', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '點下方按鈕新增課程，確認時間不衝突',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: onAdd,
            child: const Text('新增第一門課'),
          ),
        ],
      ),
    );
  }
}

// ─── 衝堂 Banner ─────────────────────────────────────────────────────────────

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.conflict});
  final Conflict conflict;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '⚠ 衝堂：${conflict.describe()}',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 統計數字 ─────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: c, fontWeight: FontWeight.w700)),
        const SizedBox(width: 3),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c)),
      ],
    );
  }
}

// ─── 課程 ListTile ────────────────────────────────────────────────────────────

class _CourseItem extends StatelessWidget {
  const _CourseItem({
    required this.pc,
    required this.onEditSlots,
    required this.onRemove,
  });

  final PlannedCourse pc;
  final VoidCallback onEditSlots;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final course = pc.course;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(course.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (course.teacher.isNotEmpty || course.credits != null)
            Text(
              [
                if (course.teacher.isNotEmpty) course.teacher,
                if (course.credits != null) '${course.credits} 學分',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
          // 時段 Chips
          if (pc.slots.isEmpty)
            GestureDetector(
              onTap: onEditSlots,
              child: Chip(
                label: const Text('點此填入上課時間'),
                avatar: Icon(Icons.schedule, size: 16, color: scheme.error),
                backgroundColor: scheme.errorContainer,
                labelStyle: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                padding: EdgeInsets.zero,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in pc.slots)
                  Chip(
                    label: Text(s.toString(), style: const TextStyle(fontSize: 12)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('編輯', style: TextStyle(fontSize: 12)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onEditSlots,
                ),
              ],
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '從預排移除',
        onPressed: onRemove,
      ),
    );
  }
}

// ─── 新增課程 Dialog ──────────────────────────────────────────────────────────

class _AddCourseDialog extends StatefulWidget {
  const _AddCourseDialog();

  @override
  State<_AddCourseDialog> createState() => _AddCourseDialogState();
}

class _AddCourseDialogState extends State<_AddCourseDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _teacher = TextEditingController();
  final _credits = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final Set<TimeSlot> _slots = {};

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _teacher.dispose();
    _credits.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final course = Course(
      name: _name.text.trim(),
      code: _code.text.trim(),
      teacher: _teacher.text.trim(),
      credits: double.tryParse(_credits.text.trim()),
    );
    Navigator.pop(
      context,
      PlannedCourse(
        course: course,
        slots: _slots.toList()..sort(),
        slotsAreManual: _slots.isNotEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增課程'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '課名 *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '請輸入課名' : null,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _code,
              decoration: const InputDecoration(labelText: '課號（選填）'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _teacher,
              decoration: const InputDecoration(labelText: '老師（選填）'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _credits,
              decoration: const InputDecoration(labelText: '學分數（選填）'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            ),
            const SizedBox(height: 16),
            Text('上課時段', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _SlotPicker(
              selected: _slots,
              onChanged: (s) => setState(() {
                if (_slots.contains(s)) {
                  _slots.remove(s);
                } else {
                  _slots.add(s);
                }
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('新增')),
      ],
    );
  }
}

// ─── 編輯時段 Dialog ──────────────────────────────────────────────────────────

class _EditSlotsDialog extends StatefulWidget {
  const _EditSlotsDialog({required this.initial});
  final List<TimeSlot> initial;

  @override
  State<_EditSlotsDialog> createState() => _EditSlotsDialogState();
}

class _EditSlotsDialogState extends State<_EditSlotsDialog> {
  late final Set<TimeSlot> _slots;

  @override
  void initState() {
    super.initState();
    _slots = Set.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯上課時段'),
      scrollable: true,
      content: _SlotPicker(
        selected: _slots,
        onChanged: (s) => setState(() {
          if (_slots.contains(s)) {
            _slots.remove(s);
          } else {
            _slots.add(s);
          }
        }),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _slots.toList()..sort()),
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

// ─── 時段格子選擇器 ───────────────────────────────────────────────────────────

/// 星期 × 節次的格子，點一下選/取消。
class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.selected, required this.onChanged});

  final Set<TimeSlot> selected;
  final ValueChanged<TimeSlot> onChanged;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  // 節次：0（早自習）到 13（第 13 節）
  static const _periods = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 只顯示週一到週五；週六日少見，用橫向捲動
    const days = 5; // 預設只顯示一到五

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        children: [
          // 表頭
          Row(
            children: [
              _cell('節', null, scheme, isHeader: true),
              for (var d = 0; d < days; d++)
                _cell(_weekdays[d], null, scheme, isHeader: true),
            ],
          ),
          // 各節
          for (final p in _periods)
            Row(
              children: [
                _cell('$p', null, scheme, isHeader: true),
                for (var d = 0; d < days; d++)
                  _cell(
                    '',
                    TimeSlot(d, p),
                    scheme,
                    onTap: onChanged,
                    isSelected: selected.contains(TimeSlot(d, p)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(
    String label,
    TimeSlot? slot,
    ColorScheme scheme, {
    bool isHeader = false,
    bool isSelected = false,
    ValueChanged<TimeSlot>? onTap,
  }) {
    const size = 40.0;
    final bg = isSelected
        ? scheme.primaryContainer
        : isHeader
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer;
    final fg = isSelected ? scheme.onPrimaryContainer : scheme.onSurface;

    return GestureDetector(
      onTap: slot != null && onTap != null ? () => onTap(slot) : null,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: label.isNotEmpty
            ? Text(label, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500))
            : isSelected
                ? Icon(Icons.check, size: 16, color: fg)
                : null,
      ),
    );
  }
}
