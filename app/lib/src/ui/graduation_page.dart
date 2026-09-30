import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../data/function_view.dart';
import '../parsing/grades.dart';
import '../parsing/graduation.dart';
import '../parsing/graduation_match.dart';
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
  GraduationMatch? _match;
  String? _error;
  bool _gradesUnavailable = false;
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
      _view = null;
      _gradesUnavailable = false;
      _result = null;
      _match = null;
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

    // 成績是**額外**拿的，而且要再走一整套查詢（見 `openGrades`）。
    //
    // **失敗不能拖累這一頁。** 學校的畢業資格本來就顯示得出來，成績只是
    // 拿來補上「學校還沒登錄的抵免」。抓不到仍顯示學校紀錄，並提示比對
    // 未完成，避免使用者把缺少資料誤認為尚未通過。
    final status = _result;
    if (status != null && !status.isEmpty) {
      try {
        final grades = await widget.controller.repository.openGrades();
        _match = matchGraduation(status, grades);
      } catch (_) {
        // 保留學校資料，但必須說明抵免比對尚未完成。
        _gradesUnavailable = true;
      }
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
                builder: (_) =>
                    RequiredCoursesPage(controller: widget.controller),
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
        if (_gradesUnavailable)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '成績比對未完成，目前僅顯示學校的畢業資格紀錄。'
                    '未標示完成的課程不一定還需要修。',
                  ),
                  TextButton(onPressed: _open, child: const Text('重試成績比對')),
                ],
              ),
            ),
          ),
        _summaryCard(context, r),
        for (final g in r.groups) ...[
          const SizedBox(height: 20),
          _groupSection(context, g),
        ],
        if (_match != null && _match!.unmatched.isNotEmpty) ...[
          const SizedBox(height: 20),
          _UnmatchedCard(courses: _match!.unmatched),
        ],
      ],
    );
  }

  Widget _message(
    BuildContext context,
    String text,
    IconData icon, {
    bool retry = false,
  }) {
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
            // **這句話是實測過的，不是免責聲明。**
            //
            // 2026-09-17：同一個帳號在成績頁有 19 筆抵免、歷年累計 40 學分，
            // 而這一頁的每一類都是「已得 0、還差全部」—— 學校還沒把抵免
            // 掛進畢業資格的必修對照。兩頁同時看一定會覺得其中一頁壞了，
            // 所以要在這裡講出來，並且指出抵免在哪裡看得到。
            Text(
              '「還差」是學校算的未通過學分。抵免和暑修的學分不一定已經'
              '反映在這一頁 —— 抵免明細在「成績」那一頁。',
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

    // **「不知道」不能寫成 0。** 解不到已得學分時寫 0，等於告訴使用者
    // 「你一分都沒拿到」—— 那跟「這一欄我沒解出來」是完全不同的兩件事。
    final earned = s.earned?.toString() ?? '—';

    // **沒解到「未通過學分」時絕對不能說「已達成」。**
    //
    // 原本寫的是 `(s.failed ?? 0) > 0 ? 還差N : 已達成`，於是學校哪天把
    // 那一欄改個名字、parser 解不到（null），畫面上每一類都會變成「已達成」
    // —— 使用者會以為自己修完了。那是這一頁最不能出錯的一句話。
    //
    // 分成三種：>0 是還差、==0 是已達成、null 就什麼都不說。
    final Widget? note = switch (s.failed) {
      null => null,
      final f when f > 0 => Text(
        '還差 $f',
        style: TextStyle(fontSize: 12, color: scheme.error),
      ),
      _ => Text('已達成', style: TextStyle(fontSize: 12, color: scheme.primary)),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(s.category)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              hasTarget ? '$earned / ${s.required_}' : earned,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (hasTarget && note != null) note,
          ],
        ),
      ],
    );
  }

  /// 這一項的狀態。沒有成績可以比對時，就只看學校自己登錄的。
  RequirementMatch _statusOf(RequiredCourse c) =>
      _match?.of(c) ?? RequirementMatch(requirement: c);

  int _doneCount(RequirementGroup g) =>
      g.courses.where((c) => _statusOf(c).done).length;

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
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Text(
                '${_doneCount(g)} / ${g.courses.length} 門',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
    final st = _statusOf(c);

    // 三態，不是兩態。「修課中」跟「還沒修」對使用者要做的事完全不同：
    // 一個是等成績，一個是要去選課。
    final (icon, color) = switch (st) {
      final s when s.done => (Icons.check_circle, scheme.primary),
      final s when s.inProgress => (Icons.pending_outlined, scheme.tertiary),
      _ => (Icons.circle_outlined, scheme.outlineVariant),
    };

    // 這一項是靠什麼算完成的。
    //
    // **學校登錄的和我們比對出來的要分得開。** 前者是權威，後者是
    // 「成績裡有一門同名的課」—— 那是推論，使用者有權知道差別，
    // 尤其在學校還沒把抵免掛進來的時候。
    final via = switch (st) {
      final s when s.bySchool && c.takenName != null && c.takenName != c.name =>
        '${c.takenTerm} ${c.takenName}',
      final s when s.bySchool => c.takenTerm ?? '',
      final s when s.course != null =>
        '成績裡有「${s.course!.name}」'
            '${s.course!.mark.note == null ? '' : '（${s.course!.mark.note}）'}',
      _ => '',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name),
                if (st.needsConfirmation)
                  const Text('通過狀態待確認', style: TextStyle(fontSize: 12)),
                if (via.isNotEmpty)
                  Text(
                    via,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
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
          // **成績那一欄不是數字。** 學校在同一欄裡混著分數和記號
          // （`抵` 抵免、`+` 成績未到、`*` 不及格），照原樣粗體印出來的話，
          // 一個「抵」看起來就像一個分數，而使用者只會覺得看不懂。
          if (c.mark != null) ...[
            const SizedBox(width: 10),
            _GradeCell(mark: c.mark!),
          ],
        ],
      ),
    );
  }
}

