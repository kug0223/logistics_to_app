// ignore_for_file: depend_on_referenced_packages
// [DU551 · F135-FIXEDWORKER-LAYOUT 후속 첫 셀] 고정근무자 관리 창(FixedWorkerManagementDialog) 날짜 모드 B — 머리 띠 날짜 행(날짜 · 요청 표시) + 카드 기본 정보/배지 배치.
//   판정 = reports/DU_audit_self_review_retro143_2026-11-21.md §5(:54–64) · §6(:68–70) + retro141 :74–76(B 는 reflow · 말줄임/숨김/글자축소 0).
//   before = 현재 A(fixed_worker_management_dialog f38608f2 = DU548 채택판) 기록 전용 · strict = 후보(83c5f7ae).
//   하네스 = DU548 날짜 모드 대역 그대로(WKND · OUTP — 한 사업장 · 같은 CF 채널 대역 · 같은 4명) + DU543 r3 일반 모드 RENEW 대역 그대로(LIST — 5명 · 연장 제안 1 ·
//     첫 진입 대상 u_a1 자동 검색 = 공유 카드 구조의 일반 모드 영향 경로 대조) + DU548 · DU543 r3 끌기 도달(명단 칸을 실제로 끌어 지연 생성 카드에 닿는다).
//   측정(읽기만) = 글마다 그려진 문단(보이는 글 = 기대 원문 · 말줄임/줄 제한 넘음 · 공용 판정기 du_word_break 의 피할 수 있는 낱말 안 끊김 · 줄 수) +
//     자리(창 ∩ 화면 ∩ 명단 칸 안 · 카드/머리 띠 상자 안 · 서로 겹침 · 배지/표시 자리 side/below) + 머리 띠 높이 · 남은 명단 칸 높이 · 닫기 도달.
//   누르는 것 0(끌기 · ensureVisible 만). 넘침 · framework 오류: strict 0(W · B 모두) · before 기록(DU548 B overflows WKND 3 · OUTP 1).
//   기본 skip — TB before/du551-tb/DU_BEFORE_OBSERVE=551 · TA after/du551-ta/없음.
//   [r2 · 시험 수리 1회차] r1 정규 TB 가 W-LIST 에서 멈춤 — 첫 진입 자동 검색이 검색 칸에 이름을 넣어 find.text 가 2 를 셌다.
//     카드 이름 찾기 3곳만 화면 글(Text 위젯) 술어 _plainText 로. 기대값 · 개수 · 단언 · 동작 · 캡처 변경 0(r1 시험 41b5d814 에서 이것만).
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
import 'support/visible_text.dart';

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

const _biz1 = 'biz1';
const _bizName = '강남 물류센터';

/// 소유자(BUSINESS_ADMIN) — DU540 · DU548 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz1], sealBase64: 'seal');
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) {
    watched.add(businessId);
    return () {};
  }
}

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

/// 오늘(KST) + [d]일의 KST 자정(UTC ms) — 창의 `FormatHelper.toKstDate` 와 같은 달력.
int _kstDayMs(int d) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + d).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
}

/// CF 응답의 시각 표기(서버 serializeFirestoreData 형식 — 앱이 `_cfHydrate` 로 Timestamp 로 되돌린다).
Map<String, Object?> _ts(int ms) => <String, Object?>{'_seconds': ms ~/ 1000, '_nanoseconds': 0};

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일(DU540 · DU543 r3 와 같은 꼴 · status 기본 CONFIRMED).
Map<String, Object?> _app(String id, String applicant, int endIn, {String status = 'CONFIRMED', Map<String, Object?> extra = const <String, Object?>{}}) =>
    <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': _biz1, 'businessName': _bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': status, 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

const _names = <String, String>{
  'u_a1': '김연장', 'u_a2': '이대기', 'u_a3': '박서명', 'u_a4': '최종료', 'u_a5': '정해지',
  'u_c1': '김가람', 'u_c2': '이나래', 'u_c3': '서다솜', 'u_c4': '박다온',
};

/// 오늘(KST)에서 며칠 뒤가 [ok] 요일인가(0–7 · 없으면 0).
int _aheadTo(bool Function(int weekday) ok) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  for (var d = 0; d < 8; d++) {
    if (ok(DateTime.utc(k.year, k.month, k.day + d).weekday)) return d;
  }
  return 0;
}

/// 날짜 모드로 보는 날 — 오늘(KST) 이후 첫 평일(월–금) / 첫 토요일(DU540 · DU548 과 같다).
int _weekdayAhead() => _aheadTo((wd) => wd <= DateTime.friday);
int _saturdayAhead() => _aheadTo((wd) => wd == DateTime.saturday);

/// 창에 넘기는 focusDate — 그 날의 로컬 자정(달력 화면 workforce_operational_view 가 넘기는 값과 같은 모양 `DateTime(y, m, d)`).
DateTime _focusDay(int ahead) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(k.year, k.month, k.day + ahead);
}

