import 'package:flutter/material.dart';

import '../parsing/models.dart';
import '../planner/plan_models.dart';
import '../storage/plan_store.dart';
import '../ui/app_controller.dart';
import 'course_browser_page.dart';
import 'plan_dialogs.dart';
import 'selection_tag.dart';
import 'theme.dart';
import 'timetable_grid.dart';

/// 預排課表頁。
///
/// 不需要登入也能使用 —— 預排是事前規劃，學校系統不提供時段資訊，
/// 所有時段都由使用者自己填入。
class PlannerPage extends StatefulWidget {
  const PlannerPage({
    super.key,
    required this.controller,
    required this.store,
    this.titleWidget,
  });

  final AppController controller;
  final PlanStore store;

  /// 蓋掉 AppBar 的標題 —— 合併分頁之後那裡放的是切換鈕。
  final Widget? titleWidget;

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

  Future<void> _editSlots(PlannedCourse pc) async {
    final result = await showDialog<List<TimeSlot>>(
      context: context,
      builder: (_) => EditSlotsDialog(initial: pc.slots),
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

  /// 開課程瀏覽頁。
  ///
  /// 以前這裡先跳一層 bottom sheet 問「從學校課程選」還是「手動輸入」。
  /// 那層 sheet 逼每個人在「我要找課」之前先回答「你想用哪種方式找課」，
  /// 而九成的答案都一樣 —— 手動輸入是查不到的時候才要的退路，不是入口。
  /// 現在直接進瀏覽頁，手動輸入放在那一頁的 ⋮ 和查詢失敗的畫面上。
  ///
  /// 沒登入也照樣進得去：瀏覽頁自己會顯示「連不上」並在那裡給手動輸入，
  /// 比在這裡攔下來丟一句 SnackBar 有用。
  Future<void> _openBrowser() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourseBrowserPage(
          controller: widget.controller,
          planStore: widget.store,
        ),
      ),
    );
    await _loadPlan();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conflicts = _plan.conflicts();

    return Scaffold(
      appBar: AppBar(
        title: widget.titleWidget ?? const Text('預排課表'),
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
        onPressed: _openBrowser,
        icon: const Icon(Icons.add),
        label: const Text('新增課程'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plan.courses.isEmpty
              ? _EmptyPlanner(onAdd: _openBrowser)
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
                        selection: widget.controller.repository.config
                            .courseSearch
                            .selectionLabel(pc.course.selectionType),
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
            '從學校的開課清單挑，或自己打。加進來會當場檢查衝堂。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: onAdd,
            child: const Text('去挑第一門課'),
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
        borderRadius: BorderRadius.circular(NtouTheme.radiusMd),
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
    this.selection = '',
  });

  final PlannedCourse pc;
  final VoidCallback onEditSlots;
  final VoidCallback onRemove;

  /// 必修 / 選修。認不得的代碼會原樣傳進來（見 `SelectorConfig.selectionLabel`）。
  /// 手動輸入的課沒有這個欄位，就是空字串。
  final String selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final course = pc.course;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Flexible(
            child: Text(course.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (selection.isNotEmpty) ...[
            const SizedBox(width: 8),
            SelectionTag(label: selection),
          ],
        ],
      ),
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
