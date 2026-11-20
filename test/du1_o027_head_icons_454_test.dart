// ignore_for_file: depend_on_referenced_packages
// [DU454 · 자체 판정 셀 · 표시만] DU-O027 지원 대화 머리 — 사업장 · 기간 줄 아이콘을 글 첫 줄 가운데에(공용 FirstLineIcon · 크기 그대로).
//   before = 현재 A(apply_work_dialog 424abe12) / strict = 후보(f2237b5c). fixture · reads · 대화 생성은 DU277 시험(du1_o027e)과 같고
//   장면은 'grouplong'(긴 사업장명 · 묶음 공고 → 기간 줄 있음)이다. tok 접두 'S927HI'(O027 + 900 · S927 화면 없음).
//   값은 닿은 즉시 지역 값으로 남긴다. 넘침은 출처와 함께 남긴다. 기본 skip — TB before/du454-tb/DU_BEFORE_OBSERVE=454 · TA after/du454-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:provider/provider.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_reads.dart';

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

class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
      );
}

final kNow = DateTime.now();
final kWorkDate = DateTime(kNow.year, kNow.month, kNow.day).add(const Duration(days: 5));
DateTime _d(int plus) => kWorkDate.add(Duration(days: plus));
DateTime _u(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// 그룹 마스터 공고. 날짜별 공고는 이것의 copy(rangeStart = 슬롯 날짜) — user_to_card 와 같다.
TOModel _to({bool pending = false}) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '강남 물류센터 상하차 단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: !pending,
      publishMode: pending ? 'scheduled' : 'immediate',
      publishAt: pending ? kNow.add(const Duration(days: 2)) : null,
      rangeStart: kWorkDate,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailData _work({String wdId = 'wd1', String workType = '상하차', String start = '09:00', String end = '18:00', int order = 0, bool full = false}) =>
    WorkDetailData(
      wdId: wdId,
      workType: workType,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 4,
      runtimeFull: full,
      startTime: start,
      endTime: end,
      order: order,
    );

/// 장면별 날짜(D+k) → 업무 목록. 빈 목록은 업무 없음 날짜다.
Map<int, List<WorkDetailData>> _plan(String sc) => switch (sc) {
      'group' => {
          0: [_work(), _work(wdId: 'wd2', workType: '피킹', start: '13:00', end: '22:00', order: 1)],
          1: [_work()],
          3: [_work(full: true)],
          4: [_work()],
          6: [_work()],
        },
      'nowork' => {0: <WorkDetailData>[], 1: [_work()]},
      _ => {0: [_work()], 1: [_work()]},
    };

bool _pendingAt(String sc, int k) => sc == 'pending' || (sc == 'group' && k == 6);

Map<DateTime, TOModel> _tos(String sc) =>
    {for (final k in _plan(sc).keys) _u(_d(k)): _to(pending: _pendingAt(sc, k)).copyWith(rangeStart: _d(k))};
Map<DateTime, List<WorkDetailData>> _wds(String sc) =>
    {for (final e in _plan(sc).entries) if (e.value.isNotEmpty) _u(_d(e.key)): e.value};
Map<DateTime, String> _slots(String sc) => {for (final k in _plan(sc).keys) _u(_d(k)): 'slot$k'};

/// 내 지원(같은 공고, 날짜별 슬롯) — 표식 점용.
ApplicationModel _myApp(int k, String st) => ApplicationModel(
      id: 'a$k',
      uid: 'u1',
      toId: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      toTitle: '강남 물류센터 상하차 단기 모집',
      selectedWorkType: '상하차',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: st,
      workDate: _d(k),
      appliedAt: DateTime(2026, 9, 25),
      slotId: 'slot$k',
    );

/// 같은 날 확정된 다른 근무(경고·알림용).
ApplicationModel _confirmed() => ApplicationModel(
      id: 'c1',
      uid: 'u1',
      toId: 'toOther',
      businessId: 'bizOther',
      businessName: '성수 창고',
      toTitle: '다른 공고',
      selectedWorkType: '피킹',
      wdId: 'wdOther',
      startTime: '10:00',
      endTime: '15:00',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      workDate: kWorkDate,
      appliedAt: DateTime(2026, 9, 25),
    );

ApplyWorkReads _reads(String sc) => ApplyWorkReads(
      applicationsForTO: ({required String toId, required String uid}) async =>
          sc == 'group' ? [_myApp(1, AppStatus.pending), _myApp(4, AppStatus.confirmed)] : <ApplicationModel>[],
      confirmedSchedules: ({required String uid, required DateTime workDate}) async =>
          sc == 'sched' ? [_confirmed()] : <ApplicationModel>[],
      conflictsForWorkDetails: ({required DateTime workDate, required List<WorkDetailData> workDetails}) async =>
          <String, ConflictInfo>{},
      myApplicationsForTOFresh: (toId) async => <ApplicationModel>[],
      businessForPolicy: (businessId) async => null,
    );

ApplyWorkDialog _dialog(String sc) => ApplyWorkDialog(
      mainTO: _to(pending: sc == 'pending'),
      workDetails: _plan(sc)[0] ?? const [],
      groupTOsByDate: _tos(sc),
      groupWorkDetailsByDate: _wds(sc),
      groupSlotIdsByDate: _slots(sc),
      businessName: sc == 'grouplong' ? '강남 디지털 단지 제2 물류센터' : '강남 물류센터',
      reads: _reads(sc),
    );

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수.
///   끊긴 자리 앞뒤가 모두 한글 음절·영숫자이고 그 사이에 공백·ZWSP·줄바꿈·구두점이 없으면 음절 끊김으로 센다.

String _f2(double v) => v.toStringAsFixed(2);

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '454';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du454-tb' && _env['DU_BEFORE_OBSERVE'] == '454') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du454-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S927HI-${v.id}-GROUPLONG 지원 대화 머리 — 사업장 · 기간 아이콘 첫 줄 가운데(긴 사업장명 · 묶음 공고)', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S927HI-${v.id}-GROUPLONG';
        final mode = _before ? 'before' : 'strict';
        _out('D454 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
        t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
        addTearDown(t.platformDispatcher.clearLocalesTestValue);
        addTearDown(t.platformDispatcher.clearLocaleTestValue);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('overflowed')) {
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
            overflows.add('${s.split('\n').first} @ $loc');
          } else {
            fwErrors.add(s.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        t.platformDispatcher.textScaleFactorTestValue = v.s;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<UserProvider>(
            create: (_) => _Applicant(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () => DialogHelper.showSheet<void>(ctx, isScrollControlled: true, builder: (_) => _dialog('grouplong')),
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 2; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.tap(find.text('열기'));
        for (var i = 0; i < 14; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        must('대화 1', find.byType(ApplyWorkDialog).evaluate().length == 1, '대화 ${find.byType(ApplyWorkDialog).evaluate().length}');
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D454 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'GROUPLONG',
            'state': state,
          });
          shots++;
        }

        // ── 머리 두 줄 — 아이콘 중심 − 같은 Row 글 첫 줄 가운데(값은 즉시) ──
        Finder inD(Finder f) => find.descendant(of: find.byType(ApplyWorkDialog), matching: f, skipOffstage: false);
        ({double d, double size, int lines, int icons, int texts}) rowOf(IconData icon, {double? below}) {
          final all = inD(find.byIcon(icon, skipOffstage: false)).evaluate().toList();
          // 같은 아이콘이 여럿이면(달력: 머리 · 날짜 영역 — TB STOP 원인) 기준선(below) 아래에서 가장 가까운 것을 고른다.
          Element? pick;
          var bestTop = double.infinity;
          for (final e in all) {
            final top = t.getRect(find.byElementPredicate((x) => identical(x, e), skipOffstage: false)).top;
            if (below != null && top < below) continue;
            if (top < bestTop) {
              bestTop = top;
              pick = e;
            }
          }
          final p0 = pick;
          if (p0 == null || (below == null && all.length != 1)) return (d: double.nan, size: -1, lines: 0, icons: all.length, texts: -1);
          final iF = find.byElementPredicate((x) => identical(x, p0), skipOffstage: false);
          Element? row;
          iF.evaluate().first.visitAncestorElements((a) {
            if (a.widget is Row) {
              row = a;
              return false;
            }
            return true;
          });
          final r = row;
          if (r == null) return (d: double.nan, size: -1, lines: 0, icons: 1, texts: -1);
          final texts = find
              .descendant(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(RichText, skipOffstage: false),
                  skipOffstage: false)
              .evaluate()
              .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText()).trim().isNotEmpty)
              // Icon 도 안에서 RichText(글리프)로 그린다 — 아이콘 아래 글은 뺀다(진단 1 NaN 원인).
              .where((e) {
                var underIcon = false;
                e.visitAncestorElements((a) {
                  if (a.widget is Icon) {
                    underIcon = true;
                    return false;
                  }
                  return !identical(a, r);
                });
                return !underIcon;
              })
              .toList();
          if (texts.length != 1) return (d: double.nan, size: -1, lines: 0, icons: 1, texts: texts.length);
          final te = texts.single;
          final rp = te.renderObject! as RenderParagraph;
          final tr = t.getRect(find.byElementPredicate((x) => identical(x, te), skipOffstage: false));
          final b0 = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
          final last = rp.getBoxesForSelection(TextSelection(baseOffset: rp.text.toPlainText().length - 1, extentOffset: rp.text.toPlainText().length)).first;
          final lines = ((last.bottom - b0.top) / (b0.bottom - b0.top)).round();
          final ir = t.getRect(iF);
          return (d: ir.center.dy - (tr.top + (b0.top + b0.bottom) / 2), size: (t.widget(iF) as Icon).size ?? -1, lines: lines, icons: all.length, texts: 1);
        }

        final biz = rowOf(Icons.business);
        final bizTop = t.getRect(inD(find.byIcon(Icons.business, skipOffstage: false)).first).top;
        final cal = rowOf(Icons.calendar_today, below: bizTop + 1);
        // [r1b · 후속114] 이 fixture 의 달력은 정확히 2 — 머리 기간 줄 1(textSecondary) + 날짜 머리 1(brand · DU276). 고른 것이 머리 기간인지도 본다.
        final calEls = inD(find.byIcon(Icons.calendar_today, skipOffstage: false)).evaluate().toList();
        final calHead = calEls.where((e) => (e.widget as Icon).color == AppColors.textSecondary).length;
        final calDate = calEls.where((e) => (e.widget as Icon).color == AppColors.brand).length;
        Element? near;
        var nearTop = double.infinity;
        for (final e in calEls) {
          final top = t.getRect(find.byElementPredicate((x) => identical(x, e), skipOffstage: false)).top;
          if (top >= bizTop + 1 && top < nearTop) {
            nearTop = top;
            near = e;
          }
        }
        final calPickHead = near != null && (near.widget as Icon).color == AppColors.textSecondary;
        _out('D454 $tok att head bizD=${_f2(biz.d)} bizLines=${biz.lines} calD=${_f2(cal.d)} calLines=${cal.lines} '
            'bizSize=${_f2(biz.size)} calSize=${_f2(cal.size)} bizIcons=${biz.icons} bizTexts=${biz.texts} calIcons=${cal.icons} calTexts=${cal.texts} '
            'calAll=${calEls.length} calHead=$calHead calDate=$calDate calPick=$calPickHead');
        await shot('1head', 'dialog-open');

        must('머리 두 줄 측정', !biz.d.isNaN && !cal.d.isNaN, '${biz.d} ${cal.d}');
        must('달력 정확 2 · 머리 기간 1 · 날짜 머리 1 · 고른 것 = 머리 기간', calEls.length == 2 && calHead == 1 && calDate == 1 && calPickHead,
            'all ${calEls.length} head $calHead date $calDate pick $calPickHead');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — 위 여백 1 · iconSize(15) 고정이라 B 첫 줄(26px) 가운데보다 위(코드 산술 ≈ 11).
            must('before B 아이콘 첫 줄 벗어남 검출', biz.d.abs() > 4 && cal.d.abs() > 4, '${_f2(biz.d)} ${_f2(cal.d)}');
          }
        } else {
          final want = v.id == 'B' ? 12.75 : 13.5;
          must('strict 아이콘 크기 그대로(iconSize 15)', (biz.size - want).abs() <= 0.05 && (cal.size - want).abs() <= 0.05, '${_f2(biz.size)} ${_f2(cal.size)}');
          must('strict 두 아이콘 = 첫 줄 가운데(±1.5)', biz.d.abs() <= 1.5 && cal.d.abs() <= 1.5, '${_f2(biz.d)} ${_f2(cal.d)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D454 $tok done state=GROUPLONG mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