/// 날짜 모드 대역 4명(DU548 과 같다 · 호출마다 새로 만든다) —
///   c1 김가람: 월–금 · 가장 최근 확정 · 토요일 = 추가근무 요청 중(WKND · 가장 넓은 배지)
///   c2 이나래: 월–금(토요일 = 비근무일) — [kind] = OUTP 이면 계약 시작(workDate)만 보는 평일 + 7일로 옮긴다(= 계약기간 외 · 그 밖 값 그대로)
///   c3 서다솜: 토 · 일 + 그 평일에 승인된 추가근무 · c4 박다온: 월–금 + 그 평일에 승인된 휴무(토요일 = 비근무일)
List<Object?> _appsDate(String kind) => <Object?>[
      _app('c1', '김가람', 60, extra: <String, Object?>{'confirmedAt': _ts(_kstDayMs(-20))}),
      _app('c2', '이나래', 90, extra: kind == 'OUTP' ? <String, Object?>{'workDate': _ts(_kstDayMs(_weekdayAhead() + 7))} : const <String, Object?>{}),
      _app('c3', '서다솜', 120, extra: <String, Object?>{'workDays': const <Object?>['토', '일'], 'extraWorkDates': <Object?>[_ts(_kstDayMs(_weekdayAhead()))]}),
      _app('c4', '박다온', 100, extra: <String, Object?>{'leaveDates': <Object?>[_ts(_kstDayMs(_weekdayAhead()))]}),
    ];

/// c1 의 대기 중인 추가 근무 요청 한 건(토요일 · 관리자가 보낸 EXTRA_WORK — DU540 DATEWKND · DU548 WKND 와 같다). 이 셀은 요청 방향 · 승인/거절을 바꾸지 않는다.
Map<String, Object?> _schedReq(int ahead) => <String, Object?>{
      'id': 'sr1', 'businessId': _biz1, 'applicationId': 'c1', 'applicantUid': 'u_c1', 'applicantName': '김가람',
      'targetDate': _ts(_kstDayMs(ahead)), 'requestType': 'EXTRA_WORK', 'requestedBy': 'ADMIN',
      'requestedByUid': 'admin1', 'requestedAt': _ts(_kstDayMs(-1)), 'reason': '일정 조정 부탁드립니다', 'status': 'PENDING',
    };

/// 일반 모드 대역 5명(DU536 · DU540 · DU543 r3 RENEW 와 같다 · 호출마다 새로 만든다) — a1 만료 10일 전 · a2 만료 5일 전 + 연장 제안 응답 대기 ·
///   a3 계약 처리 필요 · a4 종료 결정 · a5 해지 요청 중. LIST 는 첫 진입 대상 u_a1(김연장) 자동 검색 — 카드 1장.
List<Object?> _apps() => <Object?>[
      _app('a1', '김연장', 10),
      _app('a2', '이대기', 5),
      _app('a3', '박서명', 25, status: 'CONTRACT_PENDING'),
      _app('a4', '최종료', 40, extra: <String, Object?>{'renewalDecision': 'TERMINATE'}),
      _app('a5', '정해지', 60, extra: <String, Object?>{'terminationStatus': 'PENDING', 'terminationRequestedAt': _ts(_kstDayMs(-1))}),
    ];

