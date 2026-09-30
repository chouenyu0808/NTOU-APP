import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../ais/form_schema.dart';
import '../data/function_view.dart';
import '../menu/menu_catalog.dart';
import '../parsing/data_grid.dart';
import '../parsing/timetable.dart';
import 'app_controller.dart';
import 'grades_page.dart';
import 'graduation_page.dart';
import 'required_courses_page.dart';
import 'schema_field_input.dart';
import 'theme.dart';
import 'login_page.dart';
import 'school_web_handoff.dart';
import '../storage/recent_functions.dart';

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

  /// 這一組條件裡要附檔案的欄位。
  ///
  /// 學校那幾頁（學生請假上傳補件、上傳兵役相關附件）是 `<input type="file">`，
  /// 而 App 送不出檔案 —— `AisRepository._sendable` 會把這種欄位整個跳過。
  /// 送出鈕照樣按得下去，學校那邊也照樣收下，只是**收到的是一張沒有附件的申請**。
  List<SchemaField> _fileFieldsOf(SchemaGroup group) =>
      group.fields.where((f) => f.kind == FieldKind.file).toList();

  /// 按下表單上的送出鈕。
  ///
  /// 這一頁要附檔案的話**一定要先問**：送出去是不可逆的（申請已經進去了），
  /// 而少了附件這件事在學校的回應裡不會提到一個字 —— 使用者按完看到的是
  /// 「已送出」，要等到被退件才知道。
  Future<void> _submit(SchemaButton button) async {
    final view = _view;
    if (view == null) return;

    final files = _fileFieldsOf(_groupOf(view));
    if (files.isNotEmpty && !await _confirmWithoutAttachment(files)) return;

    await _run(button.name);
  }

  Future<bool> _confirmWithoutAttachment(List<SchemaField> files) async {
    // 欄位名是學校自己標的（`CNAME`），直接引用 —— 使用者在畫面上看到的
    // 就是這幾個字，說「檔案」會讓人不確定是指哪一格。
    final names =
        files.map((f) => f.label).where((l) => l.isNotEmpty).join('、');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_outlined,
            color: Theme.of(ctx).colorScheme.error),
        title: const Text('這樣送出不會附上檔案'),
        content: Text(
          names.isEmpty
              ? '這一頁要附上檔案，但 App 沒辦法傳檔。現在送出的話，學校收到的是一份沒有附件的申請。'
              : '這一頁要附上「$names」，但 App 沒辦法傳檔。現在送出的話，學校收到的是一份沒有附件的申請。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍要送出'),
          ),
        ],
      ),
    );
    return ok ?? false;
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
    final fileFields = _fileFieldsOf(group);

    return [
      if (fileFields.isNotEmpty) ...[
        _attachmentWarning(fileFields),
        SchoolWebHandoff(controller: widget.controller, functionTitle: widget.function.title),
      ],
      if (group.buttons.any((b) => b.isPrint))
        SchoolWebHandoff(controller: widget.controller, functionTitle: widget.function.title),
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
      // 學校說了話就照著講。**這一段要蓋掉下面那句「直接看下面的結果」** ——
      // 這種頁面是被踢回首頁的，下面什麼都沒有，叫使用者往下看只會讓他
      // 對著一片空白找不存在的東西。
      if (view.notice != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 20,
                      color:
                          Theme.of(context).colorScheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      view.notice!,
                      style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (fields.isEmpty && !_busy)
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
      // 送出鈕正上方，因為這句話是關於「按下去會發生什麼」——
      // 放在頁首的話，填完十個欄位捲到底要按的時候已經看不到了。

      if (buttons.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in buttons)
                FilledButton(
                  onPressed: _busy ? null : () => _submit(b),
                  child: Text(b.label),
                ),
            ],
          ),
        ),

    ];
  }

  /// 「這張申請不會帶附件」——整頁層級的那一句。
  ///
  /// 送出前的那個確認對話框是最後一道；這一句是要讓使用者在**開始填之前**
  /// 就知道從這裡送出的東西是不完整的，不要填完十個欄位才發現白填。
  Widget _attachmentWarning(List<SchemaField> files) {
    final scheme = Theme.of(context).colorScheme;
    final names =
        files.map((f) => f.label).where((l) => l.isNotEmpty).join('、');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(NtouTheme.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined,
                size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                names.isEmpty
                    ? '這一頁要附上檔案，但 App 沒辦法傳檔 —— 從這裡送出的申請不會有附件。'
                        '要附檔案的話請到學校網頁版送。'
                    : '這一頁要附上「$names」，但 App 沒辦法傳檔 —— 從這裡送出的申請不會有附件。'
                        '要附檔案的話請到學校網頁版送。',
                style: TextStyle(color: scheme.onErrorContainer, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(FunctionView view) {
    final r = view.result;
    if (r == null) {
      final group = _groupOf(view);
      // 一顆按得下去的按鈕都沒有（只有列印的那幾頁）——
      // 不要叫使用者去按一顆不存在的鈕。
      if (group.queryButtons.isEmpty) {
        // 但也不能就這樣留一片空白：上面一個學年度下拉、下面什麼都沒有，
        // 使用者分不出是 App 壞了還是自己少按了什麼。這 10 個功能
        //（列印註冊/考試請假單、在學證明申請列印…）點進來永遠是這樣，
        // 所以要說出為什麼、以及該去哪裡才印得到。
        //
        // 學校自己有話要說的時候（上面那張卡片）就不要再補一句 ——
        // 那句話才是使用者真正需要知道的原因。
        if (view.notice != null || !group.buttons.any((b) => b.isPrint)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.print_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('這一頁的內容是學校的列印報表，App 裡開不出來。'
                    '需要的話請到學校網頁版列印。'),
              ),
            ],
          ),
        );
      }

      // 會改資料的頁面（維護新生資料那一類）不是查詢頁 —— 它下面根本不會出現
      // 結果表格。跟使用者說「按上面的按鈕開始查詢」只會讓人以為自己少按了什麼。
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(widget.function.mutating
            ? '這一頁是填寫表單，填好上面的欄位再送出。'
            : '按上面的按鈕開始查詢。'),
      );
    }
    if (r.isEmpty || r.columns.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.isEmpty ? '查無符合資料' : '這份結果暫時無法在 App 顯示'),
          const SizedBox(height: 8),
          Text(r.isEmpty ? '可調整上方條件後重新查詢。' : '請至學校網頁查看完整內容。'),
          if (!r.isEmpty) SchoolWebHandoff(controller: widget.controller,
            functionTitle: widget.function.title),
        ],
      ));
    }

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
            '${r.paging.lastPage > 1 ? '（第 ${r.paging.pageNo} / ${r.paging.lastPage} 頁）' : ''}',
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
                        onTap: r.actionAt(i, col) == null ? () => showDialog<void>(
                          context: context, builder: (ctx) => AlertDialog(
                            title: Text(r.columns[col]),
                            content: SingleChildScrollView(child: SelectableText(r.rows[i][col])),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉'))],
                          )) : null,
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
        if (r.paging.lastPage > 1) _Pager(paging: r.paging, onGo: _goPage),
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
      leading: Icon(
        function.mutating ? Icons.edit_note : Icons.description_outlined,
        size: 22, color: function.mutating ? scheme.error : tint,
      ),
      title: Text(function.title),
      // **「會送出資料」這行字拿掉了。**
      //
      // 教務系統底下 53 個功能有 21 個會送出資料，每個都掛一行紅字的話
      // 那一頁就是滿螢幕的警告 —— 而警告的作用是讓人停下來，到處都是就
      // 沒人會停。同一個道理在 menu_catalog_test 裡寫過（誤標的代價是
      // 「久了就沒人看警告了」），這裡不是誤標，但效果一樣。
      //
      // 區分改成靠左邊那顆圖示：紅色的 `edit_note` vs 藍色的
      // `description_outlined`。**顏色和形狀同時不同**，所以不是只靠顏色
      // 在傳達（色盲一樣分得出來）。清單頁頂端有一行圖例說明那個紅色。
      //
      // 真正的防線本來就不在這裡，是點下去之後那個確認對話框。
      subtitle: subtitleOverride == null && !function.title.contains('上傳') && !function.title.contains('列印')
          ? null
          : Text(subtitleOverride ?? (function.title.contains('上傳') ? '附件需至學校網頁上傳' : '報表需至學校網頁列印'),
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (controller.phase != AppPhase.ready) {
      if (!await ensureSignedIn(context, controller) || !context.mounted) return;
    }

    // 少數幾個功能有專屬畫面。通用表單頁也開得起來（它讀學校自己的宣告），
    // 只是那幾頁的資料值得好好排 —— 畢業資格是一張「要求 vs 實際」的
    // 巢狀對照表，攤成通用表格的話一整欄都是空白，看不出「還差什麼」。
    //
    // 用 `code` 不用標題：學校改一個字（「查詢畢業資格」→「畢業資格查詢」）
    // 就會安靜地掉回通用頁，而畫面上只是「這一頁怎麼變醜了」。
    try {
      await RecentFunctions.record(function.path);
    } catch (_) {
      // 使用紀錄失敗不影響功能本身。
    }
    if (!context.mounted) return;
    final special = switch (function.code.toUpperCase()) {
      'ENRG010' => (BuildContext _) => GraduationPage(controller: controller),
      // 這一頁首頁也開得到（畢業進度右上角的「查其他系的規劃」）。
      // 從選單進來卻是通用表單頁的話，同一個功能會有兩種長相。
      'ENRA120' => (BuildContext _) =>
          RequiredCoursesPage(controller: controller),
      // 成績查詢走通用表單頁的話，使用者按下查詢只會看到**一列自己的學號**
      // ——真正的成績在那一列的「詳」點進去、而且還要再等一發 postback
      //（見 `AisRepository.openGrades`）。通用頁兩步都做不到。
      'GRD5010' => (BuildContext _) => GradesPage(controller: controller),
      _ => null,
    };
    if (special != null) {
      if (!context.mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: special));
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
