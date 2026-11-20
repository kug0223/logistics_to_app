// ignore_for_file: depend_on_referenced_packages
// [DU505 · 후속114 N1 앞창 · 표시만] DU-O001 근태 현황 → 일괄 '시간 조정' 창의 '조정하기' 채움 info → brand(배경 한 줄).
//   before = 현재 A(attendance_status_dialog 19d4ccf8) / strict = 후보(88daa1a2). harness 는 DU305 시험(du1_o001_followup_305f)과 같은
//   읽기 경계(AttendanceReads)를 쓴다 — 출근 처리된 2명 → '전체' 선택 → '시간 조정' → '예정(06:00)' 칩으로 '조정하기' 활성.
//   callback · guard · 선택 시각 · 반올림 · writer 는 건드리지 않는다(누르기는 칩까지 · '조정하기'는 누르지 않는다).
//   넘침은 기록만 한다(색 한 줄 변경은 배치를 바꾸지 않고, 진단 0 배정이라 base 넘침 수를 미리 알 수 없다 — 보고에 밝힌다).
//   기본 skip — TB before/du505-tb/DU_BEFORE_OBSERVE=505 · TA after/du505-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

const _biz = 'biz505';

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';
Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'info': AppColors.info, 'brand': AppColors.brand,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '505';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du505-tb' && _env['DU_BEFORE_OBSERVE'] == '505') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du505-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S901AF-${v.id}-ADJ 근태 현황 일괄 시간 조정 — 조정하기 채움', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S901AF-${v.id}-ADJ';
        final mode = _before ? 'before' : 'strict';
        _out('D505 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

        // ── fixture: 오늘 · 출근 처리된 2명(06:00 출근 · 23:59 퇴근 예정) — 정상 탭 · '시간 조정' 대상 ──
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day);
        final dayKey = FormatHelper.kstDayKeyOfCivil(day);
        UserModel user(String uid, String name, UserRole role) =>
            UserModel(uid: uid, username: name, name: name, email: '$uid@example.invalid', role: role, createdAt: DateTime(2026, 1, 1));
        Map<String, dynamic> appMap(String id, String uid) => {
              'id': id, 'uid': uid, 'toId': 'to505', 'slotId': 'slot505', 'businessId': _biz, 'wdId': 'wd-pick', 'workDetailId': 'wd-pick',
              'status': 'CONFIRMED', 'type': 'short_term', 'selectedWorkType': '피킹', 'startTime': '06:00', 'endTime': '23:59',
              'workDate': _ts(dayKey), 'createdAt': _ts(dayKey), 'appliedAt': _ts(dayKey),
            };
        Map<String, dynamic> attMap(String id, String appId, String uid) => {
              'id': id, 'applicationId': appId, 'uid': uid, 'businessId': _biz, 'status': 'present', 'checkIn': '06:00',
              'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
            };
        final apps = [appMap('ad-a', 'u-ad-a'), appMap('ad-b', 'u-ad-b')];
        final atts = [attMap('att-ad-a', 'ad-a', 'u-ad-a'), attMap('att-ad-b', 'ad-b', 'u-ad-b')];
        final names = {'u-ad-a': '김피킹', 'u-ad-b': '박피킹'};
        final business = BusinessModel(
          id: _biz, name: 'DU505 물류센터', businessNumber: '000-00-00000', category: '물류', subCategory: '포장',
          address: '경기도 평택시 서정동 1', ownerId: 'owner505', createdAt: DateTime(2026, 1, 1),
        );
        final reads = AttendanceReads(
          applicationsPaged: (payload) async {
            if (payload['type'] != null) return const [];
            return [for (final a in apps) Map<String, dynamic>.of(a)];
          },
          workTypeDocs: (id) async => const {},
          adminAttendances: ({required businessId, required startMs, required endMs}) async => [for (final a in atts) Map<String, dynamic>.of(a)],
          workDetailTimes: (workers) async => const {},
          usersBatch: ({required uids, required businessId}) async => {for (final u in uids) u: user(u, names[u] ?? u, UserRole.USER)},
          contractStatus: ({required appIds, required businessId}) async => ContractStatusBatch(statuses: {for (final id in appIds) id: 'signed'}),
          dayStaffing: ({required businessId, required dayStartMs}) async => const <DayStaffingRow>[],
          businessById: (id) async => business,
          businessNames: (ids) async => {for (final i in ids) i: business.name},
        );
        final up = UserProvider()..debugSetCurrentUser(user('owner505', 'DU505 사장', UserRole.BUSINESS_ADMIN));

        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<UserProvider>.value(
            value: up,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
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
        // 로드 대기: '전체' 선택 칸(AppCheckbox 를 감싼 GestureDetector)이 보일 때까지(최대 40 frame).
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
        // [DU505 r1 · 후속115 §2-7] 기본 탭은 '확인필요'다. 두 사람(근무 중)은 '정상' 탭에 있으므로 그 탭을 실제로 고른다.
        //   탭 수 · 선택 배지 · 조정 건수/활성을 값으로 남기고 단언한다(진단 전에 고정 · 진단 뒤 수리 0).
        final normalTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '정상');
        final reviewTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '확인필요');
        must('정상 탭 1 · 확인필요 탭 1', normalTab.evaluate().length == 1 && reviewTab.evaluate().length == 1,
            '${normalTab.evaluate().length} ${reviewTab.evaluate().length}');
        final normalN = (normalTab.evaluate().first.widget as AppTabLabel).count ?? -1;
        final reviewN = (reviewTab.evaluate().first.widget as AppTabLabel).count ?? -1;
        _out('D505 $tok att tabs normal=$normalN review=$reviewN');
        must('정상 탭 2명 · 확인필요 0명', normalN == 2 && reviewN == 0, '정상 $normalN 확인필요 $reviewN');
        await t.tap(normalTab);
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final box = findAllBox();
        must('정상 탭 전체 선택 칸 1', box != null, '탭 전환 뒤 전체 칸 없음');
        if (box == null) return; // must 가 이미 실패를 던진다 — 승격용
        await t.tap(box);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final badgeN = find.descendant(of: box, matching: rt((p) => p == '2')).evaluate().length;
        // '시간 조정' 일괄 버튼(InkWell 안 tune 아이콘 + 글).
        final adjEls = find.byType(InkWell).evaluate().where((e) =>
            find.descendant(of: fe(e), matching: find.byIcon(Icons.tune)).evaluate().length == 1 &&
            find.descendant(of: fe(e), matching: rt((p) => p == '시간 조정')).evaluate().length == 1).toList();
        must('시간 조정 버튼 1', adjEls.length == 1, '개수 ${adjEls.length}');
        final adjInk = adjEls.first.widget as InkWell;
        final adj2N = find.descendant(of: fe(adjEls.first), matching: rt((p) => p == '2건')).evaluate().length;
        _out('D505 $tok att select badge=$badgeN adjust2=$adj2N enabled=${adjInk.onTap != null}');
        must('선택 배지 2 · 조정 2건', badgeN == 1 && adj2N == 1, '배지 $badgeN 조정 $adj2N');
        must('시간 조정 활성', adjInk.onTap != null, '비활성');
        // [DU505 r2 · 후속116 §2-4] B 에서 버튼이 스크롤 영역에 가려 탭이 빗나갔다(r1c 진단) — 실제로 보이게 굴리고 다시 찾는다.
        await t.ensureVisible(fe(adjEls.first));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final adj2Els = find.byType(InkWell).evaluate().where((e) =>
            find.descendant(of: fe(e), matching: find.byIcon(Icons.tune)).evaluate().length == 1 &&
            find.descendant(of: fe(e), matching: rt((p) => p == '시간 조정')).evaluate().length == 1).toList();
        must('시간 조정 버튼 1(스크롤 뒤)', adj2Els.length == 1, '개수 ${adj2Els.length}');
        final adjBox = adj2Els.first.renderObject! as RenderBox;
        final adjCenter = adjBox.localToGlobal(adjBox.size.center(Offset.zero));
        final hit = t.hitTestOnBinding(adjCenter);
        final hitOk = hit.path.any((h) => identical(h.target, adjBox));
        _out('D505 $tok att reach hitOk=$hitOk');
        must('시간 조정 중심 hit', hitOk, '중심 $adjCenter 이 버튼에 닿지 않음');
        await t.tapAt(adjCenter);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final dlgTitle = rt((p) => p == '일괄 시간 조정');
        must('일괄 시간 조정 창 열림', dlgTitle.evaluate().length == 1, '제목 ${dlgTitle.evaluate().length}');
        // '예정(06:00)' 칩으로 출근 시간을 정해 '조정하기'를 활성으로 만든다(누르기는 칩까지).
        final chip = rt((p) => p == '예정(06:00)');
        must('예정(06:00) 칩 1', chip.evaluate().length == 1, '개수 ${chip.evaluate().length}');
        await t.ensureVisible(chip);
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(chip);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final okF = rt((p) => p == '조정하기');
        must('조정하기 1', okF.evaluate().length == 1, '개수 ${okF.evaluate().length}');
        await t.ensureVisible(okF);
        await t.pump(const Duration(milliseconds: 50));
        final btnF = find.ancestor(of: okF, matching: find.byType(ElevatedButton));
        must('조정하기 버튼 1', btnF.evaluate().length == 1, '개수 ${btnF.evaluate().length}');
        final btn = t.widget<ElevatedButton>(btnF.first);
        final enabled = btn.onPressed != null;
        final bg = btn.style?.backgroundColor?.resolve(<WidgetState>{});
        final fg = (t.widget(okF) as RichText).text.style?.color;
        final cr = _cr(fg, bg);
        _out('D505 $tok att adjust enabled=$enabled bg=${_tok(bg)} text=${_tok(fg)} cr=${_f(cr)}');
        _out('D505 $tok shot 1adjust ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1adjust', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADJ',
          'state': 'batch-adjust-ready',
        });
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        must('조정하기 활성(칩 뒤)', enabled, 'onPressed null');
        if (_before) {
          // 음성 기대(코드 확정) — 흰 글자 on info 3.12.
          must('before 채움 info · 대비 미달', bg == AppColors.info && cr < 4.5, '${_tok(bg)} ${_f(cr)}');
        } else {
          must('strict 채움 brand · 대비 ≥ 4.5', bg == AppColors.brand && cr >= 4.5, '${_tok(bg)} ${_f(cr)}');
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D505 $tok done state=ADJ mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
