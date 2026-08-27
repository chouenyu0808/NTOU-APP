import 'package:flutter/material.dart';

import '../parsing/announcements.dart';
import '../parsing/models.dart';
import '../parsing/timetable.dart' show kWeekdays;
import 'app_controller.dart';
import 'required_courses_page.dart';

/// 首頁：今天要上什麼課，一眼看完。
///
/// 為什麼獨立一頁而不是把「今天」塞進課表頁：課表頁是**整個學期**的視圖，
/// 打開要先找今天在哪一欄。真正每天會看的問題只有一個 ——「等一下有什麼課、
/// 在哪間教室」。那個問題值得一個不用捲動、不用找的位置。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onOpenTab,
    required this.onOpenPlanner,
  });

  final AppController controller;

  /// 切到別的分頁（課表 / 校務系統）。
  final ValueChanged<int> onOpenTab;

  /// 切到課表分頁，並且看的是「預排」那一份。
  ///
  /// 跟 [onOpenTab] 分開，是因為預排**不是一個分頁** —— 它是課表分頁上的
  /// 另一份。共用 `onOpenTab(1)` 的話「完整課表」和「預排課表」兩張卡
  /// 按下去會跑到同一個地方，可是兩張的副標各自承諾了不同的東西。
  final VoidCallback onOpenPlanner;

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
    final now = DateTime.now();
    final weekday = HomePage.todayIndex(now);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text('首頁', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              '${now.month} 月 ${now.day} 日 · 星期${kWeekdays[weekday.clamp(0, 6)]}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            Text('今日課程', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _TodayCard(controller: _c, weekday: weekday),

            const SizedBox(height: 28),
            Text('校園公告', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _Announcements(items: _c.announcements),

            const SizedBox(height: 28),
            Text('快捷', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _Shortcut(
              icon: Icons.calendar_month_outlined,
              title: '完整課表',
              subtitle: '這學期每一天',
              onTap: () => widget.onOpenTab(1),  // 課表
            ),
            _Shortcut(
              icon: Icons.event_note_outlined,
              title: '預排課表',
              subtitle: '從學校課程挑，先排排看',
              onTap: widget.onOpenPlanner,
            ),
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
            _Shortcut(
              icon: Icons.apps_outlined,
              title: '校務系統',
              subtitle: '成績以外的 50 個功能',
              onTap: () => widget.onOpenTab(2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 今日課程那一塊。四種狀態要**分開講**，因為使用者要做的事不一樣。
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.controller, required this.weekday});

  final AppController controller;
  final int weekday;

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
    // **不要在這裡編一個開學日期出來**：校園行事曆不在學校的學生選單裡，
    // 我們沒有那份資料，寫死一個日期只會在明年變成錯的。
    if (t.isEmpty) {
      return wrap(_Notice(
        icon: Icons.beach_access_outlined,
        title: '這學期還沒有選課資料',
        body: '${t.label}｜學校系統目前查不到修課紀錄。\n選課之後回來這裡就會出現。',
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

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < today.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  HomePage.periodLabel(today[i], weekday)
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
              title: Text(today[i].name),
              subtitle: Text(
                [
                  if (today[i].teacher.isNotEmpty) today[i].teacher,
                  if (today[i].room.isNotEmpty) today[i].room,
                ].join(' · '),
              ),
            ),
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
            body: '公告是登入時順便讀到的，不會另外打一次學校的伺服器。',
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
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

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
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
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