/// 成績裡沒有對到任何一項必修的課。
///
/// **這張卡是整個比對功能的誠實所在。**
///
/// 一般課名精準比對，領域要求另依課名開頭比對。剩下的可能是選修或未辨識
/// 的名稱；保留這些課程，讓使用者能看出自動配對的限制。
class _UnmatchedCard extends StatelessWidget {
  const _UnmatchedCard({required this.courses});

  final List<CourseGrade> courses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            '沒有對到必修的課',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '一般必修依課名比對；國文、體育等領域要求會依課名開頭比對。'
                  '以下可能是選修或尚未辨識的課程，未配對不代表沒有通過。',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final c in courses) ...[
                  Row(
                    children: [
                      Expanded(child: Text(c.name)),
                      const SizedBox(width: 8),
                      Text(
                        [
                          if (c.credits != null && c.credits != 0)
                            '${c.credits} 學分',
                          if (c.mark.note != null) c.mark.note!,
                          if (c.mark.score != null) c.mark.score!,
                        ].join('・'),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (c != courses.last) const Divider(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 必修表上的成績那一格。
///
/// 跟成績頁（`GradesPage`）講的是同一套記號 —— 同一個系統、同一份圖例。
/// 兩頁對同一個「抵」講不一樣的話，使用者會以為那是兩件事。
class _GradeCell extends StatelessWidget {
  const _GradeCell({required this.mark});

  final GradeMark mark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 有分數就以分數為主角，不及格的記號用顏色講。
    if (mark.score != null) {
      return Text(
        mark.score!,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: mark.isFailed ? scheme.error : null,
        ),
      );
    }

    // 沒有分數：認得的記號講人話，**認不得的照原樣顯示，不要自己編說法**。
    final text = mark.note ?? mark.raw;
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: mark.isTransferred ? scheme.tertiary : scheme.onSurfaceVariant,
      ),
    );
  }
}
