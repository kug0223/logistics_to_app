// ignore_for_file: depend_on_referenced_packages
// [DU310 r2 · DU-S077-JOB-TAB-310] 일자리 탭 머리·필터 줄 — W390×844/1.0·B320×640/2.0 × 기본/활성 = 4 mount, before/after 같은 순서.
//   근거: requests/DU_prep_310_r2.md §1–3 · reports/DU_audit_310_r1.md §3.1–3.4 · reports/DU_preparation_310_r1.md §2.
//   ▶ 이 파일은 records `work/du310-s077-job-tab/r2/test/` 의 **정적 사본**이다. 미래 A 경로는 test/du1_s077_job_tab_310_test.dart 하나다.
//     A 에 아직 두지 않았고, 문법·분석·실행 통과를 주장하지 않는다.
//   ▶ 실행은 DU310_RUN=1 · DU310_PHASE=before|after · DU310_DAY=2026-11-15 일 때만(기본 skip). 실제 KST 날짜·local 날짜 = DU310_DAY,
//     local 시간대 +09:00, 08:00–21:30 을 시작·mount·끝에서 검증한다. 다른 날이면 skip 이고 자동 이월하지 않는다.
//   ▶ production 편집 0 · 새 seam/계측 0. 읽기 경계는 기존 공개 생성자 `UserJobTab(reads:)`(host:38) 하나다.
//   ▶ 행동은 실제 tapAt · dragFrom · 시스템 뒤로(handlePopRoute) dispatch 만 쓴다(ensureVisible·pumpAndSettle·Navigator.pop 직접·
//     private state/callback 0). 필터 시트에는 `닫기` 글자 버튼이 없다(host:1376–1395) — 닫힘은 시스템 뒤로 한 번이다(DialogHelper.showSheet 의
//     PopScope(canPop:false)→onPopInvokedWithResult→Navigator.pop(ctx), dialog_helper.dart:537–546). 날짜·지역 시트는 각 시트의 공개 버튼이 닫는다.
//   ▶ 대역 형태는 test/user_job_tab_partial_truth_test.dart 의 _FakeCore(:50)·_P(:61)·_reads(:117)·_K1Srv(:404)·_K1H.mount(:620) 를 읽어
//     축약했다(원 파일 import·등록 0). 하네스 골격·guard·clip·PARA 는 DU306 r2 시험(records 사본)에서 복사했다.
//   ▶ after 는 check 를 단언하고 before 는 같은 측정을 같은 순서로 기록만 한다. need 는 두 phase 공통 전제(입력·계보·도달·무네트워크)다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart' show DiagnosticsTreeStyle, TextTreeRenderer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_filter_state.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab_reads.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/carrot_style_calendar.dart';
import 'package:ALfit/widgets/inputs/region_picker_sheet.dart';
import 'package:ALfit/widgets/pickers/date_picker_bottom_sheet.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

/// 초기화용 platform 대역(Firebase core — UJT :50 과 같은 형태). 업무 호출 허용이 아니다.
class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// HTTP 생성 차단·계수(DU306 과 같음).
class _NoNet extends HttpOverrides {
  int created = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('DU310 network guard');
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

const _kTestName = 'D310 S077 job-tab four scenes'; // argv.json 의 정확 이름(phase 와 무관하게 고정)
const _kDay = '2026-11-15'; // 실행 허용일 — [11-15 자체검토 허브] 2026-11-13 → 2026-11-15 로 옮김(판정 무변경)
// [11-15 자체검토 r1] 실행일을 11-13 → 11-15 로 옮기면서 '미래 두 칸'도 같은 관계로 +2일 옮긴다
//   (t0 은 11-14 가 지난 날짜가 되어 즐겨찾기 1건이 정상 숨김 → 머리말 4개, 시험 전제 이탈).
const _kFrom = '2026-11-16'; // 선택 범위 — 같은 달(11월)의 미래 두 칸, 월 이동 0
const _kTo = '2026-11-17';
const _kRangeLabel = '11/16~11/17'; // 활성 날짜 칩 라벨(host:855 의 M/d~M/d)
const _kSeoul = '서울특별시';
const _kFav1 = 'd310-t1';
const _kFav2 = 'd310-t2';

const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _fsOps = [
  'aggregateQuery', 'clearPersistence', 'disableNetwork', 'documentReferenceDelete', 'documentReferenceGet',
  'documentReferenceSet', 'documentReferenceSnapshot', 'documentReferenceUpdate', 'enableNetwork', 'loadBundle',
  'namedQueryGet', 'persistenceCacheIndexManagerRequest', 'queryGet', 'querySnapshot', 'setIndexConfiguration',
  'setLoggingEnabled', 'snapshotsInSyncSetup', 'terminate', 'transactionCreate', 'transactionGet',
  'transactionStoreResult', 'waitForPendingWrites', 'writeBatchCommit',
];
const _fnBase = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi';
const _fnOps = ['call', 'registerEventChannel'];
const _fnLegacy = 'plugins.flutter.io/firebase_functions';

const _kTol = 0.01;
const _kEps = 1e-6;
const _kAlong = 4.0; // 도달 목표: 대상이 창 가장자리에서 4 안쪽
const _kMinStrip = 2.0; // 해제점 빈 여백 띠의 최소 두께(이보다 얇으면 빈 여백 없음으로 본다)

// ── helper 별 pump·시도 상한(budget.md 의 산식 입력) ──
const _kLoad = 10; // mount 뒤 첫 로드 frames
const _kTapWait = 6; // 칩 tap(재조회)·route 열기/닫기·시스템 뒤로·해제·X 정리 뒤 frames
const _kDayWait = 2; // 달력 칸 tap 뒤
const _kCityWait = 3; // 지역 1단계(시 → 구 목록, route 변화 0) 뒤
const _kHWait = 3; // 칩 띠 가로 drag 뒤
const _kVWait = 4; // 목록 세로 drag 뒤(대역 응답·재빌드 포함)
const _kSheetWait = 3; // 시트 안 세로 drag 뒤
const _kHTry = 2; // reachH 호출당 drag 최대
const _kSheetTry = 1; // 시트 안 대상당 drag 최대(스크롤 조상이 있는 대상만 — 14·15·서울특별시)

typedef _V = ({String id, Size size, double scale, int vTry});
const _V _w = (id: 'W', size: Size(390, 844), scale: 1.0, vTry: 4);
const _V _b = (id: 'B', size: Size(320, 640), scale: 2.0, vTry: 8);

// phase 동적 상한 C — (명시 pump, 제품 mount, tap+dispatch, drag, route 열기, text, PNG). 아래 _deriveC 와 같아야 시작한다.
const _kC = (pump: 348, mount: 4, tap: 30, drag: 46, route: 6, text: 0, png: 4);
// 정상 빈 teardown(C 밖) — 장면당 빈 pumpWidget 1 + pump 1.
const _kT = (pumpWidget: 4, pump: 4);
// 실패 정리 F(C·T 밖) — 아직 mount 돼 있으면 빈 pumpWidget 1 + pump 2.
const _kF = (pumpWidget: 1, pump: 2);

/// C 를 helper 상수에서 다시 계산한다(plan/budget.md 와 같은 식).
({int pump, int mount, int tap, int drag, int route, int text, int png}) _deriveC() {
  int basicPump(_V v) => _kLoad + _kHTry * _kHWait + v.vTry * _kVWait;
  int basicDrag(_V v) => _kHTry + v.vTry;
  const reachH = 6; // 즐겨찾기·단기·날짜·지역·날짜 해제·지역 해제
  const sheetDragTargets = 3; // 14·15(날짜 시트 SingleChildScrollView)·서울특별시(지역 ListView). 선택 완료·서울특별시 전체는 고정 영역(drag 0)
  const waitTaps = 12; // 즐겨찾기·단기·날짜 열기·선택 완료·지역 열기·서울특별시 전체·배지·시스템 뒤로·날짜 해제·지역 해제·X 정리 2(before)
  const dayTaps = 2;
  const cityTaps = 1;
  const activePump = _kLoad + reachH * _kHTry * _kHWait + sheetDragTargets * _kSheetTry * _kSheetWait +
      waitTaps * _kTapWait + dayTaps * _kDayWait + cityTaps * _kCityWait;
  const activeDrag = reachH * _kHTry + sheetDragTargets * _kSheetTry;
  const activeTap = waitTaps + dayTaps + cityTaps;
  return (
    pump: basicPump(_w) + basicPump(_b) + 2 * activePump,
    mount: 4,
    tap: 2 * activeTap,
    drag: basicDrag(_w) + basicDrag(_b) + 2 * activeDrag,
    route: 2 * 3,
    text: 0,
    png: 4,
  );
}

// ── fixture(plan/fixtures.md 표와 같은 값) ──
DateTime _kstMidnight(int y, int m, int d) => DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

TOModel _flex(String id, String title, String city, String district, String addr, List<String> dates, DateTime createdAt) =>
    TOModel(
      id: id,
      businessId: 'biz-$id',
      businessName: '$district 물류센터',
      businessAddress: addr,
      businessCity: city,
      businessDistrict: district,
      type: 'flex',
      title: title,
      creatorUID: 'admin1',
      status: TOStatus.active,
      isPublished: true,
      publishMode: 'immediate',
      isManualClosed: false,
      totalSlots: dates.length,
      slotDateKeys: dates,
      totalRequired: 3,
      createdAt: createdAt,
      statusUpdatedAt: createdAt,
    );

TOModel _contract(String id, String title, String city, String district, String addr, DateTime start, DateTime end,
        DateTime createdAt) =>
    TOModel(
      id: id,
      businessId: 'biz-$id',
      businessName: '$district 물류센터',
      businessAddress: addr,
      businessCity: city,
      businessDistrict: district,
      type: 'contract',
      title: title,
      creatorUID: 'admin1',
      status: TOStatus.active,
      isPublished: true,
      publishMode: 'immediate',
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDays: const ['월', '화', '수', '목', '금'],
      rangeStart: start,
      rangeEnd: end,
      totalRequired: 3,
      createdAt: createdAt,
      statusUpdatedAt: createdAt,
    );

final List<TOModel> _page1 = [
  _flex(_kFav1, '강남 주말 피킹', _kSeoul, '강남구', '서울특별시 강남구 테헤란로 101', const [_kFrom, _kTo], _kstMidnight(2026, 11, 10)),
  _flex(_kFav2, '마포 토요일 포장', _kSeoul, '마포구', '서울특별시 마포구 월드컵로 22', const [_kFrom], _kstMidnight(2026, 11, 9)),
  _flex('d310-t3', '분당 일요일 상하차', '경기도', '성남시', '경기도 성남시 분당구 판교로 33', const [_kTo, '2026-11-18'],
      _kstMidnight(2026, 11, 8)),
  _contract('d310-t4', '수원 평일 장기 분류', '경기도', '수원시', '경기도 수원시 영통구 광교로 44', _kstMidnight(2026, 11, 16),
      _kstMidnight(2026, 12, 31), _kstMidnight(2026, 11, 7)),
  _contract('d310-t5', '송파 평일 장기 검수', _kSeoul, '송파구', '서울특별시 송파구 올림픽로 55', _kstMidnight(2026, 11, 20),
      _kstMidnight(2027, 1, 31), _kstMidnight(2026, 11, 6)),
];

/// 기본 장면 추가 페이지 — 서버 조건(isPublished·status ACTIVE)은 통과하지만 날짜가 지난 하루뿐인 단기 공고 1건.
///   화면은 host:410(isVisibleToWorkerFlex — 완전한 날짜가 모두 오늘 전)에서 숨긴다 → 표시 목록·더보기 위치 불변, hasMore=true 유지.
TOModel _hidden(int k) => _flex('d310-p${k.toString().padLeft(2, '0')}', '지난 단기 $k', _kSeoul, '강남구',
    '서울특별시 강남구 역삼로 9', const ['2026-11-12'], _kstMidnight(2026, 11, 5));

/// 읽기 경계 대역. 두 경계의 로그를 나누고 **실제로 받은 인자만** 기록한다.
class _Srv {
  _Srv({required this.page1, required this.byId, required this.hiddenCap});

