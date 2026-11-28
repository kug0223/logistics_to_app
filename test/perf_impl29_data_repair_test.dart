// ignore_for_file: depend_on_referenced_packages
// [impl_29 · 2026-11-27] 판정292 C292-02(J1) · C292-03(Q27) · C292-04(J3) 데이터 수리.
//
//   J1  공고 업무 마감·재오픈·긴급 종료 직접 쓰기가 공고 수정 토큰(editRevision)을 올린다(rules 상태 전용 갈래와 한 셀).
//       writer 는 상태 키만 바꾸고(저장된 나머지 키 보존) 이미 그 상태면 쓰지 않는다. rules 의미는 에뮬레이터로 따로 본다
//       (records/work/perf-first-load-1/impl_29/rules_emu).
//   Q27 공고 수정 커밋 뒤 슬롯 동기화만 실패 → 승인된 내 번호(보낸 값 + 1)를 채택 · 입력 보존 · 다시 저장 회복.
//       다른 관리자가 그 사이 고쳤으면 다시 저장은 여전히 충돌로 멈춘다. **실제 화면**(AdminEditTOScreen)에서
//       Firestore·Functions 플랫폼 채널만 가짜로 바꿔(서버 = editRevision 비교 흉내) 확인한다.
//   J3  업무 정체 = 업무·시작·끝(서버 compositeId). 같은 정체만 현재 상태를 잇고, 새 정체는 마감·긴급을 비운다.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/to_management/edit_to_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/visible_text.dart';

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

final _t0 = DateTime.utc(2099, 1, 1, 0);
final _t1 = DateTime.utc(2099, 1, 1, 1);

WorkDetailData _wd(String type, {
  String? wdId,
  String start = '09:00',
  String end = '18:00',
  int wage = 12000,
  bool closed = false,
  DateTime? closedAt,
  String? closedBy,
  bool emergency = false,
  DateTime? emergencyAt,
}) =>
    WorkDetailData(
      wdId: wdId, workType: type, wage: wage, wageType: 'hourly', requiredCount: 2,
      startTime: start, endTime: end,
      isManualClosed: closed, closedAt: closedAt, closedBy: closedBy,
      isEmergencyOpen: emergency, emergencyOpenedAt: emergencyAt,
    );

// ── 실제 화면 경계(플랫폼 채널) ──────────────────────────────────────────
class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'owner-q27', username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: 'biz-q27', createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

const _origTitle = '물류센터 포장 업무 모집';
const _newTitle = '물류센터 포장 업무 모집(수정)';

TOModel _flexTo(int rev) => TOModel(
      id: 'to-q27', businessId: 'biz-q27', businessName: 'QA 물류센터', type: TOType.flex, title: _origTitle,
      description: '설명', rangeStart: DateTime(2099, 1, 10), rangeEnd: DateTime(2099, 1, 12),
      workDetails: const [
        WorkDetailData(wdId: 'wd-q27', workType: '포장', workTypeIcon: 'box', workTypeColor: '#3859E8',
            workTypeBackgroundColor: '#EEF2FF', wage: 12000, wageType: 'hourly', requiredCount: 2,
            startTime: '09:00', endTime: '18:00', order: 0),
      ],
      totalRequired: 2, editRevision: rev, publishMode: 'immediate', isPublished: true,
      creatorUID: 'owner-q27', createdAt: DateTime(2026, 11, 1));

/// 서버 흉내: callableUpdateTO 는 expectedEditRevision == 현재일 때만 커밋하고 +1 한다(index.ts STALE-EDIT 와 같은 규칙).
class _Server {
  int rev;
  final updateCalls = <int>[]; // 보낸 expectedEditRevision
  int committed = 0;
  int slotQueries = 0;
  bool Function(int n) slotQueryFails = (_) => false;
  _Server(this.rev);
}

