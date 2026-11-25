// ignore_for_file: depend_on_referenced_packages
// [DU580b · 결정 미이행 장부 BL-07 · 고정근무자 관리 창 O007] 판정 원문 이행 — retro143 :64(F143-INACTIVE-SECTION 날짜 모드 구역명 '선택일 비근무' + textSecondary ·
//   F143-CARD-METADATA-CONTRAST 카드 요일 · 기간 grey500 → textSecondary) · retro134 §4 :66(반복 카드 해지 · 퇴사 · 만료 결정 넓은 주의 띠 → 중립 면 + 작은 실제 상태 칩 ·
//   남은 일수 · 예정일 · 안내 전문 보존). 장부 '판단 불가' 2는 관측만 한다: W '연장 응답 대기' 띠 마지막 줄 글자 수(retro135 :60) · B 조회 실패 본문 끝 도달(retro136 :47 · retro141 :45).
//   before = 지금 A(fixed_worker_management_dialog 767862da = DU552 채택판) 기록 · strict = r1 후보(68e1be52 = 원 BL-07 후보 71845692 + 판정171 §3 B 배치 교정).
//   [r1] 본문 · 대역 · 측정 · 기대 · 공차 · guard · 캡처 = 원 suite(ad51b093 · 원 TA 공개 9 성공 · B-LIST vis 6행 lgate STOP) 그대로 — 바뀐 것은 이 머리 주석 두 줄뿐.
//   하네스 = DU552 일반 모드 대역(5명 · 연장 제안 1) + 퇴사 요청 1명(a6) · 첫 진입 자동 검색 0(전체 명단) / DU548 날짜 모드 WKND 대역 그대로 / DU537 첫 조회 실패 대역 그대로.
//   측정 블록 = DU575 시험(5cd431b1 · 정규 DONE 5/5)의 DU571 r2 바이트(_fullShown max 판 · _midBreaks · _area · _hitWithin · _lineCount · _seeText · _btnLine) ·
//     DU309 색(_lum · _contrast · _hex · _bgOf) · A8 _fills · 지연 목록 대비 = DU581 r3 _bringBuilt(+ _plainOf).
//   누르는 것 0 · 입력 0 · 끌기 0(지연 목록 = scrollUntilVisible · 도달 = ensureVisible · 실패 본문 끝 = Scrollable.ensureVisible alignment 1.0 — DU543 r3 와 같다).
//   쓰기 0 · 허용 밖 CF 0 · HTTP 0. 기본 skip — TB before/du580bl-tb/DU_BEFORE_OBSERVE=580 · TA after/du580bl-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

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
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

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

/// 소유자(BUSINESS_ADMIN) — DU540 · DU548 · DU551 _Owner 와 같은 override(창은 `canForBusiness` · `watchBusinessPermissions` 를 부른다).
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

/// 장기 확정 지원서 한 건 — 종료일 = 오늘 + [endIn]일(DU540 · DU543 r3 · DU551 과 같은 꼴 · status 기본 CONFIRMED).
Map<String, Object?> _app(String id, String applicant, int endIn, {String status = 'CONFIRMED', Map<String, Object?> extra = const <String, Object?>{}}) =>
    <String, Object?>{
      'id': id, 'uid': 'u_$id', 'businessId': _biz1, 'businessName': _bizName, 'toId': 'to1', 'toTitle': '장기 모집',
      'selectedWorkType': '홀서빙', 'startTime': '09:00', 'endTime': '18:00', 'status': status, 'type': 'long_term',
      'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly', 'workDays': const <Object?>['월', '화', '수', '목', '금'],
      'workDate': _ts(_kstDayMs(-30)), 'workEndDate': _ts(_kstDayMs(endIn)),
      'appliedAt': _ts(_kstDayMs(-32)), 'confirmedAt': _ts(_kstDayMs(-31)),
      ...extra,
    };

/// [DU580b] DU552 이름표 + 퇴사 요청 a6(한퇴사).
const _names = <String, String>{
  'u_a1': '김연장', 'u_a2': '이대기', 'u_a3': '박서명', 'u_a4': '최종료', 'u_a5': '정해지', 'u_a6': '한퇴사',
  'u_c1': '김가람', 'u_c2': '이나래', 'u_c3': '서다솜', 'u_c4': '박다온',
};

/// [DU580b] 확정 시각 = 오늘 + [d]일 — 창은 명단을 확정 시각 내림차순으로 놓는다(fixed_worker_management_dialog :393). 같은 값이면 정렬 순서가 정해지지 않으므로
///   카드마다 하루씩 달리 줘 위 → 아래 순서를 a1 … a6 로 못 박는다(지연 목록 _bringBuilt 는 아래로만 끈다 — 위 → 아래 순서로 잰다).
Map<String, Object?> _cAt(int d) => <String, Object?>{'confirmedAt': _ts(_kstDayMs(d))};

/// 일반 모드 대역(DU536 · DU540 · DU543 r3 RENEW · DU551 LIST · DU552 의 5명 + a6) — a1 만료 10일 전(만료 결정 띠) · a2 만료 5일 전 + 연장 제안 응답 대기 ·
///   a3 계약 처리 필요 · a4 종료 결정 · a5 해지 요청 중(요청 = 어제 → 2일 후 자동 해지) · [DU580b] a6 퇴사 요청 중(요청 = 어제 · 희망일 = 30일 뒤 → 정상 요청 · 2일 후 자동 승인).
///   첫 진입 대상 없음(자동 검색 0) — 카드 6장 전부. [DU580b] 확정 시각만 카드마다 달리 줬다(_cAt · 순서 고정 — DU552 는 다섯 모두 -31).
List<Object?> _apps() => <Object?>[
      _app('a1', '김연장', 10, extra: _cAt(-21)),
      _app('a2', '이대기', 5, extra: _cAt(-22)),
      _app('a3', '박서명', 25, status: 'CONTRACT_PENDING', extra: _cAt(-23)),
      _app('a4', '최종료', 40, extra: <String, Object?>{..._cAt(-24), 'renewalDecision': 'TERMINATE'}),
      _app('a5', '정해지', 60, extra: <String, Object?>{..._cAt(-25), 'terminationStatus': 'PENDING', 'terminationRequestedAt': _ts(_kstDayMs(-1))}),
      _app('a6', '한퇴사', 90, extra: <String, Object?>{..._cAt(-26), 'resignStatus': 'PENDING', 'resignRequestedAt': _ts(_kstDayMs(-1)), 'resignRequestDate': _ts(_kstDayMs(30))}),
    ];