/// a2 의 연장 제안(응답 대기) — 효력 시작 = 지금 종료일 다음 날(DU543 r3 와 같다).
Map<String, Object?> _proposal() => <String, Object?>{
      'id': 'rp1', 'businessId': _biz1, 'businessName': _bizName, 'workerUid': 'u_a2', 'oldApplicationId': 'a2', 'status': 'PENDING',
      'effectiveStart': _ts(_kstDayMs(6)), 'effectiveEnd': _ts(_kstDayMs(36)), 'selectedWorkType': '홀서빙',
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _wtPath = 'businesses/$_biz1/workTypes';
const _appsFn = 'callableGetApplicationsByBiz';
const _schedFn = 'callableGetScheduleChangeRequestsForDate';

/// 첫 화면이 부르는 읽기 CF(DU540 · DU548 과 같은 4종) — 이 밖의 CF 이름(승인 · 거절 · 연장 포함)은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch', _schedFn};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536 · DU540 · DU548 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du551.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 4종 · workTypes 질의는 대역 응답, 그 밖 CF/Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다(DU540 · DU548 _Wire 와 같다).
class _Wire {
  _Wire(this.kind);

  /// 사례 이름 — WKND(토요일 · c1 추가근무 요청 대기 1건) · OUTP(평일 · 요청 0 · c2 계약 시작이 보는 날 뒤) · LIST(일반 모드 5명 · 연장 제안 1) · SETUP(호출 0).
  final String kind;
  final unexpected = <String>[];
  final blocked = <String>[];
  final otherFs = <String>[];
  final auth = <String>[];
  final harness = <String>[];
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return Future<ByteData?>.value(_cf(message));
    if (channel.startsWith('$_fsBase.')) return Future<ByteData?>.value(_fs(channel.substring(_fsBase.length + 1), message));
    for (final name in _authListeners) {
      if (channel == '$_authBase$name' || channel == '$_authFake$name') {
        auth.add(name);
        return handler?.call(message);
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }

  ByteData? _cf(ByteData? message) {
    const codec = StandardMessageCodec();
    try {
      final args = (codec.decodeMessage(message) as List).first as Map;
      final fn = args['functionName'].toString();
      final region = args['region'].toString();
      final params = (args['parameters'] as Map?) ?? const <Object?, Object?>{};
      if (region != 'asia-northeast3' || !_readFns.contains(fn)) {
        blocked.add('fn $fn@$region');
        return codec.encodeMessage(<Object?>['not-found', 'du551-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      final list = kind == 'LIST';
      _hit(fn);
      if (fn == _appsFn) {
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': list ? _apps() : _appsDate(kind)}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': list ? <Object?>[_proposal()] : const <Object?>[]}]);
      }
      if (fn == _schedFn) {
        // 날짜 모드의 일정 요청 조회(서비스가 businessIds · dateMs 를 보낸다) — 응답 = {items: [...]}(시각은 _ts 형식 · DU540 · DU548 과 같다).
        final items = kind == 'WKND' ? <Object?>[_schedReq(_saturdayAhead())] : const <Object?>[];
        return codec.encodeMessage(<Object?>[<String, Object?>{'items': items}]);
      }
      final uids = (params['uids'] as List).cast<String>();
      return codec.encodeMessage(<Object?>[
        <String, Object?>{
          'users': <String, Object?>{for (final u in uids) u: <String, Object?>{'name': _names[u] ?? '근로자', 'role': 'USER'}},
        },
      ]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du551-harness', null]);
    }
  }

  ByteData? _fs(String op, ByteData? message) {
    const codec = FirebaseFirestoreHostApi.codec;
    try {
      if (op == 'queryGet' && message != null) {
        // 요청 본문은 codec 으로 되읽을 수 없다(선례 du1_c1_edit_discard_test.dart:92–98) — 원본 바이트의 경로 문자열로 구분한다.
        final raw = String.fromCharCodes(message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
        if (raw.contains(_wtPath)) {
          _hit('workTypes');
          return codec.encodeMessage(<Object?>[
            PigeonQuerySnapshot(
              documents: [
                PigeonDocumentSnapshot(
                  path: '$_wtPath/wt1',
                  data: <String?, Object?>{
                    'businessId': _biz1, 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
                    'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
                  },
                  metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
                ),
              ],
              documentChanges: const [],
              metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
            ),
          ]);
        }
      }
      if (_fsWrites.contains(op)) {
        blocked.add('firestore $op');
      } else {
        otherFs.add(op);
      }
      return codec.encodeMessage(<Object?>['du551-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du551-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU551 관측 — 외부 HTTP 차단');
  }
}

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 두 상자가 겹치는가(겹친 넓이의 가로 · 세로 모두 0.5 초과).
bool _overlap(Rect a, Rect b) {
  final i = a.intersect(b);
  return i.width > 0.5 && i.height > 0.5;
}

/// 상자 [r] 를 [o] 기준 상대 좌표 'l,t,r,b'(소수 1자리)로.
String _rel(Rect r, Rect o) =>
    [r.left - o.left, r.top - o.top, r.right - o.left, r.bottom - o.top].map((x) => x.toStringAsFixed(1)).join(',');

/// 요소 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU543 r3 · DU548 `_tapNow` 와 같은 식).
({bool vis, bool hit, bool min48, Rect r}) _tapNow(WidgetTester t, Finder f, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  final min48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  return (vis: vis, hit: hit, min48: min48, r: r);
}

typedef _Txt = ({int n, String s, bool ex, int wb, int lines, Rect r});

/// 글 하나([f] = Text 위젯 하나)의 그려진 문단(읽기만) — 보이는 글(표시 제어 문자 제거) · 말줄임/줄 제한 넘음(didExceedMaxLines) ·
///   피할 수 있는 낱말 안 끊김 수(공용 판정기 du_word_break — DU538 과 같다) · 줄 수(글자 상자 윗변이 1px 넘게 내려간 횟수 + 1 · du_word_break 와 같은 줄 판정) · 자리.
_Txt _txtNow(WidgetTester t, Finder f) {
  final n = f.evaluate().length;
  if (n != 1) return (n: n, s: '', ex: false, wb: -1, lines: 0, r: Rect.zero);
  final rts = find.descendant(of: f, matching: find.byType(RichText, skipOffstage: false), skipOffstage: false).evaluate().toList();
  final nRt = rts.length;
  if (nRt != 1) return (n: -nRt, s: '', ex: false, wb: -1, lines: 0, r: Rect.zero);
  final rp = rts.first.renderObject! as RenderParagraph;
  final plain = rp.text.toPlainText();
  var lines = 0;
  double? lastTop;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      lines++;
      lastTop = top;
    }
  }
  final wb = wordBreaks(rp).where((x) => !x.forced).length;
  return (n: 1, s: visibleText(plain), ex: rp.didExceedMaxLines, wb: wb, lines: lines, r: t.getRect(f));
}

typedef _BodyObs = ({int emptyN, int failN, int toastN, String icon});

/// 본문 — 빈 상태 문구 수 · 조회 실패 안내 수(창 안) · 실패 토스트 수(창 밖) · 창 안 오류 아이콘이 있는가. 보이는 글 기준(DU540 · DU548 과 같은 식).
_BodyObs _bodyNow(WidgetTester t, Finder dlg) {
  final emptyN = find.descendant(of: dlg, matching: findVisibleText(_emptyText), skipOffstage: true).evaluate().length;
  final failN = find.descendant(of: dlg, matching: findVisibleText(_failText), skipOffstage: true).evaluate().length;
  final toastAll = findVisibleText(_failText).evaluate().length;
  final icons = find.descendant(of: dlg, matching: find.byIcon(Icons.error_outline), skipOffstage: true).evaluate().length;
  return (emptyN: emptyN, failN: failN, toastN: toastAll - failN, icon: icons == 0 ? '-' : 'n$icons');
}

typedef _HeadObs = ({int nn, int nl, int nx, int np, int vn, int pc});

/// 날짜 머리 띠 통계 칸 수(출근예정 · 휴무 · 추가근무 · 대기) · 출근예정 숫자 · '대기 n건' 칩 수(fixture 확인 · DU548 `_headNow` 와 같다).
_HeadObs _headNow(WidgetTester t, Finder dlg) {
  final titleF = find.descendant(of: dlg, matching: findVisibleTextContaining(_dateTitleTail), skipOffstage: true);
  if (titleF.evaluate().length != 1) return (nn: -1, nl: -1, nx: -1, np: -1, vn: -1, pc: -1);
  final subF = find.ancestor(of: titleF, matching: find.byType(Container)).first;
  Finder lab(String s) => find.descendant(of: subF, matching: find.text(s), skipOffstage: true);
  var vn = -1;
  final nF = lab('출근예정');
  if (nF.evaluate().length == 1) {
    final chipF = find.ancestor(of: nF, matching: find.byType(Container)).first;
    final texts = find.descendant(of: chipF, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
    if (texts.length == 2) vn = int.tryParse(texts.last.data ?? '') ?? -1;
  }
  return (
    nn: nF.evaluate().length, nl: lab('휴무').evaluate().length, nx: lab('추가근무').evaluate().length, np: lab('대기').evaluate().length,
    vn: vn, pc: lab(_pendChipText).evaluate().length,
  );
}

typedef _HdrObs = ({
  bool tfull, bool tex, int twb, int tl, bool tvis, bool tin, int cn, String cfull, String cex, String cvis, String cin, String place,
  int sn, bool svis, bool sex, String sh, bool kvis, bool khit, bool xvis, bool xhit, String raw
});

/// 날짜 머리 띠(첫 화면 · 끌기 전) — 날짜 글(전문 · 말줄임 · 낱말 안 끊김 · 줄 수 · 창 안 · 머리 띠 상자 안) · 요청 표시 칩 [chip](없으면 '-') ·
///   칩 자리(날짜 글 오른쪽 = side · 아래 = below) · 통계 라벨(수 · 머리 띠 안 + 창 안 · 말줄임) · 머리 띠 높이 · 닫기(아래 '닫기' 글 · 위 × 아이콘) 도달.
_HdrObs _hdrNow(WidgetTester t, Finder dlg, Rect screen, String chip) {
  final titleF = find.descendant(of: dlg, matching: findVisibleTextContaining(_dateTitleTail), skipOffstage: true);
  final subF = find.ancestor(of: titleF, matching: find.byType(Container)).first;
  final subR = t.getRect(subF);
  final tt = _txtNow(t, titleF);
  final tp = _tapNow(t, titleF, dlg, screen);
  final chipF = find.descendant(of: subF, matching: find.text(chip), skipOffstage: true);
  final cn = chip.isEmpty ? 0 : chipF.evaluate().length;
  var cfull = '-', cex = '-', cvis = '-', cin = '-', place = '-', craw = '-';
  if (cn == 1) {
    final co = _txtNow(t, chipF);
    final boxR = t.getRect(find.ancestor(of: chipF, matching: find.byType(Container)).first);
    final cp = _tapNow(t, chipF, dlg, screen);
    cfull = (co.n == 1 && co.s == chip).toString();
    cex = co.ex.toString();
    cvis = cp.vis.toString();
    cin = _inside(boxR, subR).toString();
    place = boxR.left >= tt.r.right - 0.5 && boxR.top < tt.r.bottom && boxR.bottom > tt.r.top
        ? 'side'
        : (boxR.top >= tt.r.bottom - 0.5 ? 'below' : 'other');
    craw = 'box ${_rel(boxR, subR)} text ${_rel(co.r, subR)} wb ${co.wb}';
  }
  var sn = 0;
  var svis = true;
  var sex = false;
  for (final lab in const ['출근예정', '휴무', '추가근무', '대기']) {
    final f = find.descendant(of: subF, matching: find.text(lab), skipOffstage: true);
    if (f.evaluate().length != 1) continue;
    sn++;
    final o = _txtNow(t, f);
    sex = sex || o.ex;
    svis = svis && _inside(o.r, subR) && _tapNow(t, f, dlg, screen).vis;
  }
  final kF = find.descendant(of: dlg, matching: find.text(_closeText), skipOffstage: true);
  final kp = kF.evaluate().length == 1 ? _tapNow(t, kF, dlg, screen) : null;
  final xF = find.descendant(of: dlg, matching: find.byIcon(Icons.close), skipOffstage: true);
  final xp = xF.evaluate().length == 1 ? _tapNow(t, xF, dlg, screen) : null;
  final raw = 'sub ${subR.height.toStringAsFixed(1)} title ${_rel(tt.r, subR)} s ${tt.s} lines ${tt.lines} wb ${tt.wb} chip $craw '
      'close ${kp?.r} ${kp?.vis}/${kp?.hit} x ${xp?.r} ${xp?.vis}/${xp?.hit}';
  return (
    tfull: tt.n == 1 && _titleRe.hasMatch(tt.s), tex: tt.ex, twb: tt.wb < 0 ? 0 : tt.wb, tl: tt.lines, tvis: tp.vis, tin: _inside(tt.r, subR),
    cn: cn, cfull: cfull, cex: cex, cvis: cvis, cin: cin, place: place, sn: sn, svis: svis, sex: sex, sh: subR.height.toStringAsFixed(1),
    kvis: kp?.vis ?? false, khit: kp?.hit ?? false, xvis: xp?.vis ?? false, xhit: xp?.hit ?? false, raw: raw,
  );
}

typedef _CardObs = ({bool full, bool ex, int wb, bool vis, bool nhit, bool inn, bool clr, String place, int wdl, String h, String geo, String raw});

/// [r2] 화면 글(Text 위젯)만 — find.text 는 검색 칸(EditableText) 글도 잡는다(일반 모드 첫 진입 자동 검색).
Finder _plainText(String s) => find.byWidgetPredicate((w) => w is Text && w.data == s, skipOffstage: false);

/// 카드 하나(이름 [who] · 이미 트리에 있다)의 기본 정보 — 이름 · 업무 · 요일 · 기간 · D-day · 날짜 배지([lab] · 비면 일반 모드 더보기 아이콘)를 글마다 읽는다(전문 · 말줄임 ·
///   낱말 안 끊김 · 요일 줄 수). 같은 순간의 자리로 카드 상자 안 · 서로 겹침 0 · 배지/더보기 자리(정보 오른쪽 = side · 아래 = below) · 카드 기준 상대 좌표(geo).
///   그 다음 글마다 ensureVisible 뒤 명단 칸 안(vis) · 이름 중심 hit(DU543 r3 · DU548 reach 와 같은 식). 누르지 않는다.
Future<_CardObs> _cardNow(WidgetTester t, Finder dlg, Rect screen, String who, String lab, String wantWd) async {
  final nameF = find.descendant(of: dlg, matching: _plainText(who), skipOffstage: false);
  final cardF = find.ancestor(of: nameF, matching: find.byType(InkWell)).first;
  final wtF = find.descendant(of: cardF, matching: find.text(_wtText, skipOffstage: false), skipOffstage: false);
  final calF = find.descendant(of: cardF, matching: find.byIcon(Icons.calendar_today_outlined, skipOffstage: false), skipOffstage: false);
  final wdF = find.descendant(of: find.ancestor(of: calF, matching: find.byType(Row)).first, matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
  final perF = find.descendant(of: cardF, matching: findVisibleTextContaining(' ~ '), skipOffstage: false);
  final ddF = find.descendant(
      of: cardF, matching: find.byWidgetPredicate((w) => w is Text && _ddRe.hasMatch(visibleText(w.data ?? '')), skipOffstage: false), skipOffstage: false);
  final isList = lab.isEmpty;
  final bdF = isList
      ? find.descendant(of: cardF, matching: find.byIcon(Icons.chevron_right, skipOffstage: false), skipOffstage: false)
      : find.descendant(of: cardF, matching: find.text(lab, skipOffstage: false), skipOffstage: false);
  final parts = <String, Finder>{'name': nameF, 'wt': wtF, 'wd': wdF, 'per': perF, 'dd': ddF, if (!isList) 'bd': bdF};
  final obs = <String, _Txt>{for (final e in parts.entries) e.key: _txtNow(t, e.value)};
  bool want(String k, String s) => switch (k) {
        'name' => s == who,
        'wt' => s == _wtText,
        'wd' => s == wantWd,
        'per' => _perRe.hasMatch(s),
        'dd' => _ddRe.hasMatch(s),
        _ => s == lab,
      };
  final full = obs.entries.every((e) => e.value.n == 1 && want(e.key, e.value.s));
  final ex = obs.values.any((o) => o.ex);
  final wb = obs.values.fold<int>(0, (a, o) => a + (o.wb < 0 ? 0 : o.wb));
  final nBox = bdF.evaluate().length;
  final cardR = t.getRect(cardF);
  final boxR = nBox != 1 ? Rect.zero : (isList ? t.getRect(bdF) : t.getRect(find.ancestor(of: bdF, matching: find.byType(Container)).first));
  final infoRs = [for (final k in const ['name', 'wt', 'wd', 'per', 'dd']) obs[k]!.r];
  final infoR = infoRs.reduce((a, b) => a.expandToInclude(b));
  final all = [...infoRs, boxR];
  final inn = nBox == 1 && all.every((r) => _inside(r, cardR));
  var clr = nBox == 1;
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      if (_overlap(all[i], all[j])) clr = false;
    }
  }
  final place = boxR.left >= infoR.right - 0.5 && boxR.top < infoR.bottom && boxR.bottom > infoR.top
      ? 'side'
      : (boxR.top >= infoR.bottom - 0.5 ? 'below' : 'other');
  final geo = '${_rel(obs['name']!.r, cardR)};${_rel(infoR, cardR)};${_rel(boxR, cardR)}';
  final wdl = obs['wd']!.lines;
  final h = cardR.height.toStringAsFixed(1);
  final txtRaw = obs.entries.map((e) => '${e.key} n${e.value.n} "${e.value.s}" ex ${e.value.ex} wb ${e.value.wb} l ${e.value.lines}').join(' · ');
  // 도달 — 글마다 하나씩 명단 칸 안으로(ensureVisible) 넣고 칸 안인가 · 이름 중심 hit.
  var vis = true;
  var nhit = false;
  var reachRaw = '';
  for (final e in parts.entries) {
    if (e.value.evaluate().length != 1) {
      vis = false;
      continue;
    }
    await t.ensureVisible(e.value);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final p = _tapNow(t, e.value, dlg, screen);
    vis = vis && p.vis;
    if (e.key == 'name') nhit = p.hit;
    reachRaw = '$reachRaw ${e.key} ${p.vis}';
  }
  final raw = 'who $who lab $lab $txtRaw card ${cardR.height.toStringAsFixed(1)} geo $geo place $place inn $inn clr $clr reach$reachRaw';
  return (full: full, ex: ex, wb: wb, vis: vis, nhit: nhit, inn: inn, clr: clr, place: place, wdl: wdl, h: h, geo: geo, raw: raw);
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'WKND', shots: 2), (id: 'OUTP', shots: 2), (id: 'LIST', shots: 1)];

/// 날짜 모드 사례별 — 카드 이름 → 날짜 배지 글(대역 + 창 `_getWorkerDayStatus` · `_buildDayStatusBadge` 소스로 정해진다 · 정렬 순서 가정 없음).
const _labels = <String, Map<String, String>>{
  'WKND': {'김가람': '추가근무 요청 중', '서다솜': '근무일', '이나래': '비근무일', '박다온': '비근무일'},
  'OUTP': {'김가람': '근무일', '서다솜': '추가근무', '이나래': '계약기간 외', '박다온': '휴무'},
};
/// 카드 이름 → 요일 글(창 `_formatWorkDays` = workDays.join(', ')).
const _days = <String, String>{'김가람': '월, 화, 수, 목, 금', '이나래': '월, 화, 수, 목, 금', '서다솜': '토, 일', '박다온': '월, 화, 수, 목, 금', '김연장': '월, 화, 수, 목, 금'};
/// 둘째 캡처 — 가장 넓은 배지 카드(WKND 김가람 '추가근무 요청 중' · OUTP 이나래 '계약기간 외')의 이름을 명단 칸 맨 위로.
const _wide = <String, String>{'WKND': '김가람', 'OUTP': '이나래'};
/// 일반 모드 대조 카드(첫 진입 대상 u_a1 자동 검색).
const _listWho = '김연장';
/// 글 원문.
const _titleText = '고정근무자 관리';
const _emptyText = '고정근무자가 없습니다';
const _failText = '고정근무자 목록을 불러오지 못했어요';
const _dateTitleTail = '근무 현황';
const _pendChipText = '대기 1건';
const _wtText = '홀서빙';
const _closeText = '닫기';
/// 날짜 글 · 기간 · D-day 전문 꼴(FormatHelper.formatDate · formatDateShort · `_buildDDayChip`).
final RegExp _titleRe = RegExp(r'^\d{1,2}/\d{1,2} \([월화수목금토일]\) 근무 현황$');
final RegExp _perRe = RegExp(r'^\d{1,2}/\d{1,2} ~ (\d{1,2}/\d{1,2}|미정)$');
final RegExp _ddRe = RegExp(r'^D-(\d+|Day)$');

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '551';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du551-tb' && _env['DU_BEFORE_OBSERVE'] == '551') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du551-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire('SETUP');
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      // FirebaseAuth 생성 때의 두 listener 등록 채널 모의(이벤트 0 · 로그인 상태 불변) — 창이 읽지 않으면 쓰이지 않는다.
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.calls.length + wire.blocked.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R551 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S951FD-${v.id}-${c.id} 고정근무자 관리 창 날짜 모드 머리 띠 날짜 행 · 카드 기본 정보 배지 배치 — 넘침 0 · 글 전문 · 순차 도달 · 일반 모드 대조', (t) async {
        final tok = 'S951FD-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire(c.id);
        final net = _NoHttp();
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D551 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
        // 카드 한 장 = 한 줄(날짜 모드 = 카드마다 · 일반 모드 = 1장 · lab '-' = 더보기 아이콘).
        void cardOut(String who, String lab, _CardObs co) => _out('D551 $tok att card who=${_enc(who)} lab=${_enc(lab)} full=${co.full} ex=${co.ex} wb=${co.wb} vis=${co.vis} nhit=${co.nhit} inn=${co.inn} clr=${co.clr} place=${co.place} wdl=${co.wdl} h=${co.h} geo=${co.geo}');

        final owner = _Owner();
        final isWknd = c.id == 'WKND';
        final isList = c.id == 'LIST';
        final isB = v.id == 'B';
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
            value: owner,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.businessAdminTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(
                  body: FixedWorkerManagementDialog(
                    key: UniqueKey(),
                    initialBusinessId: _biz1,
                    businesses: [_business(_biz1, _bizName)],
                    focusDate: isList ? null : _focusDay(isWknd ? _saturdayAhead() : _weekdayAhead()),
                    initialWorkerUid: isList ? 'u_a1' : null,
                    onChanged: () {},
                  ),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 40; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final dlg = find.byType(FixedWorkerManagementDialog);
          final nDlg = dlg.evaluate().length;
          need('창 1', nDlg == 1, '개수 $nDlg');
          final nTitle = find.text(_titleText).evaluate().length;
          need('창 제목 1', nTitle == 1, '개수 $nTitle');

          Future<void> shot(String id, String state) async {
            _out('D551 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용 — W 는 TB = TA 손 대조(후보는 문구를 바꾸지 않는다 · B 는 배치가 바뀌어 보이는 글 수가 달라질 수 있다).
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D551 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 첫 화면 — 본문 · 명단 칸(창 안 ListView 하나의 Scrollable).
          final b0 = _bodyNow(t, dlg);
          _out('D551 $tok att body emptyn=${b0.emptyN} failn=${b0.failN} toastn=${b0.toastN} icon=${b0.icon}');
          final br0 = 'empty ${b0.emptyN} fail ${b0.failN} toast ${b0.toastN} icon ${b0.icon}';
          need('본문 — 빈 상태 문구 0 · 실패 안내 0 · 토스트 0', b0.emptyN == 0 && b0.failN == 0 && b0.toastN == 0, br0);
          final listV = find.descendant(of: dlg, matching: find.byType(ListView), skipOffstage: false);
          final nLv = listV.evaluate().length;
          need('명단 ListView 1', nLv == 1, '개수 $nLv');
          final listSc = find.descendant(of: listV, matching: find.byType(Scrollable), skipOffstage: false).first;
          final lv = t.getRect(listSc).height.toStringAsFixed(1);
          raw = 'body $br0 lv $lv';

          if (isList) {
            // ② 일반 모드 대조 — 공유 카드(_buildWorkerCard)의 정보 줄 + 더보기 아이콘. 후보는 일반 모드 바깥 Row 를 그대로 두고 정보 안 이름 · 업무 · 요일 줄만 바꿨다.
            final nameN = find.descendant(of: dlg, matching: _plainText(_listWho), skipOffstage: false).evaluate().length;
            need('일반 모드 카드 이름 1(첫 진입 대상 자동 검색)', nameN == 1, '개수 $nameN');
            final co = await _cardNow(t, dlg, screen, _listWho, '', _days[_listWho]!);
            cardOut(_listWho, '', co);
            raw = '$raw card ${co.raw}';
            chk('일반 모드 $_listWho 이름 · 업무 · 요일 · 기간 · D-day 글 전문(대역 원문)', co.full, co.raw);
            chk('일반 모드 $_listWho 더보기 아이콘이 정보 오른쪽(이전 Row 그대로 · W · B 두 모드)', co.place == 'side', co.raw);
            if (!_before) {
              chk('strict 일반 모드 $_listWho 말줄임 0 · 낱말 안 끊김 0 · 카드 안 · 겹침 0 · 도달 · 이름 중심 hit', !co.ex && co.wb == 0 && co.inn && co.clr && co.vis && co.nhit, co.raw);
            }
            final nameF = find.descendant(of: dlg, matching: _plainText(_listWho), skipOffstage: false);
            await t.ensureVisible(nameF);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            await shot('1list', 'list-card-in-view');
          } else {
            // ② 날짜 머리 띠 — fixture 수(DU548 과 같다) + 날짜 행(날짜 글 · 요청 표시 칩 자리) · 통계 라벨 · 머리 띠 높이 · 닫기 도달.
            final h0 = _headNow(t, dlg);
            _out('D551 $tok att head nn=${h0.nn} nl=${h0.nl} nx=${h0.nx} np=${h0.np} vn=${h0.vn} pc=${h0.pc}');
            final hr = 'chips ${h0.nn}/${h0.nl}/${h0.nx}/${h0.np} vn ${h0.vn} pc ${h0.pc}';
            // WKND = 토요일(출근예정 서다솜 · 대기 김가람 · 비근무 2) · OUTP = 평일(출근예정 김가람 · 휴무 박다온 · 추가근무 서다솜 · 계약기간 외 이나래).
            need(isWknd ? '머리 띠 — 출근예정 1(1명) · 휴무 0 · 추가근무 0 · 대기 1 · 대기 1건 칩 1' : '머리 띠 — 출근예정 1(1명) · 휴무 1 · 추가근무 1 · 대기 0 · 대기 칩 0',
                isWknd
                    ? (h0.nn == 1 && h0.nl == 0 && h0.nx == 0 && h0.np == 1 && h0.vn == 1 && h0.pc == 1)
                    : (h0.nn == 1 && h0.nl == 1 && h0.nx == 1 && h0.np == 0 && h0.vn == 1 && h0.pc == 0),
                hr);
            final hd = _hdrNow(t, dlg, screen, isWknd ? _pendChipText : '');
            _out('D551 $tok att hdr tfull=${hd.tfull} tex=${hd.tex} twb=${hd.twb} tl=${hd.tl} tvis=${hd.tvis} tin=${hd.tin} cn=${hd.cn} cfull=${hd.cfull} cex=${hd.cex} cvis=${hd.cvis} cin=${hd.cin} place=${hd.place} sn=${hd.sn} svis=${hd.svis} sex=${hd.sex} sh=${hd.sh} lv=$lv kvis=${hd.kvis} khit=${hd.khit} xvis=${hd.xvis} xhit=${hd.xhit}');
            raw = '$raw head $hr hdr ${hd.raw}';
            chk('날짜 글 전문(월/일 (요일) 근무 현황) · 말줄임 0 · 낱말 안 끊김 0 · 창 안 · 머리 띠 안', hd.tfull && !hd.tex && hd.twb == 0 && hd.tvis && hd.tin, hd.raw);
            chk('통계 라벨 ${isWknd ? 2 : 3}개 · 머리 띠 안 + 창 안 · 말줄임 0', hd.sn == (isWknd ? 2 : 3) && hd.svis && !hd.sex, hd.raw);
            chk('닫기(아래 닫기 글) 창 안 · 중심 hit', hd.kvis && hd.khit, hd.raw);
            if (isWknd) {
              chk('요청 표시 칩 대기 1건 전문 · 말줄임 0', hd.cn == 1 && hd.cfull == 'true' && hd.cex == 'false', hd.raw);
              if (!isB) chk('W 요청 표시 칩이 날짜 글 오른쪽(이전 배치 그대로 · 두 모드)', hd.place == 'side' && hd.cvis == 'true' && hd.cin == 'true', hd.raw);
              if (!_before) chk('strict 요청 표시 칩 창 안 · 머리 띠 안 · 자리 side 또는 below', hd.cvis == 'true' && hd.cin == 'true' && hd.place != 'other', hd.raw);
            }
            await shot(isWknd ? '1wkend' : '1outp', isWknd ? 'date-weekend-first-screen' : 'date-outperiod-first-screen');

            // ③ 카드 4장 순차 도달 — 명단 칸을 실제로 끌어(한 번 60px · 최대 40번 · 개수 가드) 카드 이름이 onstage 가 되면 그 카드를 잰다
            //   (DU548 · DU543 r3 끌기 도달과 같은 식 · 대상 = 4장 전부 · 정렬 순서 가정 없음 · 먼저 보이는 것부터 · W 는 끌기 0 일 수 있다). 누르지 않는다.
            final labs = _labels[c.id]!;
            final who = labs.keys.toList();
            final measured = <String>{};
            var drags = 0;
            var cardRaw = '';
            while (measured.length < who.length && drags < 40) {
              String? next;
              for (final n in who) {
                if (!measured.contains(n) && find.descendant(of: dlg, matching: find.text(n), skipOffstage: true).evaluate().length == 1) {
                  next = n;
                  break;
                }
              }
              if (next != null) {
                final co = await _cardNow(t, dlg, screen, next, labs[next]!, _days[next]!);
                measured.add(next);
                cardOut(next, labs[next]!, co);
                cardRaw = '$cardRaw | ${co.raw}';
                chk('$next 이름 · 업무 · 요일 · 기간 · D-day · 날짜 배지(${labs[next]}) 글 전문(대역 원문)', co.full, co.raw);
                if (!isB) chk('W $next 날짜 배지가 정보 오른쪽(이전 배치 그대로 · 두 모드)', co.place == 'side', co.raw);
                if (!_before) {
                  chk('strict $next 말줄임 0 · 낱말 안 끊김 0', !co.ex && co.wb == 0, co.raw);
                  chk('strict $next 카드 안 · 정보 글/배지 겹침 0 · 배지 자리 side 또는 below', co.inn && co.clr && co.place != 'other', co.raw);
                  chk('strict $next 도달 — 글마다 명단 칸 안 · 이름 중심 hit', co.vis && co.nhit, co.raw);
                }
                continue;
              }
              await t.drag(listSc, const Offset(0, -60));
              await t.pump(const Duration(milliseconds: 50));
              drags++;
            }
            need('카드 ${who.length}장 모두 잼(끌기 최대 40번)', measured.length == who.length, 'cards ${measured.length} drags $drags');
            _out('D551 $tok att reach cards=${measured.length} drags=$drags');
            raw = '$raw reach ${measured.length}/$drags cards$cardRaw';
            // 둘째 캡처 — 가장 넓은 배지 카드의 이름을 명단 칸 맨 위로(측정은 위에서 끝났다).
            final wideF = find.descendant(of: dlg, matching: find.text(_wide[c.id]!, skipOffstage: false), skipOffstage: false);
            if (wideF.evaluate().length == 1) {
              await t.ensureVisible(wideF);
              for (var i = 0; i < 10; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
            }
            await shot(isWknd ? '2wkbadge' : '2outbadge', isWknd ? 'date-weekend-widest-badge-card' : 'date-outperiod-widest-badge-card');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ④ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer 가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // ⑤ 집계 — 읽기 호출 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
        final nApps = wire.calls[_appsFn] ?? 0;
        final nProps = wire.calls['callableGetRenewalProposalsByBiz'] ?? 0;
        final nUsers = wire.calls['callableGetUsersBatch'] ?? 0;
        final nSched = wire.calls[_schedFn] ?? 0;
        final nWt = wire.calls['workTypes'] ?? 0;
        final nWrites = wire.blocked.length;
        final nOtherFs = wire.otherFs.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.otherFs.map((x) => 'fs $x'), ...wire.harness].join(' | ');
        _out('D551 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt sched=$nSched writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R551 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D551 $tok att fw n=$nFw');
        _out('D551 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        chk(isList ? '읽기 대역 호출(지원서 1 · 업무유형 ≥1 · 일정 요청 0 — 일반 모드)' : '읽기 대역 호출(지원서 1 · 업무유형 ≥1 · 일정 요청 1)',
            nApps == 1 && nWt >= 1 && nSched == (isList ? 0 : 1), 'apps $nApps wt $nWt sched $nSched');
        // 넘침: W 는 두 모드 0(DU548 TB/TA 관측) · 일반 모드(LIST)는 두 모드 0(DU543 r3 RENEW W · B 관측) · 날짜 모드 B 는 strict 0 · before 기록(DU548 WKND 3 · OUTP 1).
        if (!isB || isList || !_before) chk('화면 전체 넘침 0(W · 일반 모드 두 모드 · 날짜 모드 B 는 strict)', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
