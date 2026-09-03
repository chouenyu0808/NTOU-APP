import 'package:flutter/material.dart';

import '../config/period_times.dart';
import '../parsing/academic_calendar.dart';
import '../parsing/announcements.dart';
import '../parsing/models.dart';
import '../parsing/timetable.dart' show kWeekdays;
import 'app_controller.dart';
import 'required_courses_page.dart';
import 'theme.dart';

/// 首頁：今天要上什麼課，一眼看完。
///
/// 為什麼獨立一頁而不是把「今天」塞進課表頁：課表頁是**整個學期**的視圖，
/// 打開要先找今天在哪一欄。真正每天會看的問題只有一個 ——「等一下有什麼課、
/// 在哪間教室」。那個問題值得一個不用捲動、不用找的位置。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    this.now,
  });

  final AppController controller;

  /// 現在幾點。**測試用；正式執行時是 null，讀真正的時鐘。**
  ///
  /// 這一頁的內容跟時間有關（哪幾堂上完了、下一堂還有幾分鐘），
  /// 直接讀 `DateTime.now()` 的話測試就變成看時鐘的 —— 同一份程式早上綠、
  /// 晚上紅，而失敗訊息完全看不出跟時間有關。
  final DateTime? now;

  /// 今天是星期幾（0 = 週一），跟 [TimeSlot.weekday] 同一套。
  ///
  /// `DateTime.weekday` 是 1 = 週一，所以減一。**這裡錯一格，整頁會顯示
  /// 隔壁那天的課** —— 而畫面上完全看不出來，使用者只會照著去上錯的課。
  static int todayIndex(DateTime now) => now.weekday - 1;

  /// 今天要上的課，照第一節排序。
  ///
  /// 一門課可能一天有好幾節（`102 103 104`），這裡只算「今天有沒有」，
  /// 顯示時再把節次收成範圍。
  static List<Course> coursesOn(TimetableResult? t, int weekday) {
    if (t == null) return const [];
    final out = [
      for (final c in t.courses)
        if (c.slots.any((s) => s.weekday == weekday)) c,
    ];
    out.sort((a, b) => _firstPeriod(a, weekday).compareTo(
          _firstPeriod(b, weekday),
        ));
    return out;
  }

  static int _firstPeriod(Course c, int weekday) => c.slots
      .where((s) => s.weekday == weekday)
      .map((s) => s.period)
      .reduce((a, b) => a < b ? a : b);

  /// 今天這門課最後一節是第幾節。
  static int lastPeriod(Course c, int weekday) => c.slots
      .where((s) => s.weekday == weekday)
      .map((s) => s.period)
      .reduce((a, b) => a > b ? a : b);

  /// 把今天的課切成「已經上完的 / 接下來那一堂 / 今天剩下的」。
  ///
  /// [now] 是當天的分鐘數（`PeriodTimes.minutesOf`）。
  ///
  /// **[times] 沒有資料時全部算成「還沒上」**（`done` 空、`next` 是第一堂）。
  /// 節次對時鐘的表學校系統裡沒有，猜一組看起來合理的時間，錯了畫面上完全
  /// 看不出來 —— 使用者會看到「已結束」而錯過一堂還沒上的課。分不出來的時候
  /// 就不要分，比分錯好。
  static ({List<Course> done, Course? next, List<Course> later}) split(
    List<Course> today,
    int weekday,
    PeriodTimes times,
    int now,
  ) {
    if (!times.isKnown || today.isEmpty) {
      return (
        done: const [],
        next: today.isEmpty ? null : today.first,
        later: today.skip(1).toList(),
      );
    }

    final done = <Course>[];
    final rest = <Course>[];
    for (final c in today) {
      if (times.hasEnded(lastPeriod(c, weekday), now)) {
        done.add(c);
      } else {
        rest.add(c);
      }
    }
    return (
      done: done,
      next: rest.isEmpty ? null : rest.first,
      later: rest.skip(1).toList(),
    );
  }

  /// 「第 2-4 節」；不連續就列出來（「第 2、5 節」）。
  static String periodLabel(Course c, int weekday) {
    final ps = c.slots.where((s) => s.weekday == weekday).map((s) => s.period).toList()
      ..sort();
    if (ps.isEmpty) return '';
    if (ps.length == 1) return '第 ${ps.first} 節';
    final continuous = ps.last - ps.first == ps.length - 1;
    return continuous
        ? '第 ${ps.first}-${ps.last} 節'
        : '第 ${ps.join('、')} 節';
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.now ?? DateTime.now();
    final weekday = HomePage.todayIndex(now);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            // 日期直接當標題。原本上面還有一行 headlineMedium 的「首頁」，
            // 那佔掉整個第一屏最上面那一行，而且它說的事使用者從底部
            // 分頁列已經知道了。
            Text(
              '${now.month} 月 ${now.day} 日',
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              '星期${kWeekdays[weekday.clamp(0, 6)]}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            _TodayCard(controller: _c, weekday: weekday, now: now),

            // 行事曆抓不到就整區不畫。它是學校官網上的東西，官網掛掉或手機
            // 沒網路都會是空的 —— 那時候放一張「載入失敗」的卡沒有幫到任何人，
            // 使用者也不能拿它做什麼。
            if (_c.calendarEvents.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('近期行事曆', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              _Calendar(events: _c.calendarEvents, now: now),
            ],

            const SizedBox(height: 28),
            Text('校園公告', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _Announcements(items: _c.announcements),

            // 快捷本來有四張，其中三張（完整課表 / 預排課表 / 校務系統）
            // 只是把底部分頁列再列一次 —— 同一個目的地給兩個入口，
            // 沒有讓人更快到，只是讓首頁更長。留下的這張是唯一
            // 不在分頁列上的。
            const SizedBox(height: 28),
            _Shortcut(
              icon: Icons.school_outlined,
              title: '畢業必修',
              subtitle: '四年要修哪些課、門檻多少',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RequiredCoursesPage(controller: _c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 今日課程那一塊。四種狀態要**分開講**，因為使用者要做的事不一樣。
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.controller,
    required this.weekday,
    required this.now,
  });

  final AppController controller;
  final int weekday;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = controller.timetable;

    Widget wrap(Widget child) => Card(
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        );

    // 還沒有任何課表 —— 可能沒登入過，也可能學校系統開不起來。
    if (t == null) {
      return wrap(_Notice(
        icon: Icons.cloud_off_outlined,
        title: '還沒有課表資料',
        body: '登入之後會自動抓，抓過一次就算離線也看得到。',
      ));
    }

    // 學校明確回「查無符合資料」—— 這是答案，不是錯誤。
    // 開學日期**不要寫死**，一律從行事曆讀（見下面的 nearestClassStart）——
    // 寫死一個日期只會在明年變成錯的。
    if (t.isEmpty) {
      return wrap(_Notice(
        icon: Icons.beach_access_outlined,
        title: '這學期還沒有選課資料',
        body: '${t.label}｜學校系統目前查不到修課紀錄。\n選課之後回來這裡就會出現。',
      ));
    }

    // 還沒開始上課 —— 課表已經有了，但那些課還沒發生。
    //
    // 不擋的話，開學前首頁會照著課表說「今天已經上完 1 堂」，
    // 而使用者根本還沒去上過任何一堂課。日期是從校園行事曆讀的
    // （學校寫「開始上課」不是「開學」），行事曆抓不到就跳過這一段 ——
    // **寧可少講一句，也不要編一個開學日期出來。**
    final classStart = nearestClassStart(controller.calendarEvents, now);
    if (classStart != null && DateTime(now.year, now.month, now.day).isBefore(classStart)) {
      return wrap(_Notice(
        icon: Icons.event_available_outlined,
        title: '${classStart.month} 月 ${classStart.day} 日開始上課',
        body: '${t.label}｜這學期共 ${t.courses.length} 門課。',
      ));
    }

    // 有課，但**一門都沒有上課時間** —— 那不是「今天沒有課」，
    // 是「我們不知道你今天有沒有課」。這兩件事在畫面上一定要分得開。
    //
    // 這是真實資料的常態，不是例外：學校這個 UI 的選課清單檢視
    // （`QUERY_BTN1`）回的 17 欄裡完全沒有上課時間和教室，也沒有隱藏欄位
    // （2026-08-25 實測）。時間只存在於 Crystal Report 的課表檢視。
    // 課表頁上有一段 `_NoSlotsNotice` 把這件事講清楚，首頁沒有 ——
    // 結果首頁會拿一個咖啡杯圖示對每一個使用者說「今天沒有課」，
    // 而他其實第二節就要進教室。**編一個錯的答案比承認不知道糟得多。**
    if (!t.hasSlots) {
      return wrap(_Notice(
        icon: Icons.schedule_outlined,
        title: '這學期有 ${t.courses.length} 門課，但沒有上課時間',
      ));
    }

    final today = HomePage.coursesOn(t, weekday);

    if (today.isEmpty) {
      return wrap(_Notice(
        icon: weekday >= 5
            ? Icons.weekend_outlined
            : Icons.free_breakfast_outlined,
        title: weekday >= 5 ? '週末，今天沒有課' : '今天沒有課',
        body: '${t.label}｜這學期共 ${t.courses.length} 門課。',
      ));
    }

    final times = PeriodTimes.ntou;
    final split = HomePage.split(
      today,
      weekday,
      times,
      PeriodTimes.minutesOf(now),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已經上完的收成一行。它們還有用（「我今天到底去了沒」），
        // 但不該跟等一下要去的課搶同樣的位置。
        if (split.done.isNotEmpty) ...[
          _DoneRow(courses: split.done, weekday: weekday),
          const SizedBox(height: 10),
        ],

        if (split.next != null) ...[
          _NextClass(
            course: split.next!,
            weekday: weekday,
            times: times,
            now: PeriodTimes.minutesOf(now),
          ),
          const SizedBox(height: 10),
        ],

        if (split.later.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              times.isKnown ? '今天還有' : '今天的課',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < split.later.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _CourseRow(course: split.later[i], weekday: weekday),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 一堂課的一列：左邊節次、右邊課名和老師 / 教室。
class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.weekday});

  final Course course;
  final int weekday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(NtouTheme.radiusMd),
        ),
        child: Text(
          HomePage.periodLabel(course, weekday)
              .replaceAll('第 ', '')
              .replaceAll(' 節', ''),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(course.name),
      subtitle: Text(
        [
          if (course.teacher.isNotEmpty) course.teacher,
          if (course.room.isNotEmpty) course.room,
        ].join(' · '),
      ),
    );
  }
}

/// 接下來那一堂 —— 首頁真正要回答的問題。
///
/// 「等一下有什麼課、在哪間教室」值得整張卡，而不是清單裡長得跟其他人
/// 一模一樣的第三列。
class _NextClass extends StatelessWidget {
  const _NextClass({
    required this.course,
    required this.weekday,
    required this.times,
    required this.now,
  });

  final Course course;
  final int weekday;
  final PeriodTimes times;
  final int now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final start = course.slots
        .where((s) => s.weekday == weekday)
        .map((s) => s.period)
        .reduce((a, b) => a < b ? a : b);

    final slot = times[start];
    final until = times.minutesUntil(start, now);
    final started = slot != null && now >= slot.start;

    // 沒有節次時間表的時候不寫「下一堂」——
    // 我們分不出哪幾堂已經上完了，說「下一堂」會是錯的。
    final label = !times.isKnown
        ? '今天第一堂'
        : started
            ? '現在'
            : '下一堂';

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // 時間只有真的知道才寫。**不要猜** —— 猜錯的話畫面上看不出來，
                // 使用者只會照著遲到。
                if (slot != null)
                  Text(
                    '${PeriodTimes.hhmm(slot.start)}'
                    '–${PeriodTimes.hhmm(slot.end)}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              course.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                HomePage.periodLabel(course, weekday),
                if (course.room.isNotEmpty) course.room,
                if (course.teacher.isNotEmpty) course.teacher,
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
              ),
            ),
            if (until != null) ...[
              const SizedBox(height: 10),
              Text(
                until >= 60
                    ? '還有 ${until ~/ 60} 小時 ${until % 60} 分'
                    : '還有 $until 分鐘',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 今天已經上完的課，收成一行可展開的。
class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.courses, required this.weekday});

  final List<Course> courses;
  final int weekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.check_circle_outline,
            size: 20, color: scheme.onSurfaceVariant),
        title: Text(
          '今天已經上完 ${courses.length} 堂',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final c in courses) _CourseRow(course: c, weekday: weekday),
        ],
      ),
    );
  }
}

