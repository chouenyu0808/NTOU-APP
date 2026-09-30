import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/exceptions.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/credential_store.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:ntou_app/src/ui/app_controller.dart';

import 'fake_ais.dart';

TimetableResult _result(String semester) => TimetableResult(
  year: '115',
  semester: semester,
  isEmpty: false,
  fetchedAt: DateTime(2026, 9, 19),
  courses: [Course(name: '學期$semester的課')],
);

class _Repository extends AisRepository {
  _Repository() : super(config: testConfig(), cache: TimetableCache());

  final requests = <({String semester, Completer<TimetableResult> result})>[];
  final cachedResults = <String, Future<TimetableResult?>>{};

  @override
  Future<TimetableResult?> cached(String year, String semester) async =>
      cachedResults[semester];

  @override
  Future<TimetableResult> fetchTimetable({
    required String year,
    required String semester,
  }) {
    final result = Completer<TimetableResult>();
    requests.add((semester: semester, result: result));
    return result.future;
  }
}

void main() {
  late _Repository repo;
  late AppController controller;
  setUp(() {
    repo = _Repository();
    controller = AppController(repository: repo, credentials: CredentialStore())
      ..year = '115'
      ..semester = '1'
      ..phase = AppPhase.ready
      ..timetable = _result('1');
  });
  tearDown(() => controller.dispose());

  test('新學期無快取且查詢失敗，不留下舊學期的課', () async {
    final pending = controller.selectSemester(newSemester: '2');
    await Future<void>.delayed(Duration.zero);
    expect(controller.timetable, isNull);
    repo.requests.single.result.completeError(const AisMessage('查詢失敗'));
    await pending;
    expect(controller.timetable, isNull);
    expect(controller.error, '查詢失敗');
    expect(controller.loadingTimetable, isFalse);
  });

  for (final fails in [false, true]) {
    test('快速切換學期時舊請求${fails ? '失敗' : '成功'}都不覆蓋新狀態', () async {
      final old = controller.refreshTimetable();
      await Future<void>.delayed(Duration.zero);
      final latest = controller.selectSemester(newSemester: '2');
      await Future<void>.delayed(Duration.zero);
      expect(repo.requests, hasLength(1), reason: '查詢必須依序使用 WebForms 狀態');
      if (fails) {
        repo.requests.first.result.completeError(const SessionExpired('舊請求過期'));
      } else {
        repo.requests.first.result.complete(_result('1'));
      }
      await old;
      await Future<void>.delayed(Duration.zero);
      expect(controller.timetable, isNull);
      expect(controller.error, isNull);
      expect(controller.phase, AppPhase.ready);
      expect(controller.loadingTimetable, isTrue);
      expect(repo.requests.last.semester, '2');
      repo.requests.last.result.complete(_result('2'));
      await latest;
      expect(controller.timetable!.semester, '2');
      expect(controller.loadingTimetable, isFalse);
    });
  }

  test('晚回來的舊學期快取不覆蓋最新選擇', () async {
    controller.phase = AppPhase.loggedOut;
    final delayed = Completer<TimetableResult?>();
    repo.cachedResults['1'] = delayed.future;
    repo.cachedResults['2'] = Future.value(_result('2'));
    final old = controller.selectSemester(newSemester: '1');
    await controller.selectSemester(newSemester: '2');
    delayed.complete(_result('1'));
    await old;
    expect(controller.timetable!.semester, '2');
  });
}