  final List<TOModel> page1;
  final Map<String, TOModel> byId;
  final int hiddenCap;
  String actor = 'init';
  final List<Map<String, Object?>> paged = [];
  final List<Map<String, Object?>> byIds = [];
  final List<Map<String, Object?>> apps = [];
  final List<String> violations = [];

  Never _bad(Map<String, Object?> e, String why) {
    violations.add(why);
    e['result'] = 'violation:$why';
    _out('D310-SRV ${jsonEncode(e)}');
    throw StateError('D310 fake contract: $why');
  }

  static String? _k(DateTime? d) => d == null ? null : FormatHelper.toKstDateKey(d);

  /// cursor = 실제 서버처럼 직전 페이지의 마지막 공고 ID(functions index.ts 의 nextLastToId). page1 끝 → 숨김 1, d310-pNN → NN+1.
  int? _nextHidden(String cursor) {
    if (cursor == page1.last.id) return 1;
    final m = RegExp(r'^d310-p(\d{2})$').firstMatch(cursor);
    return m == null ? null : int.parse(m.group(1)!) + 1;
  }

  UserJobTabReads reads() => UserJobTabReads(
        publishedTOsPaged: ({String? lastToId, TOFilterState? filter}) async {
          final f = filter;
          final e = <String, Object?>{
            'call': 'publishedTOsPaged',
            'n': paged.length + 1,
            'actor': actor,
            'cursor': lastToId,
            'filter': f == null
                ? null
                : {
                    'type': f.type,
                    'city': f.city,
                    'district': f.district,
                    'keyword': f.keyword,
                    'fav': f.showFavoritesOnly,
                    'date': f.dateRange == null ? null : '${_k(f.dateRange!.start)}~${_k(f.dateRange!.end)}',
                    'sort': f.sortBy,
                  },
          };
          paged.add(e);
          // 이 시험의 흐름에서 이 경계는 기본 조건으로만 불린다(즐겨찾기 분기는 tosByIds — host:206–213). 서버 조건이 실리면
          //   서버 필터(index.ts 의 type/city/district where)를 대역이 흉내 내야 하므로 하지 않고 위반으로 둔다(_K1Srv:444 와 같은 방식).
          if (f != null &&
              (f.type != null || f.city != null || f.district != null || (f.keyword ?? '').isNotEmpty || f.showFavoritesOnly)) {
            _bad(e, 'server-condition');
          }
          // 응답은 cursor 로만 고른다(UJT _reads:123–134 와 같은 축약 — 날짜·정렬은 화면이 거른다).
          final List<TOModel> items;
          if (lastToId == null) {
            items = page1;
          } else {
            final k = _nextHidden(lastToId);
            if (k == null || k > hiddenCap) _bad(e, 'cursor-range');
            items = [_hidden(k)];
          }
          final next = items.last.id;
          e['ids'] = items.map((x) => x.id).toList();
          e['hasMore'] = true;
          e['nextCursor'] = next;
          e['result'] = 'ok';
          _out('D310-SRV ${jsonEncode(e)}');
          return <String, dynamic>{'items': items, 'lastToId': next, 'hasMore': true};
        },
        myApplications: (uid) async {
          final e = <String, Object?>{'call': 'myApplications', 'n': apps.length + 1, 'actor': actor, 'uid': uid};
          apps.add(e);
          _out('D310-SRV ${jsonEncode(e)}');
          return const <ApplicationModel>[];
        },
        tosByIds: (ids) async {
          // 실제 인자는 ID 목록뿐이다(user_job_tab_reads.dart:28). type·city 는 이 경계에 전달되지 않으므로 기록·적용하지 않는다.
          final e = <String, Object?>{'call': 'tosByIds', 'n': byIds.length + 1, 'actor': actor, 'ids': List<String>.of(ids)};
          byIds.add(e);
          final miss = ids.where((i) => !byId.containsKey(i)).toList();
          if (miss.isNotEmpty) _bad(e, 'unknown-id $miss');
          final out = [for (final i in ids) byId[i]!];
          e['returned'] = out.map((x) => x.id).toList();
          e['result'] = 'ok';
          _out('D310-SRV ${jsonEncode(e)}');
          return out;
        },
      );
}

/// 지원자 provider 대역(UJT :61 과 같은 게터 덮개 + 즐겨찾기 ID).
class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
        favoriteToIds: const [_kFav1, _kFav2],
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

/// route 열림·닫힘 관측(하네스 전용 NavigatorObserver — production seam 아님).
class _Obs extends NavigatorObserver {
  final List<String> log = [];
  int pushes = 0;
  int pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    log.add('push:${route.runtimeType}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    log.add('pop:${route.runtimeType}');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => log.add('remove:${route.runtimeType}');
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => log.add('replace:${newRoute.runtimeType}');
}

/// 해제 tap 지점 — face 만으로 정하는 phase 무관 규칙(사전 고정, 실행 뒤 바꾸지 않는다).
///   N = face 중심의 최소 48 확장(after 의 `_chipReceiver` 와 같은 모양: ConstrainedBox(min48)+Align(1,1), cand:902–904).
///   N∖F 의 가장 두꺼운 띠(위→아래→왼→오른 순)가 _kMinStrip 이상이면 그 띠의 가운데, 아니면(face 가 양축 모두 ≥46)
///   label 상자 가운데(face 안·X 밖) — 없는 여백 좌표를 만들지 않는다.
({Offset p, String kind, double thick, Rect n}) _clearPoint(Rect face, Rect label) {
  final n = Rect.fromCenter(center: face.center, width: math.max(48.0, face.width), height: math.max(48.0, face.height));
  final strips = <(String, double, Offset)>[
    ('margin-top', face.top - n.top, Offset(face.center.dx, (n.top + face.top) / 2)),
    ('margin-bottom', n.bottom - face.bottom, Offset(face.center.dx, (face.bottom + n.bottom) / 2)),
    ('margin-left', face.left - n.left, Offset((n.left + face.left) / 2, face.center.dy)),
    ('margin-right', n.right - face.right, Offset((face.right + n.right) / 2, face.center.dy)),
  ];
  var best = strips.first;
  for (final s in strips) {
    if (s.$2 > best.$2 + 1e-9) best = s;
  }
  if (best.$2 >= _kMinStrip) return (p: best.$3, kind: best.$1, thick: best.$2, n: n);
  return (p: label.center, kind: 'label', thick: best.$2, n: n);
}

/// [CP03 C1 r2] 조상이 자식에게 실제로 거는 clip 의 정확 도형(DU306 r2 사본 그대로).
class _Clip {
  const _Clip(this.kind, this.type, {this.rect, this.rrect});
  final String kind;
  final String type;
  final Rect? rect;
  final RRect? rrect;
}

bool _inside(_Clip c, Rect r) {
  final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
  switch (c.kind) {
    case 'rect':
      final kr = c.rect!;
      return r.left >= kr.left - 0.5 && r.top >= kr.top - 0.5 && r.right <= kr.right + 0.5 && r.bottom <= kr.bottom + 0.5;
    case 'rrect':
      final kq = c.rrect!.inflate(0.5);
      return corners.every(kq.contains);
    case 'oval':
      final e = c.rect!.inflate(0.5);
      final rx = e.width / 2, ry = e.height / 2;
      if (rx <= 0 || ry <= 0) return false;
      return corners.every((o) {
        final dx = (o.dx - e.center.dx) / rx, dy = (o.dy - e.center.dy) / ry;
        return dx * dx + dy * dy <= 1.0;
      });
  }
  return false;
}

_Clip? _activeClip(RenderObject p, RenderObject c) {
  final type = p.runtimeType.toString();
  if (p is RenderClipRect) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('rect', type, rect: p.clipper?.getClip(p.size) ?? Offset.zero & p.size);
  }
  if (p is RenderClipRRect) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('rrect', type,
        rrect: p.clipper?.getClip(p.size) ?? p.borderRadius.resolve(p.textDirection).toRRect(Offset.zero & p.size));
  }
  if (p is RenderClipOval) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('oval', type, rect: p.clipper?.getClip(p.size) ?? Offset.zero & p.size);
  }
  if (p is RenderClipPath) {
    if (p.clipBehavior == Clip.none) return null;
    if (p.clipper == null) return _Clip('rect', '$type(기본 사각 path)', rect: Offset.zero & p.size);
    return _Clip('unsupported', '$type(사용자 path clipper)');
  }
  if (p is RenderClipRSuperellipse) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('unsupported', type);
  }
  if (p is RenderPhysicalModel) {
    if (p.clipBehavior == Clip.none) return null;
    final r = Offset.zero & p.size;
    return _Clip('rrect', type,
        rrect: p.clipper?.getClip(p.size) ??
            (p.shape == BoxShape.circle
                ? RRect.fromRectXY(r, r.width / 2, r.height / 2)
                : (p.borderRadius ?? BorderRadius.zero).toRRect(r)));
  }
  if (p is RenderPhysicalShape) {
    if (p.clipBehavior == Clip.none) return null;
    return _Clip('unsupported', '$type(path clipper)');
  }
  if (p is RenderWrap && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  if (p is RenderAnimatedSize && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  if (p is RenderFittedBox && p.clipBehavior != Clip.none) return _Clip('unsupported', '$type(넘침 비공개)');
  final a = p.describeApproximatePaintClip(c);
  if (a == null) return null;
  // [11-15 자체검토 r2] RenderViewportBase(가로 칩 띠 ListView 의 RenderViewport 등)는 paint 에서 pushClipRect(Offset.zero & size)
  //   사각 clip 을 쓰고 describeApproximatePaintClip 도 겹침 0 이면 그 사각을 그대로 돌려준다 — _RenderSingleChildViewport 와 같은 사각으로 다룬다.
  //   (r1 은 '미지원 근사 clip' 으로 거부해 S3 즐겨찾기 칩 탭 전 full 판정에서 멈췄다, hit=true)
  if (p is RenderFlex || p is RenderStack || p is RenderConstraintsTransformBox || p is RenderViewportBase ||
      type == '_RenderSingleChildViewport' || type == '_RenderTheater') {
    return _Clip('rect', type, rect: a);
  }
  return _Clip('unsupported', '$type(근사 clip 만 공개)');
}

void main() {
  final phase = Platform.environment['DU310_PHASE'] ?? '';
  final dayArg = Platform.environment['DU310_DAY'] ?? '';
  final run = Platform.environment['DU310_RUN'] == '1' && (phase == 'before' || phase == 'after') && dayArg == _kDay;
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    // 번들 NotoSansKR(NotoSansKR·Roboto 이름) + MaterialIcons(SDK) — du1_vq_capture.dart:31 의 공용 helper.
    await vqLoadFonts();
    // 시험 기본 글꼴(FlutterTest)도 번들 NotoSansKR Regular — 글꼴 미지정 글자가 다른 글꼴로 재지 않게(DU306 _loadFonts 와 같음).
    await (FontLoader('FlutterTest')
          ..addFont(File('assets/fonts/NotoSansKR-Regular.ttf').readAsBytes().then((x) => ByteData.view(x.buffer))))
        .load();
  });

  testWidgets(_kTestName, (t) async {
    DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));
    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final sem = t.ensureSemantics(); // 칩 의미 행렬 관측(행동 아님)
    final prevOnError = FlutterError.onError;
    final prevHttp = HttpOverrides.current;
    final net = _NoNet();
    HttpOverrides.global = net;
    final biz = <String, int>{};
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final o in _fsOps) {
      m.setMockMessageHandler('$_fsBase.$o', (msg) async {
        biz['fs.$o'] = (biz['fs.$o'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du310-blocked', 'firestore $o 차단', null]);
      });
    }
    for (final o in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$o', (msg) async {
        biz['fn.$o'] = (biz['fn.$o'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du310-blocked', 'functions $o 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du310-blocked', message: 'functions legacy ${call.method} 차단');
    });

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nRoute = 0, nText = 0, nPng = 0;
    var nTearPw = 0, nTearPump = 0, nRouteClose = 0, nX = 0, sceneX = 0;
    Map<String, Object?> counts() => {
          'phase': phase, 'pump': nPump, 'mount': nMount, 'tapDispatch': nTap, 'drag': nDrag, 'routeOpen': nRoute,
          'text': nText, 'png': nPng, 'teardownPumpWidget': nTearPw, 'teardownPump': nTearPump, 'routeClose': nRouteClose,
          'xCleanup': nX,
        };
    var scene = '-';
    var stage = 'start';
    var op = 'init';
    _Srv? srv;
    var obs = _Obs();
    final scopeLog = <String>[];
    final errors = <({String scene, String stage, int pump, String first, String full})>[];
    FlutterError.onError = (d) => errors.add((
          scene: scene,
          stage: stage,
          pump: nPump,
          first: d.exceptionAsString().split(nl).first,
          full: TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight(),
        ));
    final visited = <String>[];
    var live = false;
    var completed = false;

    Never stop(String why) {
      _out('D310-STOP ${jsonEncode({'phase': phase, 'scene': scene, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.scene}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz, 'violations': srv?.violations})}');
      for (final e in errors) {
        _out('D310-STOPERR ${jsonEncode({'scene': e.scene, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$scene/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    // after 단언 / before 기록 — 값은 항상 먼저 출력한다(D310-CHECK).
    void check(bool ok, String what, [Object? detail]) {
      _out('D310-CHECK ${jsonEncode({'phase': phase, 'scene': scene, 'stage': stage, 'what': what, 'ok': ok, 'assert': after,
        'detail': detail})}');
      if (after) need(ok, '$what ${detail ?? ''}');
    }

    void budget() {
      final ok = nPump <= _kC.pump && nMount <= _kC.mount && nTap <= _kC.tap && nDrag <= _kC.drag && nRoute <= _kC.route &&
          nText <= _kC.text && nPng <= _kC.png;
      need(ok, '한도 C 초과 ${counts()}');
    }

    void tearBudget() {
      need(nTearPw <= _kT.pumpWidget && nTearPump <= _kT.pump, '한도 T 초과 ${counts()}');
    }

    void clockGuard(String where) {
      final k = kstNow();
      final loc = DateTime.now();
      final min = k.hour * 60 + k.minute;
      need(key(k) == _kDay && key(loc) == _kDay, '$where 실행일 이탈 kst=${key(k)} local=${key(loc)} pin=$dayArg');
      need(loc.timeZoneOffset == const Duration(hours: 9), '$where local 시간대 +09:00 아님 ${loc.timeZoneOffset}');
      need(min >= 8 * 60 && min < 21 * 60 + 30, '$where 실행 시각 구간 이탈 kst=$k');
    }

    void guard(String where) {
      final ex = t.takeException();
      need(ex == null, '$where 예외: $ex');
      for (final e in errors) {
        _out('D310-ERR ${jsonEncode({'phase': phase, 'scene': e.scene, 'stage': e.stage, 'pump': e.pump, 'first': e.first,
          'full': e.full})}');
        stop('FlutterError(허용 0) ${e.first} at $where');
      }
      errors.clear();
      need(net.created == 0, '$where HttpClient ${net.created}');
      need(biz.isEmpty, '$where 업무 채널 $biz');
      final sv = srv;
      need(sv == null || sv.violations.isEmpty, '$where 대역 계약 위반 ${sv?.violations}');
    }

    // 명시 pump — 대역 actor 는 'post:<직전 행동>'(호출 시점 귀속).
    Future<void> frames(int n, String where, {int ms = 100}) async {
      srv?.actor = 'post:$op';
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(Duration(milliseconds: ms));
        guard('$where#$i');
      }
    }

    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    String plainOf(Element e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    Finder richExact(String s, {Finder? within}) {
      bool p(Widget w) => w is RichText && TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) == s;
      return within == null ? find.byWidgetPredicate(p) : find.descendant(of: within, matching: find.byWidgetPredicate(p));
    }

    List<double> rl(Rect r) => [r.left, r.top, r.right, r.bottom];
    bool near(double a, double b, double tol) => (a - b).abs() <= tol;
    Rect boxRect(RenderBox b) => MatrixUtils.transformRect(b.getTransformTo(null), Offset.zero & b.size);
    Rect rectOf(Element e) => boxRect(e.renderObject! as RenderBox);

    Element? nearest(Element e, bool Function(Widget w) p) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (p(a.widget)) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    // stop 요소(제외)에 닿기 전까지만 위로 찾는다(칩 바깥의 무관한 GestureDetector 를 receiver 로 잡지 않게).
    Element? nearestBelow(Element e, bool Function(Widget w) p, Element stopAt) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (identical(a, stopAt)) return false;
        if (p(a.widget)) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    TextStyle? styleOf(Element e) => ((e.widget as RichText).text as TextSpan).style;
    Color? colorOf(Element e) => styleOf(e)?.color;
    String hex(Color? c) => c == null ? 'null' : c.toARGB32().toRadixString(16);

    bool hitAt(Offset p, Element receiver) {
      final ro = receiver.renderObject;
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => identical(e.target, ro));
    }

    List<String> hitTop(Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.take(4).map((e) => e.target.runtimeType.toString()).toList();
    }

    // 활성 clip 사슬(CP03 정확 도형) + 화면 안 — 대상 render box 사각의 네 모서리 기준(DU306 r2 사본)
    ({bool full, List<String> failures}) clipOf(Element e, Rect screen) {
      final ro = e.renderObject! as RenderBox;
      final failures = <String>[];
      RenderObject c = ro;
      RenderObject? p = ro.parent;
      while (p != null) {
        final clip = _activeClip(p, c);
        if (clip != null) {
          final tr = MatrixUtils.getAsTranslation(ro.getTransformTo(p));
          if (clip.kind == 'unsupported') {
            failures.add('미지원 활성 clip ${clip.type}');
          } else if (tr == null) {
            failures.add('미지원 변환 ~${clip.type}');
          } else if (!_inside(clip, (Offset.zero & ro.size).shift(tr))) {
            failures.add('${clip.type} 밖');
          }
        }
        c = p;
        p = p.parent;
      }
      final g = boxRect(ro);
      final onScreen = g.left >= screen.left - 0.5 && g.top >= screen.top - 0.5 && g.right <= screen.right + 0.5 &&
          g.bottom <= screen.bottom + 0.5;
      if (!onScreen) failures.add('화면 밖 ${rl(g)}');
      return (full: failures.isEmpty, failures: failures);
    }

    // RenderParagraph → TextPainter 재구성(DU305 감사 r2 §3-1 과 같은 제약·±0.01). placeholder 가 있으면 재구성하지 않는다.
    Map<String, Object?> para(Element e, String what) {
      final ro = e.renderObject;
      need(ro is RenderParagraph, '$what RenderParagraph 아님');
      final p = ro! as RenderParagraph;
      var placeholder = false;
      p.text.visitChildren((s) {
        if (s is PlaceholderSpan) {
          placeholder = true;
          return false;
        }
        return true;
      });
      need(!placeholder, '$what placeholder — 치수 없이 재구성하지 않는다');
      final ellipsis = p.overflow == TextOverflow.ellipsis;
      final tp = TextPainter(
        text: p.text, textAlign: p.textAlign, textDirection: p.textDirection, textScaler: p.textScaler, maxLines: p.maxLines,
        ellipsis: ellipsis ? '…' : null, locale: p.locale, strutStyle: p.strutStyle, textWidthBasis: p.textWidthBasis,
        textHeightBehavior: p.textHeightBehavior,
      )..layout(minWidth: p.constraints.minWidth, maxWidth: (p.softWrap || ellipsis) ? p.constraints.maxWidth : double.infinity);
      final ts = p.textSize;
      final cs = p.constraints.constrain(tp.size);
      final ok = near(tp.width, ts.width, _kTol) && near(tp.height, ts.height, _kTol) && near(cs.width, p.size.width, _kTol) &&
          near(cs.height, p.size.height, _kTol);
      final plain = tp.plainText;
      final lines = <String>[];
      for (final lm in tp.computeLineMetrics()) {
        final b = tp.getLineBoundary(tp.getPositionForOffset(Offset(lm.left + lm.width / 2, lm.baseline - lm.ascent / 2)));
        lines.add(visibleText(plain.substring(b.start, b.end)).trim());
      }
      tp.dispose();
      final st = p.text.style;
      final rec = {'phase': phase, 'scene': scene, 'stage': stage, 'what': what, 'plain': TextLayout.plain(plain), 'lines': lines,
        'scale': p.textScaler.scale(10) / 10, 'size': [p.size.width, p.size.height], 'textSize': [ts.width, ts.height],
        'maxLines': p.maxLines, 'overflow': p.overflow.name, 'didExceedMaxLines': p.didExceedMaxLines,
        'color': hex(st?.color), 'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value, 'family': st?.fontFamily,
        'locale': p.locale?.toLanguageTag(), 'rect': rl(boxRect(p)), 'reconstructOk': ok};
      _out('D310-PARA ${jsonEncode(rec)}');
      need(ok, '$what TextPainter 재구성 불일치');
      return rec;
    }

    // ── 칩 띠·목록 ──
    Element strip() {
      final els = find
          .descendant(
              of: find.byType(UserJobTab),
              matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal))
          .evaluate()
          .toList();
      need(els.length == 1, '칩 가로띠 수 ${els.length}');
      return els.single;
    }

    ScrollPosition stripPos() {
      final s = find.descendant(of: fe(strip()), matching: find.byType(Scrollable)).evaluate().toList();
      need(s.isNotEmpty, '칩 띠 Scrollable 없음');
      return ((s.first as StatefulElement).state as ScrollableState).position;
    }

    Rect stripVp(Rect screen) => rectOf(strip()).intersect(screen);

    Element listScroll() {
      final els = find
          .descendant(
              of: find.byType(UserJobTab),
              matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
          .evaluate()
          .toList();
      need(els.length == 1, '목록 세로 Scrollable 수 ${els.length}');
      return els.single;
    }

    // 칩 하나 — 라벨 RichText(띠 안 정확 1) · face · receiver · Semantics(after) · X(활성칩)
    ({Element label, Element face, Element? receiver, Element? sem, Element? x}) chipEls(String text, {required bool activeFace}) {
      final st = strip();
      final ls = richExact(text, within: fe(st)).evaluate().toList();
      need(ls.length == 1, '칩 "$text" 수 ${ls.length}');
      final le = ls.single;
      final face = nearestBelow(
          le, (w) => activeFace ? (w is Container && w.decoration is BoxDecoration) : w is AnimatedContainer, st);
      need(face != null, '칩 "$text" face 없음');
      final f = face!;
      // after: _chipReceiver 의 GestureDetector(face 조상). before 빠른 칩: face 를 감싼 GestureDetector. before 활성칩: face 안 X 의 것.
      final up = nearestBelow(f, (w) => w is GestureDetector, st);
      final down = find.descendant(of: fe(f), matching: find.byType(GestureDetector)).evaluate().toList();
      final rcv = up ?? (down.length == 1 ? down.single : null);
      final semW = nearestBelow(f, (w) => w is Semantics && w.properties.button == true, st);
      final xs = find.descendant(of: fe(f), matching: find.byIcon(Icons.close)).evaluate().toList();
      return (label: le, face: f, receiver: rcv, sem: semW, x: xs.length == 1 ? xs.single : null);
    }

    // 의미 node — button / hasSelectedState / isSelected(null 과 false 를 나눠 적는다) + 위젯 Semantics.selected(null/false/true/absent)
    Map<String, Object?> semOf(Element le, Element? semW) {
      final node = t.semantics.find(fe(le));
      final d = node.getSemanticsData();
      final fl = d.flagsCollection;
      final hasSel = fl.hasSelectedState; // [미확인 API] A 시험에 사용례 없음(hasCheckedState 는 du1_c0:334) — A1 에서 확인
      final isSel = fl.isSelected;
      final wsel = semW == null ? 'absent' : ((semW.widget as Semantics).properties.selected?.toString() ?? 'null');
      return {
        'nodeId': node.id, 'label': visibleText(d.label), 'size': [node.rect.width, node.rect.height], 'button': fl.isButton,
        'hasSelectedState': hasSel, 'isSelected': isSel, 'selected3': hasSel ? '$isSel' : 'null', 'widgetSelected': wsel,
        'tap': d.hasAction(SemanticsAction.tap),
      };
    }

    // 칩 기하·색·의미 기록 → after 단언. state: fav-basic|fav-active|quick-basic|quick-active|active
    void chipRec(String chip, String text, String state,
        {required bool activeFace, required bool wantSelected, required Rect screen, bool reached = false}) {
      stage = 'chip:$chip';
      final c = chipEls(text, activeFace: activeFace);
      final primary = Theme.of(c.face).primaryColor;
      final face = rectOf(c.face);
      final rcv = c.receiver == null ? null : rectOf(c.receiver!);
      final n = Rect.fromCenter(center: face.center, width: math.max(48.0, face.width), height: math.max(48.0, face.height));
      final deco = (activeFace ? (c.face.widget as Container).decoration : (c.face.widget as AnimatedContainer).decoration)
          as BoxDecoration?;
      final border = deco?.border is Border ? (deco!.border! as Border).top : null;
      final icons = find.descendant(of: fe(c.face), matching: find.byType(Icon)).evaluate().toList();
      final iconColor = icons.isEmpty ? null : (icons.first.widget as Icon).color;
      final txt = styleOf(c.label);
      final sm = semOf(c.label, c.sem);
      final vc = clipOf(c.receiver ?? c.face, screen);
      final hit = c.receiver != null && hitAt((rcv ?? face).center, c.receiver!);
      final rec = <String, Object?>{
        'phase': phase, 'scene': scene, 'chip': chip, 'state': state, 'reached': reached, 'face': rl(face),
        'faceSize': [face.width, face.height], 'receiver': rcv == null ? null : rl(rcv),
        'receiverSize': rcv == null ? null : [rcv.width, rcv.height], 'nominal': rl(n), 'faceBg': hex(deco?.color),
        'border': hex(border?.color), 'borderW': border?.width, 'text': hex(txt?.color), 'weight': txt?.fontWeight?.value,
        'icon': hex(iconColor), 'primary': hex(primary), 'full': vc.full, 'failures': vc.failures, 'hit': hit, 'sem': sm,
        'stripOffset': stripPos().pixels,
      };
      _out('D310-CHIP ${jsonEncode(rec)}');
      check(rcv != null && rcv.width >= 48 - _kEps && rcv.height >= 48 - _kEps, '$chip receiver ≥48×48',
          rcv == null ? null : [rcv.width, rcv.height]);
      check(rcv != null && rcv.left <= face.left + _kTol && rcv.top <= face.top + _kTol && rcv.right >= face.right - _kTol &&
          rcv.bottom >= face.bottom - _kTol, '$chip receiver ⊇ face');
      check(rcv != null && near(rcv.left, n.left, _kTol) && near(rcv.top, n.top, _kTol) && near(rcv.right, n.right, _kTol) &&
          near(rcv.bottom, n.bottom, _kTol), '$chip receiver = face 중심 최소48 확장', rcv == null ? null : rl(rcv));
      check(sm['button'] == true && sm['selected3'] == '$wantSelected' && sm['widgetSelected'] == '$wantSelected' &&
          sm['tap'] == true, '$chip semantics button·selected=$wantSelected·tap', sm);
      switch (state) {
        case 'fav-basic':
        case 'quick-basic':
          check(deco?.color == Colors.white && border?.color == AppColors.grey300 && txt?.color == AppColors.grey700 &&
              (icons.isEmpty || iconColor == AppColors.textSecondary), '$chip 기본 흰 바탕·grey300·grey700·아이콘 textSecondary');
        case 'fav-active':
        case 'quick-active':
          check(deco?.color == primary && border?.color == primary && txt?.color == Colors.white &&
              txt?.fontWeight == FontWeight.w600 && (icons.isEmpty || iconColor == Colors.white), '$chip 활성 brand 채움·흰 글자·w600');
        case 'active':
          check(deco?.color == primary.withValues(alpha: 0.08) && border?.color == primary.withValues(alpha: 0.5) &&
              txt?.color == primary && c.x != null && (c.x!.widget as Icon).color == primary, '$chip 활성 값 칩 brand 면·글자·X');
        default:
          stop('알 수 없는 칩 상태 $state');
      }
      if (reached) check(vc.full && hit, '$chip full·hit', vc.failures);
    }

    // ── 필터 버튼·배지 ──
    ({Element ink, Element stack, Element? badge, Element? digit}) filterEls() {
      final tune = find.descendant(of: find.byType(UserJobTab), matching: find.byIcon(Icons.tune)).evaluate().toList();
      need(tune.length == 1, '필터 아이콘 수 ${tune.length}');
      final ink = nearest(tune.single, (w) => w is InkWell);
      final stack = ink == null ? null : nearest(ink, (w) => w is Stack);
      need(ink != null && stack != null, '필터 버튼 InkWell/Stack 없음');
      final st = stack!;
      // Icon 은 Text 위젯이 아니다(RichText 직접) — Stack 아래 Text 는 배지 숫자뿐이다.
      final texts = find.descendant(of: fe(st), matching: find.byType(Text)).evaluate().toList();
      need(texts.length <= 1, '배지 Text 수 ${texts.length}');
      final digit = texts.isEmpty ? null : find.descendant(of: fe(texts.single), matching: find.byType(RichText)).evaluate().first;
      final badge = texts.isEmpty ? null : nearest(texts.single, (w) => w is Container);
      return (ink: ink!, stack: st, badge: badge, digit: digit);
    }

    void filterRec(int? want, Rect screen) {
      stage = 'filter';
      final f = filterEls();
      final inkR = rectOf(f.ink);
      final hit = hitAt(inkR.center, f.ink);
      final vc = clipOf(f.ink, screen);
      final rec = <String, Object?>{'phase': phase, 'scene': scene, 'want': want, 'ink': rl(inkR), 'full': vc.full, 'hit': hit};
      if (f.badge != null) {
        final bR = rectOf(f.badge!), dR = rectOf(f.digit!);
        final deco = (f.badge!.widget as Container).decoration as BoxDecoration?;
        rec.addAll({'badge': rl(bR), 'digit': rl(dR), 'digitText': plainOf(f.digit!), 'badgeBg': hex(deco?.color),
          'badgeBorder': deco?.border is Border ? hex((deco!.border! as Border).top.color) : null,
          'digitColor': hex(colorOf(f.digit!)), 'badgeClip': clipOf(f.badge!, screen).failures});
      }
      _out('D310-FILTER ${jsonEncode(rec)}');
      need(want == null ? f.badge == null : (f.digit != null && plainOf(f.digit!) == '$want'),
          '배지 수 $want 아님 (${f.digit == null ? '-' : plainOf(f.digit!)})');
      check(inkR.width >= 48 - _kEps && inkR.height >= 48 - _kEps && vc.full && hit, '필터 버튼 ≥48·full·hit', rl(inkR));
      if (f.badge != null) {
        final bR = rectOf(f.badge!), dR = rectOf(f.digit!);
        final deco = (f.badge!.widget as Container).decoration as BoxDecoration?;
        final primary = Theme.of(f.ink).primaryColor;
        check(dR.left >= bR.left - 0.5 && dR.top >= bR.top - 0.5 && dR.right <= bR.right + 0.5 && dR.bottom <= bR.bottom + 0.5,
            '배지 숫자 box ⊂ 배지', [rl(dR), rl(bR)]);
        check(clipOf(f.badge!, screen).full, '배지 clip 0·화면 안');
        check(deco?.color == Colors.white && deco?.border is Border && (deco!.border! as Border).top.color == primary &&
            colorOf(f.digit!) == primary, '배지 흰 바탕·brand 테두리/숫자');
      }
    }

    void summaryIs(String want) {
      final els = richExact(want, within: find.byType(UserJobTab)).evaluate().toList();
      need(els.length == 1, '머리말 "$want" 아님(${els.length})');
    }

    // 실제 harness 값 — 문자열이 아니라 실행 중 읽는다.
    void envOf(_V v) {
      final ctx = t.element(find.byType(UserJobTab));
      final th = Theme.of(ctx);
      final mq = MediaQuery.of(ctx);
      final loc = Localizations.localeOf(ctx);
      final ats = th.appBarTheme.titleTextStyle;
      final env = <String, Object?>{
        'phase': phase, 'scene': scene, 'platform': th.platform.name,
        'visualDensity': [th.visualDensity.horizontal, th.visualDensity.vertical], 'tapTarget': th.materialTapTargetSize.name,
        'm3': th.useMaterial3, 'primary': hex(th.primaryColor), 'brand': hex(AppColors.brand),
        'appBarTitle': [ats?.fontFamily, ats?.fontSize, ats?.fontWeight?.value], 'dpr': mq.devicePixelRatio,
        'viewDpr': t.view.devicePixelRatio, 'textScale': mq.textScaler.scale(10) / 10, 'boldText': MediaQuery.boldTextOf(ctx),
        'padding': mq.padding.toString(), 'viewPadding': mq.viewPadding.toString(), 'viewInsets': mq.viewInsets.toString(),
        'size': [mq.size.width, mq.size.height], 'locale': loc.toLanguageTag(),
      };
      _out('D310-SCENEENV ${jsonEncode(env)}');
      need(loc == const Locale('ko', 'KR'), 'locale ${loc.toLanguageTag()}');
      need(!MediaQuery.boldTextOf(ctx), 'boldText true');
      need(near(mq.devicePixelRatio, 1.0, 1e-9) && near(t.view.devicePixelRatio, 1.0, 1e-9), 'DPR ${mq.devicePixelRatio}');
      need(mq.padding == EdgeInsets.zero && mq.viewPadding == EdgeInsets.zero && mq.viewInsets == EdgeInsets.zero, 'inset 0 아님');
      need(near(mq.textScaler.scale(10) / 10, v.scale, 1e-6), 'textScaler ${mq.textScaler}');
      need(near(mq.size.width, v.size.width, 1e-6) && near(mq.size.height, v.size.height, 1e-6), 'size ${mq.size}');
    }

    // 제목 실제 배율·머리 높이·잉크·조상 clip·TabBar/본문 점유·탭 색(after 단언, before 기록 — B before 는 1.34/44 예상).
    void titleCheck(_V v) {
      stage = 'title';
      final screen = Offset.zero & v.size;
      final abs = find.byType(AppBar).evaluate().toList();
      need(abs.length == 1, 'AppBar 수 ${abs.length}');
      final abEl = abs.single;
      final abW = abEl.widget as AppBar;
      final tl = richExact('일자리', within: fe(abEl)).evaluate().toList();
      need(tl.length == 1, '제목 수 ${tl.length}');
      final te = tl.single;
      final pr = para(te, '제목');
      final p = te.renderObject! as RenderParagraph;
      final abR = rectOf(abEl);
      final toolbar = abW.toolbarHeight ?? 56.0;
      final tbs = find.descendant(of: fe(abEl), matching: find.byType(TabBar)).evaluate().toList();
      need(tbs.length == 1, 'TabBar 수 ${tbs.length}');
      final tbR = rectOf(tbs.single);
      final bodyR = rectOf(find.byType(TabBarView).evaluate().single);
      final titleR = rectOf(te);
      final plain = p.text.toPlainText(includeSemanticsLabels: false);
      Rect? ink;
      for (final b in p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: plain.length))) {
        final r = MatrixUtils.transformRect(p.getTransformTo(null), b.toRect());
        ink = ink == null ? r : ink.expandToInclude(r);
      }
      final vc = clipOf(te, screen);
      final lineH = (pr['textSize'] as List)[1] as double;
      final wantToolbar = math.max(44.0, lineH + 8);
      final scale = p.textScaler.scale(10) / 10;
      Color? tabColor(String l) {
        final e = richExact(l, within: fe(tbs.single)).evaluate().toList();
        return e.length == 1 ? colorOf(e.single) : null;
      }

      final primary = Theme.of(te).primaryColor;
      _out('D310-TITLE ${jsonEncode({'phase': phase, 'scene': scene, 'scale': scale, 'toolbar': toolbar, 'wantToolbar': wantToolbar,
        'lineH': lineH, 'appBar': rl(abR), 'title': rl(titleR), 'ink': ink == null ? null : rl(ink), 'tabBar': rl(tbR),
        'body': rl(bodyR), 'clip': vc.failures, 'tabUnselected': hex(tabColor('내 지원')), 'tabSelected': hex(tabColor('일자리 찾기'))})}');
      check(near(scale, v.scale, 1e-6), '제목 실제 배율 = ${v.scale}', scale);
      check(near(toolbar, wantToolbar, _kTol), '머리 높이 = max(44, 줄높이+8)', [toolbar, wantToolbar]);
      check(near(abR.height, toolbar + 49, _kTol), 'AppBar 높이 = toolbar + TabBar 49', [abR.height, toolbar]);
      check(titleR.top >= abR.top - 0.5 && titleR.bottom <= abR.top + toolbar + 0.5 && vc.full, '제목 box toolbar 안·조상 clip 0',
          vc.failures);
      check(ink != null && ink.top >= abR.top - 0.5 && ink.bottom <= abR.top + toolbar + 0.5, '제목 잉크 toolbar 안',
          ink == null ? null : rl(ink));
      check(tbR.top >= abR.top + toolbar - 0.5 && tbR.bottom <= abR.bottom + 0.5 && bodyR.top >= abR.bottom - 0.5,
          'TabBar·본문 점유가 머리 아래', [rl(tbR), rl(bodyR)]);
      check(tabColor('내 지원') == AppColors.textSecondary && tabColor('일자리 찾기') == primary, '미선택 탭 textSecondary·선택 brand');
    }

    // ── 행동(전부 counts·budget 경유) ──
    Future<void> tapAt(Offset p, String what, int wait) async {
      op = 'tap:$what';
      srv?.actor = op;
      final sched = t.binding.hasScheduledFrame;
      final r0 = obs.log.length;
      nTap++;
      budget();
      await t.tapAt(p);
      guard('tap:$what');
      await frames(wait, what);
      _out('D310-TAP ${jsonEncode({'phase': phase, 'scene': scene, 'what': what, 'point': [p.dx, p.dy],
        'scheduledBefore': sched, 'framesAfter': wait, 'routes': obs.log.sublist(r0)})}');
    }

    // 대상 가운데를 누르기 전 full·hit·유일을 두 phase 공통 전제로 본다(실제 사용자 도달).
    Future<void> tapReceiver(Element target, Element receiver, String what, int wait, Rect screen) async {
      final r = rectOf(target);
      final c = clipOf(target, screen);
      final hit = hitAt(r.center, receiver);
      _out('D310-PRETAP ${jsonEncode({'phase': phase, 'scene': scene, 'what': what, 'rect': rl(r), 'full': c.full,
        'failures': c.failures, 'hit': hit, 'top': hitTop(r.center)})}');
      need(c.full && hit, '$what tap 전 full/hit 아님 ${c.failures} hit=$hit');
      await tapAt(r.center, what, wait);
    }

    // 공개 UI 뒤로 — 시스템 뒤로 dispatch 1회(tap+dispatch 에 센다). 직접 Navigator.pop 0.
    Future<void> backDispatch(String what) async {
      op = 'back:$what';
      srv?.actor = op;
      final pops0 = obs.pops;
      nTap++;
      budget();
      final handled = await t.binding.handlePopRoute();
      guard('back:$what');
      await frames(_kTapWait, 'back:$what');
      nRouteClose++;
      _out('D310-BACK ${jsonEncode({'phase': phase, 'scene': scene, 'what': what, 'handled': handled, 'pops': obs.pops - pops0,
        'sheets': find.byType(BottomSheet).evaluate().length})}');
      need(obs.pops - pops0 == 1 && find.byType(BottomSheet).evaluate().isEmpty, '$what 뒤로 1회로 닫히지 않음');
    }

    // 칩 띠 가로 도달 — 방향은 대상 위치로, 거리 = min(필요, 끝까지−2) + 손실(첫 값 kDragSlopDefault, 이후 실측), 최소 slop+2, 호출당 ≤_kHTry.
    Future<void> reachH(Element Function() target, String what, Rect screen) async {
      stage = 'reachH:$what';
      var loss = kDragSlopDefault;
      for (var i = 0;; i++) {
        final r = rectOf(target());
        final vp = stripVp(screen);
        if (r.left >= vp.left - 0.5 && r.right <= vp.right + 0.5) {
          _out('D310-REACH ${jsonEncode({'phase': phase, 'scene': scene, 'axis': 'h', 'what': what, 'tries': i, 'reached': true,
            'rect': rl(r), 'vp': rl(vp), 'offset': stripPos().pixels})}');
          return;
        }
        need(i < _kHTry, '$what 가로 도달 실패(상한 $_kHTry)');
        need(r.width <= vp.width - 2 * _kAlong, '$what 폭 ${r.width} > 띠 ${vp.width}');
        final pos = stripPos();
        final toLeft = r.right > vp.right; // 대상이 오른쪽 밖 → 내용을 왼쪽으로(손가락 왼쪽)
        final need0 = toLeft ? r.right - (vp.right - _kAlong) : (vp.left + _kAlong) - r.left;
        final room = toLeft ? pos.maxScrollExtent - pos.pixels - 2 : pos.pixels - pos.minScrollExtent - 2;
        final want = math.min(need0, room);
        need(want > 0, '$what 가로 여유 없음 need=$need0 room=$room');
        final travel = math.max(want + loss, kDragSlopDefault + 2);
        need(travel <= vp.width - 8, '$what drag 거리 $travel > 띠 폭');
        final y = vp.center.dy;
        final start = toLeft ? Offset(vp.right - 4, y) : Offset(vp.left + 4, y);
        final p0 = pos.pixels;
        op = 'drag:h#$i:$what';
        srv?.actor = op;
        nDrag++;
        budget();
        await t.dragFrom(start, Offset(toLeft ? -travel : travel, 0));
        guard('drag:$what');
        await frames(_kHWait, 'drag:$what');
        final moved = (pos.pixels - p0).abs();
        final l = travel - moved;
        if (moved > 0 && l >= 0 && l <= 2 * kDragSlopDefault) loss = l;
        _out('D310-REACH ${jsonEncode({'phase': phase, 'scene': scene, 'axis': 'h', 'what': what, 'try': i, 'dir': toLeft ? 'left' : 'right',
          'need': need0, 'room': room, 'want': want, 'travel': travel, 'before': p0, 'after': pos.pixels, 'moved': moved, 'loss': l})}');
      }
    }

    // 시트 안 세로 도달 — 대상의 세로 Scrollable 조상이 있을 때만 drag(≤_kSheetTry). 고정 영역(선택 완료·서울특별시 전체)은 drag 0, full 만 본다.
    Future<void> reachSheet(Element Function() target, String what, Rect screen) async {
      stage = 'reachSheet:$what';
      for (var i = 0;; i++) {
        final e = target();
        final r = rectOf(e);
        final se = nearest(e, (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
        final vp = se == null ? screen : rectOf(se).intersect(screen);
        final c = clipOf(e, screen);
        if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && c.full) {
          _out('D310-REACH ${jsonEncode({'phase': phase, 'scene': scene, 'axis': 'sheet', 'what': what, 'tries': i,
            'reached': true, 'rect': rl(r), 'scrollable': se != null})}');
          return;
        }
        need(se != null && i < _kSheetTry, '$what 시트 안 도달 실패(고정 영역이거나 상한 $_kSheetTry) ${c.failures}');
        final pos = ((se! as StatefulElement).state as ScrollableState).position;
        final down = r.bottom > vp.bottom; // 대상이 아래 → 내용을 위로
        final need0 = down ? r.bottom - (vp.bottom - _kAlong) : (vp.top + _kAlong) - r.top;
        final room = down ? pos.maxScrollExtent - pos.pixels - 2 : pos.pixels - pos.minScrollExtent - 2;
        final want = math.min(need0, room);
        need(want > 0, '$what 시트 여유 없음 need=$need0 room=$room');
        final travel = math.min(math.max(want + kDragSlopDefault, kDragSlopDefault + 2), vp.height - 16);
        final start = down ? Offset(vp.center.dx, vp.bottom - 8) : Offset(vp.center.dx, vp.top + 8);
        final p0 = pos.pixels;
        op = 'drag:s#$i:$what';
        srv?.actor = op;
        nDrag++;
        budget();
        await t.dragFrom(start, Offset(0, down ? -travel : travel));
        guard('drag:$what');
        await frames(_kSheetWait, 'drag:$what');
        _out('D310-REACH ${jsonEncode({'phase': phase, 'scene': scene, 'axis': 'sheet', 'what': what, 'try': i,
          'need': need0, 'room': room, 'travel': travel, 'before': p0, 'after': pos.pixels})}');
      }
    }

    // 목록 끝 `더 많은 공고 보기` 실제 drag 도달(위로만 — pull-to-refresh 0, 끝을 넘기지 않게 끝−2 까지). 장면 상한 v.vTry.
    Future<Element> reachMore(_V v, Rect screen) async {
      stage = 'reachMore';
      final lv = listScroll();
      final pos = ((lv as StatefulElement).state as ScrollableState).position;
      var loss = kDragSlopDefault;
      Element? btnOf() {
        final ts = richExact('더 많은 공고 보기', within: fe(lv)).evaluate().toList();
        need(ts.length <= 1, '더보기 수 ${ts.length}');
        return ts.isEmpty ? null : nearest(ts.single, (w) => w is OutlinedButton);
      }

      for (var i = 0;; i++) {
        final vp = rectOf(lv).intersect(screen);
        final b = btnOf();
        if (b != null) {
          final r = rectOf(b);
          if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5) {
            _out('D310-REACH ${jsonEncode({'phase': phase, 'scene': scene, 'axis': 'v', 'what': 'more', 'tries': i,
              'reached': true, 'rect': rl(r), 'vp': rl(vp), 'pixels': pos.pixels, 'max': pos.maxScrollExtent})}');
            return b;
          }
        }
        need(i < v.vTry, '더보기 세로 도달 실패(상한 ${v.vTry})');
        final remaining = pos.maxScrollExtent - pos.pixels;
        final need0 = b == null ? remaining : rectOf(b).bottom - (vp.bottom - _kAlong);
        final want = math.min(need0, remaining - 2);
        need(want > 0, '더보기 여유 없음 need=$need0 remaining=$remaining');
        final travel = math.min(math.max(want + loss, kDragSlopDefault + 2), vp.height - 36);
        final start = Offset(vp.center.dx, vp.bottom - 12);
        final p0 = pos.pixels;
        op = 'drag:v#$i';
        srv?.actor = op;
        nDrag++;
        budget();
        await t.dragFrom(start, Offset(0, -travel));
        guard('drag:v#$i');
        await frames(_kVWait, 'drag:v#$i');
        final moved = pos.pixels - p0;
        final l = travel - moved;
        if (moved > 0 && l >= 0 && l <= 2 * kDragSlopDefault) loss = l;
        _out('D310-REACH ${jsonEncode({'phase': phase, 'scene': scene, 'axis': 'v', 'what': 'more', 'try': i, 'need': need0,
          'remaining': remaining, 'want': want, 'travel': travel, 'before': p0, 'after': pos.pixels, 'moved': moved,
          'loss': l, 'max': pos.maxScrollExtent})}');
      }
    }

    void moreCheck(Element btn, Rect screen) {
      stage = 'more';
      final mats = find.descendant(of: fe(btn), matching: find.byType(Material)).evaluate().toList();
      need(mats.isNotEmpty, '더보기 Material 없음');
      final outer = rectOf(btn), visual = rectOf(mats.first);
      final vc = clipOf(btn, screen);
      final hit = hitAt(visual.center, btn);
      _out('D310-MORE ${jsonEncode({'phase': phase, 'scene': scene, 'outer': rl(outer), 'visual': rl(visual), 'full': vc.full,
        'failures': vc.failures, 'hit': hit})}');
      check(visual.height >= 48 - _kEps && outer.height >= 48 - _kEps, '더보기 높이 ≥48', [visual.height, outer.height]);
      check(vc.full && hit, '더보기 full·hit', vc.failures);
    }

    // ③ 날짜 두 칸(11/14·11/15)·선택 완료 — 현재 달 격자의 활성 칸만, 월 이동 0. 로컬 조건이라 조회 0(host:467–491).
    Future<void> pickRange(Rect screen, _Srv s) async {
      final push0 = obs.pushes;
      stage = 'dateOpen';
      await reachH(() => chipEls('날짜', activeFace: false).receiver!, 'date-open', screen);
      final c0 = chipEls('날짜', activeFace: false);
      await tapReceiver(c0.face, c0.receiver!, 'date-open', _kTapWait, screen);
      need(find.byType(DateRangePickerBottomSheet).evaluate().length == 1 && obs.pushes - push0 == 1,
          '날짜 시트 열림 아님 push+${obs.pushes - push0}');
      nRoute++;
      budget();
      need(find.byType(CarrotStyleCalendar).evaluate().length == 1, '달력 수');
      for (final d in const [16, 17]) { // [r1] _kFrom/_kTo 와 같이 +2일(16·17 도 2026-11 격자에 각 한 칸)
        stage = 'day$d';
        Element cell() {
          final all = find
              .descendant(of: find.byType(CarrotStyleCalendar), matching: find.text('$d'))
              .evaluate()
              .toList();
          // 2026-11 격자: 11/1 이 일요일이라 앞달 칸 0, 뒤달 12/1–12/12 — 14·15 는 각 한 칸(carrot_style_calendar.dart:451–476).
          need(all.length == 1, '달력 $d 칸 수 ${all.length}');
          return all.single;
        }

        final e0 = cell();
        final gd0 = nearest(e0, (w) => w is GestureDetector);
        final col0 = (e0.widget as Text).style?.color;
        need(gd0 != null && (gd0.widget as GestureDetector).onTap != null && col0 != AppColors.grey300,
            '$d 칸 비활성·다른 달(color=${hex(col0)})'); // :400–409·:420
        await reachSheet(cell, 'day$d', screen);
        final e = cell();
        await tapReceiver(e, nearest(e, (w) => w is GestureDetector)!, 'day$d', _kDayWait, screen);
      }
      stage = 'dateDone';
      final sheet = find.byType(DateRangePickerBottomSheet);
      need(find.descendant(of: sheet, matching: find.text('11월 16일')).evaluate().length == 1 &&
          find.descendant(of: sheet, matching: find.text('11월 17일')).evaluate().length == 1, '시작·종료 표시 11월 16일·17일 아님');
      Element done() {
        final l = richExact('선택 완료', within: find.byType(DateRangePickerBottomSheet)).evaluate().toList();
        need(l.length == 1, '선택 완료 수 ${l.length}');
        return l.single;
      }

      final db0 = nearest(done(), (w) => w is ElevatedButton);
      need(db0 != null && (db0.widget as ElevatedButton).onPressed != null, '선택 완료 비활성');
      await reachSheet(done, 'date-done', screen);
      final pop0 = obs.pops, b0 = s.byIds.length;
      final dt = done();
      await tapReceiver(dt, nearest(dt, (w) => w is ElevatedButton)!, 'date-done', _kTapWait, screen);
      need(find.byType(DateRangePickerBottomSheet).evaluate().isEmpty && obs.pops - pop0 == 1, '날짜 시트 닫힘 아님');
      nRouteClose++;
      need(s.byIds.length == b0 && s.paged.length == 1, '날짜 설정 조회 0 아님');
      need(richExact(_kRangeLabel, within: fe(strip())).evaluate().length == 1, '활성 날짜 칩 $_kRangeLabel 아님');
    }

    // ④ 지역 두 단계 — 서울특별시(구 있음) → 서울특별시 전체. city 변경이라 즐겨찾기 분기 재조회 +1(host:467–477, :206–213).
    Future<void> pickRegion(Rect screen, _Srv s) async {
      final push0 = obs.pushes;
      stage = 'regionOpen';
      await reachH(() => chipEls('지역', activeFace: false).receiver!, 'region-open', screen);
      final c0 = chipEls('지역', activeFace: false);
      await tapReceiver(c0.face, c0.receiver!, 'region-open', _kTapWait, screen);
      need(find.byType(RegionPickerSheet).evaluate().length == 1 && obs.pushes - push0 == 1, '지역 시트 열림 아님');
      nRoute++;
      budget();
      final sheet = find.byType(RegionPickerSheet);
      stage = 'regionCity';
      need(richExact('지역 선택', within: sheet).evaluate().length == 1, '지역 시트 1단계 제목 아님');
      Element city() {
        final l = richExact(_kSeoul, within: find.byType(RegionPickerSheet)).evaluate().toList();
        need(l.length == 1, '시 목록 $_kSeoul 수 ${l.length}');
        return l.single;
      }

      final ink0 = nearest(city(), (w) => w is InkWell);
      need(ink0 != null && find.descendant(of: fe(ink0), matching: find.byIcon(Icons.chevron_right)).evaluate().length == 1,
          '$_kSeoul 꺾쇠(구 있음) 아님'); // region_picker_sheet.dart:230–235
      await reachSheet(city, 'city', screen);
      final ce = city();
      await tapReceiver(ce, nearest(ce, (w) => w is InkWell)!, 'region-city', _kCityWait, screen);
      stage = 'regionDistrict';
      need(find.byType(RegionPickerSheet).evaluate().length == 1, '1단계 tap 뒤 시트가 닫혔다(구 없음 경로)'); // :80–84
      need(richExact('$_kSeoul — 동 선택', within: sheet).evaluate().length == 1 &&
          richExact('강남구', within: sheet).evaluate().length == 1 && richExact('마포구', within: sheet).evaluate().length == 1,
          '2단계(구 목록) 아님');
      Element all() {
        final l = richExact('$_kSeoul 전체', within: find.byType(RegionPickerSheet)).evaluate().toList();
        need(l.length == 1, '$_kSeoul 전체 수 ${l.length}');
        return l.single;
      }

      await reachSheet(all, 'city-all', screen);
      final ae = all();
      final ab = nearest(ae, (w) => w is OutlinedButton);
      need(ab != null, '$_kSeoul 전체 OutlinedButton 없음');
      final pop0 = obs.pops, b0 = s.byIds.length;
      await tapReceiver(ae, ab!, 'region-all', _kTapWait, screen);
      need(find.byType(RegionPickerSheet).evaluate().isEmpty && obs.pops - pop0 == 1, '지역 시트 닫힘 아님');
      nRouteClose++;
      need(s.byIds.length - b0 == 1 && s.paged.length == 1, 'city 변경 재조회 +1 아님 byIds+${s.byIds.length - b0}');
      need(richExact(_kSeoul, within: fe(strip())).evaluate().length == 1, '활성 지역 칩 아님');
    }

    // ⑥ 배지와 버튼이 겹친 **버튼 내부** 점 tap → 필터 시트 단 1회 → 시스템 뒤로 1회.
    Future<void> badgeTap(Rect screen, _Srv s) async {
      stage = 'badgeTap';
      final f = filterEls();
      need(f.badge != null, '배지 없음');
      final inkR = rectOf(f.ink), badgeR = rectOf(f.badge!);
      final ov = inkR.intersect(badgeR);
      need(ov.width > 1 && ov.height > 1, '배지∩버튼 겹침 없음 ${rl(ov)}');
      final p = ov.center;
      final hit = hitAt(p, f.ink);
      _out('D310-BADGE ${jsonEncode({'phase': phase, 'scene': scene, 'ink': rl(inkR), 'badge': rl(badgeR), 'overlap': rl(ov),
        'point': [p.dx, p.dy], 'hitInk': hit, 'top': hitTop(p)})}');
      check(hit, '배지 겹침 내부 점 → 필터 버튼 hit');
      final push0 = obs.pushes, b0 = s.byIds.length;
      await tapAt(p, 'badge-overlap', _kTapWait);
      final opened = find.byType(BottomSheet).evaluate().length;
      final pushed = obs.pushes - push0;
      _out('D310-BADGE-OPEN ${jsonEncode({'phase': phase, 'scene': scene, 'sheets': opened, 'pushed': pushed})}');
      check(opened == 1 && pushed == 1, '겹침 내부 tap → 필터 시트 단 1회', [opened, pushed]);
      need(opened <= 1 && pushed <= 1, '시트 중복 열림 $opened/$pushed');
      if (opened == 1) {
        nRoute++;
        budget();
        need(richExact('필터', within: find.byType(BottomSheet)).evaluate().length == 1, '필터 시트 아님');
        await backDispatch('filter-sheet');
      }
      need(s.byIds.length == b0 && s.paged.length == 1, '시트 열고 닫기 조회 0 아님');
      filterRec(4, screen);
    }

    // ⑦⑧ 활성 값 칩 전체 해제 — _clearPoint 규칙의 점을 누른다. before 에서 해제되지 않으면 X 정리(장면 ≤2·phase ≤4).
    Future<void> clearChip(String text, String what, String quick, Rect screen, _Srv s, {required int dById}) async {
      stage = 'clear:$what';
      await reachH(() => chipEls(text, activeFace: true).face, what, screen);
      final c = chipEls(text, activeFace: true);
      need(c.x != null, '$what X 아이콘 없음');
      final face = rectOf(c.face), label = rectOf(c.label), x = rectOf(c.x!);
      final cp = _clearPoint(face, label);
      final rcvR = c.receiver == null ? null : rectOf(c.receiver!);
      final inR = rcvR != null && rcvR.contains(cp.p);
      final inFace = face.contains(cp.p);
      final inX = x.inflate(0.5).contains(cp.p);
      final hit = c.receiver != null && hitAt(cp.p, c.receiver!);
      final vc = clipOf(c.face, screen);
      _out('D310-CLEARPT ${jsonEncode({'phase': phase, 'scene': scene, 'what': what, 'face': rl(face), 'label': rl(label), 'x': rl(x),
        'receiver': rcvR == null ? null : rl(rcvR), 'nominal': rl(cp.n), 'kind': cp.kind, 'thick': cp.thick,
        'marginExists': cp.kind != 'label', 'point': [cp.p.dx, cp.p.dy], 'inReceiver': inR, 'inFace': inFace, 'inX': inX,
        'hit': hit, 'top': hitTop(cp.p), 'faceFull': vc.full})}');
      need(vc.full, '$what face 가 띠 안 full 아님 ${vc.failures}');
      need(cp.kind == 'label' ? (inFace && !inX) : !inFace, '$what 해제점 규칙(사전 고정) 위반');
      if (cp.kind == 'label') {
        // R∖F 가 공집합인 조건(face 가 양축 ≥48−2)의 정적 대체 위치 — 전체 칩이 receiver 인지는 label 점으로, ≥48 은 기하로 본다.
        check(rcvR != null && near(rcvR.width, face.width, 0.5) && near(rcvR.height, face.height, 0.5),
            '$what R∖F 공집합 ⇒ receiver ≈ face', rcvR == null ? null : rl(rcvR));
      }
      check(inR && hit && !inX, '$what 해제점이 receiver 안·X 밖·hit', cp.kind);
      final b0 = s.byIds.length;
      await tapAt(cp.p, 'clear:$what', _kTapWait);
      bool clearedNow() =>
          richExact(text, within: fe(strip())).evaluate().isEmpty &&
          richExact(quick, within: fe(strip())).evaluate().length == 1;
      var cleared = clearedNow();
      _out('D310-CLEAR ${jsonEncode({'phase': phase, 'scene': scene, 'what': what, 'kind': cp.kind, 'cleared': cleared,
        'byIds': s.byIds.length - b0, 'paged': s.paged.length})}');
      check(cleared, '$what 전체 칩(${cp.kind}) tap → 해제');
      if (!cleared) {
        // before 전용 X 정리 — after 는 위 check 에서 이미 멈췄다.
        nX++;
        sceneX++;
        need(sceneX <= 2 && nX <= 4, 'X 정리 한도(장면 ≤2·phase ≤4) 초과');
        final c2 = chipEls(text, activeFace: true);
        final xr = rectOf(c2.x!);
        final xg = nearestBelow(c2.x!, (w) => w is GestureDetector, c2.face);
        need(xg != null && hitAt(xr.center, xg), '$what X 정리 hit 아님');
        await tapAt(xr.center, 'X-cleanup:$what', _kTapWait);
        cleared = clearedNow();
        need(cleared, '$what X 정리 뒤에도 해제 안 됨');
      }
      need(s.byIds.length - b0 == dById && s.paged.length == 1, '$what 해제 조회 계보 byIds+${s.byIds.length - b0}');
    }

    final capKey = GlobalKey();

    Future<void> open(String id, _V v, _Srv s) async {
      scene = id;
      stage = 'mount';
      clockGuard('mount $id');
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = v.size;
      t.view.devicePixelRatio = 1.0;
      t.view.padding = FakeViewPadding.zero;
      t.view.viewPadding = FakeViewPadding.zero;
      t.platformDispatcher.textScaleFactorTestValue = v.scale;
      t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
      srv = s;
      obs = _Obs();
      scopeLog.clear();
      sceneX = 0;
      op = 'mount';
      s.actor = op;
      nMount++;
      budget();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: capKey,
          child: MaterialApp(
            key: ValueKey('D310-$phase-$id'),
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            navigatorObservers: [obs],
            home: UserTabScope(
              switchToTab: (i) => scopeLog.add('switchToTab:$i'),
              switchToTabWithDate: (i, d) => scopeLog.add('switchToTabWithDate:$i'),
              pendingJobDate: null,
              clearPendingJobDate: () {},
              pendingScheduleMonth: null,
              clearPendingScheduleMonth: () {},
              switchToScheduleNow: () => scopeLog.add('switchToScheduleNow'),
              child: UserJobTab(reads: s.reads()),
            ),
          ),
        ),
      ));
      live = true;
      guard('mount');
      await frames(_kLoad, 'load');
      stage = 'loaded';
      envOf(v);
      need(s.paged.length == 1 && s.paged.single['cursor'] == null && s.apps.length == 1 && s.byIds.isEmpty,
          '첫 로드 계보 paged=${s.paged.length} apps=${s.apps.length} byIds=${s.byIds.length}');
      need(obs.pushes == 1, '첫 route ${obs.log}');
      summaryIs('조건에 맞는 일자리 5개 이상'); // 5건 모두 표시(host:397–457)·hasMore → '이상'(host:709)
      need(stripPos().pixels.abs() <= _kEps, '칩 띠 원점 아님');
      _out('D310-OPEN ${jsonEncode({'phase': phase, 'scene': id, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}',
        'scale': v.scale, 'counts': counts()})}');
    }

    Future<void> teardown() async {
      stage = 'teardown';
      need(scopeLog.isEmpty, '탭 전환 호출 $scopeLog');
      nTearPw++; // 정상 빈 teardown — C 밖(T)
      tearBudget();
      await t.pumpWidget(const SizedBox.shrink());
      live = false;
      guard('teardown');
      nTearPump++;
      tearBudget();
      await t.pump(const Duration(milliseconds: 50));
      guard('teardown#1');
      t.view.resetPadding();
      t.view.resetViewPadding();
      visited.add(scene);
      srv = null;
    }

    // PNG — vqCapture 는 runAsync 안 toImage 라 pump 0. 직전 단계의 frames 가 마지막 프레임이다.
    Future<void> png(String step, _V v) async {
      nPng++;
      budget();
      final ls = find
          .descendant(
              of: find.byType(UserJobTab),
              matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
          .evaluate()
          .toList();
      final listOff = ls.length == 1 ? ((ls.single as StatefulElement).state as ScrollableState).position.pixels : null;
      await vqCapture(t, capKey, 'D310-$phase-$scene-$step', conditions: {
        'phase': phase, 'scene': scene, 'step': step, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}',
        'dpr': t.view.devicePixelRatio, 'textScaler': v.scale,
        'locale': Localizations.localeOf(t.element(find.byType(UserJobTab))).toLanguageTag(), 'stripOffset': stripPos().pixels,
        'listOffset': listOff, 'realNow': DateTime.now().toIso8601String(), 'pinDay': dayArg, 'test': _kTestName,
      });
    }

    // ═══ 기본 장면(S1 W · S2 B) — 첫 페이지 5건·hasMore=true, 칩 5 기본 의미/기하, 지역 칩 가로 도달, 목록 끝 더보기 실제 도달 ═══
    Future<void> basicScene(String id, _V v) async {
      final screen = Offset.zero & v.size;
      final s = _Srv(page1: _page1, byId: {for (final x in _page1) x.id: x}, hiddenCap: 2 * v.vTry + 2);
      await open(id, v, s);
      titleCheck(v);
      filterRec(null, screen);
      chipRec('fav', '즐겨찾기', 'fav-basic', activeFace: false, wantSelected: false, screen: screen);
      chipRec('flex', '단기', 'quick-basic', activeFace: false, wantSelected: false, screen: screen);
      chipRec('contract', '장기', 'quick-basic', activeFace: false, wantSelected: false, screen: screen);
      chipRec('date', '날짜', 'quick-basic', activeFace: false, wantSelected: false, screen: screen);
      chipRec('region', '지역', 'quick-basic', activeFace: false, wantSelected: false, screen: screen);
      await png('origin', v);
      await reachH(() => chipEls('지역', activeFace: false).receiver!, 'region-quick', screen);
      chipRec('region', '지역', 'quick-basic', activeFace: false, wantSelected: false, screen: screen, reached: true);
      final btn = await reachMore(v, screen);
      moreCheck(btn, screen);
      // 추가 조회 계보 — actor 로 귀속: drag 중(scroll listener, host:166–172) / drag 뒤 frames / 그 밖(자동 이어읽기 host:262–266·:336–340).
      final cur = s.paged.where((e) => e['cursor'] != null).toList();
      int nOf(String pfx) => cur.where((e) => (e['actor'] as String).startsWith(pfx)).length;
      final byDrag = nOf('drag:v'), postDrag = nOf('post:drag:v');
      final other = cur.length - byDrag - postDrag;
      _out('D310-LOADMORE ${jsonEncode({'phase': phase, 'scene': scene, 'cursorCalls': cur.length, 'scrollListenerDuringDrag': byDrag,
        'afterDragFrames': postDrag, 'autoOrOther': other, 'cursors': cur.map((e) => e['cursor']).toList()})}');
      need(other == 0, '자동 이어읽기·기타 추가조회 $other');
      need(s.byIds.isEmpty, '기본 장면 tosByIds ${s.byIds.length}');
      summaryIs('조건에 맞는 일자리 5개 이상'); // 숨김 페이지는 표시 0 — 목록·더보기 위치 불변
      await teardown();
    }

    // ═══ 활성 장면(S3 W · S4 B) — 즐겨찾기 → 단기 → 날짜 두 칸/완료 → 지역 두 단계 → 해제 전 기하/PNG → 배지 겹침 tap → 날짜 해제 → 지역 해제 ═══
    Future<void> activeScene(String id, _V v) async {
      final screen = Offset.zero & v.size;
      final s = _Srv(page1: _page1, byId: {for (final x in _page1) x.id: x}, hiddenCap: 0);
      for (final fid in const [_kFav1, _kFav2]) {
        final x = s.byId[fid];
        // 실제 getTOsByIds 가 거르는 조건(to_firestore.dart:324)을 fixture 가 만족하는지 — 대역은 거르지 않는다.
        need(x != null && x.isPublished && !x.isClosed && !x.isSoftDeleted, '즐겨찾기 fixture $fid');
      }
      await open(id, v, s);
      titleCheck(v);
      Future<void> quickTap(String text, String what, int dById) async {
        stage = 'tap:$what';
        await reachH(() => chipEls(text, activeFace: false).receiver!, what, screen);
        final c = chipEls(text, activeFace: false);
        final b0 = s.byIds.length;
        await tapReceiver(c.face, c.receiver!, what, _kTapWait, screen);
        need(s.byIds.length - b0 == dById && s.paged.length == 1, '$what 조회 계보 byIds+${s.byIds.length - b0} paged=${s.paged.length}');
      }

      // ① 즐겨찾기 → tosByIds(provider.favoriteToIds), cursor=null·hasMore=false(host:206–213)
      await quickTap('즐겨찾기', 'fav', 1);
      need(jsonEncode(s.byIds.last['ids']) == jsonEncode(const [_kFav1, _kFav2]), 'tosByIds 인자 ${s.byIds.last['ids']}');
      summaryIs('즐겨찾기 일자리 2개');
      filterRec(1, screen);
      // ② 단기 → type 변경 reload +1, 같은 즐겨찾기 분기(인자는 ID 뿐)
      await quickTap('단기', 'flex', 1);
      summaryIs('단기 · 즐겨찾기 일자리 2개');
      filterRec(2, screen);
      // ③ 날짜 → 로컬 조건, 조회 0
      await pickRange(screen, s);
      summaryIs('$_kRangeLabel · 단기 · 즐겨찾기 일자리 2개');
      filterRec(3, screen);
      // ④ 지역 두 단계 → reload +1
      await pickRegion(screen, s);
      summaryIs('$_kRangeLabel · $_kSeoul · 단기 · 즐겨찾기 일자리 2개');
      // ⑤ 해제 전 기하·의미·PNG — 배지 4 = favorite + type + dateRange + city(district null, sortBy createdAt; to_filter_state.dart:30–32)
      stage = 'activeMeasure';
      filterRec(4, screen);
      chipRec('fav', '즐겨찾기', 'fav-active', activeFace: false, wantSelected: true, screen: screen);
      chipRec('flex', '단기', 'quick-active', activeFace: false, wantSelected: true, screen: screen);
      chipRec('contract', '장기', 'quick-basic', activeFace: false, wantSelected: false, screen: screen);
      chipRec('date', _kRangeLabel, 'active', activeFace: true, wantSelected: true, screen: screen);
      chipRec('region', _kSeoul, 'active', activeFace: true, wantSelected: true, screen: screen);
      await png('active', v);
      // ⑥ 배지 겹침 내부 tap → 시트 단 1회 → 시스템 뒤로
      await badgeTap(screen, s);
      // ⑦ 날짜 해제(조회 0) → 배지 3
      await clearChip(_kRangeLabel, 'date', '날짜', screen, s, dById: 0);
      summaryIs('$_kSeoul · 단기 · 즐겨찾기 일자리 2개');
      filterRec(3, screen);
      // ⑧ 지역 해제(clearRegion → reload +1) → 배지 2
      await clearChip(_kSeoul, 'region', '지역', screen, s, dById: 1);
      summaryIs('단기 · 즐겨찾기 일자리 2개');
      filterRec(2, screen);
      need(s.paged.length == 1 && s.byIds.length == 4 && s.apps.length == 1,
          '활성 장면 조회 계보 paged=${s.paged.length} byIds=${s.byIds.length} apps=${s.apps.length}');
      await teardown();
    }

    final sw = Stopwatch()..start();
    try {
      clockGuard('start');
      need(vqEnabled, 'PNG 캡처 비활성(DU1_VQ_PHASE 없음)');
      need(_deriveC() == _kC, 'C 리터럴 ≠ helper 산식 ${_deriveC()}');
      _out('D310-ENV ${jsonEncode({'phase': phase, 'pinDay': dayArg, 'test': _kTestName, 'realNow': DateTime.now().toIso8601String(),
        'kst': kstNow().toIso8601String(), 'offsetMin': DateTime.now().timeZoneOffset.inMinutes, 'theme': 'RoleTheme.workerTheme',
        'C': '$_kC', 'T': '$_kT', 'F': '$_kF', 'range': '$_kFrom~$_kTo',
        'fonts': 'vqLoadFonts(NotoSansKR Regular+Bold·Roboto 별칭·MaterialIcons SDK) + FlutterTest=NotoSansKR Regular'})}');

      await basicScene('S1_W_basic', _w);
      await basicScene('S2_B_basic', _b);
      await activeScene('S3_W_active', _w);
      await activeScene('S4_B_active', _b);

      const want = 'S1_W_basic|S2_B_basic|S3_W_active|S4_B_active';
      need(visited.join('|') == want, '방문 $visited');
      need(nMount == 4 && nPng == 4 && nText == 0 && nTearPw == _kT.pumpWidget && nTearPump == _kT.pump, '실행량 ${counts()}');
      need(after ? nX == 0 : nX <= 4, 'X 정리 수 $nX');
      if (after) need(nRoute == 6 && nRouteClose == 6 && nTap == 26, 'after 행동 수 ${counts()}');
      clockGuard('end');
      need(net.created == 0 && biz.isEmpty && errors.isEmpty && !live,
          '최종 상태 http=${net.created} business=$biz pending=${errors.length} live=$live');
      _out('D310-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz,
        'elapsedMs': sw.elapsedMilliseconds})}');
      completed = true;
    } finally {
      // 실패 정리 F ≤ (pumpWidget 1, pump 2): 아직 mount 돼 있으면 빈 mount 1 + pump 2(원 실패를 덮지 않게 need/stop 을 부르지 않는다).
      var cleanup = 'not-needed';
      var cleanPw = 0, cleanPump = 0;
      final cleanErrors = <String>[for (final e in errors) 'pending-before-cleanup ${e.scene}/${e.stage}#${e.pump}: ${e.first}'];
      errors.clear();
      if (live) {
        try {
          cleanPw++;
          await t.pumpWidget(const SizedBox.shrink());
          live = false;
          for (var i = 0; i < _kF.pump; i++) {
            cleanPump++;
            await t.pump(const Duration(milliseconds: 50));
          }
          final ex = t.takeException();
          if (ex != null) cleanErrors.add('cleanup-exception $ex');
          cleanup = 'done';
        } catch (e) {
          cleanup = 'failed $e';
        }
        for (final e in errors) {
          cleanErrors.add('during-cleanup ${e.scene}/${e.stage}#${e.pump}: ${e.first}');
        }
      }
      _out('D310-FINAL ${jsonEncode({...counts(), 'outcome': completed ? 'completed' : 'failed', 'cleanup': cleanup,
        'cleanupPumpWidget': cleanPw, 'cleanupPump': cleanPump, 'stillMounted': live, 'visited': visited, 'http': net.created,
        'business': biz, 'cleanupErrors': cleanErrors, 'elapsedMs': sw.elapsedMilliseconds})}');
      for (final o in _fsOps) {
        m.setMockMessageHandler('$_fsBase.$o', null);
      }
      for (final o in _fnOps) {
        m.setMockMessageHandler('$_fnBase.$o', null);
      }
      m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), null);
      FlutterError.onError = prevOnError;
      HttpOverrides.global = prevHttp;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
      sem.dispose();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