/// 近期行事曆。
///
/// 只列接下來幾筆，**而且進行中的算「接下來」** —— 選課週開始了還沒結束的
/// 時候，那正是最需要看到的一條（見 `upcoming()`）。
class _Calendar extends StatelessWidget {
  const _Calendar({required this.events, required this.now});

  final List<CalendarEvent> events;
  final DateTime now;

  /// 首頁顯示幾筆。要全部的話官網那一頁就是全部。
  static const int _limit = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = upcoming(events, now, limit: _limit);
    if (shown.isEmpty) return const SizedBox.shrink();

    final today = DateTime(now.year, now.month, now.day);

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            Builder(builder: (context) {
              final e = shown[i];
              final ongoing = e.covers(today);
              // 起訖日**不要疊成兩行塞進 leading** —— ListTile 的 leading
              // 高度是有限的，兩行 Text 會把它撐破（RenderFlex overflow）。
              // 左邊只放開始日，結束日跟「進行中」一起放到副標。
              final note = [
                if (!e.isSingleDay) '到 ${e.end.month}/${e.end.day}',
                // 「進行中」要標出來 —— 一條開始日在上禮拜的事件，
                // 光看日期會被當成已經過去了。
                if (ongoing) '進行中',
              ].join(' · ');

              return ListTile(
                leading: SizedBox(
                  width: 44,
                  child: Center(
                    child: Text(
                      '${e.start.month}/${e.start.day}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: ongoing ? scheme.primary : scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                title: Text(e.title, style: theme.textTheme.bodyMedium),
                subtitle: note.isEmpty
                    ? null
                    : Text(
                        note,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ongoing
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// 電子公布欄。只列最近幾則 —— 首頁是「順手看一眼」的地方，
/// 要全部的話選單裡有「電子公布欄 > 公告訊息查詢」。
class _Announcements extends StatelessWidget {
  const _Announcements({required this.items});

  final List<Announcement> items;

  /// 首頁顯示幾則。
  static const int _limit = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: _Notice(
            icon: Icons.campaign_outlined,
            title: '登入後顯示校園公告',
          ),
        ),
      );
    }

    final shown = items.take(_limit).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: Text(shown[i].title, style: theme.textTheme.bodyMedium),
              subtitle: Text(
                [
                  if (shown[i].date != null) _dateLabel(shown[i].date!),
                  if (shown[i].unit.isNotEmpty) shown[i].unit,
                ].join('  ·  '),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 學校的頁面用民國年，我們已經轉成西元了 —— 這裡顯示「8/26」就好。
  /// 年份對「最近的公告」沒有資訊量，佔的位置拿來放標題比較實在。
  static String _dateLabel(DateTime d) => '${d.month}/${d.day}';
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              if (body case final b?) ...[
                const SizedBox(height: 4),
                Text(
                  b,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onTap,
        ),
      );
}