/// a2 의 연장 제안(응답 대기) — 효력 시작 = 지금 종료일 다음 날(DU543 r3 · DU551 과 같다).
Map<String, Object?> _proposal() => <String, Object?>{
      'id': 'rp1', 'businessId': _biz1, 'businessName': _bizName, 'workerUid': 'u_a2', 'oldApplicationId': 'a2', 'status': 'PENDING',
      'effectiveStart': _ts(_kstDayMs(6)), 'effectiveEnd': _ts(_kstDayMs(36)), 'selectedWorkType': '홀서빙',
    };

/// 오늘(KST)에서 며칠 뒤가 [ok] 요일인가(0–7 · 없으면 0).
int _aheadTo(bool Function(int weekday) ok) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  for (var d = 0; d < 8; d++) {
    if (ok(DateTime.utc(k.year, k.month, k.day + d).weekday)) return d;
  }
  return 0;
}

/// 날짜 모드로 보는 날 — 오늘(KST) 이후 첫 평일(월–금) / 첫 토요일(DU540 과 같다).
int _weekdayAhead() => _aheadTo((wd) => wd <= DateTime.friday);
int _saturdayAhead() => _aheadTo((wd) => wd == DateTime.saturday);

/// 창에 넘기는 focusDate — 그 날의 로컬 자정(달력 화면 workforce_operational_view 가 넘기는 값과 같은 모양 `DateTime(y, m, d)`).
DateTime _focusDay(int ahead) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(k.year, k.month, k.day + ahead);
}

/// 날짜 모드 대역 4명(DU540 과 같다 · 호출마다 새로 만든다) —
///   c1 김가람: 월–금 · 가장 최근 확정(명단 맨 위 카드 · 활성 카드 기준 잉크) · 토요일 = 추가근무 요청 중(WKND)
///   c2 이나래: 월–금(토요일 = 비근무일) — [kind] = OUTP 이면 계약 시작(workDate)만 보는 평일 + 7일로 옮긴다(= 계약기간 외 · 그 밖 값 그대로)
///   c3 서다솜: 토 · 일 + 그 평일에 승인된 추가근무 · c4 박다온: 월–금 + 그 평일에 승인된 휴무(토요일 = 비근무일)
List<Object?> _appsDate(String kind) => <Object?>[
      _app('c1', '김가람', 60, extra: <String, Object?>{'confirmedAt': _ts(_kstDayMs(-20))}),
      _app('c2', '이나래', 90, extra: kind == 'OUTP' ? <String, Object?>{'workDate': _ts(_kstDayMs(_weekdayAhead() + 7))} : const <String, Object?>{}),
      _app('c3', '서다솜', 120, extra: <String, Object?>{'workDays': const <Object?>['토', '일'], 'extraWorkDates': <Object?>[_ts(_kstDayMs(_weekdayAhead()))]}),
      _app('c4', '박다온', 100, extra: <String, Object?>{'leaveDates': <Object?>[_ts(_kstDayMs(_weekdayAhead()))]}),
    ];

/// c1 의 대기 중인 추가 근무 요청 한 건(토요일 · 관리자가 보낸 EXTRA_WORK — DU540 DATEWKND 와 같다). 이 셀은 요청 방향 · 승인/거절을 바꾸지 않는다.
Map<String, Object?> _schedReq(int ahead) => <String, Object?>{
      'id': 'sr1', 'businessId': _biz1, 'applicationId': 'c1', 'applicantUid': 'u_c1', 'applicantName': '김가람',
      'targetDate': _ts(_kstDayMs(ahead)), 'requestType': 'EXTRA_WORK', 'requestedBy': 'ADMIN',
      'requestedByUid': 'admin1', 'requestedAt': _ts(_kstDayMs(-1)), 'reason': '일정 조정 부탁드립니다', 'status': 'PENDING',
    };

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _wtPath = 'businesses/$_biz1/workTypes';
const _appsFn = 'callableGetApplicationsByBiz';
const _schedFn = 'callableGetScheduleChangeRequestsForDate';

/// 첫 화면이 부르는 읽기 CF(DU540 · DU548 · DU551 과 같은 4종) — 이 밖의 CF 이름(일괄 연장 · 연장 제안 · 종료 포함)은 차단하고 센다.
const _readFns = <String>{'callableGetApplicationsByBiz', 'callableGetRenewalProposalsByBiz', 'callableGetUsersBatch', _schedFn};

