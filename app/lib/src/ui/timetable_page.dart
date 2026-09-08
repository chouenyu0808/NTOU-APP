import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../config/period_times.dart';
import '../parsing/models.dart';
import 'app_controller.dart';
import 'class_status.dart';
import 'login_page.dart';
import 'timetable_grid.dart';
import 'theme.dart';

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
          '會一併結束學校系統上的登入狀態，這樣你在瀏覽器才登得進去。',
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

class _Body extends StatefulWidget {
  const _Body({required this.controller});

  final AppController controller;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // **這一頁上跟「現在」有關的東西不只一個**：頂端的「還有 N 分鐘下課」，
    // 還有格子裡「現在這一格」的外框。兩個都是 build 當下算的，不重算就會
    // 凍住 —— 倒數卡在同一個數字，外框跨節之後還留在上一格。
    //
    // 計時器放在**這一層**而不是各自的 widget 裡：一個計時器重建整個
    // subtree，兩者一起更新、也不會有兩個計時器各跑各的。
    // （一分鐘重建一次這棵樹比捲動一幀還便宜。）
    //
    // 對齊到整分：不對齊的話，剛好在「還有 1 分鐘」那一秒進來，會晚快一
    // 分鐘才跳成 0。
    final now = DateTime.now();
    _ticker = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        if (mounted) setState(() {});
        _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted) setState(() {});
        });
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  AppController get controller => widget.controller;

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
          // 現在課上到哪了 —— 只在顯示當學期時才有意義。切去看過去的學期時
          // 「還有幾分鐘下課」是胡說，那時候不顯示。
          if (c.isCurrentSemester) NowStatus(courses: result.courses),
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
              '學校的選課清單沒有附上課時間，所以沒有畫成格子。\n'
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(NtouTheme.radiusSm)),
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

/// 課表頂端那條「現在課上到哪了」。
///
/// 邏輯全在 `classStatus`（純函式，測得很兇）。這裡只負責把四種狀態畫成
/// 一句話 —— **在課內／下一堂用醒目色，上完了／沒課用低調色**，那兩種
/// 是「現在沒事」，不需要搶眼。
class NowStatus extends StatelessWidget {
  const NowStatus({super.key, required this.courses, this.now});

  final List<Course> courses;

  /// 給測試釘住一個「現在」。正式執行時是 null，用真正的當下時間。
  ///
  /// **每分鐘重算是父層（`_Body`）在做的** —— 那裡一個計時器就把這條狀態列
  /// 和格子裡「現在這一格」的外框一起更新，不必兩個 widget 各養一個。
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = now ?? DateTime.now();
    final status = classStatus(
      courses: courses,
      times: PeriodTimes.ntou,
      weekday: t.weekday - 1,
      nowMinutes: t.hour * 60 + t.minute,
    );
    if (status == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String text, bool highlight) = switch (status) {
      InClass(:final course, :final minutesLeft) => (
          Icons.play_circle_outline,
          '${course.name}　還有 ${_mins(minutesLeft)}下課',
          true,
        ),
      NextClass(:final course, :final minutesUntil, :final startMinute) => (
          Icons.schedule,
          '下一堂 ${course.name}　${_mins(minutesUntil)}後'
              '（${PeriodTimes.hhmm(startMinute)}）',
          true,
        ),
      DoneForToday() => (Icons.check_circle_outline, '今天的課都上完了', false),
      NoClassToday() => (Icons.weekend_outlined, '今天沒有課', false),
    };

    final fg = highlight ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NtouTheme.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「45 分鐘」「1 小時 5 分」。超過一小時只寫分鐘會變成「還有 125 分鐘」，
  /// 讀起來要換算。
  static String _mins(int m) {
    if (m < 60) return '$m 分鐘';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h 小時' : '$h 小時 $r 分';
  }
}

