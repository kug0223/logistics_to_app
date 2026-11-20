// ignore_for_file: depend_on_referenced_packages
// [DU462 · 자체 판정 셀 · 표시만] DU-S071 내 지원 — 빈 상태 제목 · 안내, 삭제/실패 카드 제목 · 부제 줄바꿈(낱말 경계) · 카드 제목 색.
//   before = 현재 A(my_applications_screen 34529529 · DU461 후보) / strict = 후보. harness 는 DU461 시험(f9a744bd)과 같고 측정만 바꿨다.
//   상태 3개(EMPTY 지원 0건 · DELETED 공고 없음 · LOADFAIL 공고 불러오기 실패).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du462-tb/DU_BEFORE_OBSERVE=462 · TA after/du462-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ALfit/utils/text_layout.dart';
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

MyApplicationsReads _reads(List<ApplicationModel> apps, {bool toNull = false, bool failed = false}) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: toNull ? null : _to(), failed: failed),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

final _cases = <({String id, List<ApplicationModel> apps, bool toNull, bool failed, DateTime clock, String title, bool Function(String p) sub})>[
  (id: 'EMPTY', apps: const <ApplicationModel>[], toNull: false, failed: false, clock: _afterIntake,
    title: '아직 지원한 일자리가 없어요', sub: (p) => p == '일하고 싶은 날짜를 선택하고\n나에게 맞는 일자리를 찾아보세요.'),
  (id: 'DELETED', apps: [_mk(status: AppStatus.pending)], toNull: true, failed: false, clock: _afterIntake,
    title: '삭제된 공고', sub: (p) => p.startsWith('QA 사업장 · ') && p.endsWith(' · 공고 삭제됨')),
  (id: 'LOADFAIL', apps: [_mk(status: AppStatus.pending)], toNull: true, failed: true, clock: _afterIntake,
    title: '공고 정보를 불러오지 못했어요', sub: (p) => p.startsWith('QA 사업장 · ') && p.endsWith(' · 새로고침하면 다시 보여요')),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · ZWSP · 줄바꿈 문자 뒤에서만 일어났는가(DU450 시험 것 + 줄바꿈 문자).
({int lines, bool ok}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  double? prevTop;
  var ok = true;
  for (var i = 0; i < s.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final tp = bx.first.top;
    if (!tops.any((x) => (x - tp).abs() < 0.5)) tops.add(tp);
    if (prevTop != null && (tp - prevTop).abs() >= 0.5) {
      final raw = s.substring(0, i);
      if (!(raw.endsWith(' ') || raw.endsWith(String.fromCharCode(0x00A0)) || raw.endsWith(String.fromCharCode(0x200B)) ||
          raw.endsWith(String.fromCharCode(0x0A)))) {
        ok = false;
      }
    }
    prevTop = tp;
  }
  return (lines: tops.length, ok: ok);
}

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '462';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du462-tb' && _env['DU_BEFORE_OBSERVE'] == '462') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du462-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
      testWidgets('S071EW-${v.id}-${c.id} 내 지원 빈 상태 · 삭제 카드 줄바꿈 · 제목 색', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S071EW-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D462 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
                home: MyApplicationsScreen(reads: _reads(c.apps, toNull: c.toNull, failed: c.failed), clock: () => c.clock),
              ),
            ),
          ));
          for (var i = 0; i < 25; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

          // 설명 줄이 화면 안에 오도록 첫 줄까지 스크롤(값은 캡처 뒤 즉시 잰다).
          final first = rt((p) => p == c.title);
          must('제목 1(스크롤 전)', first.evaluate().length == 1, '개수 ${first.evaluate().length}');
          await t.ensureVisible(first);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          _out('D462 $tok shot 1ctx ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1ctx', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'context-row',
          });

          final titleF = rt((p) => p == c.title);
          final subF = rt(c.sub);
          must('제목 · 부제 1/1', titleF.evaluate().length == 1 && subF.evaluate().length == 1,
              '${titleF.evaluate().length}/${subF.evaluate().length}');
          final titleRp = t.renderObject(titleF) as RenderParagraph;
          final tb = _breaks(titleRp);
          final titleCut = titleRp.didExceedMaxLines;
          final sb = _breaks(t.renderObject(subF) as RenderParagraph);
          final titleCol = (t.widget(titleF) as RichText).text.style?.color;
          final titleBg = _bgOf(titleF.evaluate().first);
          final titleCr = _cr(titleCol, titleBg);
          if (c.id == 'EMPTY') {
            _out('D462 $tok att etitle lines=${tb.lines} ok=${tb.ok}');
            _out('D462 $tok att esub lines=${sb.lines} ok=${sb.ok}');
          } else {
            _out('D462 $tok att title text=${_tok(titleCol)} bg=${_tok(titleBg)} cr=${_f(titleCr)} cut=$titleCut lines=${tb.lines} ok=${tb.ok}');
            _out('D462 $tok att sub lines=${sb.lines} ok=${sb.ok}');
          }
          if (_before) {
            // 음성 기대 — B 는 DU461 진단 · TA 원PNG 관측(빈 상태 '일자 / 리가' · '선 / 택하고', 카드 부제 '지원 검 / 토 중'),
            //   카드 제목 색은 코드 확정(grey600 · grey50 위 4.41). 제목 잘림(cut)은 기록만 한다.
            if (v.id == 'B' && c.id == 'EMPTY') must('before B 빈 상태 제목 · 안내 음절 끊김 검출', !tb.ok && !sb.ok, 'title ${tb.ok} sub ${sb.ok}');
            if (v.id == 'B' && c.id != 'EMPTY') must('before B 카드 부제 음절 끊김 검출', !sb.ok, 'sub ${sb.ok}');
            if (c.id != 'EMPTY') {
              must('before 카드 제목 grey600 · 대비 미달 검출', titleCol == AppColors.grey600 && titleCr < 4.5, '${_tok(titleCol)} ${_f(titleCr)}');
            }
          } else {
            must('strict 제목 · 부제 낱말 경계', tb.ok && sb.ok, 'title ${tb.ok} sub ${sb.ok}');
            if (c.id != 'EMPTY') {
              must('strict 카드 제목 textSecondary · 대비 ≥ 4.5 · 잘림 없음', titleCol == AppColors.textSecondary && titleCr >= 4.5 && !titleCut,
                  '${_tok(titleCol)} ${_f(titleCr)} cut=$titleCut');
            }
          }
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D462 $tok done state=${c.id} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
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
