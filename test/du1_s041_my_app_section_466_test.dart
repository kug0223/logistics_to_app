// ignore_for_file: depend_on_referenced_packages
// [DU466 · 자체 판정 셀 · 표시만] DU-S041 공고 상세 '내 지원' 영역(내 지원에서 진입) — 이름표 · 중립 배지 · 거절 안내 대비.
//   before = 현재 A(job_posting_screen 83b0fb2f) / strict = 후보. harness 는 application_relation_projection_test 의 공고 상세 렌더
//   (JobPostingScreen + JobPostingReads 메모리 대역 · 서류 요건 충족 사용자)에 myApplication 을 넘기고 DU 캡처 · 측정을 붙였다.
//   상태 4개(CANCELED 취소 · AUTOCANCEL 자동 취소 · EXPIRED 초대 종료 · REJECTED 지원 종료 + 거절 안내).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du466-tb/DU_BEFORE_OBSERVE=466 · TA after/du466-ta/없음.
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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'b');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 서류 요건을 갖춘 **시험용** 사용자(application_relation_projection_test 와 같다 · 실제 검증 아님).
class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1), isIdVerified: true, idCardImagePath: 'users/u1/id.png', bankName: '국민은행',
        accountNumber: '1234', accountHolder: '김근로', bankbookImagePath: 'users/u1/bb.png', createdAt: DateTime(2026, 1, 1),
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

const kTo = 'to1';
const kSlot = 'slot1';
// 날짜는 오늘 기준 상대값(고정 날짜는 하루 지나면 마감 경로로 빠진다 — 원 시험 주석).
final kDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 3));

const _wd = WorkDetailData(wdId: 'wdA', workType: '상하차', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
    wage: 12000, wageType: 'hourly', requiredCount: 3, startTime: '09:00', endTime: '13:00');

ApplicationModel _app({required String status, String? cancelReason, String? rejectMessage, DateTime? invitedAt}) => ApplicationModel(
      id: 'a_$status', uid: 'u1', toId: kTo, slotId: kSlot, businessId: 'biz1', businessName: '강남 물류센터', toTitle: '단기 모집',
      selectedWorkType: '상하차', wdId: 'wdA', startTime: '09:00', endTime: '13:00', wage: 12000, wageType: 'hourly', status: status,
      workDate: kDate, appliedAt: DateTime(2026, 10, 1), cancelReason: cancelReason, rejectMessage: rejectMessage, invitedAt: invitedAt,
    );

TOModel _to() => TOModel(
      id: kTo, businessId: 'biz1', businessName: '강남 물류센터', type: 'flex', title: '단기 모집', creatorUID: 'admin1',
      status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 4, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate', createdAt: DateTime(2026, 9, 1), statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1', name: '강남 물류센터', businessNumber: '000-00-00000', category: '음식점', subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1', ownerId: 'owner1', createdAt: DateTime(2026, 9, 1),
    );

SlotModel _slot() => SlotModel(id: kSlot, toId: kTo, date: kDate, workDetails: const [_wd], status: SlotStatus.open, confirmedCount: 0,
    createdAt: DateTime(2025));

JobPostingReads _reads(ApplicationModel app) => JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => const [_wd],
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [_slot()],
      myApplications: (uid) async => [app],
      workTypeCatalog: (id) async => WorkTypeCatalog.empty,
      applicationOnce: (id) async => null,
    );

const _rejectMsg = '이번에는 경력 조건이 맞지 않아 함께하지 못하게 되었어요';

