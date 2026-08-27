import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parsing/models.dart';
import '../planner/plan_models.dart';
import 'theme.dart';

/// 預排會用到的三個對話框：新增一門課、編輯時段、時段格子。
///
/// 從 planner_page.dart 抽出來，是因為課程瀏覽頁也要用 —— 「手動輸入」
/// 現在放在瀏覽頁裡，可是瀏覽頁不能反過來 import 預排頁（預排頁已經
/// import 它了）。放在兩邊都能拿的地方才不用繞。

// ─── 新增課程 Dialog ──────────────────────────────────────────────────────────

class AddCourseDialog extends StatefulWidget {
  const AddCourseDialog({super.key});

  @override
  State<AddCourseDialog> createState() => AddCourseDialogState();
}

class AddCourseDialogState extends State<AddCourseDialog> {
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

class EditSlotsDialog extends StatefulWidget {
  const EditSlotsDialog({super.key, required this.initial});
  final List<TimeSlot> initial;

  @override
  State<EditSlotsDialog> createState() => EditSlotsDialogState();
}

class EditSlotsDialogState extends State<EditSlotsDialog> {
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
///
/// 平常只畫「一～五 × 第 1–13 節」。第 0 節、第 14–16 節和週六日，學校的下拉
/// **選得出來**（`Q_CLASS` 是 `00`–`16`、`Q_WEEK` 是 1–7），但絕大多數課排不到
/// 那裡 —— 全部攤開的話手機上每一格會細到點不準。
///
/// **有時段真的落在那些格子時才展開。** 這在手動填的時候不會發生（使用者只填得到
/// 畫得出來的格子），是「從學校課程自動帶入」之後才會的：parser 收得下 1–7 ×
/// 00–16，畫不出來的話使用者看到的是「加進來了但格子是空的」，而且那一節點不掉。
class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.selected, required this.onChanged});

  final Set<TimeSlot> selected;
  final ValueChanged<TimeSlot> onChanged;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 預設只畫到週五，第 1–13 節。
  ///
  /// 第 0 節（早自習）刻意收起來：學校的 `Q_CLASS` 有 `00`，但實際上幾乎沒課
  /// 排在那裡，白留一列只是讓每一格更細。
  static const int _defaultDays = 5;
  static const int _defaultFirstPeriod = 1;
  static const int _defaultLastPeriod = 13;

  /// 學校那邊的上限：`Q_WEEK` 到 7、`Q_CLASS` 到 16。
  static const int _maxDays = 7;
  static const int _maxPeriod = 16;

  /// 要畫幾天 —— 有時段落在六日就展開到那一天。
  int get _days {
    var n = _defaultDays;
    for (final s in selected) {
      if (s.weekday >= n) n = s.weekday + 1;
    }
    return n.clamp(_defaultDays, _maxDays);
  }

  /// 要畫哪幾節 —— 往兩端各自展開到真的有時段的那一節。
  List<int> get _periods {
    var first = _defaultFirstPeriod;
    var last = _defaultLastPeriod;
    for (final s in selected) {
      if (s.period < first) first = s.period;
      if (s.period > last) last = s.period;
    }
    first = first.clamp(0, _defaultFirstPeriod);
    last = last.clamp(_defaultLastPeriod, _maxPeriod);
    return [for (var p = first; p <= last; p++) p];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final days = _days;

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
    // 44 是可以穩定點中的最小尺寸。40 加上 1.5 的邊距，實際可點區域更小 ——
    // 這是一個 5×14 的密集格子，點錯一格就是排錯一節課。
    const size = 44.0;
    final bg = isSelected
        ? scheme.primaryContainer
        : isHeader
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer;
    final fg = isSelected ? scheme.onPrimaryContainer : scheme.onSurface;

    final cell = GestureDetector(
      onTap: slot != null && onTap != null ? () => onTap(slot) : null,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(NtouTheme.radiusXs),
        ),
        alignment: Alignment.center,
        child: label.isNotEmpty
            ? Text(label, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500))
            : isSelected
                ? Icon(Icons.check, size: 16, color: fg)
                : null,
      ),
    );

    if (slot == null) return cell;

    // 空格子只有底色，螢幕閱讀器讀不出任何東西 —— 使用者聽到的是一片沉默，
    // 完全不知道游標停在哪一格。
    return Semantics(
      label: '星期${_weekdays[slot.weekday.clamp(0, 6)]}第 ${slot.period} 節',
      selected: isSelected,
      button: true,
      child: cell,
    );
  }
}