void _stub(_Server s) {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const codec = FirebaseFirestoreHostApi.codec;
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);
  m.setMockMessageHandler('$base.queryGet', (msg) async {
    final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
    if (raw.contains('workTypes')) {
      return codec.encodeMessage(<Object?>[
        PigeonQuerySnapshot(documents: [
          PigeonDocumentSnapshot(path: 'businesses/biz-q27/workTypes/wt-1', data: <String?, Object?>{
            'businessId': 'biz-q27', 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ], documentChanges: const [], metadata: meta),
      ]);
    }
    if (raw.contains('slots')) {
      s.slotQueries++;
      if (s.slotQueryFails(s.slotQueries)) {
        return codec.encodeMessage(<Object?>['unavailable', '슬롯 조회 실패(주입)', null]);
      }
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: const [], documentChanges: const [], metadata: meta)]);
    }
    return codec.encodeMessage(<Object?>['blocked', 'query 차단', null]);
  });
  // 저장 직전 totalSlots 최신값 읽기([M-15]) — 공고 문서 한 건.
  m.setMockMessageHandler('$base.documentReferenceGet', (msg) async {
    final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
    if (!raw.contains('to-q27')) return codec.encodeMessage(<Object?>['blocked', 'doc 차단', null]);
    return codec.encodeMessage(<Object?>[
      PigeonDocumentSnapshot(path: 'tos/to-q27', data: <String?, Object?>{'totalSlots': 3, 'editRevision': s.rev}, metadata: meta),
    ]);
  });
  for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'writeBatchCommit',
    'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
    m.setMockMessageHandler('$base.$op', (msg) async => codec.encodeMessage(<Object?>['blocked', '$op 차단', null]));
  }
  m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
    const sc = StandardMessageCodec();
    final args = (sc.decodeMessage(msg) as List).first as Map;
    final name = args['functionName'];
    if (name != 'callableUpdateTO') return sc.encodeMessage(<Object?>['blocked', '$name 차단', null]);
    final expected = ((args['parameters'] as Map)['expectedEditRevision'] as num).toInt();
    s.updateCalls.add(expected);
    if (expected != s.rev) {
      return sc.encodeMessage(<Object?>['failed-precondition', 'stale',
        {'code': 'failed-precondition', 'message': '다른 관리자가 공고를 수정했습니다. 최신 내용을 다시 확인해 주세요.'}]);
    }
    s.rev++;
    s.committed++;
    return sc.encodeMessage(<Object?>[<String, Object?>{'success': true}]);
  });
}

Future<void> _settle(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester t, TOModel to) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: RoleTheme.businessAdminTheme,
      home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => AdminEditTOScreen(to: to))),
          child: const Text('host'))))),
    ),
  ));
  await t.pump();
  await t.tap(find.text('host'));
  await _settle(t);
  expect(find.byType(AdminEditTOScreen), findsOneWidget);
  final title = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == _origTitle);
  expect(title, findsOneWidget);
  await t.enterText(title, _newTitle);
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(t, 4);
}

Future<void> _tapSave(WidgetTester t) async {
  final save = findVisibleText('저장하기');
  expect(save, findsOneWidget);
  await t.tap(save);
  await _settle(t, 16);
}

