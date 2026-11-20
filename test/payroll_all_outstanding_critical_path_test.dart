// [PAYROLL-ALL-UNTRANSFERRED-CRITICAL-PATH] 홈 '급여 미이체' → 급여 지급 현황(전체 미이체 모드).
//
// 실제 화면(PayrollPaymentDashboardScreen(showAllOutstanding: true))을 띄우고
// callable 채널만 가짜 서버로 바꾼다. 서버는 요청이 **도착한 시각**의 데이터로 답하고,
// 함수·종류별 합성 지연을 준다. 각 호출의 입력(사업장·기간·급여상태·대상 근로자)과
// 도착·응답 시각을 기록하고, 탭(첫 프레임)에서 **정확한 내용**이 보일 때까지의 시간을 잰다.
//
// 정확한 내용 = 전체 미이체 머리말 금액·건수 + 근로자 카드마다 기대한 지급 준비 표시.
//   지급 준비를 모르는 카드가 '이체처리' 버튼(=지급 가능처럼 보임)을 받으면 부정확이다.
import 'support/visible_text.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

const _ch =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _biz = 'BIZ';

/// 화면이 쓰는 것과 같은 식으로 만든 전 기간 구간 시작점(730일 단위).
final _farPast = DateTime(2020, 1, 1);
int _chunkIndexOf(int startMs) {
  for (var i = 0; i < 10; i++) {
    if (_farPast.add(Duration(days: 730 * i)).millisecondsSinceEpoch ==
        startMs) {
      return i;
    }
  }
  return -1;
}

final _monthStartMs = DateTime(2026, 10, 1).millisecondsSinceEpoch;

Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// 서버 attendance 한 건.
class _Rec {
  _Rec(this.id, this.uid, this.workDate, this.net,
      {this.wageStatus = 'confirmed', DateTime? due})
      : due = due ?? workDate.add(const Duration(days: 5));
  final String id, uid, wageStatus;
  final DateTime workDate, due;
  final int net;
  Map<String, Object?> wire() => {
        'id': id, 'userId': uid, 'businessId': _biz, 'businessName': 'QA 사업장',
        'workDate': _ts(workDate), 'workType': 'QA', 'status': 'present',
        'wageStatus': wageStatus, 'adminConfirmed': true,
        'createdAt': _ts(workDate), 'paymentDueDate': _ts(due),
        'wageDetail': {'totalAmount': net, 'wageType': 'daily'},
        'wageAccountSourceBankAccountVersion': 1,
        'wageAccountSourceBankbookDocumentVersion': 1,
      };
}

class _Call {
  _Call(this.fn, this.kind, this.params, this.at);
  final String fn, kind;
  final Map<Object?, Object?> params;
  final int at;
  int? doneAt;
  String? error;
  @override
  String toString() {
    final p = <String>[];
    if (params['businessId'] != null) p.add('biz=${params['businessId']}');
    if (params['startMs'] != null) {
      final s = DateTime.fromMillisecondsSinceEpoch(params['startMs'] as int);
      final e = DateTime.fromMillisecondsSinceEpoch(params['endMs'] as int);
      p.add('[${FormatHelper.formatDateDot(s)}, ${FormatHelper.formatDateDot(e)})');
    }
    if (params['wageStatus'] != null) p.add('wage=${params['wageStatus']}');
    if (params['workerUids'] != null) {
      p.add('uids=${(params['workerUids'] as List).length}');
    }
    if (params['uids'] != null) p.add('names=${(params['uids'] as List).length}');
    return '$kind @$at→${doneAt ?? '-'}ms ${error ?? 'ok'} ${p.join(' ')}';
  }
}

int _now = 0;

class _Srv {
  _Srv(this.db);

  /// 도착 시각의 서버 데이터.
  List<_Rec> Function() db;
  final calls = <_Call>[];

  int Function(_Call c) delay = (c) => switch (c.kind) {
        'readiness' => 250,
        'names' => 120,
        'other' => 500,
        _ => 300,
      };
  String? Function(_Call c) failCode = (_) => null;

  /// 근로자별 서버 판정. null 이면 READY_AUTO.
  Map<String, String> state = {};

  // [PAYROLL-V3-RECOVERY] 응답 조작 손잡이 — 이름(없으면 그 사람은 응답에서 빠진다)·사람 번호,
  //   지급 준비에서 빠지는 사람·서버가 failed 로 돌려주는 사람·묻지 않은 사람의 덤 응답·역순 응답.
  String? Function(String uid) nameOf = (u) => 'N$u';
  Map<String, int> personNo = {};
  Set<String> omitReadiness = {};
  Set<String> failedReadiness = {};
  Map<String, String> extraReadiness = {};
  bool reverseReadiness = false;

  String _kind(String fn, Map p) {
    if (fn == 'callableGetAdminAttendances') {
      final s = p['startMs'] as int?;
      // [PAYROLL-V3-RECOVERY] 전 기간 구간이 아니면 월 조회다(이번 달 고정 → 아무 달).
      if (s == _monthStartMs || _chunkIndexOf(s ?? 0) < 0) {
        return 'month-${p['wageStatus']}';
      }
      return 'chunk${_chunkIndexOf(s ?? 0)}';
    }
    if (fn == 'callableGetPayrollReadinessBatch') return 'readiness';
    if (fn == 'callableGetUsersBatch') return 'names';
    if (fn == 'callableMarkTransferredBatch') return 'mark';
    return 'other';
  }

  Map<String, Object?> _readinessOf(String u, String st) => {
        'ready': st.startsWith('READY'),
        'state': st,
        'actor': st.startsWith('READY') ? 'NONE' : 'WORKER_OR_REVIEW',
        'accountVersion': 1,
        'bankbookVersion': 1,
      };

