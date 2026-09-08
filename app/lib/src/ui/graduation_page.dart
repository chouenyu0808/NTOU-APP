import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../data/function_view.dart';
import '../parsing/graduation.dart';
import 'app_controller.dart';
import 'required_courses_page.dart';

/// 「查詢畢業資格」——「我還差什麼才能畢業」。
///
/// 跟首頁那個「畢業必修」（必修科目表）的差別：那一份是系上的課程規劃，
/// 所有人看到的一樣；這一份是**你自己的進度**。
///
/// **一門都還沒修的時候要講實話。** 這個功能對剛轉進來、或大一上剛開學的人
/// 來說整頁都是「未修」—— 那不是壞掉，但畫面要說得出來，不然使用者會以為
/// 是 App 沒抓到資料。
class GraduationPage extends StatefulWidget {
  const GraduationPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GraduationPage> createState() => _GraduationPageState();
}

class _GraduationPageState extends State<GraduationPage> {
  FunctionView? _view;
  GraduationStatus? _result;
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
    try {
      final view = await widget.controller.repository.openGraduation();
      _view = view;
      _result = parseGraduation(view.page.html);
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
        title: const Text('畢業進度'),
        actions: [
          // 必修科目表（`ENRA120`）的入口收在這裡。
          //
          // 它跟這一頁講的是同一件事，但要自己選入學年度／部別／系所／
          // 入學身分 —— 對「查自己」來說那是多餘的摩擦，而且選錯會查到
          // 別系的規劃，畫面上完全看不出來。
          //
          // 它現在唯一還贏的地方是**查別系**（想轉系、雙主修的人），
          // 所以降級成這裡的次要入口，而不是刪掉。
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RequiredCoursesPage(controller: widget.controller),
              ),
            ),
            icon: const Icon(Icons.manage_search),
            tooltip: '查其他系的規劃',
          ),
          IconButton(
            onPressed: _busy ? null : _open,
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

    // 學校自己有話要說的時候照著講（例如非開放時間）。
    final notice = _view?.notice;
    if (notice != null) return _message(context, notice, Icons.info_outline);
    if (_error != null) {
      return _message(context, _error!, Icons.error_outline, retry: true);
    }

    final r = _result;
    if (r == null || r.isEmpty) {
      return _message(
        context,
        '這一頁沒有解出畢業資格資料。學校可能改版了。',
        Icons.help_outline,
        retry: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _summaryCard(context, r),
        for (final g in r.groups) ...[
          const SizedBox(height: 20),
          _groupSection(context, g),
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
              FilledButton.tonal(onPressed: _open, child: const Text('重試')),
            ],
          ],
        ),
      ),
    );
  }

  /// 最上面那張：每個類別還差多少。
  Widget _summaryCard(BuildContext context, GraduationStatus r) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      for (final g in r.groups)
        if (g.summary != null) g.summary!,
      ...r.otherSummaries,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('學分', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            for (final s in rows) ...[
              _creditRow(context, s),
              if (s != rows.last) const Divider(height: 20),
            ],
            const SizedBox(height: 8),
            Text(
              '「還差」是學校算的未通過學分，不含抵免與暑修的規則差異。',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _creditRow(BuildContext context, CreditSummary s) {
    final scheme = Theme.of(context).colorScheme;
    // 應修是 `-` 的類別（選修）沒有「差多少」可言，只列已得。
    final hasTarget = s.required_ != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(s.category)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              hasTarget ? '${s.earned ?? 0} / ${s.required_}' : '${s.earned ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (hasTarget && (s.failed ?? 0) > 0)
              Text(
                '還差 ${s.failed}',
                style: TextStyle(fontSize: 12, color: scheme.error),
              )
            else if (hasTarget)
              Text(
                '已達成',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
          ],
        ),
      ],
    );
  }

  /// 一個類別底下的課目，照「建議修課學期」分堆。
  Widget _groupSection(BuildContext context, RequirementGroup g) {
    final theme = Theme.of(context);
    final byTerm = <String, List<RequiredCourse>>{};
    for (final c in g.courses) {
      byTerm.putIfAbsent(c.term, () => []).add(c);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  g.category,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              Text(
                '${g.takenCount} / ${g.courses.length} 門',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final term in byTerm.keys) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      term.isEmpty ? '不分學期' : term,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                for (final c in byTerm[term]!) _courseTile(context, c),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _courseTile(BuildContext context, RequiredCourse c) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            c.taken ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: c.taken ? scheme.primary : scheme.outlineVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name),
                // 修過的話，顯示實際修的那門課 —— 領域型的要求
                //（「11-博雅課程」）底下修的是某一門具體的課，名字不一樣。
                if (c.taken && c.takenName != null && c.takenName != c.name)
                  Text(
                    '${c.takenTerm} ${c.takenName}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  )
                else if (c.taken)
                  Text(
                    '${c.takenTerm}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // **0 學分不寫「0 學分」。** 游泳和英文畢業門檻就是 0 ——
          // 那種要求是「通過」不是「拿學分」，寫成 0 學分會像是不重要。
          Text(
            c.credits == 0 ? '門檻' : '${c.credits ?? '-'} 學分',
            style: TextStyle(
              fontSize: 12,
              color: c.credits == 0 ? scheme.tertiary : scheme.onSurfaceVariant,
            ),
          ),
          if (c.grade != null) ...[
            const SizedBox(width: 10),
            Text(
              c.grade!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