void main() {
  // ── J3 · 업무 정체와 상태 승계(순수) ───────────────────────────────
  group('J3 정체 = 업무·시작·끝(서버 compositeId)', () {
    test('I29-J3-1 같은 정체는 현재 상태를 잇는다(폼 옛 사본이 다른 관리자의 마감을 덮지 않음)', () {
      final form = [_wd('상하차', wdId: 'a', wage: 13000)];
      final current = [_wd('상하차', wdId: 'a', closed: true, closedAt: _t0, closedBy: 'B')];
      final m = WorkDetailData.withStatusFrom(form, current).single;
      expect([m.isManualClosed, m.closedBy, m.closedAt, m.wage], [true, 'B', _t0, 13000]);
    });

    test('I29-J3-2 시간을 바꾼 업무는 wdId 가 같아도 새 정체 → 마감·긴급을 비운다(서버가 새 wdId 로 저장하는 것과 일치)', () {
      final form = [_wd('상하차', wdId: 'a', start: '10:00', closed: true, closedAt: _t0, closedBy: 'A', emergency: true, emergencyAt: _t0)];
      final current = [_wd('상하차', wdId: 'a', closed: true, closedAt: _t0, closedBy: 'A', emergency: true, emergencyAt: _t0)];
      final m = WorkDetailData.withStatusFrom(form, current).single;
      expect([m.isManualClosed, m.closedAt, m.closedBy, m.isEmergencyOpen, m.emergencyOpenedAt], [false, null, null, false, null]);
      expect(m.startTime, '10:00', reason: '정의는 편집본');
    });

    test('I29-J3-3 업무 이름을 바꾼 것 · 새로 넣은 것도 새 정체 → 상태 비움', () {
      final form = [_wd('분류', wdId: 'a', closed: true, closedBy: 'A'), _wd('검수', emergency: true, emergencyAt: _t0)];
      final current = [_wd('상하차', wdId: 'a', closed: true, closedBy: 'A')];
      final m = WorkDetailData.withStatusFrom(form, current);
      expect(m.every((d) => !d.isManualClosed && d.closedBy == null && !d.isEmergencyOpen), isTrue);
    });

    test('I29-J3-4 일괄 날짜 수정 — 다른 날짜의 wdId 는 달라도 같은 정체면 그 날짜의 상태, 시간 바꾼 업무는 어느 날짜든 비움', () {
      final firstDayForm = [
        _wd('상하차', wdId: 'd1a', closed: true, closedAt: _t0, closedBy: 'A'),
        _wd('분류', wdId: 'd1b', start: '13:00', closed: true, closedAt: _t0, closedBy: 'A'), // 시간 바꿈
      ];
      final otherDay = [_wd('상하차', wdId: 'd2a', emergency: true, emergencyAt: _t1), _wd('분류', wdId: 'd2b', closed: true, closedBy: 'C')];
      final r = WorkDetailData.withStatusFrom(firstDayForm, otherDay);
      expect([r[0].isManualClosed, r[0].isEmergencyOpen], [false, true], reason: '첫 날짜 마감을 퍼뜨리지 않고 그 날짜의 긴급을 잇는다');
      expect([r[1].isManualClosed, r[1].closedBy], [false, null], reason: '시간을 바꾼 업무는 새 정체');
    });

    test('I29-J3-5 화면 저장 경로 3곳이 같은 짝짓기를 쓴다(공고 수정 2 · 날짜 1 · 일괄 날짜 1)', () {
      final edit = _code('lib/screens/business_admin/to_management/edit_to_screen.dart');
      expect('WorkDetailData.listToFirestore(_workDetailsForSave)'.allMatches(edit).length, 2);
      expect(edit.contains('WorkDetailData.withStatusFrom(_workDetails, widget.to.workDetails)'), isTrue);
      expect(RegExp(r'listToCFPayload\(\s*WorkDetailData\.withStatusFrom\(updatedWorkDetails, slot\.workDetails\)\)').allMatches(edit).length, 2);
      expect(edit.contains('WorkDetailData.listToFirestore(_workDetails)'), isFalse, reason: '상태를 그대로 싣는 공고 저장이 남았다');
    });
  });

  // ── J1 · 상태 writer(순수 + 소스) ─────────────────────────────────
  group('J1 공고·슬롯 업무 상태 writer', () {
    Map<String, dynamic> raw(Map<String, dynamic> extra) => {
          'workType': 'A', 'wdId': 'wd_A', 'workTypeIcon': 'box', 'workTypeColor': '#3859E8', 'workTypeBackgroundColor': '#EEF2FF',
          'wage': 12000, 'wageType': 'hourly', 'requiredCount': 2, 'startTime': '09:00', 'endTime': '18:00', 'order': 0,
          'serverOnlyKey': 'keep-me', // 모델이 모르는 서버 키
          ...extra,
        };
    const statusKeys = {'isManualClosed', 'closedAt', 'closedBy', 'isEmergencyOpen', 'emergencyOpenedAt', 'closedReason'};
    Set<String> changedKeys(Map<String, dynamic> a, Map<String, dynamic> b) =>
        {...a.keys, ...b.keys}.where((k) => a[k] != b[k] || a.containsKey(k) != b.containsKey(k)).toSet();

    test('I29-J1-1 마감 — 상태 키만 바뀌고 저장된 나머지 키(서버 키·기본값 표기 없음)는 그대로', () {
      final cur = [raw({})];
      final r = FirestoreService.applyWorkDetailUpdates(cur, {'A_09:00_18:00'},
          (d) => d.copyWith(isManualClosed: true, closedAt: _t1, closedBy: 'owner1'));
      final after = r.raw.single as Map<String, dynamic>;
      expect(r.changed, isTrue);
      expect(changedKeys(cur.single, after).difference(statusKeys), isEmpty,
          reason: 'rules 업무별 검사(상태 키 외 변경 0)와 같은 뜻 — 예전 toMap 통째 직렬화는 baseHourlyWageMode 를 더하고 서버 키를 지웠다');
      expect(after['serverOnlyKey'], 'keep-me');
      expect(after['closedBy'], 'owner1');
    });

    test('I29-J1-2 서버 자동 마감 재오픈 — closedAt 과 closedReason 을 함께 지운다', () {
      final cur = [raw({'closedAt': Timestamp.fromDate(_t0), 'closedReason': 'TIME_EXPIRED'})];
      final r = FirestoreService.applyWorkDetailUpdates(cur, {'A_09:00_18:00'}, (d) => d.copyWith(clearClosedAt: true));
      final after = r.raw.single as Map<String, dynamic>;
      expect(after.containsKey('closedAt') || after.containsKey('closedReason'), isFalse);
      expect(changedKeys(cur.single, after).difference(statusKeys), isEmpty);
    });

    test('I29-J1-3 이미 그 상태(열린 업무 재오픈 · 긴급 아닌 업무 긴급 종료)면 쓰지 않는다 — 토큰만 올리는 빈 쓰기 0', () {
      final cur = [raw({})];
      expect(FirestoreService.applyWorkDetailUpdates(cur, {'A_09:00_18:00'}, (d) => d.copyWith(clearClosedAt: true)).changed, isFalse);
      expect(FirestoreService.applyWorkDetailUpdates(cur, {'A_09:00_18:00'}, (d) => d.copyWith(clearEmergency: true)).changed, isFalse);
    });

    test('I29-J1-4 writer 는 공고·슬롯 모두 같은 거래에서 토큰 = 최신 + 1 · 바뀐 것이 있을 때만 쓴다', () {
      final svc = _code('lib/services/firestore_service.dart');
      final i = svc.indexOf('_updateWorkDetailsInArrayAtomic({');
      final body = svc.substring(i, svc.indexOf('} catch (e) {', i));
      expect(body.contains('if (next.applied.isNotEmpty && next.changed) {'), isTrue);
      expect(RegExp(r"'editRevision': \(\(\(snap\.data\(\) as Map<String, dynamic>\)\['editRevision'\] as num\?\)\?\.toInt\(\) \?\? 0\) \+ 1")
          .hasMatch(body), isTrue);
      expect(RegExp(r"if\s*\(slotId != null\)\s*'editRevision'").hasMatch(body), isFalse, reason: '공고 문서를 빼던 조건이 남았다');
    });

    test('I29-J1-5 rules — 공고 업무 상태 직접 쓰기는 상태 전용 문(토큰 +1 · 업무 수 같음 · 업무별 상태 키만 · 상한 12)', () {
      final rules = File('firestore.rules').readAsStringSync().replaceAll('\r\n', '\n');
      expect(rules.contains("affectedKeys().hasOnly(['workDetails'])"), isFalse, reason: 'workDetails 단독 허용(토큰 없이 덮는 길)이 남았다');
      expect(rules.contains("affectedKeys().hasOnly(['workDetails', 'editRevision'])"), isTrue);
      expect(rules.contains("affectedKeys().hasAll(['workDetails', 'editRevision'])"), isTrue);
      expect(rules.contains("request.resource.data.editRevision == resource.data.get('editRevision', 0) + 1"), isTrue);
      expect(rules.contains('request.resource.data.workDetails.size() <= 12'), isTrue);
      expect(RegExp(r'toWdStatusOnlyAt\(\d+\)').allMatches(rules).length, 12, reason: '자리 0–11');
      for (final k in const ['isManualClosed', 'closedAt', 'closedBy', 'isEmergencyOpen', 'emergencyOpenedAt', 'closedReason']) {
        expect(rules.contains("'$k'"), isTrue, reason: k);
      }
      expect(rules.contains("nw[i].get('closedBy', null) == request.auth.uid"), isTrue, reason: '남의 이름으로 마감 기록 0');
    });
  });

  // ── Q27 · 실제 화면 ─────────────────────────────────────────────
  group('Q27 공고 수정 커밋 뒤 슬롯 동기화 실패 → 다시 저장(실제 AdminEditTOScreen · 플랫폼 채널만 가짜)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    setUpAll(() async {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
    });

    testWidgets('I29-Q27-a 내 수정 커밋 → 슬롯 동기화 실패 → 다시 저장은 승인된 번호(보낸 값 + 1)로 가고 회복된다 · 입력 보존', (t) async {
      final server = _Server(3)..slotQueryFails = (n) => n == 2; // 1 = 화면 열기, 2 = 첫 저장 동기화(실패), 3 = 다시 저장
      _stub(server);
      await _open(t, _flexTo(3));
      await _tapSave(t);
      expect(server.updateCalls, [3]);
      expect(server.rev, 4, reason: '공고 수정은 커밋됐다');
      expect(find.byType(AdminEditTOScreen), findsOneWidget, reason: '실패 안내 뒤 화면에 남는다');
      expect(find.byWidgetPredicate((w) => w is EditableText && w.controller.text == _newTitle), findsOneWidget, reason: '입력 보존');
      await _settle(t, 60); // 토스트 사라짐
      await _tapSave(t);
      expect(server.updateCalls, [3, 4], reason: '고치기 전에는 두 번째도 3(열 때 번호) → STALE-EDIT');
      expect(server.rev, 5);
      expect(findVisibleText('수정 내용 충돌'), findsNothing);
      await _settle(t, 30);
      expect(find.byType(AdminEditTOScreen), findsNothing, reason: '동기화 성공 → 화면을 닫는다');
    });

    testWidgets('I29-Q27-b 그 사이 다른 관리자가 공고를 고쳤으면 다시 저장은 여전히 충돌로 멈춘다(서버 최신값을 채택하지 않음)', (t) async {
      final server = _Server(3)..slotQueryFails = (n) => n == 2;
      _stub(server);
      await _open(t, _flexTo(3));
      await _tapSave(t);
      expect(server.rev, 4);
      server.rev = 5; // 다른 관리자 저장(또는 J1 업무 마감)으로 토큰이 올랐다
      await _settle(t, 60);
      await _tapSave(t);
      expect(server.updateCalls, [3, 4]);
      expect(server.rev, 5, reason: '옛 폼은 덮지 못한다');
      expect(findVisibleText('수정 내용 충돌'), findsOneWidget);
    });

    testWidgets('I29-Q27-c 슬롯 동기화가 두 번 연속 실패해도 매번 승인 번호를 이어 받는다(세 번째에 회복)', (t) async {
      final server = _Server(7)..slotQueryFails = (n) => n == 2 || n == 3;
      _stub(server);
      await _open(t, _flexTo(7));
      await _tapSave(t);
      await _settle(t, 60);
      await _tapSave(t);
      await _settle(t, 60);
      await _tapSave(t);
      expect(server.updateCalls, [7, 8, 9]);
      expect(server.committed, 3);
      await _settle(t, 30);
      expect(find.byType(AdminEditTOScreen), findsNothing);
    });
  });
}
