// ignore_for_file: depend_on_referenced_packages
// [DU459 · 자체 판정 셀 · 표시만] DU-S071 내 지원 카드 아래 상태 설명 줄(_buildContextRow) — 대비 미달 줄만 같은 함수의 기존 짝으로.
//   13px 중립 상태 문장 grey500/grey400 → grey600 · 12px 보조 줄 grey500/grey400 → textTertiary · 기한 지남 error → errorDark.
//   before = 현재 A(my_applications_screen 182f582a) / strict = 후보. harness 는 invite_closure_projection_render_test(실제 MyApplicationsScreen ·
//   LOCAL reads) 렌더 방식 + DU 캡처 · 측정. 상태 9개(초대 거절 · 거절 · 일정 겹침 취소 · 정원 소진 · 초대 효력 종료 · 확인 실패 · 제안 · 기한 지남 · 만료).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du459-tb/DU_BEFORE_OBSERVE=459 · TA after/du459-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

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

const _kUid = 'u1';

/// 지원 요건을 갖춘 **시험용** 사용자 — 실제 신원 · 계좌 검증이 아니다(IC 시험과 같다).
class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid, username: _kUid, name: 'QA 지원자', email: '$_kUid@alfit.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'), accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1), idCardImagePath: 'id_cards/$_kUid/front.jpg', isIdVerified: true,
        bankName: '국민은행', accountNumber: '000000000000', accountHolder: 'QA 지원자', bankbookImagePath: 'bankbooks/$_kUid/b.jpg',
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

final DateTime _day = FormatHelper.toKstDate(DateTime.utc(2026, 10, 20));
final DateTime _start = FormatHelper.kstWallClockInstant(_day, '20:00')!;
final DateTime _afterIntake = _start.subtract(const Duration(minutes: 30));

ApplicationModel _mk({
  required String status,
  DateTime? invitedAt,
  InviteCapacityState cap = InviteCapacityState.available,
  InviteAcceptReadiness r = InviteAcceptReadiness.ready,
  String? ended,
  String? cancelReason,
  String? conflictingBusiness,
  String? conflictingTime,
  String? offerKind,
  String? sourceWorkType,
}) =>
    ApplicationModel(
      id: 'a1', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: 'QA 사업장',
      toTitle: 'QA 공고', status: status, selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: _day, appliedAt: _day.subtract(const Duration(days: 1)), invitedAt: invitedAt,
      inviteExpiresAt: invitedAt == null ? null : _start,
      inviteAcceptDeadline: (invitedAt == null || cap == InviteCapacityState.closed) ? null : _start,
      workInstanceCapacityState: cap, inviteAcceptReadiness: r, publicIntakeClosed: false, inviteEndedReason: ended,
      cancelReason: cancelReason, conflictingBusiness: conflictingBusiness, conflictingTime: conflictingTime,
      offerKind: offerKind, sourceWorkType: sourceWorkType,
      documentAccessConsentGiven: true, documentAccessConsentVersion: DocumentAccessConsent.version,
    );

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: 'QA 사업장', type: 'flex', title: 'QA 공고', creatorUID: 'admin1',
      status: TOStatus.closed, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3,
      totalConfirmed: 0, totalPending: 1, isPublished: true, publishMode: 'immediate',
      createdAt: _day.subtract(const Duration(days: 10)), statusUpdatedAt: _day.subtract(const Duration(days: 10)),
    );

MyApplicationsReads _reads(List<ApplicationModel> apps) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

typedef _Line = ({String label, bool Function(String p) m, Color before, Color after});

final _inv = _day.subtract(const Duration(hours: 4));
const _confBiz = '다른 사업장';
const _confTime = '20:00~22:00';

