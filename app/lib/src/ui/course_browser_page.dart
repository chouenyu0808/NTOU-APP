import 'package:flutter/material.dart';

import '../ais/exceptions.dart';
import '../data/function_view.dart';
import '../parsing/models.dart';
import '../parsing/tables.dart';
import '../parsing/timetable.dart';
import '../planner/plan_models.dart';
import '../storage/plan_store.dart';
import 'app_controller.dart';
import 'plan_dialogs.dart';
import 'selection_tag.dart';

class CourseBrowserPage extends StatefulWidget {
  const CourseBrowserPage({
    super.key,
    required this.controller,
    required this.planStore,
  });

  final AppController controller;
  final PlanStore planStore;

  @override
  State<CourseBrowserPage> createState() => _CourseBrowserPageState();
}

class _CourseBrowserPageState extends State<CourseBrowserPage>
    with SingleTickerProviderStateMixin {
  FunctionView? _view;
  String? _error;
  bool _busy = true;

  late TabController _tabController;
  final _keywordController = TextEditingController();

  List<Course>? _results;

  /// 目前這個學期的預排。用來把**已經加進去的課**從搜尋結果裡濾掉。
  CoursePlan? _plan;

  /// 使用者把已排的課切回來看。
  ///
  /// 預設藏起來，但**一定要留一個切回來的開關**：默默少掉幾筆結果，
  /// 使用者第一個念頭是「搜尋壞了」，不是「喔那門我加過了」。
  bool _showPlanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _open();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.openCourseSearch();
    });
    await _loadPlan();
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on AisException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '發生未預期的錯誤（${e.runtimeType}）。';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _searchByName() async {
    final view = _view;
    final keyword = _keywordController.text.trim();
    if (view == null || keyword.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.searchCourseByName(view, keyword);
      _parseResults(_view!.page.html);
    });
  }

  Future<void> _searchByFaculty() async {
    final view = _view;
    if (view == null) return;

    final t = widget.controller.repository.config.courseSearch.facultyTab;
    final degree = view.values[t.degreeField] ?? '';
    final faculty = view.values[t.facultyField] ?? '';
    final grade = view.values[t.gradeField] ?? '';
    final classId = view.values[t.classField] ?? '';

    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.searchCourseByFaculty(
        view,
        degree,
        faculty,
        grade,
        classId,
      );
      _parseResults(_view!.page.html);
    });
  }

  Future<void> _setCascadeField(String name, String value) async {
    final view = _view;
    if (view == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    await _guard(() async {
      _view = await widget.controller.repository.cascade(view, name, value);
    });
  }

  Future<void> _loadPlan() async {
    final year = widget.controller.year;
    final semester = widget.controller.semester;
    if (year == null || semester == null) return;
    final plan = await widget.planStore.read(year, semester);
    if (mounted) setState(() => _plan = plan);
  }

  /// 這門課是不是已經在預排裡了。
  ///
  /// **比課號，不比班別。** 同一門課的 A 班和 B 班課號一樣
  /// （計算機概論兩班都是 B57011RQ）—— 已經選了 B 班之後，A 班對使用者
  /// 就沒有意義了，整門課一起藏掉才是他要的。
  ///
  /// 沒有課號的（手動輸入過的）退而求其次比課名。
  bool _isPlanned(Course c) {
    final plan = _plan;
    if (plan == null) return false;
    return plan.courses.any((p) => c.code.isNotEmpty
        ? p.course.code == c.code
        : p.course.name == c.name);
  }

  void _parseResults(String html) {
    if (isEmptyResult(html)) {
      _results = const [];
    } else {
      _results = parseCourseList(html);
    }
  }

  Future<void> _addToPlan(Course course) async {
    final year = widget.controller.year;
    final semester = widget.controller.semester;
    if (year == null || semester == null) return;

    final plan = await widget.planStore.read(year, semester) ??
        CoursePlan(year: year, semester: semester);
    
    // 「同一門課」是指**同一班**，不是同課號。真實資料裡 B57011RQ 計算機概論
    // 有 1年A班和 1年B班，兩列課號和課名都一樣 —— 用 `||` 比課名的話，
    // 使用者連想比較兩個班都做不到，而且訊息還說「已經在預排清單中了」。
    bool alreadyPlanned(PlannedCourse c) => course.code.isNotEmpty
        ? c.course.code == course.code &&
            c.course.classLabel == course.classLabel
        : c.course.name == course.name;

    if (plan.courses.any(alreadyPlanned)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('這門課已經在預排清單中了')),
      );
      return;
    }

    setState(() => _busy = true);

    // 查詢結果那張表（17 欄）**沒有上課時間**，要點進課號的詳細頁才看得到。
    // 這裡替使用者跑一次那個 postback。
    var slots = const <TimeSlot>[];
    try {
      // 同一個課號常常有好幾列（A班／B班），上課時間不一樣 ——
      // 要帶著班別和老師才認得出使用者按的是哪一列。
      final target = courseDetailTarget(
        _view!.page.html,
        course.code,
        classLabel: course.classLabel,
        teacher: course.teacher,
      );
      if (target != null) {
        slots = await widget.controller.repository
            .fetchCourseTimeSlots(_view!, target);
      }
    } catch (e) {
      // 抓時間失敗不該擋住「加入預排」—— 使用者回預排頁手動填就好，
      // 而整個動作失敗的話他連課都加不進去。
      debugPrint('抓上課時間失敗：$e');
    }
    if (mounted) setState(() => _busy = false);

    // 時段要放進 **PlannedCourse.slots**，不是 Course.slots ——
    // 預排頁的格子、衝堂檢查、「未填時段」的統計看的全是前者
    // （`CoursePlan.asCourses()` 還會拿它蓋掉 Course.slots）。
    // 放錯地方的話：時間抓到了，但畫面上跟沒抓到一模一樣。
    final planned = PlannedCourse(course: course, slots: slots);
    final newPlan = plan.copyWith(courses: [...plan.courses, planned]);
    await widget.planStore.write(newPlan);
    await _loadPlan();
    if (!mounted) return;

    // 抓不到時間就**當場**問。
    //
    // 學校的課程查詢表（17 欄）結構上就沒有上課時間，詳細頁那一趟又可能失敗，
    // 所以「加進來但沒有時段」是常態、不是例外。而沒有時段的課排不進格子、
    // 也驗不了衝堂 —— 等於這門課加了跟沒加一樣。
    //
    // 以前是丟一句「請記得回預排頁面填入上課時段」然後放他走。那句話要成立，
    // 使用者得記住是「哪一門」課還沒填、而且真的會回去 —— 兩件事都不太會發生。
    if (slots.isEmpty) {
      final picked = await showDialog<List<TimeSlot>>(
        context: context,
        builder: (_) => const EditSlotsDialog(initial: []),
      );
      if (picked != null && picked.isNotEmpty) {
        // 直接重接一次尾巴，不要用 key 去找 —— `key` 是課號，而同一個課號
        // 可能有 A 班和 B 班兩筆，比 key 會把另一班的時段一起蓋掉。
        final withSlots = plan.copyWith(
          courses: [
            ...plan.courses,
            planned.copyWith(slots: picked, slotsAreManual: true),
          ],
        );
        await widget.planStore.write(withSlots);
        await _loadPlan();
        if (!mounted) return;
        _announce(course, picked, withSlots);
        return;
      }
    }

    _announce(course, slots, newPlan);
  }

  /// 加完之後說結果 —— 而且**當場把衝堂講出來**。
  ///
  /// 衝堂本來只在預排頁上顯示。使用者在這一頁連加五門課，撞在一起的那兩門
  /// 要等他離開這一頁才會知道，那時候他已經不記得是為了什麼加的了。
  void _announce(Course course, List<TimeSlot> slots, CoursePlan plan) {
    final scheme = Theme.of(context).colorScheme;
    final key = course.code.isNotEmpty ? course.code : course.name;
    final clash = plan
        .conflicts()
        .where((c) => c.a.key == key || c.b.key == key)
        .toList();

    if (clash.isNotEmpty) {
      final other = clash.first.a.key == key ? clash.first.b : clash.first.a;
      final where = clash.first.slots.map((s) => s.toString()).join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: scheme.errorContainer,
          duration: const Duration(seconds: 6),
          content: Text(
            '已加入 ${course.name}，但和「${other.course.name}」撞在 $where。',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(slots.isEmpty
            ? '已加入 ${course.name}（還沒有上課時段）'
            : '已加入 ${course.name}，${slots.length} 節課'),
      ),
    );
  }

  /// 學校查不到、或使用者想自己打的課（校外學分、還沒開放查詢的通識）。
  Future<void> _manualAdd() async {
    final year = widget.controller.year;
    final semester = widget.controller.semester;
    if (year == null || semester == null) return;

    final added = await showDialog<PlannedCourse>(
      context: context,
      builder: (_) => const AddCourseDialog(),
    );
    if (added == null || !mounted) return;

    final plan = await widget.planStore.read(year, semester) ??
        CoursePlan(year: year, semester: semester);
    final newPlan = plan.copyWith(courses: [...plan.courses, added]);
    await widget.planStore.write(newPlan);
    await _loadPlan();
    if (!mounted) return;
    _announce(added.course, added.slots, newPlan);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = widget.controller.year ?? '?';
    final semester = widget.controller.semester ?? '?';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('從學校課程選'),
            Text(
              '加入至：$year 學年第 $semester 學期',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          // 校外學分、還沒開放查詢的通識 —— 學校查不到的課還是要排得進去。
          // 以前這是 FAB 底下 bottom sheet 的第二個選項，但那層 sheet 逼每個人
          // 在「我要找課」之前先回答「你想用哪種方式找課」，而九成的答案都一樣。
          PopupMenuButton<void>(
            tooltip: '更多',
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                onTap: _manualAdd,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('手動輸入'),
                  subtitle: Text('學校查不到的課'),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '課名搜尋'),
            Tab(text: '系所瀏覽'),
          ],
        ),
      ),
      body: _view == null && _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(
                  error: _error!,
                  onRetry: _open,
                  // 學校系統掛掉、或帳號被自己在瀏覽器上佔住的時候，
                  // 手動輸入是唯一還排得動課的路。
                  onManual: _manualAdd,
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNameTab(),
                    _buildFacultyTab(),
                  ],
                ),
    );
  }

  Widget _buildNameTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  decoration: const InputDecoration(
                    labelText: '課名關鍵字',
                    hintText: '例如：計算機',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _searchByName(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _searchByName,
                child: const Text('搜尋'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _buildResultsList()),
      ],
    );
  }

  Widget _buildFacultyTab() {
    final view = _view;
    if (view == null) return const SizedBox.shrink();

    final t = widget.controller.repository.config.courseSearch.facultyTab;

    Widget buildDropdown(String fieldName, String label) {
      final field = view.schema.fields.where((f) => f.name == fieldName).firstOrNull;
      if (field == null) return const SizedBox.shrink();

      final current = view.values[fieldName] ?? field.value;
      
      // If there are no options, the school system hasn't populated this dropdown yet
      // Or it's genuinely empty. Either way, disable it.
      if (field.options.isEmpty) {
        return DropdownButtonFormField<String>(
          initialValue: null,
          items: const [],
          onChanged: null,
          decoration: InputDecoration(labelText: label),
        );
      }

      // Check if current is valid
      final isValid = field.options.any((o) => o.value == current);
      final value = isValid ? current : field.options.first.value;

      // `initialValue` 只在建立時當初始值，之後靠 didUpdateWidget 比對新舊值
      // 才會跟著改 —— 連動下拉每次 postback 回來都會換值，所以**這一格的值
      // 一定要從 view 重新算**（而不是記在 State 裡），不然畫面會停在舊選項。
      return DropdownButtonFormField<String>(
        initialValue: value,
        items: field.options
            .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
            .toList(),
        onChanged: _busy
            ? null
            : (v) {
                if (v == null) return;
                setState(() {
                  _view = view.copyWith(values: {...view.values, fieldName: v});
                });
                if (view.needsCascade(fieldName)) {
                  _setCascadeField(fieldName, v);
                }
              },
        decoration: InputDecoration(labelText: label),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildDropdown(t.degreeField, '部別'),
              const SizedBox(height: 12),
              buildDropdown(t.facultyField, '系所'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: buildDropdown(t.gradeField, '年級')),
                  const SizedBox(width: 12),
                  Expanded(child: buildDropdown(t.classField, '班別')),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _searchByFaculty,
                child: const Text('查詢此系所課程'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _buildResultsList()),
      ],
    );
  }

  Widget _buildResultsList() {
    final results = _results;
    if (results == null) {
      return const Center(
        child: Text(
          '請設定條件並按下查詢\n注意：查詢結果不含上課時間',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (results.isEmpty) {
      return const Center(child: Text('查無符合資料'));
    }

    final planned = results.where(_isPlanned).length;
    final shown = _showPlanned
        ? results
        : results.where((c) => !_isPlanned(c)).toList();

    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '這 ${results.length} 筆都已經在預排裡了。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (planned > 0) _PlannedFilterBar(
          hidden: planned,
          showing: _showPlanned,
          onToggle: () => setState(() => _showPlanned = !_showPlanned),
        ),
        Expanded(child: _list(shown)),
      ],
    );
  }

  Widget _list(List<Course> results) {
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final course = results[index];
        final selection = widget.controller.repository.config.courseSearch
            .selectionLabel(course.selectionType);
        return ListTile(
          title: Row(
            children: [
              Flexible(child: Text(course.name)),
              if (selection.isNotEmpty) ...[
                const SizedBox(width: 8),
                SelectionTag(label: selection),
              ],
            ],
          ),
          subtitle: Text('${course.teacher} • ${course.credits}學分 • ${course.classLabel}'),
          trailing: _isPlanned(course)
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.check, size: 20),
                )
              : IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '加入預排',
                  onPressed: () => _addToPlan(course),
                ),
        );
      },
    );
  }
}

/// 「藏了幾門已排的課」那一條。
///
/// 存在的理由是**不要讓人以為搜尋壞了**：搜出 8 筆卻只看到 5 筆，
/// 第一個念頭永遠是「怎麼少了」，不是「喔那三門我加過了」。
class _PlannedFilterBar extends StatelessWidget {
  const _PlannedFilterBar({
    required this.hidden,
    required this.showing,
    required this.onToggle,
  });

  final int hidden;
  final bool showing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              showing ? '含已加入預排的 $hidden 門' : '已隱藏 $hidden 門已加入預排的課',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onToggle,
            child: Text(showing ? '隱藏' : '顯示'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.onRetry,
    this.onManual,
  });
  final String error;
  final VoidCallback onRetry;

  /// 查不到就自己打。學校那邊出問題的時候，這是唯一還排得動課的路。
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onRetry, child: const Text('重試')),
            if (onManual != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('自己打課名和時段'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}