/// Firestore 쓰기 연산 — 하나라도 오면 writes 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536 · DU540 · DU548 · DU551 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du580b.fake.auth.';
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
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다.
///   [DU580b] 사례별 응답 분기만 더했다(응답 모양 · 값 = 기존 대역 그대로): LIST = DU552 LIST(+ a6) · DATE = DU548 WKND(일정 요청 1건) ·
///   FAIL = DU537 FAIL(지원서 조회 첫 번 = 'unavailable' 오류 · 다시 시도를 누르지 않으므로 그 한 번뿐) · SETUP = 호출 0.
class _Wire {
  _Wire(this.kind);

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
        return codec.encodeMessage(<Object?>['not-found', 'du580b-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      if (fn == _appsFn) {
        if (kind == 'FAIL') {
          return codec.encodeMessage(<Object?>['unavailable', 'du580b local failure', <String, Object?>{'code': 'unavailable', 'message': 'du580b local failure'}]);
        }
        return codec.encodeMessage(<Object?>[<String, Object?>{'applications': kind == 'DATE' ? _appsDate('WKND') : _apps()}]);
      }
      if (fn == 'callableGetRenewalProposalsByBiz') {
        return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': kind == 'LIST' ? <Object?>[_proposal()] : const <Object?>[]}]);
      }
      if (fn == _schedFn) {
        // 날짜 모드의 일정 요청 조회 — DATE = DU548 WKND 의 토요일 1건 · 일반 모드는 부르지 않는다(오면 빈 목록).
        final items = kind == 'DATE' ? <Object?>[_schedReq(_saturdayAhead())] : const <Object?>[];
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
      return codec.encodeMessage(<Object?>['internal', 'du580b-harness', null]);
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
      return codec.encodeMessage(<Object?>['du580b-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return codec.encodeMessage(<Object?>['du580b-harness', '대역 오류', null]);
    }
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU580b 관측 — 외부 HTTP 차단');
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

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 그려진 글(표시 제어 문자 포함) 기준 — 낱말(공백 · 개행 · ZWSP 사이) 안에서 줄이 바뀐 횟수. NBSP · WORD JOINER 로 묶은 덩어리는 한 낱말이다.
int _midBreaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  var n = 0;
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\n') {
      lastTop = null;
      lastIdx = i;
      continue;
    }
    if (ch == _wj || ch == _zw) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    final half = (bx.first.bottom - bx.first.top) / 2;
    final wrapped = lastTop != null && top > lastTop + half;
    if (wrapped) {
      var gap = _gap(ch) || (lastIdx >= 0 && _gap(s[lastIdx]));
      for (var k = lastIdx + 1; k < i; k++) {
        if (_gap(s[k])) gap = true;
      }
      if (!gap) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU571 r2 · 판정167 시험 STOP 수리 · 판정159/161/162 방식] 세로는 줄 배치(max 상자) · 가로는 tight right(종전) · 공차 0.5 그대로.
    //   tight 세로는 run 글꼴 높이라 줄 높이 1.3 < 글꼴 원래 1.448em 이면 줄 상자 밖으로 나온다(DU559 nmraw: h+1.258). 잉크/clip 증명 아님.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// [pos] 를 눌렀을 때 맞는 대상 중에 [f] 의 위젯(자손 포함)이 만든 render object 가 있는가.
bool _hitWithin(WidgetTester t, Finder f, Offset pos) {
  final own = <Object>{};
  void walk(Element e) {
    final ro = e.renderObject;
    if (ro != null) own.add(ro);
    e.visitChildren(walk);
  }

  walk(f.evaluate().first);
  return t.hitTestOnBinding(pos).path.any((x) => own.contains(x.target));
}

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

/// [DU514 과 같다] 그린 글(표시 제어 문자 제외).
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [DU581 r2 · 판정167 시험 STOP 수리] 지연 생성 목록(사용자 목록 · 상세 시트 ListView) 안의 글이 아직 안 만들어졌을 때만
///   그 host 의 세로 목록을 끌어 만든다(누르기 아님 · 찾는 식 = _seeText 와 같은 _plainOf · 단언 없음 — 개수 판정은 _seeText 뒤 need).
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// 사례 — LIST(일반 모드 전체 명단 · 해지/퇴사/만료 띠 · 응답 대기 띠 · 카드 요일/기간) · DATE(날짜 모드 토요일 · 비근무 구역명 · 비근무 카드 요일/기간) ·
///   FAIL(첫 조회 실패 본문 · 끝 도달 · 다시 시도 · 닫기 — 관측).
const _cases = <({String id, int shots})>[(id: 'LIST', shots: 4), (id: 'DATE', shots: 1), (id: 'FAIL', shots: 2)];

/// 글 원문(대상 소스와 같다 — mkcell 이 원문 대조).
const _titleText = '고정근무자 관리';
const _emptyText = '고정근무자가 없습니다';
const _failText = '고정근무자 목록을 불러오지 못했어요';
const _termWho = '정해지';
const _termState = '계약해지 요청중';
const _termDet = '2일 후 자동 해지';
const _termWords = '계약해지요청중2일후자동해지';
const _resWho = '한퇴사';
const _resState = '퇴사 요청중';
const _resDet = '2일 후 자동 승인';
const _resWords = '퇴사요청중2일후자동승인';
const _renWho = '김연장';
const _renHead = '계약 만료 D-10';
/// 만료 결정 띠 안 글(아이콘 글리프 제외 · 공백/괄호 뺌) — 제목 '계약 만료 D-10 (M/d)' + 행동 '연장' · '종료'.
final RegExp _renWords = RegExp(r'^계약만료D-10\d{1,2}/\d{1,2}연장종료$');
const _waitWho = '이대기';
const _waitText = '연장 응답 대기 — 근무자가 제안을 확인하고 있습니다';
const _wdText = '월, 화, 수, 목, 금';
const _extText = '연장';
const _endText = '종료';
const _inactWho = '이나래';
const _sectOld = '오늘 비근무 (2명)';
const _sectNew = '선택일 비근무 (2명)';
const _sectTail = ' 비근무 (2명)';
const _retryText = '다시 시도';
const _closeText = '닫기';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '580';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du580bl-tb' && _env['DU_BEFORE_OBSERVE'] == '580') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du580bl-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R580 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S580BL-${v.id}-${c.id} 고정근무자 관리 창 BL-07 구역명 · 카드 요일/기간 · 해지/퇴사/만료 띠 중립과 작은 칩 · 응답 대기/조회 실패 관측', (t) async {
        final tok = 'S580BL-${v.id}-${c.id}';
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
        _out('D580 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final isW = v.id == 'W';
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
                    focusDate: c.id == 'DATE' ? _focusDay(_saturdayAhead()) : null,
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
          _out('D580 $tok att scr n=$nDlg');
          need('창 1', nDlg == 1, '개수 $nDlg');
          final nTitle = find.text(_titleText).evaluate().length;
          need('창 제목 1', nTitle == 1, '개수 $nTitle');

          Future<void> shot(String id, String state) async {
            _out('D580 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // ① 본문 — 빈 상태 문구 · 조회 실패 안내(창 안 · 지어진 것 기준).
          final b0 = _bodyNow(dlg);
          _out('D580 $tok att body emptyn=${b0.emptyN} failn=${b0.failN}');
          raw = 'body ${b0.emptyN}/${b0.failN}';
          final wantFail = c.id == 'FAIL' ? 1 : 0;
          need('본문 — 빈 상태 0 · 실패 안내 $wantFail', b0.emptyN == 0 && b0.failN == wantFail, raw);

          if (c.id == 'LIST') {
            // 위 → 아래 순서(a1 김연장 → a2 이대기 → a5 정해지 → a6 한퇴사 · _cAt)로 잰다 — _bringBuilt 는 아래로만 끈다.
            // ② 만료 결정 띠(김연장 · D-10) — 제목 = 상태 줄(후보 = 칩) · 띠 면/선/아이콘 · 연장/종료 그대로 → 연장 채움(A8) → 캡처.
            final rn = await _bandStep(t, dlg, screen, _renWho, null, (s) => s.startsWith(_renHead), Icons.event_note, _renWords.hasMatch);
            _out('D580 $tok att ren n=${rn.see.n} words=${rn.band.words} band=${rn.band.band} border=${rn.band.border} icon=${rn.band.icon} chip=${rn.band.chip} fg=${rn.band.fg} cr=${rn.band.cr} ok45=${rn.band.ok45} sep=${rn.band.sep} cw=${rn.band.cw} bw=${rn.band.bw} ch=${rn.band.ch} bh=${rn.band.bh} name=${rn.see.name} full=${rn.see.full} brk=${rn.see.brk} lines=${rn.see.lines} vis=${rn.see.vis}');
            need('만료 결정 띠 제목 1', rn.see.n == 1, rn.band.raw);
            final ac = _actsOf(dlg, _renWho);
            _out('D580 $tok att acts efill=${ac.efill} ebrand=${ac.ebrand} dfill=${ac.dfill}');
            raw = '$raw ren ${rn.band.raw} acts ${ac.efill}/${ac.dfill}';
            await shot('1ren', 'list-renewal-band');

            // ③ 같은 카드(김연장)의 요일 · 기간 — 하나씩 ensureVisible 뒤 같은 글을 잰다.
            final mo = await _metaOf(t, dlg, _renWho, screen);
            _out('D580 $tok att meta wd=${mo.wd} per=${mo.per} wcr=${mo.wcr} pcr=${mo.pcr} wok=${mo.wok} pok=${mo.pok} wvis=${mo.wvis} pvis=${mo.pvis}');
            raw = '$raw meta ${mo.raw}';

            // ④ 연장 응답 대기 띠(이대기) — 관측(장부 '판단 불가' · retro135 :60 W 마지막 '다' 홀로 줄) → 캡처.
            final wo = await _waitStep(t, dlg, screen);
            _out('D580 $tok att wait n=${wo.n} lines=${wo.lines} lastn=${wo.lastn} solo=${wo.solo} full=${wo.full} brk=${wo.brk} vis=${wo.vis} last=${wo.last}');
            need('연장 응답 대기 글 1', wo.n == 1, 'n ${wo.n}');
            raw = '$raw wait ${wo.lines}/${wo.lastn}';
            await shot('2wait', 'list-waiting-band');

            // ⑤ 해지 요청 띠(정해지) — 상태 글(base = 한 줄 전체 · 후보 = 칩) · 띠 면/선/아이콘 · 칩 짝 · 낱말 그대로 → 본문(남은 일수) → 캡처.
            final te = await _bandStep(t, dlg, screen, _termWho, _before ? '$_termState ($_termDet)' : _termState, (s) => s.startsWith(_termState),
                Icons.cancel_outlined, (w) => w == _termWords);
            _out('D580 $tok att term n=${te.see.n} words=${te.band.words} band=${te.band.band} border=${te.band.border} icon=${te.band.icon} chip=${te.band.chip} fg=${te.band.fg} cr=${te.band.cr} ok45=${te.band.ok45} sep=${te.band.sep} cw=${te.band.cw} bw=${te.band.bw} ch=${te.band.ch} bh=${te.band.bh} name=${te.see.name} full=${te.see.full} brk=${te.see.brk} lines=${te.see.lines} vis=${te.see.vis}');
            need('해지 상태 글 1', te.see.n == 1, te.band.raw);
            final td = await _detStep(t, dlg, screen, _termDet);
            _out('D580 $tok att termd n=${td.n} fg=${td.fg} face=${td.face} cr=${td.cr} ok45=${td.ok45} full=${td.full} lines=${td.lines} vis=${td.vis}');
            raw = '$raw term ${te.band.raw} det ${td.n}/${td.fg}';
            await shot('3term', 'list-termination-band');

            // ⑥ 퇴사 요청 띠(한퇴사) — 같은 잣대.
            final re = await _bandStep(t, dlg, screen, _resWho, _before ? '$_resState ($_resDet)' : _resState, (s) => s.startsWith(_resState),
                Icons.exit_to_app, (w) => w == _resWords);
            _out('D580 $tok att res n=${re.see.n} words=${re.band.words} band=${re.band.band} border=${re.band.border} icon=${re.band.icon} chip=${re.band.chip} fg=${re.band.fg} cr=${re.band.cr} ok45=${re.band.ok45} sep=${re.band.sep} cw=${re.band.cw} bw=${re.band.bw} ch=${re.band.ch} bh=${re.band.bh} name=${re.see.name} full=${re.see.full} brk=${re.see.brk} lines=${re.see.lines} vis=${re.see.vis}');
            need('퇴사 상태 글 1', re.see.n == 1, re.band.raw);
            final rd = await _detStep(t, dlg, screen, _resDet);
            _out('D580 $tok att resd n=${rd.n} fg=${rd.fg} face=${rd.face} cr=${rd.cr} ok45=${rd.ok45} full=${rd.full} lines=${rd.lines} vis=${rd.vis}');
            raw = '$raw res ${re.band.raw} det ${rd.n}/${rd.fg}';
            await shot('4res', 'list-resign-band');
          } else if (c.id == 'DATE') {
            // ② 구역명(인원 · 글 · 색 · 위에서부터 끌어 지음) → 캡처 → ③ 그 아래 비근무 카드(이나래)의 요일 · 기간(아래로만 끈다).
            final so = await _sectStep(t, dlg, screen);
            _out('D580 $tok att sect n=${so.n} new=${so.isNew} cnt=${so.cnt} fg=${so.fg} cr=${so.cr} ok45=${so.ok45} full=${so.full} brk=${so.brk} lines=${so.lines} vis=${so.vis}');
            need('비근무 구역명 1', so.n == 1, 'n ${so.n}');
            await shot('1sect', 'date-inactive-section');
            final dm = await _metaOf(t, dlg, _inactWho, screen);
            _out('D580 $tok att dmeta wd=${dm.wd} per=${dm.per} wcr=${dm.wcr} pcr=${dm.pcr} wok=${dm.wok} pok=${dm.pok} wvis=${dm.wvis} pvis=${dm.pvis}');
            raw = '$raw sect ${so.n}/${so.fg}/${so.cnt} dmeta ${dm.raw}';
          } else {
            // ② 조회 실패 본문 — 첫 화면(끌기 전) 시작/끝 글자 보임 · 글 높이/칸 높이 → 캡처 → 끝을 칸 아래에 맞춰 끈다(alignment 1.0) → 끝 글자 보임 · 다시 시도 · 닫기.
            await _bringBuilt(t, dlg, _failText);
            final ff = _rtOne(dlg, (s) => s == _failText);
            final nFf = ff == null ? 0 : 1;
            need('조회 실패 본문 글 1', nFf == 1, 'n $nFf');
            final ffv = ff!;
            final e0 = _endsOf(t, ffv, screen);
            _out('D580 $tok att fail n=$nFf th=${e0.th} vh=${e0.vh} fit=${e0.fit} sv0=${e0.sv} ev0=${e0.ev}');
            await shot('1fail', 'load-failed-first-screen');
            await Scrollable.ensureVisible(t.element(ffv), alignment: 1.0);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final e1 = _endsOf(t, ffv, screen);
            final px = _paraOf(t, ffv, screen);
            _out('D580 $tok att failend ev1=${e1.ev} full=${px.full} brk=${px.brk} lines=${px.lines} vis=${px.vis}');
            final ro = _btnLine(t, dlg, (s) => s == _retryText, screen);
            _out('D580 $tok att retry n=${ro.n} dis=${ro.dis} m48=${ro.m48} vis=${ro.vis} hit=${ro.hit}');
            final co = _btnLine(t, dlg, (s) => s == _closeText, screen);
            _out('D580 $tok att close n=${co.n} dis=${co.dis} m48=${co.m48} vis=${co.vis} hit=${co.hit}');
            raw = '$raw fail ${e0.th}/${e0.vh} sv0 ${e0.sv} ev0 ${e0.ev} ev1 ${e1.ev} retry ${ro.vis}/${ro.hit} close ${co.vis}/${co.hit}';
            await shot('2end', 'load-failed-scrolled-to-end');
          }
          // 화면 전체 채움 단추(A8 기록) — 마지막 캡처 화면 기준.
          final fl = _fills(t);
          _out('D580 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
          raw = '$raw fills ${fl.list}';
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑥ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer 가 끝날 시간을 준다.
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

        // ⑦ 집계 — 읽기 호출 수 · 차단된 쓰기/허용 밖 CF 수 · 그 밖 Firestore 연산 · 예상 밖 채널 · HTTP.
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
        _out('D580 $tok att wire apps=$nApps props=$nProps users=$nUsers wt=$nWt sched=$nSched writes=$nWrites otherfs=$nOtherFs unexpected=$nUnexp http=$nHttp harness=$nHarness');

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
        _out('R580 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D580 $tok att fw n=$nFw');
        _out('D580 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 0 · 대역 오류 0(업무 writer 불실행)', nWrites == 0 && nHttp == 0 && nHarness == 0, unText);
        // B(320 · 2.0) · N(320 · 1.0) 의 넘침 · framework 오류는 기록만(DU548 · DU552 와 같이 TB/TA 손 대조) — W strict 는 0.
        if (!_before && isW) chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
        if (!_before && isW) chk('strict W 미처리 framework 예외 0', nFw == 0, fwRaw);
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

// 측정 도우미(DU571 r2 바이트 그대로 · DU573 r1 · DU575 와 같이 main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

typedef _SeeObs = ({int n, bool name, bool full, int brk, int lines, bool vis});

/// [DU571] 바뀐 글 하나 — 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 가 정확히 하나일 때 **그 RichText 를** ensureVisible 로 넣고,
///   같은 요소로 읽는 이름(가장 가까운 Semantics 조상 label = 그 글 원문) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 화면 ∩ 스크롤 칸 안을 잰다
///   (DU570 의 같은 이름 도우미와 같은 잣대 · 찾는 조건만 함수 · await 뒤에는 Element 를 직접 읽지 않고 같은 finder 로 다시 잡는다).
Future<_SeeObs> _seeText(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, name: false, full: false, brk: 0, lines: 0, vis: false);
  final el = es.first;
  final want = TextLayout.plain((el.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  await t.ensureVisible(tf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final rp = t.renderObject<RenderParagraph>(tf);
  final sem = find.ancestor(of: tf, matching: find.byType(Semantics, skipOffstage: false)).evaluate();
  final label = sem.isEmpty ? null : (sem.first.widget as Semantics).properties.label;
  return (
    n: 1,
    name: label == want,
    full: _fullShown(rp, rp.size),
    brk: _midBreaks(rp),
    lines: _lineCount(rp),
    vis: _inside(t.getRect(tf), _area(tf, screen)),
  );
}

typedef _BtnObs = ({int n, bool dis, bool m48, bool vis, bool hit});

/// [DU571] 그 글이 든 버튼 — 그린 글이 [match] 에 맞고 ButtonStyleButton 조상이 있는 RichText 가 정확히 하나일 때 **그 버튼 한 요소로**
///   비활성(onPressed null · 행동 불변) · 받는 자리(48 기록) · 화면 ∩ 스크롤 칸 안 · 중심 hit 를 잰다(ensureVisible 0 · 누르지 않는다).
_BtnObs _btnLine(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .where((e) {
        final ef = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        return find.ancestor(of: ef, matching: btn).evaluate().isNotEmpty;
      })
      .toList();
  if (es.length != 1) return (n: es.length, dis: false, m48: false, vis: false, hit: false);
  final el = es.first;
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  final bf = find.ancestor(of: tf, matching: btn).first;
  final r = t.getRect(bf);
  return (
    n: 1,
    dis: (t.widget(bf) as ButtonStyleButton).onPressed == null,
    m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
    vis: _inside(r, _area(bf, screen)),
    hit: _hitWithin(t, bf, r.center),
  );
}

// [DU575] 색 도우미 — DU309 시험(du1_confirm_color_split_309_test :84–95 · :162–183)과 같은 식(bgOf 는 main 안 지역 함수를 최상위 _bgOf 로만 옮김).

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ColoredBox) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).canvasColor;
    }
    if (c == null || c.a == 0) return true;
    layers.add(c);
    return c.a < 1.0;
  });
  var out = layers.isEmpty ? Colors.white : layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

/// [DU575 · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 카드 행 단추(_inviteActionButton = GestureDetector + Container)는 여기 들지 않는다 — README A8 표.
typedef _FillObs = ({int n, int brand, int err, int none, int other, String list});

_FillObs _fills(WidgetTester t) {
  final rows = <String>[];
  var b = 0, er = 0, no = 0, ot = 0;
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final bf = find.byElementPredicate((x) => identical(x, e));
    final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
    final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
    final texts = find
        .descendant(of: bf, matching: find.byType(RichText), skipOffstage: false)
        .evaluate()
        .where((r) => find.ancestor(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon)).evaluate().isEmpty)
        .toList();
    final lab = texts.isEmpty ? '-' : TextLayout.plain((texts.first.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    if (fc == null || fc.a == 0) {
      no++;
      rows.add('$lab:none');
    } else {
      if (fc.toARGB32() == AppColors.brand.toARGB32()) {
        b++;
      } else if (fc.toARGB32() == AppColors.errorDark.toARGB32()) {
        er++;
      } else {
        ot++;
      }
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

// ───────────── [DU580b] 새 측정 — 위 재사용 도우미(_seeText · _btnLine · _bringBuilt · _bgOf · _contrast · _hex · _fullShown · _midBreaks · _lineCount · _area · _inside)만 부른다 ─────────────

typedef _BodyObs = ({int emptyN, int failN});

/// 본문 — 빈 상태 문구 수 · 조회 실패 안내 수(창 안 · 지어진 것 · 그린 글 기준).
_BodyObs _bodyNow(Finder dlg) {
  int n(String s) => find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == s), skipOffstage: false).evaluate().length;
  return (emptyN: n(_emptyText), failN: n(_failText));
}

/// 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 하나의 Finder — 정확히 하나가 아니면 null(아이콘 글리프는 한글 조건에 맞지 않는다).
Finder? _rtOne(Finder host, bool Function(String s) match) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return null;
  final el = es.first;
  return find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
}

typedef _DetObs = ({int n, String fg, String face, String cr, bool ok45, bool full, int lines, bool vis});

/// 띠 본문(후보에서만 따로 된 글 — 자동 처리까지 남은 일수 · 예정일) — 후보: 짓고(_bringBuilt) _seeText(ensureVisible 한 같은 글)로 재고 그 글의 색 · 뒤 바탕 · 대비.
///   base 는 그 글이 상태 글 괄호 안에 있어 따로 된 글 0(n=0 · 끌기 0).
Future<_DetObs> _detStep(WidgetTester t, Finder dlg, Rect screen, String det) async {
  if (!_before) await _bringBuilt(t, dlg, det);
  final see = await _seeText(t, dlg, (s) => s == det, screen);
  final f = _rtOne(dlg, (s) => s == det);
  if (see.n != 1 || f == null) return (n: see.n, fg: '-', face: '-', cr: '0.00', ok45: false, full: false, lines: 0, vis: false);
  final el = f.evaluate().first;
  final Color fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(el);
  final cr = _contrast(fg, face);
  return (n: 1, fg: _hex(fg), face: _hex(face), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5, full: see.full, lines: see.lines, vis: see.vis);
}

typedef _ActObs = ({String efill, bool ebrand, String dfill});

/// 만료 결정 띠의 연장 · 종료 채움(A8 · 값만) — 카드(이름 [who] 의 가장 가까운 InkWell) 안 그 글의 가장 가까운 Material 색(투명 = none).
_ActObs _actsOf(Finder dlg, String who) {
  final nameF = _rtOne(dlg, (s) => s == who);
  if (nameF == null) return (efill: '-', ebrand: false, dfill: '-');
  final card = find.ancestor(of: nameF, matching: find.byType(InkWell)).first;
  String fillOf(String label) {
    final f = _rtOne(card, (s) => s == label);
    if (f == null) return '-';
    final Color? c = (find.ancestor(of: f, matching: find.byType(Material)).evaluate().first.widget as Material).color;
    return c == null || c.a == 0 ? 'none' : _hex(c);
  }

  final e = fillOf(_extText);
  return (efill: e, ebrand: e == _hex(AppColors.brand), dfill: fillOf(_endText));
}

typedef _InkObs = ({String fg, String cr, bool ok, bool vis});

/// 카드 [card] 안 글 하나 — 그 RichText 를 ensureVisible 로 넣고 같은 글의 글자색 · 뒤 바탕 대비 · 화면 ∩ 스크롤 칸 안(점검표 A1).
Future<_InkObs> _inkAt(WidgetTester t, Finder card, bool Function(String s) match, Rect screen) async {
  final f = _rtOne(card, match);
  if (f == null) return (fg: '-', cr: '0.00', ok: false, vis: false);
  await t.ensureVisible(f);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final el = f.evaluate().first;
  final Color fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final cr = _contrast(fg, _bgOf(el));
  return (fg: _hex(fg), cr: cr.toStringAsFixed(2), ok: cr >= 4.5, vis: _inside(t.getRect(f), _area(f, screen)));
}

typedef _MetaObs = ({String wd, String per, String wcr, String pcr, bool wok, bool pok, bool wvis, bool pvis, String raw});

/// 카드(이름 [who]) 요일 · 기간 — 카드를 짓고(_bringBuilt) 요일 글('월, 화, 수, 목, 금') · 기간 글(' ~ ' 든 글)을 하나씩 잰다.
Future<_MetaObs> _metaOf(WidgetTester t, Finder dlg, String who, Rect screen) async {
  await _bringBuilt(t, dlg, who);
  final nameF = _rtOne(dlg, (s) => s == who);
  if (nameF == null) return (wd: '-', per: '-', wcr: '0.00', pcr: '0.00', wok: false, pok: false, wvis: false, pvis: false, raw: 'name 0');
  final card = find.ancestor(of: nameF, matching: find.byType(InkWell)).first;
  final w = await _inkAt(t, card, (s) => s == _wdText, screen);
  final p = await _inkAt(t, card, (s) => s.contains(' ~ '), screen);
  return (wd: w.fg, per: p.fg, wcr: w.cr, pcr: p.cr, wok: w.ok, pok: p.ok, wvis: w.vis, pvis: p.vis, raw: 'who $who wd ${w.fg}/${w.cr} per ${p.fg}/${p.cr}');
}

typedef _BandObs = ({bool words, String band, bool border, String icon, String chip, String fg, String cr, bool ok45, bool sep, String cw, String bw, String ch, String bh, String raw});

const _BandObs _bandNone = (words: false, band: '-', border: false, icon: '-', chip: '-', fg: '-', cr: '0.00', ok45: false, sep: false, cw: '0.0', bw: '0.0', ch: '0.0', bh: '0.0', raw: 'none');

/// 띠 하나 — [label] = 상태 글 RichText 하나(base = 띠 글 전체 · 후보 = 칩 글). 같은 줄(가장 가까운 Row) 아이콘 [ic] 의 가장 가까운 BoxDecoration 상자 = 띠 ·
///   상태 글의 가장 가까운 색 있는 BoxDecoration 상자 = 칩(base 는 띠 자신) — 띠 면 색 · 선 · 아이콘 색 · 칩 색 · 글자색 · 글 뒤 실제 바탕 대비 · 상자 크기 ·
///   띠 안 글(아이콘 글리프 제외 · 표시 제어 문자 제외 · 공백/괄호 뺌)이 원문 낱말 그대로인가([wordsOk]). 값만 읽는다(누르기 · 끌기 0).
_BandObs _bandOf(WidgetTester t, Finder label, IconData ic, bool Function(String joined) wordsOk) {
  final el = label.evaluate().first;
  final Color fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final cr = _contrast(fg, _bgOf(el));
  Element? chipE;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null) {
      chipE = a;
      return false;
    }
    return true;
  });
  final rowF = find.ancestor(of: label, matching: find.byType(Row)).first;
  final icons = find.descendant(of: rowF, matching: find.byIcon(ic, skipOffstage: false), skipOffstage: false).evaluate().toList();
  final ce = chipE;
  if (icons.length != 1 || ce == null) {
    return (words: false, band: '-', border: false, icon: '-', chip: '-', fg: _hex(fg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5,
        sep: false, cw: '0.0', bw: '0.0', ch: '0.0', bh: '0.0', raw: 'icons ${icons.length} chip ${ce != null}');
  }
  final icE = icons.first;
  Element? bandE;
  icE.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration) {
      bandE = a;
      return false;
    }
    return true;
  });
  final be = bandE;
  if (be == null) return _bandNone;
  final bd = (be.widget as DecoratedBox).decoration as BoxDecoration;
  final cd = (ce.widget as DecoratedBox).decoration as BoxDecoration;
  final Color? icC = (icE.widget as Icon).color;
  // 띠 안 글 — 아이콘(글리프 RichText)은 글이 아니다(점검 v26 · `is Icon` 조상 제외).
  final parts = <String>[];
  void walk(Element e) {
    final w = e.widget;
    if (w is Icon) return;
    if (w is RichText) parts.add(TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)));
    e.visitChildren(walk);
  }

  be.visitChildren(walk);
  final joined = parts.join().replaceAll(RegExp(r'[\s()]'), '');
  final cs = (ce.renderObject! as RenderBox).size;
  final bs = (be.renderObject! as RenderBox).size;
  return (
    words: wordsOk(joined),
    band: _hex(bd.color ?? Colors.transparent),
    border: bd.border != null,
    icon: icC == null ? '-' : _hex(icC),
    chip: _hex(cd.color ?? Colors.transparent),
    fg: _hex(fg),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    sep: !identical(ce, be),
    cw: cs.width.toStringAsFixed(1),
    bw: bs.width.toStringAsFixed(1),
    ch: cs.height.toStringAsFixed(1),
    bh: bs.height.toStringAsFixed(1),
    raw: 'words ${_enc(joined)} band ${_hex(bd.color ?? Colors.transparent)} chip ${_hex(cd.color ?? Colors.transparent)} ${cs.width.toStringAsFixed(1)}x${cs.height.toStringAsFixed(1)} '
        'in ${bs.width.toStringAsFixed(1)}x${bs.height.toStringAsFixed(1)}',
  );
}

