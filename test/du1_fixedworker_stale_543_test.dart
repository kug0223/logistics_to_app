// ignore_for_file: depend_on_referenced_packages
// [DU543 · stale] 고정근무자 관리 창(FixedWorkerManagementDialog) — 같은 사업장 재조회 실패(stale) 안내 + 다시 시도 · 상태변경 행동 · 일괄처리 · 상세 진입 비활성 ·
//   수동 사업장 전환 때 검색 비움 · 이 읽기의 실패 토스트 생략.
//   판정 = reports/DU_audit_self_review_retro135_2026-11-19.md §4 PP-FIXEDWORKER-READERROR-SCOPE-20261119 1항 + DU_audit_self_review_retro136_2026-11-19.md §4 · §5-3 · §5-4.
//   before = 현재 A(fixed_worker_management_dialog b297233f = DU540 채택판) 기록 전용 · strict = 후보(b0cccab2).
//   하네스 = DU539(두 사업장 · 사업장 선택 칸) + DU540(한 사업장 · 날짜 모드) 그대로 + 쓰기 CF 대역 1종 — SAME 사례에서만 callableCreateRenewalProposal 성공 응답 정확 1회
//     (감사136 §4 'SAME 관측 방법' · W · B 각 1 · 합 2 · 채널 안에서 끝냄 · 실서버 0). 그 밖 쓰기 CF/Firestore 쓰기는 차단하고 센다.
//   사례 5: RENEW(회귀 · 행동 활성) · FAIL(첫 조회 실패 — 본문 유지 · 토스트 0) · DATE(날짜 모드 — 승인/거절 활성 · 안내 0) ·
//     SWITCH(두 사업장 — 첫 진입 대상 자동 검색 → B 전환 → A 로 돌아옴) · SAME(연장 제안 성공 → 같은 사업장 재조회 실패 → stale · 비활성 → (strict) 다시 시도 성공).
//   누르는 것: SAME = 카드 띠 '연장' · 확인창 '연장 제안 보내기'(허용 대역 1회) · 카드(행동 시트 열기 — 읽기) · (strict) '다시 시도'. SWITCH = 사업장 선택 칸 · 목록 행.
//     비활성 대상은 누르지 않고 onPressed/onTap 값으로 잰다. 그 밖(승인 · 거절 · 일괄 연장 · 종료 · 시트 행)은 누르지 않는다.
//   기본 skip — TB before/du543-tb/DU_BEFORE_OBSERVE=543 · TA after/du543-ta/없음.
//   [r2 · 실행 전 판정 DU_decision_du543_preexecution_scope_2026-11-20] 허용 대역 gate 에 oldApplicationId=a1 검사 · stale 안내 수 키 onst(= offstage 제외 트리 존재 —
//     칸 안 가시 · 전문 · 첫 화면 인증 아님) · 막힌/다시 열린 버튼 표현(dis · redis · 시트 상세 행) · 명단 칸/첫 카드 높이 기록(view) · 안내 전문 끝 도달(tend) · 첫 카드 도달(reach).
//     대역 응답 총량 = 진단 2 + TB 2 + TA 2(사례마다 정확 1 · 판정 §2).
//   [r3 · 시험 수리 1회차] B-SAME 은 안내가 명단 칸을 채워 카드가 지연 생성 밖이었다(r2 진단 STOP) — 맨 위 값 · 1stale 캡처 · 안내 끝 뒤에 명단 칸을 실제로 끌어
//     카드에 닿은 다음 명단 유지 · 카드 띠 버튼 · 막힌 표현을 재고, 다시 시도 전에는 맨 위로 다시 끌어 닿는다(끌기 한 번 60px · 최대 20번 · W 는 끌기 0).
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
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/app_select_field.dart';

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
const _biz2 = 'biz2';
const _bizName2 = '역삼 카페';

/// 소유자(BUSINESS_ADMIN) — DU539 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz1, _biz2], sealBase64: 'seal');
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

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일.
Map<String, Object?> _app(String id, String applicant, int endIn,
        {String status = 'CONFIRMED', Map<String, Object?> extra = const <String, Object?>{}, String biz = _biz1, String bizName = _bizName}) =>
    <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': biz, 'businessName': bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': status, 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

const _names = <String, String>{
  'u_a1': '김연장', 'u_a2': '이대기', 'u_a3': '박서명', 'u_a4': '최종료', 'u_a5': '정해지',
  'u_c1': '김가람', 'u_c2': '이나래', 'u_c3': '서다솜', 'u_d1': '박다온', 'u_d2': '최라희',
};

/// 두 사업장 사례(SWITCH)의 근무자 이름 — A(biz1) 3명 · B(biz2) 2명.
const _namesA = <String>{'김가람', '이나래', '서다솜'};
const _namesB = <String>{'박다온', '최라희'};

/// 두 사업장 사례의 지원서 — 모두 만료가 멀다(만료 임박 띠 · 위험 통계 칩 없음). 호출마다 새로 만든다(DU539 와 같다).
List<Object?> _apps2(String biz) => biz == _biz1
    ? <Object?>[_app('c1', '김가람', 60), _app('c2', '이나래', 90), _app('c3', '서다솜', 120)]
    : <Object?>[_app('d1', '박다온', 70, biz: _biz2, bizName: _bizName2), _app('d2', '최라희', 100, biz: _biz2, bizName: _bizName2)];

/// 대역 5명(DU536 · DU540 과 같다 · 호출마다 새로 만든다) — a1 만료 10일 전 · a2 만료 5일 전 + 연장 제안 응답 대기 ·
///   a3 계약 처리 필요 · a4 종료 결정 · a5 해지 요청 중(통계 '해지대기').
List<Object?> _apps() => <Object?>[
      _app('a1', '김연장', 10),
      _app('a2', '이대기', 5),
      _app('a3', '박서명', 25, status: 'CONTRACT_PENDING'),
      _app('a4', '최종료', 40, extra: <String, Object?>{'renewalDecision': 'TERMINATE'}),
      _app('a5', '정해지', 60, extra: <String, Object?>{'terminationStatus': 'PENDING', 'terminationRequestedAt': _ts(_kstDayMs(-1))}),
    ];

/// a2 의 연장 제안(응답 대기) — 효력 시작 = 지금 종료일 다음 날(미래 → 응답 가능).
Map<String, Object?> _proposal() => <String, Object?>{
      'id': 'rp1', 'businessId': _biz1, 'businessName': _bizName, 'workerUid': 'u_a2', 'oldApplicationId': 'a2', 'status': 'PENDING',
      'effectiveStart': _ts(_kstDayMs(6)), 'effectiveEnd': _ts(_kstDayMs(36)), 'selectedWorkType': '홀서빙',
    };

/// 오늘(KST) 이후 첫 평일(월–금)까지 며칠(0–7) — 날짜 모드로 보는 날(DU540 과 같다).
int _weekdayAhead() {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  for (var d = 0; d < 8; d++) {
    if (DateTime.utc(k.year, k.month, k.day + d).weekday <= DateTime.friday) return d;
  }
  return 0;
}

/// 창에 넘기는 focusDate — 그 날의 로컬 자정(달력 화면 workforce_operational_view 가 넘기는 값과 같은 모양 `DateTime(y, m, d)`).
DateTime _focusDay(int ahead) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(k.year, k.month, k.day + ahead);
}

/// 날짜 모드 대역 2명(DU540 의 c1 · c2 와 같다) — c1 김가람: 월–금 · 가장 최근 확정(맨 위 카드) · 그 평일에 대기 중인 휴무 요청(인라인 승인/거절) · c2 이나래: 월–금.
List<Object?> _appsDate() => <Object?>[
      _app('c1', '김가람', 60, extra: <String, Object?>{'confirmedAt': _ts(_kstDayMs(-20))}),
      _app('c2', '이나래', 90),
    ];

