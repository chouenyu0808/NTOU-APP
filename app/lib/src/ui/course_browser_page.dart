import 'dart:async';

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
    required this.year,
    required this.semester,
  });

  final AppController controller;
  final PlanStore planStore;

  /// 要加進**哪一份**預排。
  ///
  /// **一定要由呼叫端指定，不能自己去讀 `controller.year`。** 預排最主要的
  /// 用途就是排下學期，而 `controller.year` 是登入時那個當學期 —— 兩者一旦
  /// 不同，使用者在這一頁加的課會被寫進他沒在看的那份預排，回到預排頁
  /// 一門都不會出現，而畫面上完全沒有線索。
  final String year;
  final String semester;

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

  /// 要不要顯示跟預排撞在一起的課。
  ///
  /// **預設是顯示。** 上課時間是捲到那一列才去抓的，所以「衝堂」這件事一開始
  /// 對每一列都還不知道，是一列一列陸續確定的。預設隱藏的話，列會在探測完成
  /// 的當下從使用者手指底下消失 —— 他正在看的東西自己不見了。
  bool _showClashing = true;

  // ---------- 每一列的上課時間（拿來標衝堂） ----------
  //
  // **查詢結果那 17 欄沒有上課時間**，所以每一門都得走一次「點課號 →
  // fn_open → GET 詳細頁」才知道它排在哪幾節。一次把整頁結果都抓完是不行的：
  // 搜「計算機」會回好幾十筆，那是上百次請求，而選課尖峰時學校的機器正忙。
  //
  // 所以只抓**使用者真的捲到的那幾列**（`itemBuilder` 只會為看得見的列跑），
  // 一次一門排隊送，抓過的存起來不重抓。

  /// 課號＋班別 → 那門課的時段。抓成功才會進來。
  final Map<String, List<TimeSlot>> _slots = {};

  /// 抓過但失敗（或學校根本沒給時間）的。
  ///
  /// 跟「還沒抓」要分得開：都當成「沒有時段」的話，畫面上會用一模一樣的樣子
  /// 表達「不衝堂」和「不知道衝不衝」—— 而前者是承諾，後者不是。
  final Set<String> _slotsUnknown = {};

  final List<Course> _probeQueue = [];
  bool _probing = false;

  /// 這一批總共要查幾門（給進度用）。
  int _probeTotal = 0;

  /// 一次搜尋最多主動查幾門的時間。
  ///
  /// 剩下的仍然會在使用者捲到時補查。設上限是因為全校範圍的查詢可能回上百筆，
  /// 每一門兩次請求 —— 那在選課尖峰時是對學校機器的一次小型洪水，
  /// 而使用者八成只看前面幾十筆。
  static const int _probeEagerLimit = 60;

  /// 換一次搜尋就 +1。舊的探測回來時對不上就丟掉 ——
  /// 不然上一次搜尋的結果會蓋到這一次的列上。
  int _probeToken = 0;

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
      _resetProbes();
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
      _resetProbes();
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
    final plan = await widget.planStore.read(widget.year, widget.semester);
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
    _resetProbes();
    if (isEmptyResult(html)) {
      _results = const [];
    } else {
      _results = parseCourseList(html);
      // 先把整批的上課時間查起來，不要等使用者捲到才一列一列等。
      _probeAll(_results!);
    }
  }

  // ---------- 衝堂探測 ----------

  String _keyOf(Course c) => PlannedCourse(course: c).key;

  /// 搜尋一有結果就把整批排進去查，不要等使用者捲到。
  ///
  /// 原本是捲到哪一列才查哪一列，省請求，但畫面上就是一路「查上課時間中…」
  /// 跟著手指跑 —— 課一多就等到不想等。改成搜尋完就在背景一門一門查完，
  /// 使用者捲下去的時候多半已經有答案了。
  void _probeAll(List<Course> results) {
    for (final c in results.take(_probeEagerLimit)) {
      _ensureSlots(c);
    }
    _probeTotal = _probeQueue.length;
  }

  /// 這一列還不知道時間的話，排進佇列。
  void _ensureSlots(Course course) {
    final key = _keyOf(course);
    if (_slots.containsKey(key) ||
        _slotsUnknown.contains(key) ||
        _probeQueue.any((c) => _keyOf(c) == key)) {
      return;
    }
    _probeQueue.add(course);
    // itemBuilder 正在 build，不能在這裡 setState —— 下一格再開工。
    scheduleMicrotask(_drainProbeQueue);
  }

  Future<void> _drainProbeQueue() async {
    if (_probing) return;
    _probing = true;
    final token = _probeToken;

    while (_probeQueue.isNotEmpty && mounted && token == _probeToken) {
      final course = _probeQueue.removeAt(0);
      final key = _keyOf(course);
      var slots = const <TimeSlot>[];
      try {
        // 同一個課號常有 A班／B班，時間不一樣 —— 要帶班別和老師才認得出這一列。
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
        // 探測失敗只影響「標不標得出衝堂」，不該讓整頁跳錯誤 ——
        // 使用者是來找課的，不是來看錯誤訊息的。
        debugPrint('探測上課時間失敗（${course.code}）：$e');
      }
      if (!mounted || token != _probeToken) break;
      setState(() {
        if (slots.isEmpty) {
          _slotsUnknown.add(key);
        } else {
          _slots[key] = slots;
        }
      });
    }
    _probing = false;
    if (mounted && _probeQueue.isEmpty && token == _probeToken) {
      setState(() => _probeTotal = 0);
    }
  }

  /// 換搜尋條件時把探測結果丟掉。
  void _resetProbes() {
    _probeToken++;
    _probeQueue.clear();
    _probeTotal = 0;
    _slots.clear();
    _slotsUnknown.clear();
  }

  /// 這門課跟預排裡的哪一門撞在哪幾節。不衝突或還不知道就回 null。
  ({PlannedCourse other, List<TimeSlot> slots})? _clashOf(Course course) {
    final plan = _plan;
    final mine = _slots[_keyOf(course)];
    if (plan == null || mine == null) return null;

    final key = _keyOf(course);
    for (final planned in plan.courses) {
      // 自己跟自己不算 —— 已加入的課還會出現在清單上（切「顯示已排」時）。
      if (planned.key == key) continue;
      final hit = planned.slots.where(mine.contains).toList()..sort();
      if (hit.isNotEmpty) return (other: planned, slots: hit);
    }
    return null;
  }

  Future<void> _addToPlan(Course course) async {
    final plan = await widget.planStore.read(widget.year, widget.semester) ??
        CoursePlan(year: widget.year, semester: widget.semester);

    // 「同一門課」是指**同一班**，不是同課號。真實資料裡 B57011RQ 計算機概論
    // 有 1年A班和 1年B班，兩列課號和課名都一樣 —— 只比課號的話，
    // 使用者連想比較兩個班都做不到，而且訊息還說「已經在預排清單中了」。
    //
    // 這個判斷跟 [PlannedCourse.key] 是同一套 —— 兩邊分歧過一次，
    // 症狀是加得進去但編輯時段會蓋到另一班。
    if (plan.contains(PlannedCourse(course: course).key)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('這門課已經在預排清單中了')),
      );
      return;
    }

    setState(() => _busy = true);

    // 查詢結果那張表（17 欄）**沒有上課時間**，要點進課號的詳細頁才看得到。
    //
    // 標衝堂的探測多半已經抓過這一門了 —— 有就直接用，不要再打一次學校的
    // 伺服器問同一個問題。
    var slots = _slots[_keyOf(course)] ?? const <TimeSlot>[];
    try {
      if (slots.isEmpty) {
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
        // `key` 認的是「課號＋班別」，所以 `update` 只會動到剛加的那一筆，
        // 不會碰到同課號的另一班。
        final withSlots = newPlan.update(
          planned.copyWith(slots: picked, slotsAreManual: true),
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
    // 用 PlannedCourse 算，不要在這裡重寫一次 key 的組法 ——
    // 兩處分歧的話衝堂會比對到錯的那一筆（或整個比不到）。
    final key = PlannedCourse(course: course).key;
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
    final added = await showDialog<PlannedCourse>(
      context: context,
      builder: (_) => const AddCourseDialog(),
    );
    if (added == null || !mounted) return;

    final plan = await widget.planStore.read(widget.year, widget.semester) ??
        CoursePlan(year: widget.year, semester: widget.semester);

    // 走 `add()` 而不是自己接在後面 —— 手動輸入沒有課號，同一個課名打兩次
    // 會變成兩筆共用同一個 key 的課，之後編輯時段或刪除會兩筆一起動。
    if (plan.contains(added.key)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('預排裡已經有「${added.course.name}」了')),
      );
      return;
    }

    final newPlan = plan.add(added);
    await widget.planStore.write(newPlan);
    await _loadPlan();
    if (!mounted) return;
    _announce(added.course, added.slots, newPlan);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = widget.year;
    final semester = widget.semester;

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
    var shown = _showPlanned
        ? results
        : results.where((c) => !_isPlanned(c)).toList();

    // 只算**已經查到時間而且真的撞到**的。還沒探測到的列不算衝堂 ——
    // 那是「還不知道」，把它藏起來等於用一個我們沒查證的理由把課擋掉。
    final clashing = shown.where((c) => _clashOf(c) != null).length;
    if (!_showClashing) {
      shown = shown.where((c) => _clashOf(c) == null).toList();
    }

    return Column(
      children: [
        if (planned > 0)
          _FilterBar(
            icon: Icons.filter_alt_outlined,
            label: _showPlanned
                ? '含已加入預排的 $planned 門'
                : '已隱藏 $planned 門已加入預排的課',
            showing: _showPlanned,
            onToggle: () => setState(() => _showPlanned = !_showPlanned),
          ),
        if (clashing > 0)
          _FilterBar(
            icon: Icons.error_outline,
            label: _showClashing
                ? '其中 $clashing 門跟預排撞堂'
                : '已隱藏 $clashing 門撞堂的課',
            showing: _showClashing,
            onToggle: () => setState(() => _showClashing = !_showClashing),
          ),
        if (_probeTotal > 0 && _probeQueue.isNotEmpty)
          _ProbeProgress(
            done: _probeTotal - _probeQueue.length,
            total: _probeTotal,
          ),
        // **開關要一直在**，就算濾到一筆都不剩。
        // 收起來之後整頁變空白又沒有開關的話，使用者就切不回來了。
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      clashing > 0 && !_showClashing
                          ? '這 ${results.length} 筆不是已經在預排裡，'
                              '就是跟預排撞在一起。'
                          : '這 ${results.length} 筆都已經在預排裡了。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _list(shown),
        ),
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
        // 捲到才抓時間 —— build 的時候順手排隊。
        _ensureSlots(course);
        final clash = _clashOf(course);

        return ListTile(
          isThreeLine: true,
          title: Row(
            children: [
              Flexible(child: Text(course.name)),
              if (selection.isNotEmpty) ...[
                const SizedBox(width: 8),
                SelectionTag(label: selection),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${course.teacher} • ${course.credits}學分 • ${course.classLabel}'),
              const SizedBox(height: 2),
              _ClashHint(
                clash: clash,
                slots: _slots[_keyOf(course)],
                unknown: _slotsUnknown.contains(_keyOf(course)),
              ),
            ],
          ),
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

/// 清單上方那一條「藏了幾門、要不要顯示」。
///
/// 存在的理由是**不要讓人以為搜尋壞了**：搜出 8 筆卻只看到 5 筆，
/// 第一個念頭永遠是「怎麼少了」，不是「喔那三門我加過了」。
///
/// 目前有兩條：已加入預排的、以及跟預排撞堂的。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.icon,
    required this.label,
    required this.showing,
    required this.onToggle,
  });

  final IconData icon;
  final String label;
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
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
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

/// 一列上的衝堂標示。
///
/// **三種狀態要分得開**：還在查、查不到、以及查到了。把「查不到」畫成
/// 跟「沒衝堂」一樣的空白，等於用沉默承諾了一件我們其實不知道的事 ——
/// 使用者會照著加課，然後在預排頁才發現撞在一起。
class _ClashHint extends StatelessWidget {
  const _ClashHint({
    required this.clash,
    required this.slots,
    required this.unknown,
  });

  final ({PlannedCourse other, List<TimeSlot> slots})? clash;
  final List<TimeSlot>? slots;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;

    if (clash case final c?) {
      final where = c.slots.map((s) => s.toString()).join('、');
      return Row(
        children: [
          Icon(Icons.error_outline, size: 14, color: scheme.error),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '和「${c.other.course.name}」撞在 $where',
              style: small?.copyWith(color: scheme.error),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (slots != null) {
      final when = slots!.map((s) => s.toString()).join('、');
      return Text(when, style: small?.copyWith(color: scheme.onSurfaceVariant));
    }

    if (unknown) {
      return Text('查不到上課時間',
          style: small?.copyWith(color: scheme.onSurfaceVariant));
    }

    return Text('查上課時間中…',
        style: small?.copyWith(color: scheme.onSurfaceVariant));
  }
}


/// 「正在查上課時間」那一條。
///
/// 查詢結果本身沒有上課時間，得一門一門去問學校 —— 這會花上幾秒到十幾秒。
/// 不講的話，畫面上是一整排「查上課時間中…」慢慢變，看起來像卡住了。
class _ProbeProgress extends StatelessWidget {
  const _ProbeProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: total == 0 ? null : done / total,
            ),
          ),
          const SizedBox(width: 10),
          Text('正在查上課時間 $done / $total',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
