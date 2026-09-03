import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../ais/form_schema.dart';
import '../data/function_view.dart';
import '../menu/menu_catalog.dart';
import '../parsing/data_grid.dart';
import '../parsing/timetable.dart';
import 'app_controller.dart';
import 'schema_field_input.dart';
import 'theme.dart';

/// 通用的功能頁。
///
/// **這一頁沒有為任何特定功能寫過一行程式碼。** 表單欄位、中文標籤、下拉選項、
/// 按鈕文字，全部是從學校那一頁自己的宣告讀出來的
/// （`CNAME` / `ml` / `<option>`），結果表格也是照學校給的欄名和欄序畫。
///
/// 所以學校加一個欄位、改一個標籤、多一顆按鈕，App 自動就跟上，不用改版。
/// 代價是畫面比不上手工雕的 —— 值得為特定功能做專屬畫面時再另外做（課表就是）。
class FunctionPage extends StatefulWidget {
  const FunctionPage({
    super.key,
    required this.controller,
    required this.function,
  });

  final AppController controller;
  final AisFunction function;

  @override
  State<FunctionPage> createState() => _FunctionPageState();
}

class _FunctionPageState extends State<FunctionPage> {
  FunctionView? _view;
  String? _error;
  bool _busy = true;

  /// 目前選到的標籤頁。分頁式的頁面（課程課表查詢有六組）一次只顯示一組 ——
  /// 全部攤平的話畫面上會有六顆都叫「查詢」的按鈕。
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.openFunction(widget.function);
    });
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on AisException catch (e) {
      _error = e.message;
    } catch (e) {
      // 只說類型不說內容 —— 這條路徑上可能有頁面碎片
      _error = '發生未預期的錯誤（${e.runtimeType}）。';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setField(String name, String value) async {
    final view = _view;
    if (view == null) return;

    // 連動欄位改了要重送整張表單，伺服器才會把下游的下拉填好。
    if (view.needsCascade(name)) {
      setState(() {
        _busy = true;
        // 舊的錯誤要清掉，不然上一次連動失敗的紅框會一直蓋在後來成功的結果上面
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

  Future<void> _run(String button, {int? pageNo}) async {
    final view = _view;
    if (view == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final group = _groupOf(view);
    await _guard(() async {
      _view = await widget.controller.repository.runQuery(
        view,
        button,
        pageNo: pageNo,
        tabIndex: view.schema.isTabbed ? group.index : null,
      );
    });
  }

  /// 按下一列上的鈕。
  ///
  /// 會改資料的（加選 / 退選）**一定要先問**。學校的網頁版按下去就直接送了，
  /// 但那是在滑鼠和大螢幕上；手機上一根手指滑過整排「加選」，誤觸的代價是
  /// 一門他沒想選的課，而選課期間結束之後就退不掉了。
  Future<void> _runAction(RowAction action) async {
    final view = _view;
    if (view == null) return;

    // 「詳」的內容**每一列自己就帶著**（`KEY` 屬性）—— 不用送 postback。
    //
    // 送出去反而是壞的：學校那顆回的不是表格，而是同一頁再注入一行
    // `fn_open(...)`，我們把它當成查詢結果去解析就是一片空白 ——
    // 使用者按下去什麼都沒發生。
    if (!action.mutating && action.data.isNotEmpty) {
      await _showRowDetail(action);
      return;
    }

    if (action.mutating && !await _confirmAction(action)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.runRowAction(view, action.target);
    });
  }

  /// 「詳」：把這一列 `KEY` 裡的東西攤開給使用者看。
  Future<void> _showRowDetail(RowAction action) async {
    // 學校的欄位代碼 → 人看得懂的名字。認不出來的就不顯示 ——
    // 把 `IS_MAST_DOCTOR_MERGE` 之類的內部旗標倒給使用者只是雜訊。
    const labels = <String, String>{
      'CH_LESSON': '課名',
      'ENG_LESSON': '英文課名',
      'COSID': '課號',
      'OPEN_CLASSID': '開課班別',
      'CRD': '學分',
      'LECTR_TCH_CH': '授課老師',
      'FACULTY_NAME': '開課單位',
      'MAX_ST': '人數上限',
      'GRADE': '年級',
    };

    final rows = <(String, String)>[
      for (final e in labels.entries)
        if ((action.data[e.key] ?? '').isNotEmpty) (e.value, action.data[e.key]!),
    ];
    final seg = action.data['SEG'] ?? '';
    final slots = parseTimeCodes(seg);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action.courseName,
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (slots.isNotEmpty)
                _DetailRow(
                  label: '上課時間',
                  value: slots.map((s) => s.toString()).join('、'),
                ),
              for (final (label, value) in rows)
                if (label != '課名') _DetailRow(label: label, value: value),
              if (action.notice.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(action.notice,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmAction(RowAction action) async {
    final name = action.courseName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name.isEmpty ? action.label : '${action.label}「$name」'),
        // 加選須知要在按之前看到。「須於實習前至系辦完成實習申請流程」
        // 這種話，事後才看到就太晚了。沒有須知的話就不放內文 ——
        // 標題已經說了要做什麼，再補一句只是廢話。
        content: action.notice.isEmpty ? null : Text(action.notice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  SchemaGroup _groupOf(FunctionView view) {
    final groups = view.schema.groups;
    if (groups.isEmpty) {
      return const SchemaGroup(label: '', index: 0, fields: [], buttons: []);
    }
    return groups[_tab.clamp(0, groups.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      appBar: AppBar(
        title: Text(view?.title ?? widget.function.title),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (_error != null) _ErrorBanner(_error!, onRetry: _open),
          if (view != null) ...[
            ..._buildForm(view),
            const Divider(height: 32),
            _buildResult(view),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildForm(FunctionView view) {
    final group = _groupOf(view);
    final fields = group.visibleFields;
    final buttons = group.queryButtons;

    return [
      if (view.schema.isTabbed)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              for (var i = 0; i < view.schema.groups.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(view.schema.groups[i].label),
                    selected: _tab == i,
                    onSelected: _busy ? null : (_) => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
      if (fields.isEmpty && !_busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('這一頁沒有查詢條件，直接看下面的結果。'),
        ),
      for (final f in fields)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SchemaFieldInput(
            field: f,
            value: view.values[f.name] ?? f.value,
            enabled: !_busy,
            onChanged: (v) => _setField(f.name, v),
          ),
        ),
      if (buttons.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in buttons)
                FilledButton(
                  onPressed: _busy ? null : () => _run(b.name),
                  child: Text(b.label),
                ),
            ],
          ),
        ),

    ];
  }

  Widget _buildResult(FunctionView view) {
    final r = view.result;
    if (r == null) {
      // 一顆按得下去的按鈕都沒有（只有列印的那幾頁）——
      // 不要叫使用者去按一顆不存在的鈕。
      if (_groupOf(view).queryButtons.isEmpty) return const SizedBox.shrink();

      // 會改資料的頁面（維護新生資料那一類）不是查詢頁 —— 它下面根本不會出現
      // 結果表格。跟使用者說「按上面的按鈕開始查詢」只會讓人以為自己少按了什麼。
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(widget.function.mutating
            ? '這一頁是填寫表單，填好上面的欄位再送出。'
            : '按上面的按鈕開始查詢。'),
      );
    }
    if (r.isEmpty || r.columns.isEmpty) return const SizedBox.shrink();

    // 一頁可能有不只一張表（線上加退選：上面是可加選的課，下面是已選上的、
    // 帶著退選鈕的那張）。少畫一張等於整個退選功能不存在。
    if (view.extraResults.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grid(r),
          for (final extra in view.extraResults)
            if (extra.columns.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _grid(extra),
            ],
        ],
      );
    }
    return _grid(r);
  }

  Widget _grid(DataGridResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '${r.rowCount} 筆'
            '${r.paging.hasMore ? '（第 ${r.paging.pageNo} / ${r.paging.lastPage} 頁）' : ''}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        // 橫向捲動：學校的表格動輒 17 欄，手機螢幕塞不下
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 64,
            columns: [for (final c in r.columns) DataColumn(label: Text(c))],
            rows: [
              // 用列索引跑，不是 for-in —— 動作是靠 (列, 欄) 對回去的，
              // 拿列的內容去反查會在兩列一模一樣時對到錯的那一列。
              for (var i = 0; i < r.rows.length; i++)
                DataRow(
                  cells: [
                    for (var col = 0; col < r.rows[i].length; col++)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          // 這一格可以按（加選 / 退選 / 詳）就畫成鈕。畫成純文字的話
                          // 使用者會一直戳它 —— 學校的畫面上那本來就是連結。
                          child: switch (r.actionAt(i, col)) {
                            final a? => _ActionButton(
                                action: a,
                                onTap: _busy ? null : () => _runAction(a),
                              ),
                            _ => Text(r.rows[i][col],
                                overflow: TextOverflow.ellipsis),
                          },
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (r.paging.hasMore) _Pager(paging: r.paging, onGo: _goPage),
      ],
    );
  }

  void _goPage(int pageNo) {
    final view = _view;
    if (view == null) return;
    // 翻頁要重按**當初那一組**的查詢鈕 —— 用別組的會查成別的東西
    final buttons = _groupOf(view).queryButtons;
    if (buttons.isEmpty) return;
    _run(buttons.first.name, pageNo: pageNo);
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.paging, required this.onGo});

  final GridPaging paging;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: paging.pageNo > 1 ? () => onGo(paging.pageNo - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${paging.pageNo} / ${paging.lastPage}'),
            IconButton(
              onPressed: paging.hasMore ? () => onGo(paging.pageNo + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
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
        borderRadius: BorderRadius.circular(NtouTheme.radiusSm),
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

/// 選單上的一個功能項目。
///
/// 會改資料的功能在點進去之前會先問一句 —— **不是擋**，是不要讓人在選課期間
/// 手滑點進「線上加退選」。
class FunctionTile extends StatelessWidget {
  const FunctionTile({
    super.key,
    required this.controller,
    required this.function,
    this.color,
    this.subtitleOverride,
  });

  final AppController controller;
  final AisFunction function;
  final Color? color;

  /// 蓋掉預設的副標。搜尋結果用它放「模組 › 群組」的麵包屑 ——
  /// 50 個功能裡有好幾組名字很像的，只給名稱分不出來是哪一個。
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (function.mutating ? scheme.error : tint)
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(NtouTheme.radiusMd),
        ),
        child: Icon(
          function.mutating ? Icons.edit_note : Icons.description_outlined,
          size: 19,
          color: function.mutating ? scheme.error : tint,
        ),
      ),
      title: Text(function.title),
      subtitle: function.mutating
          ? Text(
              subtitleOverride == null
                  ? '會送出資料'
                  : '$subtitleOverride　·　會送出資料',
              style: TextStyle(color: scheme.error, fontSize: 12),
            )
          : (subtitleOverride == null
              ? null
              : Text(subtitleOverride!,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant))),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (controller.phase != AppPhase.ready) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請先登入')));
      return;
    }

    if (function.mutating) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_outlined,
              color: Theme.of(ctx).colorScheme.error),
          title: Text(function.title),
          content: Text(function.mutationWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('我知道，繼續'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FunctionPage(controller: controller, function: function),
      ),
    );
  }
}


/// 結果表格裡一列上的鈕。
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, this.onTap});

  final RowAction action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 學校自己就說這門不能加 —— 畫成暗的，但**留在畫面上**。
    // 整顆拿掉的話那一列會少一格，使用者會以為是 App 沒畫出來。
    final blocked = action.mutating && action.blocked;
    return TextButton(
      onPressed: blocked ? null : onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(action.label),
    );
  }
}


/// 「詳」面板上的一行。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