/// 띠 한 단계 — 카드(이름 [who])와 상태 글([want] · null 이면 카드만)을 짓고(_bringBuilt) 상태 글을 _seeText(ensureVisible 한 같은 글)로 잰 뒤 같은 글로 _bandOf.
Future<({_SeeObs see, _BandObs band})> _bandStep(WidgetTester t, Finder dlg, Rect screen, String who, String? want, bool Function(String s) match, IconData ic,
    bool Function(String joined) wordsOk) async {
  await _bringBuilt(t, dlg, who);
  if (want != null) await _bringBuilt(t, dlg, want);
  final see = await _seeText(t, dlg, match, screen);
  final lf = _rtOne(dlg, match);
  return (see: see, band: lf == null ? _bandNone : _bandOf(t, lf, ic, wordsOk));
}

/// 그려진 문단의 마지막 줄 — 글자(표시 제어 · 빈칸 제외) 중 맨 아래 줄(top 이 가장 큰 줄 · 1px 안)에 든 글자 수와 그 글자들.
({int n, String s}) _lastLine(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <int, double>{};
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    tops[i] = bx.first.top;
  }
  if (tops.isEmpty) return (n: 0, s: '');
  final mx = tops.values.reduce(math.max);
  final idx = tops.keys.where((i) => tops[i]! > mx - 1).toList()..sort();
  return (n: idx.length, s: idx.map((i) => s[i]).join());
}