  Future<ByteData?> handle(ByteData? data) async {
    final args = (const StandardMessageCodec().decodeMessage(data) as List)
        .first as Map;
    final fn = args['functionName'] as String;
    final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
    final c = _Call(fn, _kind(fn, p), p, _now);
    calls.add(c);
    final rows = db(); // 도착 시각의 데이터
    await Future<void>.delayed(Duration(milliseconds: delay(c)));
    c.doneAt = _now;
    final code = failCode(c);
    if (code != null) {
      c.error = code;
      return const StandardMessageCodec()
          .encodeMessage(<Object?>[code, 'mock', null]);
    }
    Object? body;
    switch (c.kind) {
      case 'names':
        body = {
          'users': {
            for (final u in (p['uids'] as List).cast<String>())
              if (nameOf(u) != null)
                u: {
                  'name': nameOf(u), 'username': u, 'role': 'USER',
                  if (personNo[u] != null) 'personNo': personNo[u],
                }
          }
        };
      case 'readiness':
        var asked = (p['workerUids'] as List).cast<String>().toList();
        if (reverseReadiness) asked = asked.reversed.toList();
        body = {
          'readiness': {
            for (final u in asked)
              if (!omitReadiness.contains(u) && !failedReadiness.contains(u))
                u: _readinessOf(u, state[u] ?? 'READY_AUTO'),
            for (final e in extraReadiness.entries)
              if (!asked.contains(e.key)) e.key: _readinessOf(e.key, e.value),
          },
          'failed': [
            for (final u in asked)
              if (failedReadiness.contains(u)) u
          ],
        };
      case 'mark':
        body = {
          'processed': (p['attendanceIds'] as List).length,
          'skipped': <String>[], 'alreadyTransferred': <String>[], 'blocked': {},
        };
      case 'other':
        body = {'requests': <Object?>[], 'items': <Object?>[]};
      default:
        final s = p['startMs'] as int, e = p['endMs'] as int;
        final ws = p['wageStatus'] as String?;
        body = {
          'items': [
            for (final r in rows)
              if (r.workDate.millisecondsSinceEpoch >= s &&
                  r.workDate.millisecondsSinceEpoch < e &&
                  (ws == null || r.wageStatus == ws))
                r.wire()
          ],
          'limitReached': false,
        };
    }
    return const StandardMessageCodec().encodeMessage(<Object?>[body]);
  }

  List<_Call> of(String kindPrefix) =>
      calls.where((c) => c.kind.startsWith(kindPrefix)).toList();
}

Future<void> _mount(WidgetTester t, _Srv s,
    {bool allOutstanding = true, int year = 2026, int month = 10,
    Size size = const Size(1080, 4000), double dpr = 1.0, double textScale = 1.0}) async {
  _now = 0;
  t.view.physicalSize = size;
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, s.handle);
  addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      // [PAYROLL-V3-NAME] 좁은 화면·글자 확대 조건(기본 1.0 = 예전과 같음).
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: PayrollPaymentDashboardScreen(
        businessId: _biz, businessName: 'QA 사업장',
        year: year, month: month, showAllOutstanding: allOutstanding,
      ),
    ),
  ));
}

Future<void> _advance(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 10) {
    await t.pump(const Duration(milliseconds: 10));
    _now += 10;
  }
}

/// 화면이 지금 말하는 것.
class _Seen {
  _Seen(WidgetTester t)
      : header = findVisibleText('전체 미이체').evaluate().isNotEmpty,
        empty = findVisibleText('미이체 급여가 없습니다').evaluate().isNotEmpty,
        inlineError = findVisibleText('급여 정보를 불러오지 못했습니다').evaluate().isNotEmpty,
        screenError = findVisibleText('급여 현황을 불러오지 못했습니다.').evaluate().isNotEmpty,
        review = findVisibleText('통장사본 확인').evaluate().length,
        view = findVisibleText('통장사본 보기').evaluate().length,
        unknown = findVisibleText('지급 준비 상태 조회 실패').evaluate().length,
        payable = findVisibleText('이체처리').evaluate().length,
        // [PAYROLL-V3-CONNECTED] 판정 없는 카드 = 통장사본 보기 없이 이체처리만 단 카드.
        //   예전에는 준비된 카드에 이체처리가 아예 없어서(62507e1 이후 통장사본 버튼이 가렸다)
        //   '이체처리 0' 이 곧 정확이었다. 이제 준비된 카드는 보기 + 이체처리를 함께 단다.
        bare = findVisibleText('이체처리').evaluate().length - findVisibleText('통장사본 보기').evaluate().length,
        texts = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data ?? '')
            .toList();
  final bool header, empty, inlineError, screenError;
  final int review, view, unknown, payable, bare;
  final List<String> texts;
  /// [CLOSEOUT.2] 목록을 끝까지 내리며 본 판정 없는 카드 최댓값(scanAll 이 채운다).
  int scanBare = 0;
  bool shows(String s) => texts.contains(s);
  @override
  String toString() =>
      'header=$header empty=$empty inlineErr=$inlineError screenErr=$screenError '
      '확인=$review 보기=$view 조회실패=$unknown 이체처리=$payable 판정없음=$bare';
}

/// 정확한 내용이 보일 때까지 기다린 시간(ms). 끝까지 안 되면 -1.
Future<int> _untilAccurate(WidgetTester t, bool Function(_Seen s) ok,
    {int maxMs = 6000}) async {
  for (var e = 0; e <= maxMs; e += 10) {
    if (ok(_Seen(t))) return _now;
    await _advance(t, 10);
  }
  return -1;
}

// ── 기본 표본: 세 근로자, 세 구간 ────────────────────────────────────────────
//   A: 이번 달(10월) — 월 조회에도, 전 기간 조회 마지막 구간에도 나온다.
//   B: 2024-06 — 전 기간 조회 셋째 구간에만. 통장사본 수동 확인 대상.
//   C: 2021-05 — 첫 구간에만.
//   D: 이번 달 이체완료 — 월 조회(transferred)에만.
List<_Rec> _base(String p) => [
      _Rec('${p}a1', '${p}A', DateTime(2026, 10, 10), 100000),
      _Rec('${p}b1', '${p}B', DateTime(2024, 6, 10), 50000),
      _Rec('${p}c1', '${p}C', DateTime(2021, 5, 1), 30000),
      _Rec('${p}d1', '${p}D', DateTime(2026, 10, 3), 70000,
          wageStatus: 'transferred'),
    ];

bool _accurate3(_Seen s, {int total = 180000, int groups = 3}) =>
    s.header &&
    s.shows(FormatHelper.formatWage(total)) &&
    s.shows('$groups건') &&
    s.review == 1 &&
    s.view == groups - 1 &&
    s.unknown == 0 &&
    // [PAYROLL-V3-CONNECTED 기대 갱신] 예전: payable == 0. 준비된 카드(수동 확인 1명 제외)는
    //   이체처리를 단다 — 배너 도착 목록에서 이체 처리 입구가 다시 생겼다. 판정 없는 카드는 여전히 0.
    s.payable == groups - 1 &&
    s.bare == 0;

