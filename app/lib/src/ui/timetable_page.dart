import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../parsing/models.dart';
import 'app_controller.dart';
import 'login_page.dart';
import 'timetable_grid.dart';

class TimetablePage extends StatelessWidget {
  const TimetablePage({
    super.key,
    required this.controller,
    this.showLoginAction = true,
    this.titleWidget,
  });

  final AppController controller;

  /// 蓋掉 AppBar 的標題。
  ///
  /// 課表和預排合併成同一個分頁之後，標題位置放的是那組切換鈕 ——
  /// 那個切換本身就是這一頁的身分，再加一列標題只是重複。
  final Widget? titleWidget;

  /// 顯示「登入更新」那顆 FAB。
  ///
  /// 從登入頁進來看快取時要關掉 —— 那裡按登入等於在登入頁上面再開一個登入頁。
  final bool showLoginAction;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          appBar: AppBar(
            title: titleWidget ?? const Text('我的課表'),
            // 登出搬到「校務系統 > 帳號」了 —— 那不屬於課表。
            bottom: c.years.isEmpty
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(56),
                    child: _SemesterBar(controller: c),
                  ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              if (c.phase == AppPhase.ready) {
                await c.refreshTimetable();
              } else {
                await _openLogin(context, c);
              }
            },
            child: _Body(controller: c),
          ),
          floatingActionButton: (c.phase == AppPhase.ready || !showLoginAction)
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openLogin(context, c),
                  icon: const Icon(Icons.login),
                  label: const Text('登入更新'),
                ),
        );
      },
    );
  }

  Future<void> _openLogin(BuildContext context, AppController c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LoginPage(controller: c)),
    );
  }

}

/// 登出前先講清楚會發生什麼事。
///
/// 學校系統一次只允許一個 session，App 沒登出的話使用者在瀏覽器登入會被
/// 自己的 App 擋掉 —— 而那個錯誤訊息完全看不出原因。
Future<void> confirmLogout(BuildContext context, AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登出'),
        // 為什麼特別講：學校系統一次只允許一個 session，App 沒登出的話
        // 使用者在瀏覽器登入會被自己的 App 擋掉，而那個錯誤訊息完全看不出原因。
        content: const Text(
          '會一併結束學校系統上的登入狀態，這樣你在瀏覽器才登得進去。\n'
          '課表快取會留著。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
  if (ok ?? false) await c.logout();
}

class _SemesterBar extends StatelessWidget {
  const _SemesterBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: c.year,
              isDense: true,
              decoration: const InputDecoration(
                labelText: '學年度',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                for (final y in c.years)
                  DropdownMenuItem(value: y.value, child: Text(y.label)),
              ],
              onChanged: (v) => c.selectSemester(newYear: v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: c.semester,
              isDense: true,
              decoration: const InputDecoration(
                labelText: '學期',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                for (final s in c.semesters)
                  DropdownMenuItem(value: s.value, child: Text(s.label)),
              ],
              onChanged: (v) => c.selectSemester(newSemester: v),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final result = c.timetable;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (c.error != null) _Banner.error(c.error!),
        if (c.showingCache && result != null) _Banner.cache(result.fetchedAt),
        if (c.loadingTimetable) const LinearProgressIndicator(),
        if (result == null)
          const _Empty(
            icon: Icons.calendar_month_outlined,
            title: '還沒有課表',
            body: '登入教學務系統之後，這裡會顯示你的選課清單。',
          )
        else if (result.isEmpty)
          _Empty(
            icon: Icons.event_busy_outlined,
            title: '${result.label}沒有修課紀錄',
            // 「查無符合資料」是學校明確回的答案，不是 App 出錯。
            // 這兩件事在畫面上一定要分得開，不然使用者會一直重試。
            body: '學校系統回覆「查無符合資料」——\n'
                '這個學期你沒有選課，或是還沒到開放查詢的時間。',
          )
        else ...[
          const SizedBox(height: 12),
          TimetableGrid(courses: result.courses),
          if (!result.hasSlots) const _NoSlotsNotice(),
          const SizedBox(height: 12),
          for (final course in result.courses) _CourseTile(course: course),
          _FetchedAt(result.fetchedAt),
        ],
      ],
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (course.code.isNotEmpty) course.code,
      if (course.teacher.isNotEmpty) course.teacher,
      if (course.classLabel.isNotEmpty) course.classLabel,
      if (course.credits != null) '${_trim(course.credits!)} 學分',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ExpansionTile(
        title: Text(course.name, style: theme.textTheme.titleSmall),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 認得的欄位放上面，其餘原封不動列出來。
          // 個人選課清單的欄位還沒見過真實資料，所以「認不得」是常態 ——
          // 與其藏起來，不如全部顯示，至少使用者看得到學校給了什麼。
          for (final e in course.raw.entries)
            if (e.value.isNotEmpty && e.value != '&nbsp;')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        e.key,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(e.value, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// 課有抓到，但沒有時段可以排進格子。
///
/// **這通常不是解析失敗，是資料本來就沒有。** 2026-08-25 實測：學校這個 UI 的
/// 清單檢視（`QUERY_BTN1`）回的 17 欄裡**完全沒有上課時間和教室**，
/// 也沒有隱藏欄位。時間只存在於 Crystal Report 的課表檢視（`QUERY_BTN3`）。
///
/// 所以這裡的文案不能寫成「看不懂」—— 那會讓使用者以為 App 壞了，
/// 或是去懷疑自己的選課資料有問題。要講的是「這個來源沒有這個欄位」。
class _NoSlotsNotice extends StatelessWidget {
  const _NoSlotsNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.grid_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '學校的選課清單沒有附上課時間，所以沒有畫成格子 —— '
              '這不是漏抓，那個查詢本來就不含時間和教室欄位。\n'
              '下面是完整的修課清單，展開可以看到學校給的每一個欄位。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner._({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  factory _Banner.error(String message) => _Banner._(
        icon: Icons.error_outline,
        text: message,
        background: null,
        foreground: null,
      );

  factory _Banner.cache(DateTime fetchedAt) => _Banner._(
        icon: Icons.cloud_off_outlined,
        text: '顯示的是 ${_when(fetchedAt)} 抓到的資料，還沒跟學校核對。',
        background: null,
        foreground: null,
      );

  final IconData icon;
  final String text;
  final Color? background;
  final Color? foreground;

  static String _when(DateTime t) =>
      intl.DateFormat('M/d HH:mm').format(t.toLocal());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = icon == Icons.error_outline;
    final bg = background ??
        (isError ? scheme.errorContainer : scheme.surfaceContainerHighest);
    final fg = foreground ?? (isError ? scheme.onErrorContainer : scheme.onSurface);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}

class _FetchedAt extends StatelessWidget {
  const _FetchedAt(this.time);

  final DateTime time;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          '更新於 ${intl.DateFormat('yyyy/M/d HH:mm').format(time.toLocal())}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