typedef _WaitObs = ({int n, int lines, int lastn, bool solo, bool full, int brk, bool vis, String last});

/// 연장 응답 대기 띠 글(관측 · 이 셀은 바꾸지 않는다) — 카드 · 글을 짓고 _seeText 로 잰 뒤 마지막 줄 글자 수(1 = 한 글자 홀로 줄).
Future<_WaitObs> _waitStep(WidgetTester t, Finder dlg, Rect screen) async {
  await _bringBuilt(t, dlg, _waitWho);
  await _bringBuilt(t, dlg, _waitText);
  final see = await _seeText(t, dlg, (s) => s == _waitText, screen);
  final f = _rtOne(dlg, (s) => s == _waitText);
  if (see.n != 1 || f == null) return (n: see.n, lines: 0, lastn: 0, solo: false, full: false, brk: 0, vis: false, last: '-');
  final ll = _lastLine(t.renderObject<RenderParagraph>(f));
  return (n: 1, lines: see.lines, lastn: ll.n, solo: ll.n == 1, full: see.full, brk: see.brk, vis: see.vis, last: _enc(ll.s));
}

typedef _SectObs = ({int n, bool isNew, String cnt, String fg, String cr, bool ok45, bool full, int brk, int lines, bool vis});

/// 날짜 모드 비근무 구역명 — 그 글을 짓고(base '오늘 비근무 (2명)' · 후보 '선택일 비근무 (2명)') _seeText 로 잰 뒤 같은 글의 인원 · 글자색 · 뒤 바탕 대비.
Future<_SectObs> _sectStep(WidgetTester t, Finder dlg, Rect screen) async {
  await _bringBuilt(t, dlg, _before ? _sectOld : _sectNew);
  final see = await _seeText(t, dlg, (s) => s.endsWith(_sectTail), screen);
  final f = _rtOne(dlg, (s) => s.endsWith(_sectTail));
  if (see.n != 1 || f == null) {
    return (n: see.n, isNew: false, cnt: '-', fg: '-', cr: '0.00', ok45: false, full: false, brk: 0, lines: 0, vis: false);
  }
  final el = f.evaluate().first;
  final txt = TextLayout.plain((el.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
  final cm = RegExp(r'\((\d+)명\)').firstMatch(txt);
  final Color fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final cr = _contrast(fg, _bgOf(el));
  return (
    n: 1, isNew: txt.startsWith('선택일 비근무'), cnt: cm?.group(1) ?? '-', fg: _hex(fg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5,
    full: see.full, brk: see.brk, lines: see.lines, vis: see.vis,
  );
}

typedef _EndObs = ({bool sv, bool ev, String th, String vh, bool fit});

/// 조회 실패 본문 글(지금 자리 · 끌기 0) — 첫 글자 · 마지막 글자(표시 제어 · 빈칸 제외)의 글자 상자가 화면 ∩ 스크롤 칸 안인가 · 문단 높이 · 가장 가까운 스크롤 칸 높이 · 한 칸에 다 드는가.
_EndObs _endsOf(WidgetTester t, Finder tf, Rect screen) {
  final rp = t.renderObject<RenderParagraph>(tf);
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final area = _area(tf, screen);
  bool shownAt(int i) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) return false;
    final o = rp.localToGlobal(Offset(bx.first.left, bx.first.top));
    return _inside(Rect.fromLTWH(o.dx, o.dy, bx.first.right - bx.first.left, bx.first.bottom - bx.first.top), area);
  }

  var first = -1;
  var last = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    if (first < 0) first = i;
    last = i;
  }
  final sc = find.ancestor(of: tf, matching: find.byType(Scrollable)).evaluate().toList();
  final vh = sc.isEmpty ? 0.0 : (sc.first.renderObject! as RenderBox).size.height;
  final th = rp.size.height;
  return (sv: first >= 0 && shownAt(first), ev: last >= 0 && shownAt(last), th: th.toStringAsFixed(1), vh: vh.toStringAsFixed(1), fit: th <= vh + 0.5);
}

typedef _ParaObs = ({bool full, int brk, int lines, bool vis});

/// 문단 하나(지금 자리 · 끌기 0) — 전문(max 판 _fullShown) · 낱말 안 끊김 · 줄 수 · 문단 전체가 화면 ∩ 스크롤 칸 안인가.
_ParaObs _paraOf(WidgetTester t, Finder tf, Rect screen) {
  final rp = t.renderObject<RenderParagraph>(tf);
  return (full: _fullShown(rp, rp.size), brk: _midBreaks(rp), lines: _lineCount(rp), vis: _inside(t.getRect(tf), _area(tf, screen)));
}