/// c1 의 대기 중인 휴무 요청 한 건(지원자가 보낸 LEAVE · 대상 날짜 = 오늘(KST) + [ahead]일 — DU540 의 평일 대기 요청 사례와 같다).
Map<String, Object?> _schedReq(int ahead) => <String, Object?>{
      'id': 'sr1', 'businessId': _biz1, 'applicationId': 'c1', 'applicantUid': 'u_c1', 'applicantName': '김가람',
      'targetDate': _ts(_kstDayMs(ahead)), 'requestType': 'LEAVE', 'requestedBy': 'APPLICANT',
      'requestedByUid': 'u_c1', 'requestedAt': _ts(_kstDayMs(-1)), 'reason': '일정 조정 부탁드립니다', 'status': 'PENDING',
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
String _wtPathOf(String biz) => 'businesses/$biz/workTypes';
const _appsFn = 'callableGetApplicationsByBiz';
const _schedFn = 'callableGetScheduleChangeRequestsForDate';

/// [감사136 §4 'SAME 관측 방법'] 허용한 쓰기 CF — SAME 사례에서만 성공 대역 응답 정확 1회(그 밖 · 두 번째부터는 차단하고 센다).
const _mutFn = 'callableCreateRenewalProposal';

/// 첫 화면이 부르는 읽기 CF(일반 모드 3종 + 날짜 모드의 일정 요청 1종) — 이 밖의 CF 이름(승인 · 거절 · 연장 제안 포함)은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch', _schedFn};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// 사례@사업장별 — 지원서 조회 CF 의 몇 번째를 실패시키는가(FAIL = 첫 조회 · SAME = 연장 제안 성공 뒤의 재조회).
const _failAt = <String, Set<int>>{'FAIL@biz1': {1}, 'SAME@biz1': {2}};

/// [DU526 · DU534 · DU536 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du543.fake.auth.';
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

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 4종 · workTypes 질의는 대역 응답, SAME 의 연장 제안은 성공 대역 1회, 그 밖 CF/Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  _Wire(this.kind);

  /// 사례 이름 — FAIL(첫 조회 실패) · SAME(재조회 실패) · SWITCH(두 사업장 대역) · DATE(날짜 모드 대역) · 그 밖(5명 대역).
  final String kind;
  final unexpected = <String>[];
  final blocked = <String>[];
  final otherFs = <String>[];
  final auth = <String>[];
  final harness = <String>[];

  /// 허용 쓰기 대역(연장 제안 성공 응답)을 받은 원본 지원서 id — SAME 만 정확 1.
  final mutations = <String>[];
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
      if (region == 'asia-northeast3' && fn == _mutFn && kind == 'SAME' && mutations.isEmpty && params['oldApplicationId'] == 'a1') {
        // 기존 연장 → 성공 뒤 재조회 경로(창 _sendRenewalProposal)를 열기 위한 성공 응답 하나 — 채널 안에서 끝낸다(실서버 0 · 저장 0).
        mutations.add((params['oldApplicationId'] ?? '-').toString());
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposalId': 'rp-du543'}]);
      }
      if (region != 'asia-northeast3' || !_readFns.contains(fn)) {
        blocked.add('fn $fn@$region');
        return codec.encodeMessage(<Object?>['not-found', 'du543-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      final biz = (params['businessId'] ?? '-').toString();
      final two = kind == 'SWITCH';
      final dated = kind == 'DATE';
      _hit(fn);
      _hit('$fn@$biz');
      if (fn == _appsFn) {
        final nth = calls['$fn@$biz'] ?? 0;
        if ((_failAt['$kind@$biz'] ?? const <int>{}).contains(nth)) {
          return codec.encodeMessage(<Object?>['unavailable', 'du543 local failure', <String, Object?>{'code': 'unavailable', 'message': 'du543 local failure'}]);
        }
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': two ? _apps2(biz) : (dated ? _appsDate() : _apps())}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': (two || dated) ? const <Object?>[] : <Object?>[_proposal()]}]);
      }
      if (fn == _schedFn) {
        // 날짜 모드의 일정 요청 조회(서비스가 businessIds · dateMs 를 보낸다) — 응답 = {items: [...]}(시각은 _ts 형식).
        return codec.encodeMessage(<Object?>[<String, Object?>{'items': dated ? <Object?>[_schedReq(_weekdayAhead())] : const <Object?>[]}]);
      }
      final uids = (params['uids'] as List).cast<String>();
      return codec.encodeMessage(<Object?>[
        <String, Object?>{
          'users': <String, Object?>{for (final u in uids) u: <String, Object?>{'name': _names[u] ?? '근로자', 'role': 'USER'}},
        },
      ]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du543-harness', null]);
    }
  }

  ByteData? _fs(String op, ByteData? message) {
    const codec = FirebaseFirestoreHostApi.codec;
    try {
      if (op == 'queryGet' && message != null) {
        // 요청 본문은 codec 으로 되읽을 수 없다(선례 du1_c1_edit_discard_test.dart:92–98) — 원본 바이트의 경로 문자열로 구분한다.
        final raw = String.fromCharCodes(message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
        final wtBiz = raw.contains(_wtPathOf(_biz2)) ? _biz2 : _biz1;
        final wtPath = _wtPathOf(wtBiz);
        if (raw.contains(wtPath)) {
          _hit('workTypes');
          return codec.encodeMessage(<Object?>[
            PigeonQuerySnapshot(
              documents: [
                PigeonDocumentSnapshot(
                  path: '$wtPath/wt1',
                  data: <String?, Object?>{
                    'businessId': wtBiz, 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
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
      return codec.encodeMessage(<Object?>['du543-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du543-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU543 관측 — 외부 HTTP 차단');
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

String _hex(Color col) {
  String h(double x) => (x * 255).round().toRadixString(16).padLeft(2, '0');
  return '${h(col.a)}${h(col.r)}${h(col.g)}${h(col.b)}';
}

/// WCAG 대비 — [fg] 글자 · [bg] 불투명 바탕.
double _contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// 값이 모두 같으면 그 값, 아니면 '-'.
String _one(Iterable<String> xs) {
  final s = xs.toSet();
  return s.length == 1 ? s.first : '-';
}

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

/// [f](글)에서 가장 가까운 Container 의 면 색(BoxDecoration.color · 없으면 Container.color · 그것도 없으면 투명).
Color _faceOf(WidgetTester t, Finder f) {
  final box = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first);
  final d = box.decoration;
  if (d is BoxDecoration) return d.color ?? Colors.transparent;
  return box.color ?? Colors.transparent;
}

/// [f](글)에서 가장 가까운 Container 의 테두리 색(BoxDecoration.border 가 Border 일 때 윗변 색) — 테두리가 없으면 '-'.
String _edgeOf(WidgetTester t, Finder f) {
  final d = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first).decoration;
  final b = d is BoxDecoration ? d.border : null;
  return b is Border ? _hex(b.top.color) : '-';
}

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

final String _wantWhite = _hex(Colors.white);
final String _wantLine = _hex(AppColors.border);
final String _wantText1 = _hex(AppColors.textPrimary);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantGrey100 = _hex(AppColors.grey100);
final String _wantErr = _hex(AppColors.error);
final String _wantErrDark = _hex(AppColors.errorDark);
final String _wantBrand = _hex(AppColors.brand);
final String _wantTxtDis = _hex(AppColors.textDisabled);
final String _wantDisBg = _hex(AppColors.disabledBackground);

/// 통계 줄 바탕(grey50) — 칩 면이 반투명일 때 대비를 재는 밑색.
const Color _statsUnder = AppColors.grey50;

typedef _ChipObs = ({int n, String face, String bd, String lab, String bub, String num, bool cr});

/// 통계 칸 하나([label]) — 칸 면 · 선 · 라벨 글 · 숫자 방울 면 · 숫자 글 색과 대비(라벨/칸 면 · 숫자/방울 면). 위젯 값만 읽는다(DU536 과 같은 식).
_ChipObs _chip(WidgetTester t, String label) {
  final labF = find.text(label);
  final n = labF.evaluate().length;
  if (n != 1) return (n: n, face: '-', bd: '-', lab: '-', bub: '-', num: '-', cr: false);
  final chipF = find.ancestor(of: labF, matching: find.byType(Container)).first;
  final faceC = _faceOf(t, labF);
  final labC = _fgOf(t, labF);
  final bd = _edgeOf(t, labF);
  final texts = find.descendant(of: chipF, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
  final boxes = find.descendant(of: chipF, matching: find.byType(Container), skipOffstage: true).evaluate().map((e) => e.widget as Container).toList();
  if (texts.length != 2 || boxes.length != 1) return (n: n, face: _hex(faceC), bd: bd, lab: _hex(labC), bub: '-', num: '-', cr: false);
  final bubDeco = boxes.first.decoration;
  final bubC = bubDeco is BoxDecoration ? (bubDeco.color ?? Colors.transparent) : Colors.transparent;
  final numC = texts.last.style?.color ?? Colors.black;
  final under = Color.alphaBlend(faceC, _statsUnder);
  final cr = _contrast(labC, under) >= 4.5 && _contrast(numC, Color.alphaBlend(bubC, under)) >= 4.5;
  return (n: n, face: _hex(faceC), bd: bd, lab: _hex(labC), bub: _hex(bubC), num: _hex(numC), cr: cr);
}

typedef _StatsObs = ({int n0, int n1, int nx, String face, String bd, String lab, String bub, String num0, String num1, String numx, bool cr, String raw});

/// 통계 줄 — '전체' · '근무중' · (있으면) '해지대기'. 출력 한 줄(키 고정 · DU536 과 같은 키).
_StatsObs _statsLine(WidgetTester t, String tok) {
  final c0 = _chip(t, '전체');
  final c1 = _chip(t, '근무중');
  final cx = _chip(t, '해지대기');
  final shown = [c0, c1, if (cx.n == 1) cx];
  final face = _one(shown.map((x) => x.face));
  final bd = _one(shown.map((x) => x.bd));
  final lab = _one(shown.map((x) => x.lab));
  final bub = _one(shown.map((x) => x.bub));
  final cr = shown.every((x) => x.cr);
  _out('D543 $tok att stats n0=${c0.n} n1=${c1.n} nx=${cx.n} face=$face bd=$bd lab=$lab bub=$bub num0=${c0.num} num1=${c1.num} numx=${cx.num} cr45=$cr');
  return (
    n0: c0.n, n1: c1.n, nx: cx.n, face: face, bd: bd, lab: lab, bub: bub, num0: c0.num, num1: c1.num, numx: cx.num, cr: cr,
    raw: 'n ${c0.n}/${c1.n}/${cx.n} face $face bd $bd lab $lab bub $bub num ${c0.num}/${c1.num}/${cx.num} cr $cr',
  );
}

/// 통계 칸 단언(두 모드 — base 가 이미 DU536 · DU537 채택판이다): 바깥 면 · 선 · 라벨 중립 · 방울 grey100 · 전체/근무중 숫자 textPrimary · (있으면) 해지대기 숫자 errorDark.
List<(String, bool, String)> _statsChecks(_StatsObs so, {required bool withRisk}) => [
      ('통계 칸 면 = 흰색 · 선 = border · 라벨 = textSecondary · 숫자 방울 = grey100(DU536 그대로)', so.face == _wantWhite && so.bd == _wantLine && so.lab == _wantText2 && so.bub == _wantGrey100, so.raw),
      ('전체 · 근무중 숫자 = textPrimary(DU536 그대로)', so.num0 == _wantText1 && so.num1 == _wantText1, so.raw),
      if (withRisk) ('해지대기 칸 1 · 숫자 = errorDark(DU536 그대로)', so.nx == 1 && so.numx == _wantErrDark, so.raw),
      ('통계 칸 글/면 대비 ≥4.5', so.cr, so.raw),
    ];

/// 통계 칸 하나([label])의 숫자 — 칸이 하나가 아니거나 숫자가 아니면 -1(DU539 와 같다).
int _chipVal(WidgetTester t, String label) {
  final labF = find.text(label);
  if (labF.evaluate().length != 1) return -1;
  final chipF = find.ancestor(of: labF, matching: find.byType(Container)).first;
  final texts = find.descendant(of: chipF, matching: find.byType(Text), skipOffstage: true).evaluate().map((e) => e.widget as Text).toList();
  if (texts.length != 2) return -1;
  return int.tryParse(texts.last.data ?? '') ?? -1;
}

typedef _BodyObs = ({int emptyN, int failN, int toastN, String icon, int staleN});

/// 본문 — 빈 상태 문구 수 · 조회 실패 안내 수(창 안) · 실패 토스트 수(창 밖 — 본문과 토스트가 같은 글이라 화면 전체 수에서 창 안 수를 뺀다) ·
///   창 안 오류 아이콘 색(하나일 때만 · 아니면 '-') · 같은 사업장 재조회 실패 안내 수(창 안 · 트리 기준). 보이는 글 기준(DU537 과 같은 식).
_BodyObs _bodyNow(WidgetTester t, Finder dlg) {
  final emptyN = find.descendant(of: dlg, matching: findVisibleText(_emptyText), skipOffstage: true).evaluate().length;
  final failN = find.descendant(of: dlg, matching: findVisibleText(_failText), skipOffstage: true).evaluate().length;
  final toastAll = findVisibleText(_failText).evaluate().length;
  final toastIn = find.descendant(of: dlg, matching: findVisibleText(_failText), skipOffstage: true).evaluate().length;
  final icons = find.descendant(of: dlg, matching: find.byIcon(Icons.error_outline), skipOffstage: true).evaluate().toList();
  final ic = icons.length == 1 ? (icons.first.widget as Icon).color : null;
  final staleN = find.descendant(of: dlg, matching: findVisibleText(_staleText), skipOffstage: false).evaluate().length;
  return (emptyN: emptyN, failN: failN, toastN: toastAll - toastIn, icon: ic == null ? '-' : _hex(ic), staleN: staleN);
}

/// 행동 위젯 하나가 눌릴 수 있는가(값만 읽는다 · 누르지 않는다) — TextButton.onPressed · InkWell.onTap · GestureDetector.onTap 이 있으면 'true'. 없으면 '-'.
String _on(WidgetTester t, Finder f) {
  if (f.evaluate().isEmpty) return '-';
  final w = t.widget(f.first);
  if (w is TextButton) return (w.onPressed != null).toString();
  if (w is InkWell) return (w.onTap != null).toString();
  if (w is GestureDetector) return (w.onTap != null).toString();
  return '?';
}

typedef _LiveObs = ({int staleN, String bulkOn, String extOn, String endOn});

/// 명단의 stale 안내 수(트리 · 화면 밖 포함) · 일괄 연장(TextButton) · 카드 띠 연장/종료(InkWell)가 눌릴 수 있는가 — 위젯 값만('-' = 없음).
_LiveObs _liveNow(WidgetTester t, Finder dlg) {
  Finder inDlg(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
  return (
    staleN: inDlg(findVisibleText(_staleText)).evaluate().length,
    bulkOn: _on(t, inDlg(find.widgetWithText(TextButton, _bulkText, skipOffstage: false))),
    extOn: _on(t, find.ancestor(of: inDlg(find.text(_extText, skipOffstage: false)), matching: find.byType(InkWell))),
    endOn: _on(t, find.ancestor(of: inDlg(find.text(_endText, skipOffstage: false)), matching: find.byType(InkWell))),
  );
}

/// 창 안 Text 위젯 중 글이 [names] 에 든 것의 수(트리 · 화면 밖 포함 · 검색 칸 EditableText 는 세지 않는다).
int _textN(Finder dlg, Set<String> names) => find
    .descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Text && names.contains(w.data)), skipOffstage: false)
    .evaluate()
    .length;

/// 창 안 검색 칸의 글(_enc · 빈 값 '-'). 검색 칸이 하나가 아니면 '?'.
String _queryOf(WidgetTester t, Finder dlg) {
  final f = find.descendant(of: dlg, matching: find.byType(TextField), skipOffstage: false);
  if (f.evaluate().length != 1) return '?';
  return _enc(t.widget<TextField>(f).controller?.text ?? '');
}

typedef _ColObs = ({String bulkFg, String extBg, String extFg, String endFg});

/// [r2] 막힌 · 다시 열린 버튼 표현 — 일괄 연장 글 색 · 카드 띠 '연장' 채움면(Material) · 글 색 · '종료' 글 색(위젯 값 · 트리 기준 · 없으면 '-').
_ColObs _colorsNow(WidgetTester t, Finder dlg) {
  Finder inDlg(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
  final bulkF = inDlg(find.text(_bulkText, skipOffstage: false));
  final extF = inDlg(find.text(_extText, skipOffstage: false));
  final endF = inDlg(find.text(_endText, skipOffstage: false));
  String fg(Finder f) => f.evaluate().length == 1 ? _hex(_fgOf(t, f)) : '-';
  final extBg = extF.evaluate().length == 1
      ? _hex(t.widget<Material>(find.ancestor(of: extF, matching: find.byType(Material)).first).color ?? Colors.transparent)
      : '-';
  return (bulkFg: fg(bulkF), extBg: extBg, extFg: fg(extF), endFg: fg(endF));
}

typedef _ViewObs = ({String vph, String nth, String nvh, String cvh});

/// [r2 · 계측 · 기록만] stale 안내가 든 명단 칸(가장 가까운 Scrollable) 높이 · 안내 글 문단 높이 · 안내 상자의 칸 안 높이 · 첫 카드의 칸 안 높이
///   (카드 이름이 onstage 일 때만 잰다 — 아니면 0.0 · 화면 밖 rect 를 재지 않는다). 안내가 없으면 모두 0.0.
_ViewObs _viewNow(WidgetTester t, Finder dlg) {
  final txtF = find.descendant(of: dlg, matching: findVisibleText(_staleText), skipOffstage: true);
  if (txtF.evaluate().length != 1) return (vph: '0.0', nth: '0.0', nvh: '0.0', cvh: '0.0');
  final vp = t.getRect(find.ancestor(of: txtF, matching: find.byType(Scrollable)).first);
  double inVp(Rect r) {
    final h = r.intersect(vp).height;
    return h > 0 ? h : 0.0;
  }
  final rts = find.descendant(of: txtF, matching: find.byType(RichText), skipOffstage: true).evaluate().where((e) => !_underIcon(e)).toList();
  final nth = rts.length == 1 ? (rts.first.renderObject! as RenderParagraph).size.height : 0.0;
  final nvh = inVp(t.getRect(find.ancestor(of: txtF, matching: find.byType(Container)).first));
  final cardF = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Text && _sameName.contains(w.data)), skipOffstage: true);
  final cvh = cardF.evaluate().length == 1 ? inVp(t.getRect(find.ancestor(of: cardF, matching: find.byType(Material)).first)) : 0.0;
  return (vph: vp.height.toStringAsFixed(1), nth: nth.toStringAsFixed(1), nvh: nvh.toStringAsFixed(1), cvh: cvh.toStringAsFixed(1));
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 버튼 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 `_tapNow` 와 같은 식).
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

/// Icon 글리프의 RichText 인가(Icon 도 안에서 RichText 로 그려진다) — 글의 RichText 만 세려고 뺀다.
bool _underIcon(Element e) {
  var under = false;
  e.visitAncestorElements((a) {
    if (a.widget is Icon) under = true;
    return !under;
  });
  return under;
}

/// 글 하나([textF] = Text 위젯)의 낱말 안 줄바꿈 수(공용 판정기 du_word_break — 피할 수 있는 것 + 불가피한 것)와 문단 높이.
({int n, int wb, String h, String raw}) _wordsOf(WidgetTester t, Finder textF) {
  final n = textF.evaluate().length;
  if (n != 1) return (n: n, wb: 0, h: '0.0', raw: 'n $n');
  final rts = find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).evaluate().where((e) => !_underIcon(e)).toList();
  final nRt = rts.length;
  if (nRt != 1) return (n: 0, wb: 0, h: '0.0', raw: 'richtext $nRt');
  final rp = rts.first.renderObject! as RenderParagraph;
  final wbs = wordBreaks(rp);
  final h = rp.size.height.toStringAsFixed(1);
  return (n: 1, wb: wbs.length, h: h, raw: 'h $h w ${rp.size.width.toStringAsFixed(1)} wb ${wbs.join(' / ')}');
}

/// 통계 칩 — 보이는 칩 수 · 줄 수(칩 윗변 값의 가짓수) · 칩 안 라벨이 모두 한 줄인가(라벨 높이가 '전체' 라벨과 같다).
const _chipLabels = ['전체', '근무중', '계약 종료', '계약 확인', '퇴사대기', '해지대기'];
({int chips, int rows, bool oneline}) _chipsNow(WidgetTester t) {
  final tops = <String>{};
  final hs = <double>[];
  for (final lab in _chipLabels) {
    final f = find.text(lab);
    if (f.evaluate().length != 1) continue;
    tops.add(t.getRect(find.ancestor(of: f, matching: find.byType(Container)).first).top.toStringAsFixed(1));
    hs.add(t.getSize(f).height);
  }
  final oneline = hs.isNotEmpty && hs.every((h) => (h - hs.first).abs() < 0.5);
  return (chips: hs.length, rows: tops.length, oneline: oneline);
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'RENEW', shots: 2), (id: 'FAIL', shots: 1), (id: 'DATE', shots: 1), (id: 'SWITCH', shots: 2), (id: 'SAME', shots: 2)];

/// 사례별 — 첫 진입 대상 uid(창의 initialWorkerUid → 로드 뒤 그 사람 이름으로 자동 검색) · RENEW 카드의 D-day 글 · 카드 띠 글(보이는 글의 앞부분).
const _focus = <String, String>{'RENEW': 'u_a1', 'SAME': 'u_a1', 'SWITCH': 'u_c1'};
const _dday = <String, String>{'RENEW': 'D-10'};
const _bandText = <String, String>{'RENEW': '계약 만료 D-10'};
/// 글 원문.
const _titleText = '고정근무자 관리';
const _emptyText = '고정근무자가 없습니다';
const _loadingText = '고정근무자 로딩 중...';
const _expiringText = '계약 만료 임박';
const _bulkText = '일괄 연장';
const _extText = '연장';
const _endText = '종료';
const _okText = '승인';
const _noText = '거절';
const _retryText = '다시 시도';
const _proposeText = '연장 제안 보내기';
const _okToastPart = '연장 제안을 보냈습니다';
const _noMatchPart = '검색 결과가 없습니다';
/// 조회 실패 본문 · 같은 조회의 토스트(before = DU540 채택판은 둘 다 이 글 · strict = 후보는 토스트 없음).
const _failText = '고정근무자 목록을 불러오지 못했어요';
/// 같은 사업장 재조회 실패 안내(감사135 §4-1 원문).
const _staleText = '최신 정보를 불러오지 못했어요. 아래는 이전에 받은 내용입니다.';
/// SAME 사례의 카드 한 사람(첫 진입 대상 a1).
const _sameName = <String>{'김연장'};
/// 행동 시트의 행 제목(있을 수 있는 8행 — a1 에는 6행이 선다: 근로계약서 작성 · 해지 요청 취소 없음).
const _sheetTitles = <String>['상세 정보 보기', '추가근무 요청', '휴무 요청', '계약 연장 제안', '근로계약서 작성', '계약 만료 후 종료', '중도 계약 해지 요청', '해지 요청 취소'];
const _detailTitle = '상세 정보 보기';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '543';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du543-tb' && _env['DU_BEFORE_OBSERVE'] == '543') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du543-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    final nCf = wire.calls.length + wire.blocked.length + wire.mutations.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R543 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S911FT-${v.id}-${c.id} 고정근무자 관리 창 같은 사업장 재조회 실패 — 이전 명단 앞 안내 · 상태변경 행동 · 상세 진입 비활성 · 전환 때 검색 비움 · 실패 토스트 0', (t) async {
        final tok = 'S911FT-${v.id}-${c.id}';
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
        _out('D543 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final isRenew = c.id == 'RENEW';
        final isDate = c.id == 'DATE';
        final isTwo = c.id == 'SWITCH';
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
                  body: isTwo
                      ? FixedWorkerManagementDialog(
                          key: UniqueKey(),
                          businessIds: const [_biz1, _biz2],
                          initialBusinessId: _biz1,
                          businesses: [_business(_biz1, _bizName), _business(_biz2, _bizName2)],
                          initialWorkerUid: _focus[c.id],
                          onChanged: () {},
                        )
                      : FixedWorkerManagementDialog(
                          key: UniqueKey(),
                          initialBusinessId: _biz1,
                          businesses: [_business(_biz1, _bizName)],
                          initialWorkerUid: _focus[c.id],
                          focusDate: isDate ? _focusDay(_weekdayAhead()) : null,
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
            _out('D543 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용 — TB = TA 는 로그 대조.
          final words = <String>{};
          for (final e in find.descendant(of: dlg, matching: find.byType(Text), skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D543 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 본문 — 모든 사례 공통(첫 화면).
          final b0 = _bodyNow(t, dlg);
          _out('D543 $tok att body emptyn=${b0.emptyN} failn=${b0.failN} toastn=${b0.toastN} icon=${b0.icon} stalen=${b0.staleN}');
          final br0 = 'empty ${b0.emptyN} fail ${b0.failN} toast ${b0.toastN} icon ${b0.icon} stale ${b0.staleN}';
          raw = 'body $br0';

          if (isDate) {
            // ② 날짜 모드(stale 아님) — 인라인 승인 · 거절이 눌릴 수 있다(값만 · 누르지 않는다). stale 동안의 날짜 모드는 허용 대역으로 만들 수 없다(README).
            need('날짜 모드 본문 — 빈 상태 문구 0 · 실패 안내 0 · 토스트 0 · stale 안내 0', b0.emptyN == 0 && b0.failN == 0 && b0.toastN == 0 && b0.staleN == 0, br0);
            final okF = find.descendant(of: dlg, matching: find.text(_okText), skipOffstage: true);
            final noF = find.descendant(of: dlg, matching: find.text(_noText), skipOffstage: true);
            final nOk = okF.evaluate().length;
            final nNo = noF.evaluate().length;
            final okOn = _on(t, find.ancestor(of: okF, matching: find.byType(GestureDetector)));
            final noOn = _on(t, find.ancestor(of: noF, matching: find.byType(GestureDetector)));
            final okFace = nOk == 1 ? _hex(_faceOf(t, okF)) : '-';
            final okFg = nOk == 1 ? _hex(_fgOf(t, okF)) : '-';
            final noFg = nNo == 1 ? _hex(_fgOf(t, noF)) : '-';
            _out('D543 $tok att dlive okn=$nOk non=$nNo okon=$okOn noon=$noOn okface=$okFace okfg=$okFg nofg=$noFg');
            final dr = 'ok $nOk/$okOn $okFace/$okFg no $nNo/$noOn $noFg';
            raw = '$raw dlive $dr';
            need('인라인 승인 · 거절 각 1', nOk == 1 && nNo == 1, dr);
            if (!_before) chk('strict 날짜 모드(stale 아님) — 승인 · 거절 눌릴 수 있다(onTap 있음)', okOn == 'true' && noOn == 'true', dr);
            chk('날짜 모드(stale 아님) — 승인 brand 채움 · 흰 글 · 거절 errorDark 글(DU540 그대로 · 비활성 짝은 stale 일 때만)', okFace == _wantBrand && okFg == _wantWhite && noFg == _wantErrDark, dr);
            await shot('1date', 'date-pending-actions-live');
          } else if (isTwo) {
            // ③ 두 사업장 — 첫 진입 대상 자동 검색(김가람) → B 선택 → A 로 돌아옴. 누르는 것 = 사업장 선택 칸 · 목록 행(읽기만 일으킨다).
            Future<void> switchTo(String name) async {
              final selF = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is AppSelectField<String>), skipOffstage: true);
              final nSel = selF.evaluate().length;
              need('사업장 선택 칸 1', nSel == 1, '개수 $nSel');
              await t.tap(selF);
              for (var i = 0; i < 12; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final rowF = find.text(name);
              final nRow = rowF.evaluate().length;
              need('선택 목록의 $name 1', nRow == 1, '개수 $nRow');
              await t.tap(rowF);
              for (var i = 0; i < 40; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
            }

            ({String q, int an, int bn, int nomatch, int selA, int selB}) swNow() => (
                  q: _queryOf(t, dlg),
                  an: _textN(dlg, _namesA),
                  bn: _textN(dlg, _namesB),
                  nomatch: find.descendant(of: dlg, matching: findVisibleTextContaining(_noMatchPart), skipOffstage: false).evaluate().length,
                  selA: find.descendant(of: dlg, matching: find.text(_bizName), skipOffstage: true).evaluate().length,
                  selB: find.descendant(of: dlg, matching: find.text(_bizName2), skipOffstage: true).evaluate().length,
                );

            final w0 = swNow();
            _out('D543 $tok att sw0 q=${w0.q} an=${w0.an} bn=${w0.bn} nomatch=${w0.nomatch} sela=${w0.selA} selb=${w0.selB}');
            final r0 = 'q ${w0.q} an ${w0.an} bn ${w0.bn} nomatch ${w0.nomatch} sel ${w0.selA}/${w0.selB}';
            need('A 첫 화면 — 첫 진입 대상 자동 검색(김가람) · A 이름 1 · B 이름 0 · 선택 칸 = A',
                w0.q == _enc('김가람') && w0.an == 1 && w0.bn == 0 && w0.nomatch == 0 && w0.selA == 1 && w0.selB == 0, r0);

            await switchTo(_bizName2);
            final w1 = swNow();
            _out('D543 $tok att sw1 q=${w1.q} an=${w1.an} bn=${w1.bn} nomatch=${w1.nomatch} sela=${w1.selA} selb=${w1.selB}');
            final r1 = 'q ${w1.q} an ${w1.an} bn ${w1.bn} nomatch ${w1.nomatch} sel ${w1.selA}/${w1.selB}';
            need('B 선택 뒤 — 선택 칸 = B · A 이름 0', w1.selA == 0 && w1.selB == 1 && w1.an == 0, r1);
            if (!_before) chk('strict 수동 전환 — 검색어 빈 값 · 검색 결과 없음 0 · B 이름 ≥1', w1.q == '-' && w1.nomatch == 0 && w1.bn >= 1, r1);
            await shot('1sw', 'switched-to-biz-b');

            await switchTo(_bizName);
            final w2 = swNow();
            _out('D543 $tok att sw2 q=${w2.q} an=${w2.an} bn=${w2.bn} nomatch=${w2.nomatch} sela=${w2.selA} selb=${w2.selB}');
            final r2 = 'q ${w2.q} an ${w2.an} bn ${w2.bn} nomatch ${w2.nomatch} sel ${w2.selA}/${w2.selB}';
            need('A 로 돌아온 뒤 — 선택 칸 = A · B 이름 0', w2.selA == 1 && w2.selB == 0 && w2.bn == 0, r2);
            if (!_before) chk('strict A 로 돌아온 뒤 — 첫 진입 대상 자동 검색 다시 넣지 않음(검색어 빈 값 · 검색 결과 없음 0) · A 이름 ≥2', w2.q == '-' && w2.nomatch == 0 && w2.an >= 2, r2);
            raw = '$raw sw0 $r0 sw1 $r1 sw2 $r2';
            await shot('2back', 'switched-back-to-biz-a');
          } else if (c.id == 'SAME') {
            // ④ 같은 사업장 — 연장 제안 성공(허용 대역 1회) → 재조회 실패 → stale. 누르는 것 = 카드 띠 '연장' · '연장 제안 보내기' · 카드(시트 열기 · 읽기) · (strict) '다시 시도'.
            final p0 = _liveNow(t, dlg);
            final names0 = _textN(dlg, _sameName);
            final tot0 = _chipVal(t, '전체');
            _out('D543 $tok att pre stalen=${p0.staleN} bulkon=${p0.bulkOn} exton=${p0.extOn} endon=${p0.endOn} names=$names0 tot=$tot0');
            final q0 = 'stale ${p0.staleN} bulk ${p0.bulkOn} ext ${p0.extOn} end ${p0.endOn} names $names0 tot $tot0';
            need('연장 전 — 안내 0 · 일괄 연장 · 연장 · 종료 눌릴 수 있다 · 카드 1 · 전체 5',
                p0.staleN == 0 && p0.bulkOn == 'true' && p0.extOn == 'true' && p0.endOn == 'true' && names0 == 1 && tot0 == 5, q0);

            final sameExt = find.ancestor(of: find.descendant(of: dlg, matching: find.text(_extText), skipOffstage: false), matching: find.byType(InkWell));
            await t.ensureVisible(sameExt.first);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            await t.tap(sameExt.first);
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final sendF = find.text(_proposeText);
            final nSend = sendF.evaluate().length;
            need('연장 제안 확인창의 보내기 1', nSend == 1, '개수 $nSend');
            await t.tap(sendF);
            for (var i = 0; i < 20; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            // 재조회가 끝난 직후(실패 토스트 4초 · 성공 토스트 2초 안).
            final nMut = wire.mutations.length;
            final nApps1 = wire.calls[_appsFn] ?? 0;
            final b1 = _bodyNow(t, dlg);
            final okToast = findVisibleTextContaining(_okToastPart).evaluate().length;
            _out('D543 $tok att st mut=$nMut apps=$nApps1 toastn=${b1.toastN} okt=$okToast');
            final q1 = 'mut $nMut ${wire.mutations.join('+')} apps $nApps1 toast ${b1.toastN} okt $okToast';
            need('연장 제안 대역 정확 1회 · 지원서 조회 2(첫 조회 + 실패한 재조회)', nMut == 1 && nApps1 == 2, q1);
            if (!_before) chk('strict 재조회 실패 — 이 읽기의 실패 토스트 0', b1.toastN == 0, q1);

            // 토스트가 내려간 뒤의 화면.
            for (var i = 0; i < 5; i++) {
              await t.pump(const Duration(seconds: 1));
            }
            final s2 = _liveNow(t, dlg);
            final tot2 = _chipVal(t, '전체');
            final b2 = _bodyNow(t, dlg);
            // onst = skipOffstage:true finder 수 — offstage 제외 트리 존재다(칸 안 가시 · 전문 · 첫 화면 인증 아님 · 판정 :65). 끌기 전 맨 위 값.
            final onst2 = find.descendant(of: dlg, matching: findVisibleText(_staleText), skipOffstage: true).evaluate().length;
            final load2 = find.descendant(of: dlg, matching: find.text(_loadingText), skipOffstage: true).evaluate().length;
            final v2 = _viewNow(t, dlg);
            _out('D543 $tok att view vph=${v2.vph} nth=${v2.nth} nvh=${v2.nvh} cvh=${v2.cvh}');
            final q2v = 'vph ${v2.vph} nth ${v2.nth} nvh ${v2.nvh} cvh ${v2.cvh}';
            await shot('1stale', 'same-biz-reload-failed');

            // 안내 전문 끝까지 닿는가 — 글 아래 끝을 명단 칸 아래 끝에 맞춰 끈다(Scrollable.ensureVisible · alignment 1.0) → 글 아래 끝이 칸 안인가. 숨김 · 말줄임 · 글자 축소 0(제품 그대로).
            final teF = find.descendant(of: dlg, matching: findVisibleText(_staleText), skipOffstage: false);
            final nTe = teF.evaluate().length;
            var teIn = false;
            if (nTe == 1) {
              await Scrollable.ensureVisible(t.element(teF), alignment: 1.0);
              for (var i = 0; i < 10; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final teVp = t.getRect(find.ancestor(of: teF, matching: find.byType(Scrollable)).first);
              final teR = t.getRect(teF);
              teIn = teR.bottom <= teVp.bottom + 0.5 && teR.bottom >= teVp.top - 0.5;
            }
            _out('D543 $tok att tend n=$nTe in=$teIn');
            final q2t = 'n $nTe in $teIn';
            if (!_before) chk('strict stale 안내 전문 끝 — 끌어서 글 아래 끝이 명단 칸 안(숨김 · 말줄임 · 축소 0)', nTe == 1 && teIn, q2t);

            // [r3] 첫 카드 도달 — 명단 칸(안내 · 카드의 Scrollable)을 실제로 끌어(한 번 60px · 최대 20번 · 개수 가드) 카드 이름이 onstage 가 되면 멈추고 맞춘다.
            //   B 는 안내가 칸을 채워 카드가 지연 생성 밖이다(r2 진단). W 는 처음부터 보여 끌기 0. 끌기는 칸 중심에서 · 측정은 onstage 뒤(화면 밖 rect 0).
            final nameF = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Text && _sameName.contains(w.data)), skipOffstage: false);
            final nameOn = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Text && _sameName.contains(w.data)), skipOffstage: true);
            // 명단 칸 = 창 안 ListView 하나의 Scrollable(지연 생성되는 자식에 기대지 않는다 — 안내가 칸 밖으로 버려져도 같은 칸).
            final listV = find.descendant(of: dlg, matching: find.byType(ListView), skipOffstage: false);
            final nLv = listV.evaluate().length;
            need('명단 ListView 1 · 카드 이름 트리 0 또는 1', nLv == 1 && nameF.evaluate().length <= 1, '개수 $nLv');
            final listSc = find.descendant(of: listV, matching: find.byType(Scrollable), skipOffstage: false).first;
            var cDrags = 0;
            while (nameOn.evaluate().isEmpty && cDrags < 20) {
              await t.drag(listSc, const Offset(0, -60));
              await t.pump(const Duration(milliseconds: 50));
              cDrags++;
            }
            final nName = nameOn.evaluate().length;
            need('카드 이름 1(끌어서 · 최대 20번)', nName == 1, '개수 $nName 끌기 $cDrags');
            await t.ensureVisible(nameOn);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final pc = _tapNow(t, nameOn, dlg, screen);
            _out('D543 $tok att reach drags=$cDrags cvis=${pc.vis} chit=${pc.hit}');
            final q2r = 'drags $cDrags name ${pc.r} vis ${pc.vis} hit ${pc.hit}';

            // 명단 유지 · 카드 띠 연장/종료 · 일괄 연장 · 막힌 표현 — 카드가 트리에 든 뒤에 잰다(안내 · 통계 · 본문 · 로딩은 위 맨 위 값).
            final s2c = _liveNow(t, dlg);
            final names2 = _textN(dlg, _sameName);
            _out('D543 $tok att stale stalen=${s2.staleN} onst=$onst2 names=$names2 tot=$tot2 bulkon=${s2c.bulkOn} exton=${s2c.extOn} endon=${s2c.endOn} loading=$load2 failn=${b2.failN} toastn=${b2.toastN}');
            final q2 = 'stale ${s2.staleN} onst $onst2 names $names2 tot $tot2 bulk ${s2c.bulkOn} ext ${s2c.extOn} end ${s2c.endOn} loading $load2 fail ${b2.failN} toast ${b2.toastN}';
            need('재조회 실패 뒤 — 이전 명단 유지(카드 1 · 전체 5) · 로딩 0 · 첫 조회 실패 본문 0', names2 == 1 && tot2 == 5 && load2 == 0 && b2.failN == 0, q2);
            if (!_before) {
              chk('strict stale — 안내 1(트리) · offstage 제외 트리 1(칸 안 가시 · 전문 · 첫 화면 인증 아님) · 실패 토스트 0', s2.staleN == 1 && onst2 == 1 && b2.toastN == 0, q2);
              chk('strict stale — 일괄 연장 · 연장 · 종료 비활성(값 null · 누르지 않음)', s2c.bulkOn == 'false' && s2c.extOn == 'false' && s2c.endOn == 'false', q2);
            }
            final c2 = _colorsNow(t, dlg);
            _out('D543 $tok att dis bulkfg=${c2.bulkFg} extbg=${c2.extBg} extfg=${c2.extFg} endfg=${c2.endFg}');
            final q2c = 'bulk ${c2.bulkFg} ext ${c2.extBg}/${c2.extFg} end ${c2.endFg}';
            if (!_before) {
              chk('strict stale — 막힌 버튼 기존 비활성 짝(일괄 연장 글 · 연장 글 textDisabled · 연장 채움 disabledBackground · 종료 글 textDisabled)',
                  c2.bulkFg == _wantTxtDis && c2.extBg == _wantDisBg && c2.extFg == _wantTxtDis && c2.endFg == _wantTxtDis, q2c);
            }

            // 행동 시트 — 맞춘 카드 이름을 눌러 연다(읽기). 행은 누르지 않고 onTap 값으로 잰다. 닫기는 루트 Navigator pop(시험만).
            await t.tap(nameOn);
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            var rows = 0;
            var off = 0;
            var detOn = '-';
            var detFg = '-';
            var detIc = '-';
            for (final title in _sheetTitles) {
              final tf = find.text(title, skipOffstage: false);
              if (tf.evaluate().length != 1) continue;
              rows++;
              final on = _on(t, find.ancestor(of: tf, matching: find.byType(InkWell)));
              if (on == 'false') off++;
              if (title == _detailTitle) {
                detOn = on;
                detFg = _hex(_fgOf(t, tf));
                final ics = find.descendant(of: find.ancestor(of: tf, matching: find.byType(InkWell)).first, matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
                detIc = ics.isEmpty ? '-' : _hex((ics.first.widget as Icon).color ?? Colors.black);
              }
            }
            _out('D543 $tok att sheet rows=$rows off=$off deton=$detOn tfg=$detFg ifg=$detIc');
            final q3 = 'rows $rows off $off detail $detOn fg $detFg icon $detIc';
            need('행동 시트 행 6(a1)', rows == 6, q3);
            if (!_before) {
              chk('strict stale — 행동 시트 6행 전부 비활성 · 상세 정보 보기 비활성', off == 6 && detOn == 'false', q3);
              chk('strict stale — 시트 행 기존 비활성 짝(상세 정보 보기 제목 · 아이콘 textDisabled · 시트를 연 시점 값)', detFg == _wantTxtDis && detIc == _wantTxtDis, q3);
            }
            navigatorKey.currentState?.pop();
            for (var i = 0; i < 12; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final left = find.text(_detailTitle, skipOffstage: false).evaluate().length;
            need('행동 시트 닫힘', left == 0, '남은 $left');

            // 다시 시도 — strict 만 실제로 누른다(읽기 재호출 · 쓰기 0). before 는 버튼이 없다 — 누르지 않고 같은 화면을 기록한다.
            final retryF = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _retryText, skipOffstage: false), skipOffstage: false);
            // [r3] 맨 위로 다시 끌어(한 번 60px · 최대 20번 · 맨 위면 멈춤 · 개수 가드) 다시 시도가 onstage 가 되게 한 뒤 센다 — 카드까지 끈 B 에서 안내가 지연 생성 밖일 수 있다.
            //   W 는 끌기 0 · before 는 안내가 없어 맨 위까지만.
            final retryOn = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _retryText), skipOffstage: true);
            var rDrags = 0;
            while (retryOn.evaluate().isEmpty && t.state<ScrollableState>(listSc).position.pixels > 0 && rDrags < 20) {
              await t.drag(listSc, const Offset(0, 60));
              await t.pump(const Duration(milliseconds: 50));
              rDrags++;
            }
            final nRetry = retryF.evaluate().length;
            var rVis = false;
            var rHit = false;
            var rMin48 = false;
            var rr = '-';
            if (nRetry == 1) {
              await t.ensureVisible(retryF);
              for (var i = 0; i < 10; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final p4 = _tapNow(t, retryF, dlg, screen);
              rVis = p4.vis;
              rHit = p4.hit;
              rMin48 = p4.min48;
              rr = p4.r.toString();
            }
            _out('D543 $tok att retry n=$nRetry drags=$rDrags vis=$rVis hit=$rHit min48=$rMin48');
            final q4 = 'n $nRetry drags $rDrags vis $rVis hit $rHit min48 $rMin48 r $rr';
            if (!_before) chk('strict 다시 시도 1 · 명단 칸 안 보임 · 중심 hit · ≥48', nRetry == 1 && rVis && rHit && rMin48, q4);
            var tapped = false;
            if (!_before) {
              need('다시 시도 1(탭 직전)', nRetry == 1, '개수 $nRetry');
              await t.tap(retryF);
              tapped = true;
            }
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final s5 = _liveNow(t, dlg);
            final names5 = _textN(dlg, _sameName);
            final tot5 = _chipVal(t, '전체');
            final b5 = _bodyNow(t, dlg);
            final load5 = find.descendant(of: dlg, matching: find.text(_loadingText), skipOffstage: true).evaluate().length;
            final nApps5 = wire.calls[_appsFn] ?? 0;
            final query5 = _queryOf(t, dlg);
            _out('D543 $tok att rs tapped=$tapped stalen=${s5.staleN} names=$names5 tot=$tot5 bulkon=${s5.bulkOn} exton=${s5.extOn} endon=${s5.endOn} apps=$nApps5 q=$query5 failn=${b5.failN} toastn=${b5.toastN} loading=$load5');
            final q5 = 'tapped $tapped stale ${s5.staleN} names $names5 tot $tot5 bulk ${s5.bulkOn} ext ${s5.extOn} end ${s5.endOn} apps $nApps5 q $query5 '
                'fail ${b5.failN} toast ${b5.toastN} loading $load5';
            final c5 = _colorsNow(t, dlg);
            _out('D543 $tok att redis bulkfg=${c5.bulkFg} extbg=${c5.extBg} extfg=${c5.extFg} endfg=${c5.endFg}');
            final q5c = 'bulk ${c5.bulkFg} ext ${c5.extBg}/${c5.extFg} end ${c5.endFg}';
            raw = '$raw pre $q0 st $q1 view $q2v tend $q2t reach $q2r stale $q2 dis $q2c sheet $q3 retry $q4 rs $q5 redis $q5c';
            if (!_before) {
              chk('strict 다시 시도 성공 — 지원서 조회 3 · 안내 0 · 일괄 연장 · 연장 · 종료 다시 눌릴 수 있다',
                  nApps5 == 3 && s5.staleN == 0 && s5.bulkOn == 'true' && s5.extOn == 'true' && s5.endOn == 'true', q5);
              chk('strict 다시 시도 성공 — 명단 1 · 전체 5 · 같은 사업장 검색어 유지(김연장) · 실패 0 · 토스트 0 · 로딩 0',
                  names5 == 1 && tot5 == 5 && query5 == _enc('김연장') && b5.failN == 0 && b5.toastN == 0 && load5 == 0, q5);
              chk('strict 다시 시도 성공 — 버튼 표현 활성으로 복귀(일괄 연장 brand · 연장 brand 채움/흰 글 · 종료 textSecondary)',
                  c5.bulkFg == _wantBrand && c5.extBg == _wantBrand && c5.extFg == _wantWhite && c5.endFg == _wantText2, q5c);
            }
            await shot('2retry', 'same-biz-after-retry');
          } else {
            // ⑤ (회귀 · 일반 모드 · DU540 TA 측정 그대로) 머리 통계 · 칩 배치.
            final so = _statsLine(t, tok);
            final lay = _chipsNow(t);
            _out('D543 $tok att lay chips=${lay.chips} rows=${lay.rows} oneline=${lay.oneline}');
            final wantChips = isRenew ? 3 : 2;
            need('통계 칸 전체 · 근무중 각 1 · 해지대기 ${isRenew ? 1 : 0} · 칩 $wantChips', so.n0 == 1 && so.n1 == 1 && so.nx == (isRenew ? 1 : 0) && lay.chips == wantChips, so.raw);
            for (final x in _statsChecks(so, withRisk: isRenew)) {
              chk(x.$1, x.$2, x.$3);
            }
            final lr = 'chips ${lay.chips} rows ${lay.rows} oneline ${lay.oneline}';
            chk('통계 칩 안 줄바꿈 0(라벨 한 줄)', lay.oneline, lr);
            if (!isB) chk('W 통계 칩 한 줄(이전과 같다)', lay.rows == 1, lr);
            raw = '$raw stats ${so.raw} lay $lr';

            if (isRenew) {
              // ⑥ 만료 임박 띠 — 글 낱말 안 끊김 · 일괄 연장(색 · 보임 · hit · 받는 자리 기록 · 글 아래로 내려갔는가). 누르지 않는다.
              final bulkBtn = find.descendant(of: dlg, matching: find.widgetWithText(TextButton, _bulkText), skipOffstage: true);
              final extInk = find.ancestor(of: find.text(_extText), matching: find.byType(InkWell));
              final endInk = find.ancestor(of: find.text(_endText), matching: find.byType(InkWell));
              final ddF = find.text(_dday[c.id] ?? '(없음)');
              final bulkF = find.text(_bulkText);
              final nBulk = bulkF.evaluate().length;
              need('일괄 연장 1 · 버튼 1', nBulk == 1 && bulkBtn.evaluate().length == 1, '글 $nBulk');
              final fgC = t.widget<Text>(bulkF).style?.color ?? Colors.black;
              final faceC = _faceOf(t, bulkF);
              final resolved = t.widget<TextButton>(bulkBtn).style?.foregroundColor?.resolve(<WidgetState>{});
              final bulkCr = _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5;
              final btnFg = resolved == null ? '-' : _hex(resolved);
              _out('D543 $tok att bulk n=$nBulk fg=${_hex(fgC)} btnfg=$btnFg face=${_hex(faceC)} cr45=$bulkCr');
              final bandF = find.descendant(of: dlg, matching: findVisibleTextContaining(_expiringText), skipOffstage: true);
              final bw = _wordsOf(t, bandF);
              need('만료 임박 띠 글 1', bw.n == 1, bw.raw);
              final bp = _tapNow(t, bulkBtn, dlg, screen);
              final stack = bp.r.top >= t.getRect(bandF).bottom - 0.5;
              _out('D543 $tok att band n=${bw.n} wb=${bw.wb} h=${bw.h} bvis=${bp.vis} bhit=${bp.hit} bmin48=${bp.min48} stack=$stack');
              final bandRaw = '${bw.raw} bulk ${bp.r} vis ${bp.vis} hit ${bp.hit} min48 ${bp.min48} stack $stack';
              raw = '$raw band $bandRaw';
              chk('만료 임박 띠 글 낱말 안 끊김 0(DU538 그대로)', bw.wb == 0, bandRaw);
              chk('일괄 연장 화면 안 · 중심 hit(DU538 그대로)', bp.vis && bp.hit, bandRaw);
              chk(isB ? 'B 일괄 연장이 글 아래로(DU538 그대로)' : 'W 일괄 연장이 글 옆(DU538 그대로)', stack == isB, bandRaw);

              // ⑦ 카드 — D-day 칩(색 = DU536 그대로) · 카드 띠 글의 낱말 안 끊김.
              final nDd = ddF.evaluate().length;
              need('D-day 칩 1', nDd == 1, '개수 $nDd');
              final ddFg = t.widget<Text>(ddF).style?.color ?? Colors.black;
              final ddFace = _faceOf(t, ddF);
              final ddCr = _contrast(ddFg, Color.alphaBlend(ddFace, Colors.white)) >= 4.5;
              _out('D543 $tok att dday n=$nDd fg=${_hex(ddFg)} face=${_hex(ddFace)} bd=${_edgeOf(t, ddF)} cr45=$ddCr');
              final cbF = find.descendant(of: dlg, matching: findVisibleTextContaining(_bandText[c.id]!), skipOffstage: true);
              final cw = _wordsOf(t, cbF);
              need('카드 띠 글 1', cw.n == 1, cw.raw);
              _out('D543 $tok att cband n=${cw.n} wb=${cw.wb} h=${cw.h}');
              raw = '$raw cband ${cw.raw}';
              chk('카드 결정 필요 띠 글 낱말 안 끊김 0(DU538 그대로)', cw.wb == 0, cw.raw);

              // ⑧ 연장 · 종료 — 색(DU536 그대로) · 눌릴 수 있는가(stale 아님 — 값만) → 첫 화면 캡처 → 끌어 보임 · hit · 받는 자리(기록). 누르지 않는다.
              final extF = find.text(_extText);
              final endF = find.text(_endText);
              final nExt = extF.evaluate().length;
              final nEnd = endF.evaluate().length;
              need('연장 · 종료 각 1', nExt == 1 && nEnd == 1, 'ext $nExt end $nEnd');
              final under = Color.alphaBlend(_faceOf(t, extF), Colors.white);
              final extBgC = t.widget<Material>(find.ancestor(of: extF, matching: find.byType(Material)).first).color ?? Colors.transparent;
              final endBgC = t.widget<Material>(find.ancestor(of: endF, matching: find.byType(Material)).first).color ?? Colors.transparent;
              final extFgC = _fgOf(t, extF);
              final endFgC = _fgOf(t, endF);
              final rnCr = _contrast(extFgC, Color.alphaBlend(extBgC, under)) >= 4.5 && _contrast(endFgC, Color.alphaBlend(endBgC, under)) >= 4.5;
              _out('D543 $tok att renew extn=$nExt endn=$nEnd extbg=${_hex(extBgC)} extfg=${_hex(extFgC)} endbg=${_hex(endBgC)} endfg=${_hex(endFgC)} cr45=$rnCr');
              final lv = _liveNow(t, dlg);
              _out('D543 $tok att live stalen=${lv.staleN} bulkon=${lv.bulkOn} exton=${lv.extOn} endon=${lv.endOn}');
              final lvr = 'stale ${lv.staleN} bulk ${lv.bulkOn} ext ${lv.extOn} end ${lv.endOn}';
              raw = '$raw live $lvr';
              if (!_before) chk('strict stale 아님 — 안내 0 · 일괄 연장 · 연장 · 종료 눌릴 수 있다', lv.staleN == 0 && lv.bulkOn == 'true' && lv.extOn == 'true' && lv.endOn == 'true', lvr);
              await shot('1renew', 'list-first-screen');
              await t.ensureVisible(extInk.first);
              for (var i = 0; i < 10; i++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              final pe = _tapNow(t, extInk.first, dlg, screen);
              final pd = _tapNow(t, endInk.first, dlg, screen);
              final a48 = pe.min48 && pd.min48;
              _out('D543 $tok att acts extvis=${pe.vis} exthit=${pe.hit} endvis=${pd.vis} endhit=${pd.hit} min48=$a48');
              final actRaw = 'ext ${pe.r} vis ${pe.vis} hit ${pe.hit} end ${pd.r} vis ${pd.vis} hit ${pd.hit} min48 $a48';
              raw = '$raw acts $actRaw';
              chk('연장 · 종료 — 명단 칸 안(끌어 넣은 뒤 · hit 은 기록 · DU538 그대로)', pe.vis && pd.vis, actRaw);
              await shot('2acts', 'list-actions-in-view');
            } else {
              // 첫 조회 실패 — 본문(DU537 · DU539) 그대로 · 이 읽기의 실패 토스트 0(strict · 감사136 §5-4).
              need('첫 조회 실패 — 빈 상태 문구 0 · 실패 안내 1 · 오류 아이콘 = error · stale 안내 0(DU537 · DU539 그대로)',
                  b0.emptyN == 0 && b0.failN == 1 && b0.icon == _wantErr && b0.staleN == 0, br0);
              if (!_before) chk('strict 첫 조회 실패 — 이 읽기의 실패 토스트 0', b0.toastN == 0, br0);
              // (before 는 실패 토스트 4초가 내려간 뒤의 본문.)
              for (var i = 0; i < 5; i++) {
                await t.pump(const Duration(seconds: 1));
              }
              await shot('1fail', 'load-failed');
            }
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑨ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer 가 끝날 시간을 준다.
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

        // ⑩ 집계 — 읽기 호출 수 · 허용 쓰기 대역 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
        final nApps = wire.calls[_appsFn] ?? 0;
        final nProps = wire.calls['callableGetRenewalProposalsByBiz'] ?? 0;
        final nUsers = wire.calls['callableGetUsersBatch'] ?? 0;
        final nSched = wire.calls[_schedFn] ?? 0;
        final nWt = wire.calls['workTypes'] ?? 0;
        final nMutAll = wire.mutations.length;
        final mutApp = wire.mutations.isEmpty ? '-' : wire.mutations.join('+');
        final nWrites = wire.blocked.length;
        final nOtherFs = wire.otherFs.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.otherFs.map((x) => 'fs $x'), ...wire.harness].join(' | ');
        _out('D543 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt sched=$nSched mut=$nMutAll mutapp=$mutApp writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

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
        _out('R543 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D543 $tok att fw n=$nFw');
        _out('D543 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침: W 전부 strict 0 · B 는 RENEW · FAIL 만 strict 0(DU540 관측 0) — 그 밖 B(DATE · SWITCH · SAME)는 기록만(TB · TA 로그 대조).
        //   framework 예외: 날짜 모드 B 만 기록(DU540 처럼 넘침에 딸린 오류 가능) · 그 밖 strict 0.
        final wantApps = isTwo ? 3 : (c.id == 'SAME' ? (_before ? 2 : 3) : 1);
        final wantSched = isDate ? 1 : 0;
        final wantMut = c.id == 'SAME' ? 1 : 0;
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('허용 쓰기 대역(연장 제안 성공) — SAME 만 정확 1회 · 대상 a1 · 그 밖 0', nMutAll == wantMut && mutApp == (wantMut == 1 ? 'a1' : '-'), 'mut $nMutAll $mutApp');
        chk('읽기 대역 호출(지원서 $wantApps · 업무유형 ≥1 · 일정 요청 $wantSched)', nApps == wantApps && nWt >= 1 && nSched == wantSched, 'apps $nApps wt $nWt sched $nSched');
        if (!_before && (!isB || isRenew || c.id == 'FAIL')) chk('strict 화면 전체 넘침 0(W 전부 · B 는 RENEW · FAIL)', nOvf == 0, ovfRaw);
        if (!_before && !(isDate && isB)) chk('strict 미처리 framework 예외 0(날짜 모드 B 는 기록)', nFw == 0, fwRaw);
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
