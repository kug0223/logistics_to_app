// ignore_for_file: depend_on_referenced_packages
// [DU509 · NDB-1 · DU-O001 디자인·브랜드 판정(11-18) · 표시만 · r3] 근태 현황 → 일괄 '시간 조정' 창을 공용 StyledDialog 셸 + 중립 출퇴근 입력 + W/B 배치로.
//   before = 현재 A(attendance_status_dialog 88daa1a2 · 직접 Dialog) / strict = 후보(67725bff · StyledDialog · 중립 행 · 조작 줄 분리).
//   harness 는 DU505 시험과 같은 읽기 경계(AttendanceReads) — 출근 처리된 2명 → 정상 탭 → '전체' → '시간 조정'.
//   [r3 · 후속118 §2 · 후속119b §3] r2(8571ed26) 위에 더한 것:
//     ① 무실서비스 경계 — Functions 의 실제 Pigeon 채널(dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call)을
//        StandardMessageCodec 으로 대역한다(요청 [인자 Map] · 성공 [결과] · 그 밖 함수 이름은 Pigeon 오류 응답으로 차단). 호출은 전부 기록한다.
//        allMessagesHandler 로 'flutter/' 밖 채널은 전부 기록 + 차단(응답 없음)하고 끝에 0 을 단언한다. 'flutter/' 는 원래 경로 그대로 넘긴다.
//     ② 실제 탭 · 반환 — NavigatorObserver 로 일괄 창 route 를 잡고 route.popped 를 탭 · 닫힘과 따로 본다.
//        '취소' → false · Functions 0 / 다시 열어 퇴근만 '직접' 18:00 → 활성 '조정하기' → true → '근태 수정 사유' 실제 입력 · 그 창의 '확인' →
//        callableBatchAdjustAttendanceTime 정확 1회(사업장 · 정확 2대상 · 퇴근 epoch · 출근 필드 없음 · 사유) · callableReportLate 0 ·
//        성공 뒤 근태 다시 읽기 = 가짜 reader 정확 1회(제품이 삼킨 예외면 0 이다).
//        퇴근을 예정(23:59)이 아니라 18:00 으로 두는 이유: 06:00 출근 → 23:59 = 17h59m > isValidWorkPeriod 16h → entries 0 →
//        사유 창 · 호출 없이 경고만 내고 끝난다(_processBatchAdjustTime). 출근은 비워 두어 lateChanges 0 → 지각 호출 없음.
//     ③ 직접 시각 — 시트 빠른 선택 09:00 → 실제 '선택 완료' → 출근 09:00 / 다시 '직접' → 14:00 으로 바꾼 뒤 시트 '취소' → 09:00 그대로.
//     ④ 셸 면 · 창 안 finder 를 일괄 창 Dialog 로 좁혔다 — r2 는 find.byType(Dialog) 첫 Material(= 뒤 근태 현황 AppModalShell 흰 면)을 읽었다.
//   상태: ADJ = 열림 → 예정 출근 · 퇴근(둘 다) → 출근 지우기 → 직접 선택 완료/취소 → 다시 지우기(퇴근만) → 도달 → 끝 → 취소(false) →
//         다시 열기 → 퇴근 직접 18:00 → 조정하기(true) → 사유 입력 · 확인 → 호출 1 · 다시 읽기 1.
//         RULE(사업장 기준 + 한 명 다른 약속 기준) = 혼합 안내 · 토글 켜기 · 미리보기(조정하기를 누르지 않는다 · Functions 0).
//   before 는 관측 기록 + 코드 확정 음성만 단언(셸 면 ≠ 흰색 · 값 든 행 면/선 ≠ 중립 · B 넘침 > 0 · 토글 트랙 ≠ brand)
//     + 두 모드 공통 무실서비스(예상 밖 채널 0 · 예상 밖 Functions 0 · 지각 호출 0). 닿지 않는 조작은 hit=false 로 남기고 건너뛴다.
//   기본 skip — TB before/du509-tb/DU_BEFORE_OBSERVE=509 · TA after/du509-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/common/app_tab_label.dart';
import 'package:ALfit/widgets/pickers/time_picker_bottom_sheet.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';

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

/// [r3] 일괄 창 · 시간 시트 · 사유 창 route 를 push 순서대로 모은다(반환값은 route.popped 로 따로 본다).
class _RouteLog extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

const _biz = 'biz509';

// [r3] cloud_functions_platform_interface 5.8.2 · messages.pigeon.dart — CloudFunctionsHostApi.call(접미사 없음).
//   _PigeonCodec 은 StandardMessageCodec 에 int → int64 쓰기만 더하고 읽기 사용자 형식은 없다 → StandardMessageCodec 으로 그대로 읽고 쓴다.
const _fnChanName = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fnChannel = BasicMessageChannel<Object?>(_fnChanName, StandardMessageCodec());
const _batchFn = 'callableBatchAdjustAttendanceTime';
const _lateFn = 'callableReportLate';
const _reason = 'DU509 시험 사유 · 실제 퇴근 시각 확인';