final _cases = <({String id, ApplicationModel app, DateTime clock, List<_Line> lines})>[
  (id: 'REJINV', app: _mk(status: AppStatus.rejected, invitedAt: _inv), clock: _afterIntake, lines: [
    (label: '초대 거절', m: (p) => p == '초대를 거절했어요', before: AppColors.grey500, after: AppColors.grey600),
  ]),
  (id: 'REJ', app: _mk(status: AppStatus.rejected), clock: _afterIntake, lines: [
    (label: '거절', m: (p) => p == '이번 지원은 확정되지 않았어요', before: AppColors.grey500, after: AppColors.grey600),
  ]),
  (id: 'CONFL', app: _mk(status: AppStatus.autoCanceled, cancelReason: 'SCHEDULE_CONFLICT', conflictingBusiness: _confBiz, conflictingTime: _confTime),
    clock: _afterIntake, lines: [
    (label: '겹침 취소 문장', m: (p) => p == '확정된 일정과 시간이 겹쳐 자동 취소됐어요', before: AppColors.grey500, after: AppColors.grey600),
    (label: '겹침 맥락', m: (p) => p == '확정된 근무: $_confBiz · $_confTime', before: AppColors.grey400, after: AppColors.textTertiary),
  ]),
  (id: 'FULL', app: _mk(status: AppStatus.invited, invitedAt: _inv, cap: InviteCapacityState.full), clock: _afterIntake, lines: [
    (label: '정원 소진 보조', m: (p) => p == '자리가 다시 생기면 수락할 수 있어요', before: AppColors.grey500, after: AppColors.textTertiary),
  ]),
  (id: 'CLOSED', app: _mk(status: AppStatus.invited, invitedAt: _inv, cap: InviteCapacityState.closed, ended: 'RECRUIT_ENDED'),
    clock: _afterIntake, lines: [
    (label: '효력 종료 보조', m: (p) => p == '사업장이 모집을 마감해 수락할 수 없어요', before: AppColors.grey500, after: AppColors.textTertiary),
    (label: '자동 정리 안내', m: (p) => p == '초대 기한이 지나면 목록에서 자동으로 정리돼요', before: AppColors.grey400, after: AppColors.textTertiary),
  ]),
  (id: 'UNKNOWN', app: _mk(status: AppStatus.invited, invitedAt: _inv, cap: InviteCapacityState.unknown), clock: _afterIntake, lines: [
    (label: '확인 실패 보조', m: (p) => p == '새로고침 후 다시 확인해 주세요', before: AppColors.grey500, after: AppColors.textTertiary),
  ]),
  (id: 'OFFER', app: _mk(status: AppStatus.invited, invitedAt: _inv, offerKind: 'ALTERNATIVE_WORK', sourceWorkType: '상차'),
    clock: _afterIntake, lines: [
    (label: '제안 안내', m: (p) => p == '수락하면 기존 지원(상차)은 자동으로 정리돼요', before: AppColors.grey500, after: AppColors.textTertiary),
    (label: '수락 기한', m: (p) => p.startsWith('~') && p.endsWith(' 만료'), before: AppColors.grey500, after: AppColors.textTertiary),
  ]),
  (id: 'LATE', app: _mk(status: AppStatus.invited, invitedAt: _inv), clock: _start, lines: [
    (label: '기한 지남', m: (p) => p.startsWith('수락 기한이 지났어요'), before: AppColors.error, after: AppColors.errorDark),
  ]),
  (id: 'EXPIRED', app: _mk(status: AppStatus.expired, invitedAt: _inv), clock: _afterIntake, lines: [
    (label: '만료', m: (p) => p == '초대 유효기간이 종료되었어요', before: AppColors.grey400, after: AppColors.grey600),
  ]),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? w.text.toPlainText(includeSemanticsLabels: false) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '459';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du459-tb' && _env['DU_BEFORE_OBSERVE'] == '459') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du459-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600,
  'error': AppColors.error, 'errorDark': AppColors.errorDark, 'grey50': AppColors.grey50, 'surface': AppColors.surface,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 가장 가까운 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님)).
Color? _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((x) {
    final w = x.widget;
    Color? c;
    if (w is Container) {
      c = w.color ?? (w.decoration is BoxDecoration ? (w.decoration! as BoxDecoration).color : null);
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color;
    }
    if (c != null) {
      found = c;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
      testWidgets('S071CX-${v.id}-${c.id} 내 지원 카드 상태 설명 줄 — 대비 · 같은 함수 짝', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S071CX-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D459 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              // 넘침 출처(파일:줄)를 함께 남긴다(DU446 · 447 교훈).
              final full = d.toString();
              final k = full.indexOf('The relevant error-causing widget was');
              final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
              overflows.add('${m.split('\n').first} @ $loc');
            } else {
              fwErrors.add(m.split('\n').first);
              prev?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = prev);
          t.view.physicalSize = Size(v.w, v.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: MyApplicationsScreen(reads: _reads([c.app]), clock: () => c.clock),
              ),
            ),
          ));
          for (var i = 0; i < 25; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

          // 설명 줄이 화면 안에 오도록 첫 줄까지 스크롤(값은 캡처 뒤 즉시 잰다).
          final first = rt(c.lines.first.m);
          must('${c.lines.first.label} 1(스크롤 전)', first.evaluate().length == 1, '개수 ${first.evaluate().length}');
          await t.ensureVisible(first);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          _out('D459 $tok shot 1ctx ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1ctx', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'context-row',
          });

          final toks = <String>[];
          var minCr = double.infinity;
          for (var i = 0; i < c.lines.length; i++) {
            final l = c.lines[i];
            final f = rt(l.m);
            must('${l.label} 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
            final col = (t.widget(f) as RichText).text.style?.color;
            final bg = _bgOf(f.evaluate().first);
            final cr = _cr(col, bg);
            toks.add(_tok(col));
            minCr = math.min(minCr, cr);
            // 줄 출력은 lgate 선언형(att l0 · att l1 · 키 글자 그대로) — 진단(833579c7)의 'line <이름>' 출력은 선언 밖 kind 라 바꿨다.
            if (i == 0) {
              _out('D459 $tok att l0 text=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
            } else {
              _out('D459 $tok att l1 text=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
            }
            if (_before) {
              must('before ${l.label} ${_tok(l.before)} · 대비 미달 검출', col == l.before && cr < 4.5, '${_tok(col)} ${_f(cr)}');
            } else {
              must('strict ${l.label} ${_tok(l.after)} · 대비 ≥ 4.5', col == l.after && cr >= 4.5, '${_tok(col)} ${_f(cr)}');
            }
          }
          _out('D459 $tok att ctx n=${c.lines.length} toks=${toks.join('+')} minCr=${_f(minCr)}');
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D459 $tok done state=${c.id} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 50));
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