// 상태 → (배지 글 · before 글자색/면 · 거절 안내 있음)
final _cases = <({String id, ApplicationModel app, String badge, Color beforeText, Color beforeBg, bool hasSub})>[
  (id: 'CANCELED', app: _app(status: AppStatus.canceled, cancelReason: 'USER_CANCELED'), badge: '취소',
    beforeText: AppColors.textSecondary, beforeBg: AppColors.grey100, hasSub: false),
  (id: 'AUTOCANCEL', app: _app(status: AppStatus.autoCanceled, cancelReason: 'SCHEDULE_CONFLICT'), badge: '자동 취소',
    beforeText: AppColors.textSecondary, beforeBg: AppColors.grey100, hasSub: false),
  (id: 'EXPIRED', app: _app(status: AppStatus.expired, invitedAt: DateTime(2026, 10, 1)), badge: '초대 종료',
    beforeText: AppColors.textSecondary, beforeBg: AppColors.grey100, hasSub: false),
  (id: 'REJECTED', app: _app(status: AppStatus.rejected, rejectMessage: _rejectMsg), badge: '지원 종료',
    beforeText: AppColors.errorDark, beforeBg: AppColors.errorBg, hasSub: true),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '466';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du466-tb' && _env['DU_BEFORE_OBSERVE'] == '466') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du466-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey100': AppColors.grey100, 'grey200': AppColors.grey200, 'grey400': AppColors.grey400, 'grey500': AppColors.grey500,
  'grey600': AppColors.grey600, 'errorDark': AppColors.errorDark, 'errorBg': AppColors.errorBg,
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
      testWidgets('S041MA-${v.id}-${c.id} 공고 상세 내 지원 영역 — 이름표 · 배지 · 안내 대비', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S041MA-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D466 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
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
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 50));
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _Applicant()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: JobPostingScreen(to: _to(), workDetails: const [], slotDate: kDate, myApplication: c.app, reads: _reads(c.app)),
              ),
            ),
          ));
          for (var i = 0; i < 25; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

          // '내 지원' 영역까지 스크롤(값은 캡처 뒤 즉시 잰다).
          final labelF = rt((p) => p == '내 지원');
          final badgeF = rt((p) => p == c.badge);
          must('이름표 · 배지 1/1', labelF.evaluate().length == 1 && badgeF.evaluate().length == 1,
              '${labelF.evaluate().length}/${badgeF.evaluate().length}');
          // 진단(d5dc1ff9)은 배지로 스크롤해 이름표가 화면 위로 밀렸다 — 캡처 구도만 이름표 기준으로 바꿨다(측정 동일).
          await t.ensureVisible(labelF);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          _out('D466 $tok shot 1mine ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1mine', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'my-application-section',
          });

          final labelC = (t.widget(labelF) as RichText).text.style?.color;
          final labelBg = _bgOf(labelF.evaluate().first);
          final labelCr = _cr(labelC, labelBg);
          final badgeC = (t.widget(badgeF) as RichText).text.style?.color;
          final badgeBg = _bgOf(badgeF.evaluate().first);
          final badgeCr = _cr(badgeC, badgeBg);
          _out('D466 $tok att label text=${_tok(labelC)} bg=${_tok(labelBg)} cr=${_f(labelCr)}');
          _out('D466 $tok att badge text=${_tok(badgeC)} bg=${_tok(badgeBg)} cr=${_f(badgeCr)}');
          // [DU466e] 상태 문장 = 배지와 같은 Row 안의 다른 RichText. 낱말 안 줄바꿈 수(wordBreaks)를 즉시 잰다.
          final badgeEl = badgeF.evaluate().first;
          Element? rowEl;
          badgeEl.visitAncestorElements((a) {
            if (a.widget is Row) {
              rowEl = a;
              return false;
            }
            return true;
          });
          final rowE = rowEl;
          final mainEls = rowE == null ? <Element>[] : find.descendant(of: find.byElementPredicate((x) => identical(x, rowE), skipOffstage: false),
              matching: find.byType(RichText), skipOffstage: false).evaluate().where((e) => !identical(e, badgeEl)).toList();
          must('상태 문장 1', mainEls.length == 1, '개수 ${mainEls.length}');
          final mainBreaks = wordBreaks(mainEls.single.renderObject! as RenderParagraph).length;
          Color? subC;
          var subCr = 0.0;
          var subBreaks = -1;
          if (c.hasSub) {
            final subF = rt((p) => p == _rejectMsg);
            must('거절 안내 1', subF.evaluate().length == 1, '개수 ${subF.evaluate().length}');
            subC = (t.widget(subF) as RichText).text.style?.color;
            final subBg = _bgOf(subF.evaluate().first);
            subCr = _cr(subC, subBg);
            _out('D466 $tok att sub text=${_tok(subC)} bg=${_tok(subBg)} cr=${_f(subCr)}');
            subBreaks = wordBreaks(subF.evaluate().first.renderObject! as RenderParagraph).length;
          }
          _out('D466 $tok att words main=$mainBreaks sub=$subBreaks');
          if (_before) {
            // 음성 기대(코드 확정) — 이름표 grey400(1.88) · 중립 배지 grey600/grey100(4.22) · grey600/grey200(3.97) · 거절 안내 grey500(2.68).
            // [DU466e] base = 466 채택판(ae08d54f) — 이름표 textSecondary · 중립 배지 textSecondary/grey100 · 거절 배지 빨강 · 거절 안내 textTertiary(466 TA 관측).
            must('before 이름표 textSecondary(466 채택)', labelC == AppColors.textSecondary && labelCr >= 4.5, '${_tok(labelC)} ${_f(labelCr)}');
            must('before 배지 색 · 면(코드 그대로)', badgeC == c.beforeText && badgeBg == c.beforeBg, '${_tok(badgeC)} ${_tok(badgeBg)}');
            if (c.hasSub) must('before 거절 안내 textTertiary(466 채택)', subC == AppColors.textTertiary && subCr >= 4.5, '${_tok(subC)} ${_f(subCr)}');
          } else {
            must('strict 이름표 textSecondary · 대비 ≥ 4.5', labelC == AppColors.textSecondary && labelCr >= 4.5, '${_tok(labelC)} ${_f(labelCr)}');
            // [DU466e] 네 상태 모두 같은 중립 배지 짝 · 상태 문장 · 거절 사유 낱말 경계.
            must('strict 중립 배지 textSecondary/grey100 · 대비 ≥ 4.5', badgeC == AppColors.textSecondary && badgeBg == AppColors.grey100 && badgeCr >= 4.5,
                '${_tok(badgeC)} ${_tok(badgeBg)} ${_f(badgeCr)}');
            if (c.hasSub) must('strict 거절 안내 textTertiary · 대비 ≥ 4.5', subC == AppColors.textTertiary && subCr >= 4.5, '${_tok(subC)} ${_f(subCr)}');
            must('strict 상태 문장 낱말 경계', mainBreaks == 0, '끊김 $mainBreaks');
            if (c.hasSub) must('strict 거절 사유 낱말 경계', subBreaks == 0, '끊김 $subBreaks');
            must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D466 $tok done state=${c.id} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
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
