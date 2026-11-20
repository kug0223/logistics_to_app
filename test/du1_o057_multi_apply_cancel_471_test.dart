// ignore_for_file: depend_on_referenced_packages
// [DU471 · 자체 판정 셀 · 표시만] 지원 확인 시트(여러 건 · MultiApplyConfirmSheet) — '취소' 글자 버튼 textSecondary · '나머지 N개' 안내 textTertiary.
//   before = 현재 A(multi_apply_confirm_sheet 5e62ee6f) / strict = 후보. harness 는 multi_apply_confirm_sheet_layout_test 의 시트 열기
//   (DialogHelper.showSheet · 공고 상세와 같은 인자 · 서류 요건 충족 사용자)에 DU 캡처 · 측정을 붙였다.
//   상태 2개(ONE 1건 · BLOCK 2건 중 1건 이미 지원 → '나머지 1개' 안내).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du471-tb/DU_BEFORE_OBSERVE=471 · TA after/du471-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

import 'support/du1_vq_capture.dart';

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

/// 서류 요건을 갖춘 **시험용** 사용자(원 시험과 같다 · 실제 검증 아님).
class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1), isIdVerified: true, idCardImagePath: 'users/u1/id.png', bankName: '국민은행',
        accountNumber: '1234', accountHolder: '김근로', bankbookImagePath: 'users/u1/bb.png', createdAt: DateTime(2026, 1, 1),
      );
}

final kFuture = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 5));

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: '강남 물류센터 주식회사', type: 'flex', title: '단기 모집', creatorUID: 'a',
      status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 50, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate', rangeStart: kFuture, createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _wd(int i) => WorkDetailData(
      wdId: 'wd$i', workType: '냉장분류', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
      wage: 12000, wageType: 'hourly', requiredCount: 10, startTime: '18:00', endTime: '22:30', breakMinutes: 30,
    );

SlotModel _slot(int i) => SlotModel(id: 'slot$i', toId: 'to1', date: kFuture.add(Duration(days: i)), workDetails: [_wd(i)], status: SlotStatus.open);

/// 0번 근무에 이미 낸 지원(PENDING) — 관계 판정으로 제출 대상에서 빠진다(MAC-61 과 같은 축).
ApplicationModel _applied0() => ApplicationModel(
      id: 'a_pending_wd0', uid: 'u1', toId: 'to1', slotId: 'slot0', businessId: 'biz1', businessName: '강남 물류센터 주식회사',
      toTitle: '단기 모집', selectedWorkType: '냉장분류', wdId: 'wd0', startTime: '18:00', endTime: '22:30', wage: 12000,
      wageType: 'hourly', status: AppStatus.pending, workDate: kFuture, appliedAt: DateTime(2026, 10, 1),
    );

final _cases = <({String id, int count, List<ApplicationModel> myApps})>[
  (id: 'ONE', count: 1, myApps: const <ApplicationModel>[]),
  (id: 'BLOCK', count: 2, myApps: [_applied0()]),
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '471';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du471-tb' && _env['DU_BEFORE_OBSERVE'] == '471') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du471-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'surface': AppColors.surface,
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
    // [진단 수리 1/3] TextButton 은 투명(알파 0) Material 을 만든다 — 칠한 색이 아니므로 건너뛴다(진단에서 bg=x00000000).
    if (c != null && c.a > 0) {
      found = c;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async => FirebasePlatform.instance = _FakeCore());

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
      testWidgets('S957MC-${v.id}-${c.id} 지원 확인 시트(O057 · tok 은 오버레이 +900) — 취소 · 나머지 안내 대비', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S957MC-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D471 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

          final items = <({SlotModel? slot, WorkDetailData work})>[for (var i = 0; i < c.count; i++) (slot: _slot(i), work: _wd(i))];
          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<UserProvider>(
              create: (_) => _Applicant(),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (inner) => ElevatedButton(
                        onPressed: () => DialogHelper.showSheet<MultiApplyResult>(
                          inner,
                          useRootNavigator: true,
                          isScrollControlled: true,
                          builder: (_) => MultiApplyConfirmSheet(items: items, to: _to(), myApplications: c.myApps),
                        ),
                        child: const Text('열기'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await t.pump();
          await t.tap(find.text('열기'));
          // 충돌 체크는 진짜 async 를 두 틱 준다(원 시험과 같다).
          for (var k = 0; k < 2; k++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
            for (var i = 0; i < 20; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
          must('시트 열림', find.byType(MultiApplyConfirmSheet).evaluate().length == 1, '시트 ${find.byType(MultiApplyConfirmSheet).evaluate().length}');

          final cancelF = rt((p) => p == '취소');
          must('취소 1', cancelF.evaluate().length == 1, '개수 ${cancelF.evaluate().length}');
          Finder? restF;
          if (c.id == 'BLOCK') {
            restF = rt((p) => p == '나머지 1개는 이미 지원 중이거나 확정된 근무와 겹쳐요.');
            must('나머지 안내 1', restF.evaluate().length == 1, '개수 ${restF.evaluate().length}');
            await t.ensureVisible(restF);
          } else {
            await t.ensureVisible(cancelF);
          }
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          _out('D471 $tok shot 1sheet ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1sheet', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': 'multi-apply-sheet',
          });

          final cancelC = (t.widget(cancelF) as RichText).text.style?.color;
          final cancelBg = _bgOf(cancelF.evaluate().first);
          final cancelCr = _cr(cancelC, cancelBg);
          _out('D471 $tok att cancel text=${_tok(cancelC)} bg=${_tok(cancelBg)} cr=${_f(cancelCr)}');
          Color? restC;
          var restCr = 0.0;
          if (restF != null) {
            restC = (t.widget(restF) as RichText).text.style?.color;
            final restBg = _bgOf(restF.evaluate().first);
            restCr = _cr(restC, restBg);
            _out('D471 $tok att rest text=${_tok(restC)} bg=${_tok(restBg)} cr=${_f(restCr)}');
          }
          if (_before) {
            // 음성 기대(코드 확정) — 취소 grey400(1.88) · 나머지 안내 grey500(2.68).
            must('before 취소 grey400 · 대비 미달 검출', cancelC == AppColors.grey400 && cancelCr < 4.5, '${_tok(cancelC)} ${_f(cancelCr)}');
            if (restF != null) must('before 나머지 안내 grey500 · 대비 미달 검출', restC == AppColors.grey500 && restCr < 4.5, '${_tok(restC)} ${_f(restCr)}');
          } else {
            must('strict 취소 textSecondary · 대비 ≥ 4.5', cancelC == AppColors.textSecondary && cancelCr >= 4.5, '${_tok(cancelC)} ${_f(cancelCr)}');
            if (restF != null) must('strict 나머지 안내 textTertiary · 대비 ≥ 4.5', restC == AppColors.textTertiary && restCr >= 4.5, '${_tok(restC)} ${_f(restCr)}');
            must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D471 $tok done state=${c.id} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
          await t.pump(const Duration(seconds: 5));
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
