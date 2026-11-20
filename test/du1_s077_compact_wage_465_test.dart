// ignore_for_file: depend_on_referenced_packages
// [DU465 · 자체 판정 셀 · 표시만] DU-S077 일자리 탭 작은(compact) 공고 카드 — 급여 말줄임 제거(Expanded · 쉼표 뒤 줄바꿈).
//   before = 현재 A(user_to_card 6cc6415d · DU464 후보) / strict = 후보. harness 는 DU464 시험(cf233974)과 같고 측정만 급여 · 모집 현황 위치로 바꿨다.
//   작은 카드는 펼침이 없다(compact: true · selectedNotifier 없음). W 는 가로 배치, B 는 덩어리 줄바꿈 배치(_rowFits 300)라 두 분기를 함께 본다. 넘침은 출처와 함께 남긴다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du465-tb/DU_BEFORE_OBSERVE=465 · TA after/du465-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/user/cards/user_to_card.dart';

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

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

const _works0 = WorkDetailData(wdId: 'wdA', workType: '분류', wage: 12000, requiredCount: 3, startTime: '09:00', endTime: '13:00');
const _works1 = WorkDetailData(wdId: 'wdB', workType: '상차', wage: 13000, requiredCount: 2, startTime: '14:00', endTime: '18:00');

TOModel _toOf({required String id, required String type, required List<WorkDetailData> works, int required = 0, int confirmed = 0}) => TOModel(
      id: id, businessId: 'biz1', businessName: '골든패스 테스트 사업장', businessCity: '평택시', type: type,
      title: '물류센터 공고 $id', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: works, slotDateKeys: type == 'flex' ? [_key(_day(2)), _key(_day(3))] : const [], totalSlots: type == 'flex' ? 2 : 0,
      totalRequired: required, totalConfirmed: confirmed, totalPending: 0, isPublished: true, publishMode: 'immediate',
      rangeStart: _day(2), rangeEnd: _day(30), createdAt: _day(-3), statusUpdatedAt: _day(-3),
    );

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

final _cases = <({String id, TOModel to, List<(String, bool Function(String p), Color before)> lines})>[
  // 단기 · 업무 시간이 서로 달라 '업무 2종'.
  (id: 'FLEX', to: _toOf(id: 'F', type: 'flex', works: const [_works0, _works1]), lines: [
    ('type', (p) => p.startsWith('단기 · '), AppColors.grey500),
    ('suffix', (p) => p == '업무 2종', AppColors.grey500),
  ]),
  // 장기 · 잔여 2명.
  (id: 'OPEN', to: _toOf(id: 'O', type: 'contract', works: const [_works0], required: 3, confirmed: 1), lines: [
    ('type', (p) => p.startsWith('장기 · '), AppColors.grey500),
    ('recruit', (p) => p == '잔여 2명', AppColors.grey500),
  ]),
  // 장기 · 모집 마감.
  (id: 'FULLC', to: _toOf(id: 'C', type: 'contract', works: const [_works0], required: 2, confirmed: 2), lines: [
    ('type', (p) => p.startsWith('장기 · '), AppColors.grey500),
    ('recruit', (p) => p == '모집 마감', AppColors.grey400),
  ]),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '465';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du465-tb' && _env['DU_BEFORE_OBSERVE'] == '465') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du465-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · 이름 가운데 표시(ZWSP) 뒤에서만 일어났는가.

/// 놓인 면 — 가장 가까운 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님)).

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · ZWSP · 줄바꿈 문자 뒤에서만 일어났는가(DU462 시험 것).
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

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
    testWidgets('S077CW-${v.id}-${c.id} 작은 공고 카드 — 급여 말줄임 없음 · 쉼표 뒤 줄바꿈', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S077CW-${v.id}-${c.id}';
        final mode = _before ? 'before' : 'strict';
        _out('D465 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          child: ChangeNotifierProvider<UserProvider>.value(
            value: _UserDouble(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: Scaffold(
                backgroundColor: AppColors.background,
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: UserTOCard(
                    to: c.to,
                    myApplications: const [],
                    onApplySuccess: () {},
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D465 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        await shot('1card', 'card-compact');

        // ── 급여 줄(값은 즉시) — 잘림 · 줄 수 · 줄바꿈 경계, 모집 현황(있으면) 카드 안 ──
        final wageF = rt((p) => p.startsWith('12,000원'));
        must('급여 1', wageF.evaluate().length == 1, '개수 ${wageF.evaluate().length}');
        final wageRp = t.renderObject(wageF) as RenderParagraph;
        final wageCut = wageRp.didExceedMaxLines;
        final wb = _breaks(wageRp);
        final cardR = t.getRect(find.byType(UserTOCard));
        final recruitF = rt((p) => p == '잔여 2명' || p == '모집 마감');
        final recruitIn = recruitF.evaluate().isEmpty || t.getRect(recruitF).right <= cardR.right - 1;
        _out('D465 $tok att wage cut=$wageCut lines=${wb.lines} ok=${wb.ok} recruitIn=$recruitIn');
        if (_before) {
          // 음성 기대 — B FLEX 급여 '12,00…'(DU464 진단 B 원PNG) · B FULLC '12…'(DU464 TA 합성) 관측. 같은 말줄임 조합의 cut 값은 DU462 TB 실측 true.
          if (v.id == 'B' && (c.id == 'FLEX' || c.id == 'FULLC')) must('before B 급여 잘림 검출', wageCut, 'cut=$wageCut');
        } else {
          must('strict 급여 잘림 없음 · 쉼표 뒤 줄바꿈 · 모집 현황 카드 안', !wageCut && wb.ok && recruitIn, 'cut=$wageCut ok=${wb.ok} in=$recruitIn');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D465 $tok done state=${c.id} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
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