String _f1(double v) => v.toStringAsFixed(1);
String _f2(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'brand': AppColors.brand, 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary,
  'grey100': AppColors.grey100, 'grey200': AppColors.grey200, 'grey300': AppColors.grey300, 'grey400': AppColors.grey400,
  'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'grey700': AppColors.grey700, 'warningDark': AppColors.warningDark,
  'success': AppColors.success, 'successBg': AppColors.successBg, 'purple': AppColors.purple, 'purpleBg': AppColors.purpleBg,
  'info': AppColors.info, 'infoBg': AppColors.infoBg, 'infoDark': AppColors.infoDark,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '509';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du509-tb' && _env['DU_BEFORE_OBSERVE'] == '509') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du509-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _infoText = '입력한 시간으로만 조정됩니다.\n비워두면 해당 시간은 변경되지 않습니다.';
const _mixedText = '대상자마다 적용되는 근태 기준이 다릅니다.\n각 근무에 약속된 기준으로 처리됩니다.';

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const fixtures = ['ADJ', 'RULE'];
  for (final fx in fixtures) {
    for (final v in views) {
      testWidgets('S901BS-${v.id}-$fx 일괄 시간 조정 창 — 공용 셸 · 중립 입력 · 실제 탭·반환 · 무실서비스 경계', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S901BS-${v.id}-$fx';
          final mode = _before ? 'before' : 'strict';
          _out('D509 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              overflows.add(m.split('\n').first);
            } else {
              fwErrors.add(m.split('\n').first);
              prev?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = prev);
          t.view.physicalSize = Size(v.w, v.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          // 단언은 모아 두었다가 넘침 수집기를 되돌린 뒤 한꺼번에 던진다(DU475 진단 — 바꾼 채 실패하면 tearDownAll 이 멈춘다).
          final checks = <(String, bool, String)>[];
          void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
          void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
          Future<void> frames(int n) async {
            for (var i = 0; i < n; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          // ── [r3] 무실서비스 경계 — 실제 Pigeon 채널 대역 + 그 밖 채널 전부 기록 · 차단 ──
          //   요청 = [인자 Map{appName, functionName, functionUri, origin, region, timeout, parameters, limitedUseAppCheckToken}].
          //   성공 응답 = [결과] · 차단 응답 = [code, message, details](Pigeon 오류 → 제품에는 FirebaseFunctionsException).
          final msgr = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final fnCalls = <Map<String, Object?>>[];
          final blocked = <String>[];
          final fwCh = <String>{};
          msgr.setMockDecodedMessageHandler<Object?>(_fnChannel, (req) async {
            final arg = req is List && req.length == 1 && req.first is Map
                ? Map<String, Object?>.from(req.first as Map)
                : <String, Object?>{'functionName': '(요청 형식 다름)'};
            fnCalls.add(arg);
            if (arg['functionName'] == _batchFn) {
              return <Object?>[
                <String, Object?>{'processed': 2, 'skipped': <Object?>[]},
              ];
            }
            return <Object?>['du509-blocked', '예상 밖 Functions 호출 차단', null];
          });
          msgr.allMessagesHandler = (channel, handler, message) {
            if (channel == _fnChanName && handler != null) return handler(message);
            if (channel.startsWith('flutter/')) {
              // 프레임워크 채널(문자 입력 · 시스템 소리 · 커서 등)은 경계 설치 전과 같은 경로 — 이름만 남긴다.
              fwCh.add(channel);
              return handler != null ? handler(message) : msgr.delegate.send(channel, message);
            }
            blocked.add(channel);
            return null;
          };
          addTearDown(() {
            msgr.allMessagesHandler = null;
            msgr.setMockDecodedMessageHandler<Object?>(_fnChannel, null);
          });

          // ── fixture: 오늘 · 출근 처리된 2명(06:00 출근 · 23:59 퇴근 예정) ──
          //   RULE: 사업장 근태 기준 = 기본값 · 박피킹 지원서만 지각 유예 15분 약속 → 대상자 기준 혼합.
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day);
          final dayKey = FormatHelper.kstDayKeyOfCivil(day);
          UserModel user(String uid, String name, UserRole role) =>
              UserModel(uid: uid, username: name, name: name, email: '$uid@example.invalid', role: role, createdAt: DateTime(2026, 1, 1));
          Map<String, dynamic> appMap(String id, String uid, {Map<String, dynamic>? snap}) => {
                'id': id, 'uid': uid, 'toId': 'to509', 'slotId': 'slot509', 'businessId': _biz, 'wdId': 'wd-pick', 'workDetailId': 'wd-pick',
                'status': 'CONFIRMED', 'type': 'short_term', 'selectedWorkType': '피킹', 'startTime': '06:00', 'endTime': '23:59',
                'workDate': _ts(dayKey), 'createdAt': _ts(dayKey), 'appliedAt': _ts(dayKey),
                if (snap != null) 'attendancePolicySnapshot': snap,
              };
          Map<String, dynamic> attMap(String id, String appId, String uid) => {
                'id': id, 'applicationId': appId, 'uid': uid, 'businessId': _biz, 'status': 'present', 'checkIn': '06:00',
                'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
              };
          final rule = fx == 'RULE';
          final apps = [
            appMap('bs-a', 'u-bs-a'),
            appMap('bs-b', 'u-bs-b', snap: rule ? {...const AttendanceRules().toMap(), 'lateGrace': 15} : null),
          ];
          final atts = [attMap('att-bs-a', 'bs-a', 'u-bs-a'), attMap('att-bs-b', 'bs-b', 'u-bs-b')];
          final names = {'u-bs-a': '김피킹', 'u-bs-b': '박피킹'};
          final business = BusinessModel(
            id: _biz, name: 'DU509 물류센터', businessNumber: '000-00-00000', category: '물류', subCategory: '포장',
            address: '경기도 평택시 서정동 1', ownerId: 'owner509', createdAt: DateTime(2026, 1, 1),
            attendanceRules: rule ? AttendanceRules.defaults() : null,
          );
          // [r3] 근태 읽기 횟수 — 성공 뒤 _refreshAttendanceOnly 가 이 가짜 reader 를 정확 1회 더 부르는지 본다.
          var attReads = 0;
          final reads = AttendanceReads(
            applicationsPaged: (payload) async {
              if (payload['type'] != null) return const [];
              return [for (final a in apps) Map<String, dynamic>.of(a)];
            },
            workTypeDocs: (id) async => const {},
            adminAttendances: ({required businessId, required startMs, required endMs}) async {
              attReads++;
              return [for (final a in atts) Map<String, dynamic>.of(a)];
            },
            workDetailTimes: (workers) async => const {},
            usersBatch: ({required uids, required businessId}) async => {for (final u in uids) u: user(u, names[u] ?? u, UserRole.USER)},
            contractStatus: ({required appIds, required businessId}) async => ContractStatusBatch(statuses: {for (final id in appIds) id: 'signed'}),
            dayStaffing: ({required businessId, required dayStartMs}) async => const <DayStaffingRow>[],
            businessById: (id) async => business,
            businessNames: (ids) async => {for (final i in ids) i: business.name},
          );
          final up = UserProvider()..debugSetCurrentUser(user('owner509', 'DU509 사장', UserRole.BUSINESS_ADMIN));
          final routes = _RouteLog();

          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<UserProvider>.value(
              value: up,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                navigatorObservers: [routes],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR')],
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(body: AttendanceStatusDialog(date: day, businessIds: const [_biz], initialBusinessId: _biz, reads: reads)),
              ),
            ),
          ));
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)));
          Element? nearest(Element e, bool Function(Widget w) test) {
            Element? hit;
            e.visitAncestorElements((a) {
              if (test(a.widget)) {
                hit = a;
                return false;
              }
              return true;
            });
            return hit;
          }

          Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e));
          Element? recvOf(Element e) => nearest(e, (w) => w is InkWell || w is GestureDetector);
          bool enabledOf(Element? r) {
            final w = r?.widget;
            if (w is InkWell) return w.onTap != null;
            if (w is GestureDetector) return w.onTap != null;
            return false;
          }

          double minSide(Element? r) {
            final ro = r?.renderObject;
            if (ro is! RenderBox || !ro.hasSize) return 0;
            return math.min(ro.size.width, ro.size.height);
          }

          // 중심이 화면 안이고 그 receiver 에 닿는가(누르지 않는다). 스크롤 가능한 곳이면 먼저 보이게 굴린다.
          Future<bool> reachOf(Element? Function() get) async {
            final e0 = get();
            if (e0 == null) return false;
            try {
              await t.ensureVisible(fe(e0));
            } catch (_) {}
            await frames(4);
            final e = get();
            final ro = e?.renderObject;
            if (ro is! RenderBox || !ro.hasSize || !ro.attached) return false;
            final c = ro.localToGlobal(ro.size.center(Offset.zero));
            if (!(Offset.zero & Size(v.w, v.h)).contains(c)) return false;
            return t.hitTestOnBinding(c).path.any((h) => identical(h.target, ro));
          }

          Future<bool> tapRecv(Element? Function() get) async {
            final ok = await reachOf(get);
            if (!ok) return false;
            final ro = get()!.renderObject! as RenderBox;
            await t.tapAt(ro.localToGlobal(ro.size.center(Offset.zero)));
            await frames(8);
            return true;
          }

          // 로드 대기 → 정상 탭 → 전체 → '시간 조정'(DU505 와 같은 경로)
          Finder? findAllBox() {
            final els = rt((p) => p == '전체').evaluate().where((e) {
              final g = nearest(e, (w) => w is GestureDetector);
              return g != null && find.descendant(of: fe(g), matching: find.byType(AppCheckbox)).evaluate().length == 1;
            }).toList();
            return els.length == 1 ? fe(nearest(els.first, (w) => w is GestureDetector)!) : null;
          }

          Finder? allBox;
          for (var i = 0; i < 40 && allBox == null; i++) {
            await t.pump(const Duration(milliseconds: 50));
            allBox = findAllBox();
          }
          must('전체 선택 칸 1', allBox != null, '로드 뒤 전체 칸 없음');
          final normalTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '정상');
          must('정상 탭 1', normalTab.evaluate().length == 1, '개수 ${normalTab.evaluate().length}');
          await t.tap(normalTab);
          await frames(12);
          final box = findAllBox();
          must('정상 탭 전체 선택 칸 1', box != null, '탭 전환 뒤 전체 칸 없음');
          if (box == null) return;
          await t.tap(box);
          await frames(6);
          List<Element> adjButtons() => find.byType(InkWell).evaluate().where((e) =>
              find.descendant(of: fe(e), matching: find.byIcon(Icons.tune)).evaluate().length == 1 &&
              find.descendant(of: fe(e), matching: rt((p) => p == '시간 조정')).evaluate().length == 1).toList();
          must('시간 조정 버튼 1', adjButtons().length == 1, '개수 ${adjButtons().length}');
          final n0 = routes.pushed.length;
          final opened = await tapRecv(() => adjButtons().length == 1 ? adjButtons().first : null);
          await frames(6);
          must('시간 조정 입구 hit · 창 열림', opened && rt((p) => p == '일괄 시간 조정').evaluate().length == 1,
              'hit $opened 제목 ${rt((p) => p == '일괄 시간 조정').evaluate().length}');

          // ── 창 안 측정 도구 — [r3] 일괄 창 Dialog 로 좁힌다(뒤의 근태 현황도 AppModalShell = Dialog 다) ──
          Finder batchDlg() => find.ancestor(of: rt((p) => p == '일괄 시간 조정'), matching: find.byType(Dialog));
          Finder inDlg(Finder f) => find.descendant(of: batchDlg(), matching: f);
          Element? one(Finder f) {
            final l = f.evaluate().toList();
            return l.length == 1 ? l.first : null;
          }

          Element? rowOf(String label) {
            final e = one(inDlg(rt((p) => p == label)));
            if (e == null) return null;
            return nearest(e, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null);
          }

          final valRe = RegExp(r'^\d\d:\d\d$');
          Element? valueOf(String label) {
            final r = rowOf(label);
            if (r == null) return null;
            final l = find.descendant(of: fe(r), matching: rt((p) => p == '미설정' || valRe.hasMatch(p))).evaluate().toList();
            return l.isEmpty ? null : l.first;
          }

          String valText(String label) {
            final e = valueOf(label);
            return e == null ? '-' : _plainOf(e.widget);
          }

          Element? textIn(String label, String text) {
            final r = rowOf(label);
            if (r == null) return null;
            return one(find.descendant(of: fe(r), matching: rt((p) => p == text)));
          }

          Element? clearIn(String label) {
            final r = rowOf(label);
            if (r == null) return null;
            final ic = one(find.descendant(of: fe(r), matching: find.byIcon(Icons.close)));
            return ic == null ? null : nearest(ic, (w) => w is GestureDetector);
          }

          Element? btnText(String s) => one(inDlg(rt((p) => p == s)));
          Color? fillOf(Element? textEl) {
            if (textEl == null) return null;
            final eb = nearest(textEl, (w) => w is ElevatedButton);
            if (eb != null) {
              final b = eb.widget as ElevatedButton;
              final st = b.onPressed == null ? <WidgetState>{WidgetState.disabled} : <WidgetState>{};
              return b.style?.backgroundColor?.resolve(st);
            }
            final db = nearest(textEl, (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null);
            return db == null ? null : ((db.widget as DecoratedBox).decoration as BoxDecoration).color;
          }

          Color? inkOf(Element? textEl) => textEl == null ? null : (textEl.widget as RichText).text.style?.color;
          int breaksOf(Element? textEl) {
            final ro = textEl?.renderObject;
            return ro is RenderParagraph ? wordBreaks(ro).length : -1;
          }

          ({String bg, String line, String lw}) decoOf(Element? r) {
            final d = (r?.widget as Container?)?.decoration as BoxDecoration?;
            final b = d?.border as Border?;
            return (bg: _tok(d?.color), line: _tok(b?.top.color), lw: b == null ? '0.0' : _f1(b.top.width));
          }

          double rowLine(String sub, String label, String quick, IconData ic, bool hit) {
            final r = rowOf(label);
            final dc = decoOf(r);
            final icon = r == null ? null : one(find.descendant(of: fe(r), matching: find.byIcon(ic)));
            final chipT = textIn(label, quick);
            final direct = textIn(label, '직접');
            final rx = [minSide(recvOf(chipT ?? r!)), minSide(recvOf(direct ?? r!)), if (clearIn(label) != null) minSide(clearIn(label))].reduce(math.min);
            final lab = breaksOf(one(inDlg(rt((p) => p == label))));
            final vt = valText(label), ik = _tok(inkOf(valueOf(label))), icn = _tok((icon?.widget as Icon?)?.color);
            final ch = _tok(fillOf(chipT)), chi = _tok(inkOf(chipT)), rxs = _f1(rx);
            if (sub == 'rowin') {
              _out('D509 $tok att rowin hit=$hit val=$vt bg=${dc.bg} line=${dc.line} lw=${dc.lw} ink=$ik icon=$icn chip=$ch chipInk=$chi rx=$rxs lab=$lab');
            } else {
              _out('D509 $tok att rowout hit=$hit val=$vt bg=${dc.bg} line=${dc.line} lw=${dc.lw} ink=$ik icon=$icn chip=$ch chipInk=$chi rx=$rxs lab=$lab');
            }
            return rx;
          }

          // ── [r3] 일괄 창 route 식별 — 이 탭으로 push 된 route 1개 · DialogRoute · 제목이 그 route 소속 ──
          final newRoutes = routes.pushed.sublist(n0);
          final route1 = newRoutes.length == 1 ? newRoutes.first : null;
          final title1 = one(rt((p) => p == '일괄 시간 조정'));
          final route1Ok = route1 is DialogRoute && title1 != null && identical(ModalRoute.of(title1), route1);
          var popped1 = 'pending';
          route1?.popped.then((r) {
            popped1 = r.toString();
          });
          _out('D509 $tok att route pushed=${newRoutes.length} dialog=${route1 is DialogRoute} scope=$route1Ok');

          if (fx == 'ADJ') {
            // ① 열림(값 없음) — [r3] 셸 면은 일괄 창 Dialog 의 Material(r2 는 뒤 근태 현황 Dialog 를 읽었다)
            final shellBg = t.widget<Material>(find.descendant(of: batchDlg(), matching: find.byType(Material)).first).color;
            _out('D509 $tok att shell bg=${_tok(shellBg)}');
            final okT0 = btnText('조정하기');
            final idleEnabled = enabledOf(okT0 == null ? null : recvOf(okT0));
            _out('D509 $tok att idle in=${valText('출근 시간')} out=${valText('퇴근 시간')} enabled=$idleEnabled fill=${_tok(fillOf(okT0))} ink=${_tok(inkOf(okT0))}');
            _out('D509 $tok shot 1open ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1open', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADJ',
              'state': 'open-empty',
            });
            // ② 예정 출근 · 예정 퇴근(둘 다)
            final hitIn = await tapRecv(() {
              final e = textIn('출근 시간', '예정(06:00)');
              return e == null ? null : recvOf(e);
            });
            final rxIn = rowLine('rowin', '출근 시간', '예정(06:00)', Icons.login, hitIn);
            // [r2 · DU509 진단 STOP] 단언 재료는 측정 시점에 잡는다(창을 닫은 뒤 다시 읽지 않는다).
            final dcIn = decoOf(rowOf('출근 시간'));
            final hitOut = await tapRecv(() {
              final e = textIn('퇴근 시간', '예정(23:59)');
              return e == null ? null : recvOf(e);
            });
            final rxOut = rowLine('rowout', '퇴근 시간', '예정(23:59)', Icons.logout, hitOut);
            final okT = btnText('조정하기');
            final fill = fillOf(okT), ink = inkOf(okT);
            final adjEnabled = enabledOf(okT == null ? null : recvOf(okT));
            _out('D509 $tok att adjust enabled=$adjEnabled fill=${_tok(fill)} ink=${_tok(ink)} cr=${_f2(_cr(fill, ink))}');
            _out('D509 $tok shot 2both ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_2both', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADJ',
              'state': 'both-set',
            });
            // ③ 출근 지우기 → 퇴근만
            final hitClear = await tapRecv(() => clearIn('출근 시간'));
            final okT2 = btnText('조정하기');
            _out('D509 $tok att clear hit=$hitClear in=${valText('출근 시간')} enabled=${enabledOf(okT2 == null ? null : recvOf(okT2))}');

            // ── [r3] 시간 선택 시트 도구 — 시트 안 글만 찾는다(일괄 창 · 사유 창의 '취소' · '확인'과 섞이지 않게) ──
            Element? sheetRecv(String s) {
              final e = one(find.descendant(of: find.byType(TimePickerBottomSheet), matching: rt((p) => p == s)));
              return e == null ? null : recvOf(e);
            }

            // 같은 시각 글 개수 — 빠른 선택 칩 1 + 선택 표시 1 = 2 이면 시트 선택값이 그 시각이다(휠은 '09' · '00' 따로).
            int sheetCount(String s) => find.descendant(of: find.byType(TimePickerBottomSheet), matching: rt((p) => p == s)).evaluate().length;
            // 시트 버튼으로 닫는다. 닿지 않으면 바깥 막(8,8)으로 닫고(반환 null) 'barrier' 로 남긴다.
            Future<String> closeSheet(String btn, String tag) async {
              final ok = await tapRecv(() => sheetRecv(btn));
              if (!ok) await t.tapAt(const Offset(8, 8));
              await frames(16);
              return ok ? tag : 'barrier';
            }

            // ④ [r3] 출근 '직접' → 시트(초기 06:00) → 빠른 선택 09:00 → 실제 '선택 완료' → 출근 09:00(시트 반환값이 행에 들어간다)
            final hitPick = await tapRecv(() {
              final e = textIn('출근 시간', '직접');
              return e == null ? null : recvOf(e);
            });
            await frames(12);
            final pickOpen = find.byType(TimePickerBottomSheet).evaluate().length == 1;
            var chipP = false;
            var selP = false;
            var viaP = 'none';
            if (pickOpen) {
              chipP = await tapRecv(() => sheetRecv('09:00'));
              selP = sheetCount('09:00') == 2;
              viaP = await closeSheet('선택 완료', 'done');
            }
            final pickClosed = find.byType(TimePickerBottomSheet).evaluate().isEmpty;
            final inAfterPick = valText('출근 시간');
            _out('D509 $tok att pick hit=$hitPick opened=$pickOpen chip=$chipP sel=$selP closed=$pickClosed via=$viaP in=$inAfterPick');
            // ⑤ 출근 '직접' 다시 → 시트(초기 09:00) → 14:00 으로 바꾼 뒤 시트 '취소' → 출근 09:00 그대로(반환 null)
            final hitDirect = await tapRecv(() {
              final e = textIn('출근 시간', '직접');
              return e == null ? null : recvOf(e);
            });
            await frames(12);
            final sheetOpen = find.byType(TimePickerBottomSheet).evaluate().length == 1;
            var chipC = false;
            var selC = false;
            var via = 'none';
            if (sheetOpen) {
              chipC = await tapRecv(() => sheetRecv('14:00'));
              selC = sheetCount('14:00') == 2;
              via = await closeSheet('취소', 'cancel');
            }
            final sheetClosed = find.byType(TimePickerBottomSheet).evaluate().isEmpty;
            final inAfterDirect = valText('출근 시간');
            _out('D509 $tok att direct hit=$hitDirect opened=$sheetOpen chip=$chipC sel=$selC closed=$sheetClosed via=$via in=$inAfterDirect');
            // ⑥ [r3] 출근 다시 지우기 → 퇴근만(r2 의 끝 상태와 같다)
            final hitReclear = await tapRecv(() => clearIn('출근 시간'));
            final inAfterReclear = valText('출근 시간');
            final okT3 = btnText('조정하기');
            final enReclear = enabledOf(okT3 == null ? null : recvOf(okT3));
            _out('D509 $tok att reclear hit=$hitReclear in=$inAfterReclear enabled=$enReclear');
            // ⑦ 도달(누르지 않는다) — 취소 · 조정하기 · 칩 · 직접 · 지우기
            Element? recvText(String s) {
              final e = btnText(s);
              return e == null ? null : recvOf(e);
            }

            final rCancel = await reachOf(() => recvText('취소'));
            final rAdjust = await reachOf(() => recvText('조정하기'));
            final rChipIn = await reachOf(() {
              final e = textIn('출근 시간', '예정(06:00)');
              return e == null ? null : recvOf(e);
            });
            final rChipOut = await reachOf(() {
              final e = textIn('퇴근 시간', '예정(23:59)');
              return e == null ? null : recvOf(e);
            });
            final rDirectIn = await reachOf(() {
              final e = textIn('출근 시간', '직접');
              return e == null ? null : recvOf(e);
            });
            final rClearOut = await reachOf(() => clearIn('퇴근 시간'));
            _out('D509 $tok att reach cancel=$rCancel adjust=$rAdjust chipIn=$rChipIn chipOut=$rChipOut directIn=$rDirectIn clearOut=$rClearOut');
            // ⑧ 낱말 조판(맨 위로 굴린 뒤 · RenderParagraph 전문)
            try {
              await t.ensureVisible(inDlg(rt((p) => p == '일괄 시간 조정')));
            } catch (_) {}
            await frames(4);
            final wTitle = breaksOf(btnText('일괄 시간 조정'));
            final wSub = breaksOf(btnText('2명 대상'));
            final wInfo = breaksOf(btnText(_infoText));
            final wIn = breaksOf(btnText('출근 시간'));
            final wOut = breaksOf(btnText('퇴근 시간'));
            _out('D509 $tok att words title=$wTitle sub=$wSub info=$wInfo labIn=$wIn labOut=$wOut');
            // ⑨ 끝까지(주행동이 보이게)
            final okEnd = recvText('조정하기');
            if (okEnd != null) {
              try {
                await t.ensureVisible(fe(okEnd));
              } catch (_) {}
            }
            await frames(4);
            _out('D509 $tok shot 3end ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_3end', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADJ',
              'state': 'out-only-end',
            });
            // ⑩ '취소' 실제 탭 → 닫힘 · [r3] route.popped = false(탭 · 닫힘과 따로) · Functions 0
            final hitClose = await tapRecv(() => recvText('취소'));
            await frames(12);
            final closed = rt((p) => p == '일괄 시간 조정').evaluate().isEmpty;
            final callsAtClose = fnCalls.length;
            _out('D509 $tok att close hit=$hitClose closed=$closed popped=$popped1 calls=$callsAtClose');

            // ⑪ [r3] 다시 열기 → 퇴근만 '직접' → 빠른 선택 18:00 → '선택 완료'(06:00 출근 기준 12시간 · 출근 비움 = lateChanges 0)
            //   예정(23:59)은 06:00 → 23:59 = 17h59m > isValidWorkPeriod 16h 라 entries 0 → 사유 창 · 호출 없이 경고만 내고 끝난다.
            final n1 = routes.pushed.length;
            final reopened = closed && await tapRecv(() => adjButtons().length == 1 ? adjButtons().first : null);
            await frames(6);
            final route2 = routes.pushed.length == n1 + 1 ? routes.pushed.last : null;
            final title2 = one(rt((p) => p == '일괄 시간 조정'));
            final route2Ok = reopened && route2 is DialogRoute && title2 != null && identical(ModalRoute.of(title2), route2);
            var popped2 = 'pending';
            route2?.popped.then((r) {
              popped2 = r.toString();
            });
            final directOut = route2Ok &&
                await tapRecv(() {
                  final e = textIn('퇴근 시간', '직접');
                  return e == null ? null : recvOf(e);
                });
            await frames(12);
            final outSheet = find.byType(TimePickerBottomSheet).evaluate().length == 1;
            var chipO = false;
            var selO = false;
            var viaO = 'none';
            if (outSheet) {
              chipO = await tapRecv(() => sheetRecv('18:00'));
              selO = sheetCount('18:00') == 2;
              viaO = await closeSheet('선택 완료', 'done');
            }
            final in2 = valText('출근 시간');
            final out2 = valText('퇴근 시간');
            final okT4 = btnText('조정하기');
            final en2 = enabledOf(okT4 == null ? null : recvOf(okT4));
            _out('D509 $tok att reopen hit=$reopened route=$route2Ok direct=$directOut sheet=$outSheet chip=$chipO sel=$selO via=$viaO in=$in2 out=$out2 enabled=$en2');
            // ⑫ 활성 '조정하기' 실제 탭 → route.popped = true → 일괄 창 닫힘 → 사유 창(아직 Functions 0)
            final n2 = routes.pushed.length;
            final reads0 = attReads;
            final hitSubmit = route2Ok && en2 && await tapRecv(() => recvText('조정하기'));
            await frames(12);
            final submitClosed = rt((p) => p == '일괄 시간 조정').evaluate().isEmpty;
            final callsAtSubmit = fnCalls.length;
            _out('D509 $tok att submit hit=$hitSubmit popped=$popped2 closed=$submitClosed calls=$callsAtSubmit');
            // ⑬ '근태 수정 사유'(DialogHelper.showTextInput) — 실제 입력 · 그 창 안의 '확인'(시트 · 일괄 창 버튼과 구별)
            Finder reasonDlg() => find.ancestor(of: rt((p) => p == '근태 수정 사유'), matching: find.byType(Dialog));
            Element? reasonRecv(String s) {
              final e = one(find.descendant(of: reasonDlg(), matching: rt((p) => p == s)));
              return e == null ? null : recvOf(e);
            }

            final reasonOpen = reasonDlg().evaluate().length == 1;
            final route3 = routes.pushed.length == n2 + 1 ? routes.pushed.last : null;
            final title3 = one(rt((p) => p == '근태 수정 사유'));
            final route3Ok = reasonOpen && route3 is DialogRoute && title3 != null && identical(ModalRoute.of(title3), route3);
            final field = find.descendant(of: reasonDlg(), matching: find.byType(TextField));
            final fieldOne = field.evaluate().length == 1;
            if (reasonOpen && fieldOne) {
              await t.enterText(field, _reason);
              await frames(4);
            }
            final typedOk = fieldOne && t.widget<TextField>(field).controller?.text == _reason;
            _out('D509 $tok shot 4reason ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_4reason', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADJ',
              'state': 'reason-typed',
            });
            final hitReasonOk = typedOk && await tapRecv(() => reasonRecv('확인'));
            await frames(16);
            final reasonGone = reasonDlg().evaluate().isEmpty;
            _out('D509 $tok att reason open=$reasonOpen route=$route3Ok field=$fieldOne typed=$typedOk hit=$hitReasonOk closed=$reasonGone');
            // ⑭ 경계에 닿은 호출 — 측정 시점 값으로 잡는다(퇴근 기대 = 근무일 KST 18:00 instant · 출근 필드 없음)
            final c1 = fnCalls.isEmpty ? const <String, Object?>{} : fnCalls.first;
            final params = c1['parameters'] is Map ? Map<String, Object?>.from(c1['parameters'] as Map) : const <String, Object?>{};
            final ents = <Map<String, Object?>>[
              if (params['entries'] is List)
                for (final e in params['entries'] as List)
                  if (e is Map) Map<String, Object?>.from(e),
            ];
            final wantOutMs = DateTime.utc(dayKey.year, dayKey.month, dayKey.day, 18, 0).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
            final ids = (ents.map((e) => e['attendanceId'].toString()).toList()..sort()).join(',');
            final pkeys = (params.keys.toList()..sort()).join(',');
            final outOk = ents.length == 2 && ents.every((e) => e['checkOutMs'] == wantOutMs);
            final anyIn = ents.any((e) => e.containsKey('checkInMs'));
            final fieldsOk = ents.length == 2 && ents.every((e) => const ['attendanceId', 'status', 'resetWageDetail', 'workHours'].every(e.containsKey));
            final reasonOk = ents.length == 2 && ents.every((e) => e['reason'] == _reason);
            final outV = ents.isEmpty ? 0 : (ents.first['checkOutMs'] as int? ?? 0);
            final reload = attReads - reads0;
            final raw = fnCalls.isEmpty ? '-' : base64Url.encode(utf8.encode(jsonEncode(fnCalls))).replaceAll('=', '');
            String sv(Object? x) => x == null ? '-' : x.toString();
            final fnName = sv(c1['functionName']), fnApp = sv(c1['appName']), fnRegion = sv(c1['region']), fnTimeout = sv(c1['timeout']);
            final fnOrigin = sv(c1['origin']), fnBiz = sv(params['businessId']);
            final pkeysOut = pkeys.isEmpty ? '-' : pkeys, idsOut = ids.isEmpty ? '-' : ids;
            _out('D509 $tok att fncall n=${fnCalls.length} name=$fnName app=$fnApp region=$fnRegion timeout=$fnTimeout origin=$fnOrigin pkeys=$pkeysOut biz=$fnBiz targets=${ents.length} ids=$idsOut outMs=$outOk inMs=$anyIn fields=$fieldsOk reason=$reasonOk outV=$outV outWant=$wantOutMs reload=$reload raw=$raw');
            if (_before) {
              chk('before 셸 면 흰색 아님(직접 Dialog 기본 면)', shellBg != null && _tok(shellBg) != 'white', _tok(shellBg));
              if (hitIn) {
                chk('before 값 든 출근 행 면/선 중립 아님', !(dcIn.bg == 'white' && dcIn.line == 'brand'), '${dcIn.bg}/${dcIn.line}');
              }
              if (v.id == 'B') chk('before B 넘침 > 0', overflows.isNotEmpty, '넘침 ${overflows.length}');
            } else {
              chk('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
              chk('strict 예정 출근 · 퇴근 · 지우기 · 직접 · 다시 지우기 · 닫기 hit', hitIn && hitOut && hitClear && hitPick && hitDirect && hitReclear && hitClose,
                  '$hitIn $hitOut $hitClear $hitPick $hitDirect $hitReclear $hitClose');
              chk('strict 직접 선택 완료 — 시트 열림 · 09:00 선택 · 선택 완료 탭 · 닫힘 · 출근 09:00', pickOpen && chipP && selP && viaP == 'done' && pickClosed && inAfterPick == '09:00',
                  '$pickOpen $chipP $selP $viaP $pickClosed $inAfterPick');
              chk('strict 직접 취소 — 14:00 으로 바꾼 뒤 시트 취소 · 닫힘 · 출근 09:00 그대로', sheetOpen && chipC && selC && via == 'cancel' && sheetClosed && inAfterDirect == '09:00',
                  '$sheetOpen $chipC $selC $via $sheetClosed $inAfterDirect');
              chk('strict 다시 지우기 → 출근 미설정 · 조정하기 활성(퇴근만)', inAfterReclear == '미설정' && enReclear, '$inAfterReclear $enReclear');
              chk('strict 조작 receiver ≥ 48(예정 · 직접 · 지우기)', rxIn >= 48 - 0.01 && rxOut >= 48 - 0.01, '${_f1(rxIn)} ${_f1(rxOut)}');
              chk('strict 도달 6', rCancel && rAdjust && rChipIn && rChipOut && rDirectIn && rClearOut, '$rCancel $rAdjust $rChipIn $rChipOut $rDirectIn $rClearOut');
              chk('strict 낱말 끊김 0', wTitle == 0 && wSub == 0 && wInfo == 0 && wIn == 0 && wOut == 0, '$wTitle $wSub $wInfo $wIn $wOut');
              chk('strict 조정하기 대비 ≥ 4.5', _cr(fill, ink) >= 4.5, _f2(_cr(fill, ink)));
              chk('strict 취소 탭 → 닫힘 · route.popped false · Functions 0', closed && popped1 == 'false' && callsAtClose == 0, '$closed $popped1 $callsAtClose');
              chk('strict 다시 열기 route · 퇴근 직접 18:00 선택 완료 · 출근 미설정 · 조정하기 활성',
                  reopened && route2Ok && directOut && outSheet && chipO && selO && viaO == 'done' && in2 == '미설정' && out2 == '18:00' && en2,
                  '$reopened $route2Ok $directOut $outSheet $chipO $selO $viaO $in2 $out2 $en2');
              chk('strict 조정하기 탭 → route.popped true · 일괄 창 닫힘 · 사유 전 Functions 0', hitSubmit && popped2 == 'true' && submitClosed && callsAtSubmit == 0,
                  '$hitSubmit $popped2 $submitClosed $callsAtSubmit');
              chk('strict 사유 창 — route · 입력 · 그 창 확인 탭 · 닫힘', reasonOpen && route3Ok && fieldOne && typedOk && hitReasonOk && reasonGone,
                  '$reasonOpen $route3Ok $fieldOne $typedOk $hitReasonOk $reasonGone');
              chk('strict Functions 정확 1회 — 이름 · [DEFAULT] · asia-northeast3 · 60000 · origin 없음',
                  fnCalls.length == 1 && fnName == _batchFn && fnApp == defaultFirebaseAppName && fnRegion == 'asia-northeast3' && fnTimeout == '60000' && fnOrigin == '-',
                  'n=${fnCalls.length} $fnName $fnApp $fnRegion $fnTimeout $fnOrigin');
              chk('strict payload — 사업장 · 정확 2대상 · 퇴근 epoch · 출근 필드 없음 · 필드 · 사유',
                  pkeys == 'businessId,entries' && fnBiz == _biz && ents.length == 2 && ids == 'att-bs-a,att-bs-b' && outOk && !anyIn && fieldsOk && reasonOk,
                  '$pkeysOut $fnBiz ${ents.length} $idsOut $outOk $anyIn $fieldsOk $reasonOk outV=$outV want=$wantOutMs');
              chk('strict 성공 뒤 근태 다시 읽기 = 가짜 reader 정확 1회(삼킨 예외면 0)', reload == 1, 'reload=$reload');
            }
          } else {
            // RULE: 혼합 안내 · 토글 켜기 · 예정 출근 → 미리보기
            final mixedEl = btnText(_mixedText);
            final mixedFound = mixedEl != null, mixedInk = _tok(inkOf(mixedEl));
            _out('D509 $tok att mixed found=$mixedFound ink=$mixedInk');
            Element? togRecv() {
              final e = btnText('근태 기준 적용');
              return e == null ? null : nearest(e, (w) => w is InkWell);
            }

            final hitTog = await tapRecv(togRecv);
            final sw = find.descendant(of: batchDlg(), matching: find.byType(Switch));
            final swW = sw.evaluate().length == 1 ? t.widget<Switch>(sw) : null;
            final togEl = btnText('근태 기준 적용');
            final togBox = togEl == null
                ? null
                : nearest(togEl, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null);
            final togLine = decoOf(togBox).line;
            _out('D509 $tok att toggle hit=$hitTog on=${swW?.value ?? false} line=$togLine track=${_tok(swW?.activeTrackColor)}');
            final hitPrev = await tapRecv(() {
              final e = textIn('출근 시간', '예정(06:00)');
              return e == null ? null : recvOf(e);
            });
            final prevRe = RegExp(r'^(적용해도 입력한 시각 그대로예요|(김피킹|박피킹) .+: \d\d:\d\d|외 \d+명도 바뀌어요|나머지 \d+명은 입력한 시각 그대로예요)$');
            final prevEls = inDlg(rt((p) => prevRe.hasMatch(p))).evaluate().toList();
            _out('D509 $tok att preview hit=$hitPrev lines=${prevEls.length} ink=${_tok(prevEls.isEmpty ? null : inkOf(prevEls.first))}');
            _out('D509 $tok shot 1rule ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1rule', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'RULE',
              'state': 'rule-on-preview',
            });
            final wMixed = breaksOf(btnText(_mixedText));
            final wTog = breaksOf(btnText('근태 기준 적용'));
            _out('D509 $tok att words mixed=$wMixed toggle=$wTog');
            final callsRule = fnCalls.length;
            chk('혼합 안내 보임 · warningDark', mixedFound && mixedInk == 'warningDark', mixedInk);
            if (_before) {
              if (swW != null) chk('before 토글 트랙 brand 아님', _tok(swW.activeTrackColor) != 'brand', _tok(swW.activeTrackColor));
            } else {
              chk('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
              chk('strict 토글 hit · 켜짐 · brand 선/트랙', hitTog && (swW?.value ?? false) && togLine == 'brand' && _tok(swW?.activeTrackColor) == 'brand',
                  '$hitTog ${swW?.value} $togLine');
              chk('strict 미리보기 ≥ 1줄', hitPrev && prevEls.isNotEmpty, '$hitPrev ${prevEls.length}');
              chk('strict 낱말 끊김 0', wMixed == 0 && wTog == 0, '$wMixed $wTog');
              chk('strict RULE Functions 0(조정하기를 누르지 않는다)', callsRule == 0, 'calls=$callsRule');
            }
          }
          // ── [r3] 경계 집계(두 상태 공통 · 측정 시점) — 예상 밖 채널 · 예상 밖 Functions · 지각 호출은 두 모드 모두 0 ──
          final nBatch = fnCalls.where((c) => c['functionName'] == _batchFn).length;
          final nLate = fnCalls.where((c) => c['functionName'] == _lateFn).length;
          final nOther = fnCalls.length - nBatch - nLate;
          final blockedCh = blocked.isEmpty ? '-' : (blocked.toSet().toList()..sort()).join(',');
          final fwList = fwCh.isEmpty ? '-' : (fwCh.toList()..sort()).join(',');
          _out('D509 $tok att boundary calls=${fnCalls.length} batch=$nBatch late=$nLate fnOther=$nOther blocked=${blocked.length} blockedCh=$blockedCh fwCh=$fwList');
          chk('두 모드 무실서비스 — 예상 밖 채널 0 · 예상 밖 Functions 0 · 지각 호출 0', blocked.isEmpty && nOther == 0 && nLate == 0,
              'blocked=$blockedCh other=$nOther late=$nLate');
          if (!_before) chk('strict 일괄 창 route 식별 — push 1 · DialogRoute · 제목이 그 route 소속', route1Ok, 'pushed=${newRoutes.length} ok=$route1Ok');
          // 측정 끝 — 넘침 수집기를 되돌린 뒤(한 곳) 모은 단언을 던진다.
          FlutterError.onError = prev;
          for (final c in checks) {
            must(c.$1, c.$2, c.$3);
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          final caps = fx == 'ADJ' ? 4 : 1;
          _out('D509 $tok done state=$fx mode=$mode captures=$caps overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
          await t.pumpWidget(const SizedBox.shrink());
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