void _log(String name, _Srv s, _Seen seen, int ms) {
  // ignore: avoid_print
  print('── $name  accurate@${ms}ms  $seen');
  for (final c in s.calls) {
    // ignore: avoid_print
    print('   $c');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('PAO-1 정상 — 조회 입력·순서·대기 구간 기록, 정확한 내용', (t) async {
    final s = _Srv(() => _base('n1'))..state = {'n1B': 'BANK_OCR_UNCERTAIN'};
    await _mount(t, s);
    final ms = await _untilAccurate(t, _accurate3);
    await _advance(t, 1500);
    final seen = _Seen(t);
    _log('PAO-1', s, seen, ms);
    expect(ms, greaterThan(0));
    // 합성 지연(근태 300·지급 준비 250·이름 120ms): 직렬 구간이면 1450ms 였다.
    expect(ms, lessThanOrEqualTo(600));
    expect(_accurate3(seen), isTrue);
    // 네 구간: 같은 사업장, 끊김·겹침 없는 반열림 구간, 모두 confirmed.
    final chunks = s.of('chunk');
    expect(chunks.map((c) => c.kind).toSet(), {'chunk0', 'chunk1', 'chunk2', 'chunk3'});
    expect(chunks.length, 4);
    for (final c in chunks) {
      expect(c.params['businessId'], _biz);
      expect(c.params['wageStatus'], 'confirmed');
    }
    chunks.sort((a, b) => (a.params['startMs'] as int).compareTo(b.params['startMs'] as int));
    for (var i = 1; i < chunks.length; i++) {
      expect(chunks[i].params['startMs'], chunks[i - 1].params['endMs']);
    }
    // 네 구간은 함께 출발한다(직렬이 아니다).
    expect(chunks.map((c) => c.at).toSet().length, 1,
        reason: '구간 조회가 앞 구간 응답을 기다린다');
    // 전 기간 경로의 지급 준비 조회는 그 경로의 근로자 전부를 묻는다.
    final rd = s.of('readiness');
    expect(rd.any((c) => (c.params['workerUids'] as List).toSet()
        .containsAll({'n1A', 'n1B', 'n1C'})), isTrue);
  });

  testWidgets('PAO-2 F4 — 월 조회가 늦으면 두 지급 준비 조회가 서로를 덮는가', (t) async {
    final s = _Srv(() => _base('n2'))..state = {'n2B': 'BANK_OCR_UNCERTAIN'};
    s.delay = (c) => switch (c.kind) {
          'month-confirmed' || 'month-transferred' => 900, // 콜드 시작 수준
          'readiness' => 60,
          'names' => 40,
          'other' => 500,
          _ => 100,
        };
    await _mount(t, s);
    await _advance(t, 3000);
    final seen = _Seen(t);
    _log('PAO-2', s, seen, -1);
    // [PAYROLL-V3-CONNECTED 기대 갱신] 예전: payable == 0 (준비된 카드에도 이체처리가 없던 때의 신호).
    expect(seen.bare, 0, reason: '지급 준비를 모르는 카드가 이체처리 버튼을 받았다');
    expect(_accurate3(seen), isTrue);
  });

  testWidgets('PAO-3 구간 하나 실패 → 0건·0원이 아니라 실패 화면', (t) async {
    final s = _Srv(() => _base('n3'));
    s.failCode = (c) => c.kind == 'chunk2' ? 'unavailable' : null;
    await _mount(t, s);
    await _advance(t, 3000);
    final seen = _Seen(t);
    _log('PAO-3', s, seen, -1);
    expect(seen.inlineError, isTrue);
    expect(seen.empty, isFalse);
    expect(seen.header, isFalse);
    expect(seen.payable, 0);
  });

  testWidgets('PAO-4 권한 거절(근태 조회 전부) → 금액 없이 실패 화면', (t) async {
    final s = _Srv(() => _base('n4'));
    s.failCode = (c) =>
        c.fn == 'callableGetAdminAttendances' ? 'permission-denied' : null;
    await _mount(t, s);
    await _advance(t, 3000);
    final seen = _Seen(t);
    _log('PAO-4', s, seen, -1);
    expect(seen.screenError || seen.inlineError, isTrue);
    expect(seen.header, isFalse);
    expect(seen.empty, isFalse);
    expect(seen.payable, 0);
  });

  testWidgets('PAO-5 지급 준비 조회 실패(전 기간 경로) → 이체처리가 아니라 조회 실패', (t) async {
    final s = _Srv(() => _base('n5'))..state = {'n5B': 'BANK_OCR_UNCERTAIN'};
    s.failCode = (c) => c.kind == 'readiness' &&
            (c.params['workerUids'] as List).contains('n5B')
        ? 'internal'
        : null;
    s.delay = (c) => switch (c.kind) {
          'month-confirmed' || 'month-transferred' => 700,
          'readiness' => 60,
          'names' => 40,
          'other' => 500,
          _ => 100,
        };
    await _mount(t, s);
    await _advance(t, 3000);
    final seen = _Seen(t);
    _log('PAO-5', s, seen, -1);
    expect(seen.header, isTrue);
    expect(seen.shows(FormatHelper.formatWage(180000)), isTrue);
    expect(seen.payable, 0, reason: '조회 실패한 근로자가 이체처리 버튼을 받았다');
    expect(seen.unknown, 3);
  });

  testWidgets('PAO-6 응답 역전 — 새로고침 뒤 늦게 온 옛 조회가 새 화면을 덮지 않는다', (t) async {
    var v2 = false; // 새로고침 시점에 C 가 이체돼 미이체에서 빠졌다
    final s = _Srv(() => [
          for (final r in _base('n6'))
            if (!(v2 && r.uid == 'n6C')) r,
        ])..state = {'n6B': 'BANK_OCR_UNCERTAIN'};
    s.delay = (c) => switch (c.kind) {
          'readiness' => 60,
          'names' => 40,
          'other' => 500,
          _ => c.at < 300 ? 1500 : 80, // 첫 조회는 느리고, 새로고침은 빠르다
        };
    await _mount(t, s);
    await _advance(t, 300);
    v2 = true;
    await t.tap(find.byIcon(Icons.refresh_rounded));
    await _advance(t, 4000);
    final seen = _Seen(t);
    _log('PAO-6', s, seen, -1);
    expect(_accurate3(seen, total: 150000, groups: 2), isTrue,
        reason: '옛 응답(C 포함)이 새 결과를 덮었다');
  });

  testWidgets('PAO-7 200명 초과 — 201번째부터 지급 준비가 비어 이체처리가 되지 않는다', (t) async {
    final recs = [
      for (var i = 0; i < 250; i++)
        _Rec('n7r$i', 'n7W${i.toString().padLeft(3, '0')}',
            DateTime(2024, 1, 1).add(Duration(days: i)), 1000),
    ];
    final s = _Srv(() => recs);
    await _mount(t, s);
    await _advance(t, 3000);
    final rd = s.of('readiness');
    final asked = <String>{
      for (final c in rd) ...(c.params['workerUids'] as List).cast<String>()
    };
    _log('PAO-7', s, _Seen(t), -1);
    expect(findVisibleText(FormatHelper.formatWage(250000)), findsOneWidget);
    // 마지막 카드까지 내려 본다(지급 기한 순 → 마지막 = 201번째 이후).
    await t.drag(find.byType(ListView), const Offset(0, -200000));
    await _advance(t, 500);
    final end = _Seen(t);
    // ignore: avoid_print
    print('   PAO-7 end-of-list $end');
    expect(rd.every((c) => (c.params['workerUids'] as List).length <= 200), isTrue);
    expect(asked.length, 250, reason: '200명을 넘는 근로자는 지급 준비를 묻지 않았다');
    // [PAYROLL-V3-CONNECTED 기대 갱신] 예전: end.payable == 0. 준비된 카드는 보기 + 이체처리 —
    //   지급 준비가 비어 이체처리만 단 카드(201번째 이후 결함의 모양)가 없어야 한다.
    expect(end.bare, 0);
    expect(end.view, greaterThan(0));
  });

  testWidgets('PAO-8 이 모드엔 연·월 이동이 없다 — 월 변경 경합 대상 아님', (t) async {
    final s = _Srv(() => _base('n8'));
    await _mount(t, s);
    await _advance(t, 2500);
    expect(findVisibleText('2026년'), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byType(TabBar), findsNothing);
  });
  testWidgets('PAO-M1 월별 모드 — 이름·지급 준비 조회가 함께 출발하고, 지급 준비는 월 근로자 전부를 묻는다', (t) async {
    final s = _Srv(() => _base('m1'));
    await _mount(t, s, allOutstanding: false);
    await _advance(t, 2000);
    _log('PAO-M1', s, _Seen(t), -1);
    final names = s.of('names'), rd = s.of('readiness');
    expect(s.of('chunk'), isEmpty, reason: '월별 모드는 전 기간 조회를 하지 않는다');
    expect(rd.length, 1);
    expect(names, isNotEmpty);
    expect(rd.single.at, names.first.at, reason: '이름·지급 준비 조회가 같은 시각에 출발하지 않았다(직렬로 바뀜)');
    expect((rd.single.params['workerUids'] as List).toSet(), {'m1A', 'm1D'});
  });

  testWidgets('PAO-M2 전체 미이체 모드 — 월 경로는 지급 준비를 묻지 않는다(전 기간 경로 1회만)', (t) async {
    final s = _Srv(() => _base('m2'));
    s.delay = (c) => switch (c.kind) {
          'month-confirmed' || 'month-transferred' => 50, // 월 경로가 먼저 끝나도
          'readiness' => 60,
          'names' => 40,
          'other' => 500,
          _ => 300,
        };
    await _mount(t, s);
    await _advance(t, 2500);
    _log('PAO-M2', s, _Seen(t), -1);
    final rd = s.of('readiness');
    expect(rd.length, 1, reason: '월 경로가 지급 준비를 따로 물었다');
    expect((rd.single.params['workerUids'] as List).toSet(), {'m2A', 'm2B', 'm2C'});
    expect(s.of('names'), isNotEmpty, reason: '월 경로의 이름 조회는 그대로 돈다');
  });

  // ══ [PAYROLL-V3-RECOVERY-AND-READINESS-CLOSEOUT.2 · A] '다시 시도'가 실패한 조회를 되살린다 ══
  //
  //   읽기 둘: 월 조회(_load → _loadError, 실패하면 화면 전체 오류가 목록을 가린다)와
  //   전 기간 미이체 조회(_loadAllOutstanding → _outstandingLoadError, 목록 자리의 오류).
  //   버튼: 화면 전체 오류 '다시 시도' → _retryFailedReads(월 + 실패해 있는 미이체),
  //   목록 오류 '다시 시도' → _loadAllOutstanding, 이전 조회 안내 '다시 조회' → _loadAllOutstanding.
  group('PAO-R 실패 조회 복구', () {
    ({int month, int chunk}) count(_Srv s) =>
        (month: s.of('month').length, chunk: s.of('chunk').length);

    Future<_Srv> start(WidgetTester t, String p,
        {required bool monthFail, required bool chunkFail}) async {
      final s = _Srv(() => _base(p))..state = {'${p}B': 'BANK_OCR_UNCERTAIN'};
      var mf = monthFail, cf = chunkFail;
      s.failCode = (c) => (mf && c.kind.startsWith('month')) ||
              (cf && c.kind.startsWith('chunk'))
          ? 'unavailable'
          : null;
      _flags[s] = (setMonth: (v) => mf = v, setChunk: (v) => cf = v);
      await _mount(t, s);
      await _advance(t, 2000);
      return s;
    }

    Future<void> tapRetry(WidgetTester t, {String label = '다시 시도'}) async {
      expect(findVisibleText(label), findsOneWidget, reason: '오류 옆 버튼이 하나가 아니다');
      await t.tap(findVisibleText(label));
      await _advance(t, 20);
      // 읽는 동안: 금액·이체 버튼이 보이지 않는다(지급 가능처럼 보이지 않는다).
      final mid = _Seen(t);
      expect(mid.bare, 0);
      await _advance(t, 2000);
    }

    testWidgets('PAO-R1 월 성공 · 미이체 실패 → 목록 오류 다시 시도 = 미이체만 다시 읽는다', (t) async {
      final s = await start(t, 'r1', monthFail: false, chunkFail: true);
      var seen = _Seen(t);
      expect(seen.screenError, isFalse);
      expect(seen.inlineError, isTrue);
      expect(seen.payable, 0);
      final c0 = count(s);
      _flags[s]!.setChunk(false);
      await tapRetry(t);
      seen = _Seen(t);
      _log('PAO-R1', s, seen, -1);
      expect(count(s).chunk - c0.chunk, 4);
      expect(count(s).month - c0.month, 0, reason: '목록 오류 버튼이 월까지 다시 읽었다');
      expect(_accurate3(seen), isTrue);
    });

    testWidgets('PAO-R2 월 실패 · 미이체 성공 → 화면 오류 다시 시도 = 월만 다시 읽는다', (t) async {
      final s = await start(t, 'r2', monthFail: true, chunkFail: false);
      var seen = _Seen(t);
      expect(seen.screenError, isTrue);
      expect(seen.header, isFalse);
      expect(seen.payable, 0);
      final c0 = count(s);
      _flags[s]!.setMonth(false);
      await tapRetry(t);
      seen = _Seen(t);
      _log('PAO-R2', s, seen, -1);
      expect(count(s).month - c0.month, 2);
      expect(count(s).chunk - c0.chunk, 0, reason: '성공해 있는 미이체 조회를 다시 보냈다');
      expect(_accurate3(seen), isTrue);
    });

    testWidgets('PAO-R3 둘 다 실패 → 미이체만 회복 → 월 회복: 버튼마다 실패한 것만', (t) async {
      final s = await start(t, 'r3', monthFail: true, chunkFail: true);
      expect(_Seen(t).screenError, isTrue);
      var c0 = count(s);
      _flags[s]!.setChunk(false); // 미이체만 회복
      await tapRetry(t);
      var seen = _Seen(t);
      expect(count(s).month - c0.month, 2);
      expect(count(s).chunk - c0.chunk, 4);
      expect(seen.screenError, isTrue, reason: '월은 아직 실패 — 화면 오류가 남아야 한다');
      expect(seen.payable, 0);
      c0 = count(s);
      _flags[s]!.setMonth(false); // 월 회복
      await tapRetry(t);
      seen = _Seen(t);
      _log('PAO-R3', s, seen, -1);
      expect(count(s).month - c0.month, 2);
      expect(count(s).chunk - c0.chunk, 0, reason: '이미 회복한 미이체를 또 읽었다');
      expect(_accurate3(seen), isTrue);
    });

    testWidgets('PAO-R4 둘 다 실패 → 월만 회복: 화면 오류 버튼 뒤 목록 오류 버튼 하나', (t) async {
      final s = await start(t, 'r4', monthFail: true, chunkFail: true);
      var c0 = count(s);
      _flags[s]!.setMonth(false);
      await tapRetry(t);
      var seen = _Seen(t);
      expect(count(s).month - c0.month, 2);
      expect(count(s).chunk - c0.chunk, 4, reason: '실패해 있던 미이체를 함께 다시 읽지 않았다');
      expect(seen.screenError, isFalse);
      expect(seen.inlineError, isTrue);
      expect(seen.payable, 0);
      c0 = count(s);
      _flags[s]!.setChunk(false);
      await tapRetry(t);
      seen = _Seen(t);
      _log('PAO-R4', s, seen, -1);
      expect(count(s).chunk - c0.chunk, 4);
      expect(count(s).month - c0.month, 0);
      expect(_accurate3(seen), isTrue);
    });

    testWidgets('PAO-R5 둘 다 실패 → 둘 다 회복: 화면 오류 버튼 한 번으로 정확한 목록', (t) async {
      // 부정 대조: onPressed: _load(예전) 이면 월만 돌아와 목록 오류가 남는다 → 이 테스트가 실패한다.
      final s = await start(t, 'r5', monthFail: true, chunkFail: true);
      final c0 = count(s);
      _flags[s]!
        ..setMonth(false)
        ..setChunk(false);
      await tapRetry(t);
      final seen = _Seen(t);
      _log('PAO-R5', s, seen, -1);
      expect(count(s).month - c0.month, 2);
      expect(count(s).chunk - c0.chunk, 4);
      expect(_accurate3(seen), isTrue, reason: '한 번 눌렀는데 목록이 돌아오지 않았다');
    });

    testWidgets('PAO-R6 이전 조회(stale) — 다시 조회 = 미이체만, 회복 뒤 이체처리 입구', (t) async {
      final s = await start(t, 'r6', monthFail: false, chunkFail: false);
      expect(_accurate3(_Seen(t)), isTrue);
      _flags[s]!.setChunk(true);
      await t.tap(find.byIcon(Icons.refresh_rounded)); // 월+미이체 새로고침, 미이체만 실패
      await _advance(t, 2000);
      var seen = _Seen(t);
      expect(seen.shows('다시 조회'), isTrue);
      final c0 = count(s);
      _flags[s]!.setChunk(false);
      await tapRetry(t, label: '다시 조회');
      seen = _Seen(t);
      _log('PAO-R6', s, seen, -1);
      expect(count(s).chunk - c0.chunk, 4);
      expect(count(s).month - c0.month, 0);
      expect(seen.shows('다시 조회'), isFalse);
      expect(_accurate3(seen), isTrue);
    });
  });

  // ══ [CLOSEOUT.2 · B] 월별 지급 준비 — 200명 경계·부분 응답·월 이동 ══════════════════════
  //
  //   200 = 서버 callableGetPayrollReadinessBatch 한 요청의 근로자 상한(초과는 invalid-argument).
  //   예전 월 경로는 근로자 전부를 한 번에 넘겼고 loadBatch 가 take(200)으로 잘랐다.
  group('PAO-B 월별 지급 준비', () {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final y = kst.year, m = kst.month;
    final prev = DateTime(y, m - 1, 1);

    /// 오늘 지급 예정(이체 대기 탭 기본 날짜) — n 명, 근로자마다 rowsPer 건.
    List<_Rec> month(String p, int n, {int rowsPer = 1, DateTime? at}) => [
          for (var i = 0; i < n; i++)
            for (var k = 0; k < rowsPer; k++)
              _Rec('$p-r$i-$k', '$p${i.toString().padLeft(3, '0')}',
                  DateTime((at ?? kst).year, (at ?? kst).month, 10, k), 1000,
                  due: DateTime.now()),
        ];

    Future<_Seen> scanAll(WidgetTester t) async {
      // 끝까지 내리며 판정 없는 카드(bare)·조회 실패 카드 최댓값을 모은다.
      var bare = 0, unknown = 0, view = 0;
      for (var i = 0; i < 60; i++) {
        final s = _Seen(t);
        bare = bare > s.bare ? bare : s.bare;
        unknown += s.unknown;
        view += s.view;
        await t.drag(find.byType(ListView).first, const Offset(0, -1500));
        await _advance(t, 30);
      }
      final end = _Seen(t);
      // ignore: avoid_print
      print('   scan bare(max)=$bare unknown(sum)=$unknown view(sum)=$view end=$end');
      return end..scanBare = bare;
    }

    Set<String> asked(_Srv s) => {
          for (final c in s.of('readiness'))
            ...(c.params['workerUids'] as List).cast<String>()
        };

    Future<void> goMonth(WidgetTester t, int d, {bool wait = true}) async {
      // 월 이동 화살표는 이체현황 탭 머리말에만 있다(0=연, 1=월). 카드는 미이체 탭.
      await t.tap(find.descendant(of: find.byType(TabBar), matching: findVisibleText('이체현황')));
      await _advance(t, 400);
      await t.tap(find.byIcon(d < 0 ? Icons.chevron_left : Icons.chevron_right).at(1));
      await _advance(t, 20);
      if (!wait) return;
      await _advance(t, 2500); // 로딩 중엔 탭·화살표가 없다(화면 전체 로딩)
      await t.tap(find.descendant(of: find.byType(TabBar), matching: findVisibleText('미이체')));
      await _advance(t, 400);
    }

    for (final n in [199, 200, 201]) {
      testWidgets('PAO-B1 $n명 — 200명씩 나눠 묻고, 끝 카드까지 판정이 있다', (t) async {
        final recs = month('b$n', n);
        final s = _Srv(() => recs);
        await _mount(t, s, allOutstanding: false, year: y, month: m);
        await _advance(t, 2500);
        final rd = s.of('readiness');
        _log('PAO-B1 $n', s, _Seen(t), -1);
        expect(rd.length, n > 200 ? 2 : 1);
        expect(rd.every((c) => (c.params['workerUids'] as List).length <= 200), isTrue);
        expect(asked(s).length, n);
        final end = await scanAll(t);
        expect(end.scanBare, 0, reason: '판정 없이 이체처리만 단 카드가 있다');
        expect(end.unknown, 0);
        expect(end.view, greaterThan(0));
      });
    }

    testWidgets('PAO-B2 순서 뒤섞인 응답·덤 응답·한 사람 여러 건 — id 로 합친다', (t) async {
      final recs = month('b2', 201, rowsPer: 2);
      final s = _Srv(() => recs)
        ..reverseReadiness = true
        ..extraReadiness = {'ghost': 'READY_AUTO', 'b2200': 'BANK_OCR_UNCERTAIN'}
        ..state = {'b2000': 'BANK_OCR_UNCERTAIN'};
      // 첫 배치(b2000 포함)가 늦게 온다 — 배치 응답 순서가 요청 순서와 다르다.
      s.delay = (c) => c.kind == 'readiness'
          ? ((c.params['workerUids'] as List).contains('b2000') ? 600 : 50)
          : 100;
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      final seen = _Seen(t);
      _log('PAO-B2', s, seen, -1);
      expect(seen.review, 1, reason: 'b2000 의 수동 확인 판정이 다른 사람에게 갔거나 사라졌다');
      expect(seen.shows('2건'), isTrue, reason: '한 사람 두 건이 한 카드로 묶이지 않았다');
      final end = await scanAll(t);
      // 첫 배치의 덤 응답(b2200=수동 확인)이 둘째 배치의 b2200(정상)을 덮지 않는다.
      expect(end.review, 0);
      expect(end.scanBare, 0);
      expect(end.unknown, 0);
    });

    testWidgets('PAO-B3 한 배치 실패 → 그 배치만 조회 실패, 이체처리 없음', (t) async {
      final recs = month('b3', 201);
      final s = _Srv(() => recs);
      s.failCode = (c) => c.kind == 'readiness' &&
              (c.params['workerUids'] as List).contains('b3200')
          ? 'internal'
          : null;
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      final failedBatch = s.of('readiness').firstWhere((c) => c.error != null);
      final size = (failedBatch.params['workerUids'] as List).length;
      final end = await scanAll(t);
      _log('PAO-B3', s, end, -1);
      expect(size, 1);
      expect(end.scanBare, 0);
      expect(end.shows('지급 준비 상태 조회 실패'), isTrue);
    });

    testWidgets('PAO-B4 한 사람 빠짐·서버 failed → 그 사람만 모름(미등록·준비완료·0 아님)', (t) async {
      final recs = month('b4', 3);
      final s = _Srv(() => recs)
        ..omitReadiness = {'b4000'}
        ..failedReadiness = {'b4001'};
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      final seen = _Seen(t);
      _log('PAO-B4', s, seen, -1);
      expect(seen.unknown, 2);
      expect(seen.view, 1);
      expect(seen.payable, 1);
      expect(seen.bare, 0);
      expect(seen.shows('근로자 정보 보완 대기'), isFalse);
      expect(seen.shows('통장사본 확인 필요'), isFalse);
    });

    testWidgets('PAO-B5 권한 거절 → 전원 모름, 새로고침으로 회복(이름 캐시가 막지 않는다)', (t) async {
      final recs = month('b5', 3);
      final s = _Srv(() => recs);
      var deny = true;
      s.failCode = (c) => deny && c.kind == 'readiness' ? 'permission-denied' : null;
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      var seen = _Seen(t);
      expect(seen.unknown, 3);
      expect(seen.payable, 0);
      final before = s.of('readiness').length;
      deny = false;
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await _advance(t, 2500);
      seen = _Seen(t);
      _log('PAO-B5', s, seen, -1);
      expect(s.of('readiness').length - before, 1,
          reason: '이름이 캐시돼 있다고 지급 준비 재조회를 건너뛰었다');
      expect(seen.unknown, 0);
      expect(seen.view, 3);
      expect(seen.bare, 0);
    });

    testWidgets('PAO-B6 월 왕복 — 돌아온 달의 지급 준비를 다시 묻는다', (t) async {
      final s = _Srv(() => [...month('b6', 2), ...month('b6p', 2, at: prev)])
        ..state = {'b6000': 'BANK_OCR_UNCERTAIN'};
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      expect(_Seen(t).review, 1);
      await goMonth(t, -1); // 이전 달
      await goMonth(t, 1); // 다시 이번 달(이름은 캐시됨)
      final seen = _Seen(t);
      _log('PAO-B6', s, seen, -1);
      expect(asked(s).containsAll({'b6000', 'b6001', 'b6p000', 'b6p001'}), isTrue);
      expect(s.of('readiness').last.params['workerUids'], unorderedEquals(['b6000', 'b6001']));
      expect(seen.review, 1, reason: '떠나온 달의 판정이 남아 이 달 카드 판정이 사라졌다');
      expect(seen.bare, 0);
    });

    testWidgets('PAO-B7 느린 지급 준비 — 응답 전엔 판정 없는 카드가 없고, 도착 뒤 그 달 판정만', (t) async {
      // 월 조회 중엔 화면 전체가 로딩이라 월을 다시 바꿀 수 없다(월 이동 화살표가 그 화면 안에 있다).
      //   그래서 월 경로의 지급 준비는 다음 월 조회보다 늦게 도착할 수 없다 — 대신 느린 응답을 기다리는
      //   동안 화면이 무엇을 말하는지, 도착한 판정이 어느 달 근로자에게 붙는지를 본다.
      //   겹칠 수 있는 유일한 쌍(통장사본 검토 뒤 재조회 ↔ 월 조회)은 _loadPayrollReadiness 순번(PR-51).
      final s = _Srv(() => [...month('b7', 2), ...month('b7p', 2, at: prev)])
        ..state = {'b7p001': 'BANK_OCR_UNCERTAIN'};
      s.delay = (c) => switch (c.kind) {
            'readiness' when (c.params['workerUids'] as List).contains('b7p000') => 1500,
            'readiness' => 60,
            'names' => 40,
            'other' => 500,
            _ => 100,
          };
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      await goMonth(t, -1, wait: false); // 이전 달 — 지급 준비가 느리다
      await _advance(t, 300);
      final mid = _Seen(t);
      expect(mid.payable, 0, reason: '지급 준비 응답 전에 이체처리가 보였다');
      expect(find.byIcon(Icons.chevron_left), findsNothing, reason: '로딩 중에 월을 또 바꿀 수 있다');
      await _advance(t, 2500);
      await t.tap(find.descendant(of: find.byType(TabBar), matching: findVisibleText('미이체')));
      await _advance(t, 400);
      final seen = _Seen(t);
      _log('PAO-B7', s, seen, -1);
      expect(seen.review, 1, reason: '이전 달 b7p001 의 수동 확인 판정');
      expect(seen.view, 1); // b7p000(준비 완료) — 수동 확인 카드는 '통장사본 확인'
      expect(seen.bare, 0);
      expect(seen.unknown, 0);
      expect(seen.shows('Nb7000'), isFalse, reason: '떠나온 달의 카드가 남았다');
    });
  });

  // ══ [CLOSEOUT.2 · C] 이름 — 카드·확인 창·처리 대상이 같은 사람 ═══════════════════════════
  group('PAO-C 이름·대상', () {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final y = kst.year, m = kst.month;
    final day = DateTime(y, m, 10);

    Future<void> payCardWith(WidgetTester t, String amount) async {
      final cards = find.ancestor(
          of: findVisibleText('이체처리'),
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_WorkerPayCard'));
      final target = cards.evaluate().where((e) => find
          .descendant(of: find.byWidget(e.widget), matching: findVisibleText(amount))
          .evaluate()
          .isNotEmpty);
      expect(target.length, 1, reason: '$amount 카드가 하나가 아니다');
      await t.tap(find.descendant(
          of: find.byWidget(target.single.widget), matching: findVisibleText('이체처리')));
      await _advance(t, 300);
    }

    String dialogMessage() => find
        .byType(Text)
        .evaluate()
        // [DU285 따라잡기] 확인창 본문이 기본 배율에서도 넘치면 낱말 묶기(WJ) 꼴로 표시된다 — 보이는 글을 원문으로 비교한다
        .map((e) => TextLayout.plain((e.widget as Text).data ?? ''))
        .firstWhere((s) => s.contains('이체 완료 처리하시겠습니까'), orElse: () => '');

    Future<_Call> confirmAndSkipNote(WidgetTester t, _Srv s) async {
      await t.tap(findVisibleText('이체 완료 처리').last);
      await _advance(t, 300);
      await t.tap(findVisibleText('건너뛰기'));
      await _advance(t, 1500);
      return s.of('mark').single;
    }

    for (final reversed in [false, true]) {
      testWidgets('PAO-C1 동명이인 — 카드 금액·확인 창 번호·처리 id 가 같은 사람 (서버 순서 ${reversed ? '역순' : '정순'})', (t) async {
        final recs = [
          _Rec('c1-x1', 'cX1', day, 10000, due: DateTime.now()),
          _Rec('c1-x2', 'cX2', day, 20000, due: DateTime.now()),
        ];
        final s = _Srv(() => reversed ? recs.reversed.toList() : recs)
          ..nameOf = ((u) => '김동명')
          ..personNo = {'cX1': 1, 'cX2': 2};
        await _mount(t, s, allOutstanding: false, year: y, month: m);
        await _advance(t, 2500);
        expect(findVisibleText('김동명'), findsNWidgets(2));
        // [PAYROLL-V3-NAME · O2] 카드에도 확인 창과 같은 인력번호가 보인다.
        expect(findVisibleText('P-001'), findsOneWidget);
        expect(findVisibleText('P-002'), findsOneWidget);
        await payCardWith(t, FormatHelper.formatWage(20000));
        final msg = dialogMessage();
        final label2 = UserModel(uid: 'cX2', username: 'cX2', name: '김동명',
                email: '', role: UserRole.USER, personNo: 2)
            .nameWithPersonNo;
        // ignore: avoid_print
        print('   PAO-C1 dialog="${msg.split('\n').first}" expect=$label2');
        expect(msg, startsWith('$label2님께'));
        expect(msg, contains(FormatHelper.formatWage(20000)));
        final mark = await confirmAndSkipNote(t, s);
        expect(mark.params['attendanceIds'], ['c1-x2']);
        final n = ((mark.params['notifications'] as List).single as Map);
        expect(n['userId'], 'cX2');
        expect(n['attendanceId'], 'c1-x2');
        expect(n['workerName'], '김동명', reason: '서버로 가는 이름에 번호가 섞였다');
      });
    }

    testWidgets('PAO-C2 이름 모름 — 다른 사람 이름·예금주로 채우지 않는다', (t) async {
      final recs = [
        _Rec('c2-k', 'cKnown', day, 10000, due: DateTime.now()),
        _Rec('c2-u', 'cUnknown', day, 30000, due: DateTime.now()),
      ];
      final s = _Srv(() => recs)..nameOf = ((u) => u == 'cKnown' ? '홍길동' : null);
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      final seen = _Seen(t);
      expect(seen.shows('홍길동'), isTrue);
      // [PAYROLL-V3-NAME 기대 갱신] 예전: 카드 = uid('cUnknown'), 확인 창 = '이름 없음님께', 알림 이름 = '이름 없음'.
      //   이제 카드·확인 창 모두 '이름 확인 불가', uid 는 이름 자리에 없고, 알림에는 이름 칸이 없다.
      expect(seen.shows('cUnknown'), isFalse, reason: 'uid 를 이름 자리에 썼다');
      expect(seen.shows('이름 확인 불가'), isTrue);
      await payCardWith(t, FormatHelper.formatWage(30000));
      final msg = dialogMessage();
      // ignore: avoid_print
      print('   PAO-C2 dialog="${msg.split('\n').first}"');
      expect(msg.contains('홍길동'), isFalse, reason: '모르는 사람 확인 창에 다른 사람 이름');
      expect(msg, startsWith('이름 확인 불가 근로자에게'));
      expect(msg.contains('님께'), isFalse, reason: '상태 문구에 호칭을 붙였다');
      final mark = await confirmAndSkipNote(t, s);
      expect(mark.params['attendanceIds'], ['c2-u']);
      final n = ((mark.params['notifications'] as List).single as Map);
      expect(n['userId'], 'cUnknown');
      // ignore: avoid_print
      print('   PAO-C2 notification.workerName="${n['workerName']}" (현재 동작 기록)');
      expect(n['workerName'], isNot('홍길동'));
      expect(n.containsKey('workerName'), isFalse, reason: '모르는 이름을 대체 문구로 서버에 보냈다');
    });

    // ── [PAYROLL-V3-NAME.3] 이름 reader 만 실패 — 지급 준비 reader 와 섞지 않는다 ──
    testWidgets('PAO-C3 이름 조회 실패·준비 유효 → 확인 불가 표시, 이체 입구 유지, 알림 이름 없음, 새로고침 회복', (t) async {
      final recs = [
        _Rec('c3-a', 'cA', day, 10000, due: DateTime.now()),
        _Rec('c3-b', 'cB', day, 20000, due: DateTime.now()),
      ];
      var namesDown = true;
      final s = _Srv(() => recs)..personNo = {'cA': 7, 'cB': 8};
      s.failCode = (c) => namesDown && c.kind == 'names' ? 'unavailable' : null;
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      var seen = _Seen(t);
      _log('PAO-C3', s, seen, -1);
      expect(findVisibleText('이름 확인 불가'), findsNWidgets(2));
      expect(seen.shows('cA') || seen.shows('cB'), isFalse, reason: 'uid 를 이름 자리에 썼다');
      expect(seen.payable, 2, reason: '이름만 실패했는데 이체 입구를 막았다');
      expect(seen.bare, 0);
      expect(seen.unknown, 0, reason: '이름 실패가 지급 준비 판정을 흐렸다');
      await payCardWith(t, FormatHelper.formatWage(20000));
      expect(dialogMessage(), startsWith('이름 확인 불가 근로자에게'));
      final mark = await confirmAndSkipNote(t, s);
      expect(mark.params['attendanceIds'], ['c3-b']);
      final n = ((mark.params['notifications'] as List).single as Map);
      expect(n['userId'], 'cB');
      expect(n.containsKey('workerName'), isFalse);
      // 실패한 이름은 캐시하지 않는다 — 새로고침하면 다시 묻고, 번호와 이름이 돌아온다.
      namesDown = false;
      await t.tap(find.byIcon(Icons.refresh_rounded));
      await _advance(t, 2500);
      seen = _Seen(t);
      expect(seen.shows('NcA'), isTrue);
      expect(seen.shows('P-007'), isTrue);
      expect(findVisibleText('이름 확인 불가'), findsNothing);
    });

    testWidgets('PAO-C4 이름·지급 준비 모두 실패 → 지급 준비 gate 그대로(이체처리 0)', (t) async {
      final recs = [_Rec('c4-a', 'c4A', day, 10000, due: DateTime.now())];
      final s = _Srv(() => recs);
      s.failCode = (c) => c.kind == 'names' ? 'unavailable' : c.kind == 'readiness' ? 'internal' : null;
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      final seen = _Seen(t);
      expect(seen.shows('이름 확인 불가'), isTrue);
      expect(seen.unknown, 1);
      expect(seen.payable, 0);
      expect(s.of('mark'), isEmpty);
    });

    testWidgets('PAO-C5 이체 호출 실패 → 거짓 성공 없음, 사용자 재탭마다 1회', (t) async {
      final recs = [_Rec('c5-a', 'c5A', day, 10000, due: DateTime.now())];
      final s = _Srv(() => recs);
      s.failCode = (c) => c.kind == 'mark' ? 'internal' : null;
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 2500);
      await payCardWith(t, FormatHelper.formatWage(10000));
      await confirmAndSkipNote(t, s);
      await _advance(t, 1500);
      expect(s.of('mark').length, 1);
      expect(findVisibleTextContaining('이체 완료 처리되었습니다'), findsNothing);
      expect(_Seen(t).payable, 1, reason: '실패했는데 목록이 처리된 것처럼 바뀌었다');
      await payCardWith(t, FormatHelper.formatWage(10000));
      await t.tap(findVisibleText('이체 완료 처리').last);
      await _advance(t, 300);
      await t.tap(findVisibleText('건너뛰기'));
      await _advance(t, 1500);
      expect(s.of('mark').length, 2, reason: '재탭 1회에 호출 1회가 아니다');
    });

    testWidgets('PAO-C6 일괄 알림 정보 — 모르는 이름은 uid 로 채우지 않고 칸을 뺀다', (t) async {
      final s = _Srv(() => []);
      await _mount(t, s, allOutstanding: false, year: y, month: m);
      await _advance(t, 1000);
      AttendanceModel rec(String id, String uid) => AttendanceModel.fromMap({
            'userId': uid, 'businessId': _biz, 'businessName': 'QA 사업장',
            'workDate': Timestamp.fromDate(day), 'createdAt': Timestamp.fromDate(day),
            'status': 'present', 'wageStatus': 'confirmed', 'workType': 'QA',
            'wageDetail': {'totalAmount': 1000, 'wageType': 'daily'},
          }, id);
      final infos = buildTransferNotificationInfos(
          records: [rec('c6-1', 'u1'), rec('c6-2', 'u2')], workerNameByUid: {'u1': '홍길동'});
      expect(infos.map((i) => i.workerName).toList(), ['홍길동', null]);
      final f = PayrollPaymentService().markTransferredBatch(
          attendanceIds: ['c6-1', 'c6-2'], businessId: _biz, notificationInfos: infos);
      await _advance(t, 500);
      await f;
      final ns = (s.of('mark').single.params['notifications'] as List).cast<Map>();
      expect(ns.map((n) => n['userId']).toList(), ['u1', 'u2']);
      expect(ns[0]['workerName'], '홍길동');
      expect(ns[1].containsKey('workerName'), isFalse, reason: '예전: uid 가 이름으로 갔다');
    });

    testWidgets('PAO-C7 360dp·글자 1.3배·긴 이름 + 인력번호 — 넘침 없음, 이체 입구 보임', (t) async {
      final recs = [_Rec('c7-a', 'c7A', day, 1234567, due: DateTime.now())];
      final s = _Srv(() => recs)
        ..nameOf = ((u) => '가나다라마바사아자차카타파하가나다')
        ..personNo = {'c7A': 1234};
      // 넘침은 화면 어디서 났는지로 가른다 — 이번 판정은 **카드(_WorkerPayCard) 안**만이다.
      //   (테스트 폰트는 번들 NotoSansKR 보다 넓다. 카드 밖 기존 줄의 넘침은 BACKLOG 로 기록만 한다.)
      final src = File('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart')
          .readAsLinesSync();
      final cardStart = src.indexWhere((l) => l.startsWith('class _WorkerPayCard ')) + 1;
      final cardEnd = src.indexWhere((l) => l.startsWith('class '), cardStart) + 1;
      final where = <int>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        for (final mm in RegExp(r'payroll_payment_dashboard_screen\.dart:(\d+)')
            .allMatches(d.toString())) {
          where.add(int.parse(mm.group(1)!));
        }
      };
      await _mount(t, s, allOutstanding: false, year: y, month: m,
          size: const Size(1080, 2400), dpr: 3.0, textScale: 1.3);
      await _advance(t, 2500);
      FlutterError.onError = prev;
      // ignore: avoid_print
      print('   PAO-C7 넘침 위치(줄) ${where.toSet()} · 카드 범위 $cardStart–$cardEnd');
      expect(where.where((l) => l >= cardStart && l < cardEnd), isEmpty, reason: '카드 안에서 넘쳤다');
      expect(findVisibleText('P-1234'), findsOneWidget);
      expect(findVisibleText('이체처리'), findsOneWidget);
      final btn = t.getRect(find.ancestor(of: findVisibleText('이체처리'), matching: find.byType(ElevatedButton)));
      expect(btn.right <= 360 && btn.left >= 0, isTrue, reason: '처리 입구가 화면 밖으로 밀렸다 $btn');
    });
  });
}

/// [CLOSEOUT.2] PAO-R 의 서버 실패 손잡이(테스트마다 하나).
final _flags = Expando<({void Function(bool) setMonth, void Function(bool) setChunk})>();
