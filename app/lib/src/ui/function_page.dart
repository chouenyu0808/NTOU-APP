import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../ais/form_schema.dart';
import '../data/function_view.dart';
import '../menu/menu_catalog.dart';
import '../parsing/data_grid.dart';
import 'app_controller.dart';
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
          if (widget.function.mutating) const _MutatingBanner(),
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
          child: _FieldInput(
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
      // 會改資料的頁面（維護新生資料那一類）不是查詢頁 —— 它下面根本不會出現
      // 結果表格。跟使用者說「按上面的按鈕開始查詢」只會讓人以為自己少按了什麼。
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(widget.function.mutating
            ? '這一頁是填寫表單，填好上面的欄位再送出。'
            : '按上面的按鈕開始查詢。'),
      );
    }
    // 「學校說沒資料」和「我們沒解析出表格」必須分開講 ——
    // 前者要說沒資料，後者要說 App 可能需要更新。
    if (r.isEmpty) {
      return const _Notice(
        icon: Icons.inbox_outlined,
        text: '學校系統回覆「查無符合資料」。這是查詢結果，不是錯誤。',
      );
    }
    if (r.columns.isEmpty) {
      return const _Notice(
        icon: Icons.help_outline,
        text: '這一頁的結果不是表格，App 看不懂它的格式。\n'
            '可能是報表或需要另外處理的畫面。',
      );
    }

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
              for (final row in r.rows)
                DataRow(
                  cells: [
                    for (final cell in row)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(cell, overflow: TextOverflow.ellipsis),
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
    if (field.kind == FieldKind.select) {
      if (field.needsCascade) {
        // 0 個選項的下拉。送出去會踩 event validation，所以擋在這裡，
        // 並且說清楚要先動哪一格 —— 不然使用者只會覺得這個欄位壞了。
        return TextField(
          enabled: false,
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
            helperText: '要先選上面的條件，這一格才會有選項',
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

    return TextFormField(
      initialValue: value,
      enabled: enabled,
      maxLength: field.maxLength,
      keyboardType:
          field.kind == FieldKind.number ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      onChanged: onChanged,
    );
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

class _MutatingBanner extends StatelessWidget {
  const _MutatingBanner();

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
      child: Row(
        children: [
          Icon(Icons.edit_note, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '這一頁會真的送出資料，不只是查詢。',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      );
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
