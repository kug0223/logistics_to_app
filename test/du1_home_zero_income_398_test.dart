// [DU398 S080] 지원자 홈 0수입 안내 낱말 묶기(소급 32 §3) — 새 파일 · 정확 2 public(B 320x640@2.0 · N 390x844@1.0).
//   fixture: 기준 2026-11-08(KST 10:00 clock) · 조회 성공 · 지원/근태/계약 0 → 확정 0 · 예정 0 → 0수입 카드. VQ 와 같은 fake core · 글꼴 등록 · ko_KR.
//   독립 기대(제품 TextLayout 미사용): 제목 '아직 표시할 수입 금액이 없어요' · 안내 '확정 금액과 근무 예정 수입이 여기에 표시돼요'.
//   DU_BEFORE_OBSERVE=398(before, 원 제품): B 안내 raw=false — 낱말 분절 정확 1(수→입), N raw=true. 그 밖 계약은 두 모드 모두 엄격.
//   strict(after): B/N 분절 0. 공통: 가시 글자 가로 초과 0 · 말줄임 0 · 줄 수 B 2 / N 1(사전 기대) · 글자 12 · textSecondary · 가운데 ·
//     제목 위 · 비겹침 · 표 행(근무 완료/예상 수입) 0 · 원문 semantics label 정확 1 · WJ 넣은 변형 label 0 · viewport/화면 안 · 넘침/예외 0.
//   측정(로컬): 가시 글자 = U+0020 · U+00A0 · 개행 · U+2060 · U+200B 아닌 글자. 줄 전환 사이 원문에 개행/U+0020 이면 허용, 그 밖은 분절.
//     공백 상자 가로 초과는 기록만(DU397 수리 규칙). 세로 기록. 카드 높이는 기록하고 TB/TA 비교는 실행 뒤 별도 대조.
//   누르지 않는다(수입 상세 · 날짜 · 일자리 등 목적지 0).
// ignore_for_file: depend_on_referenced_packages
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';
import 'support/checkin_contract_fixture.dart';

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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 9), totalWorkDays: 3);
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

// 기준 2026-11-08 KST 10:00 = UTC 01:00(env 와 무관하게 고정)
final DateTime _clock = DateTime.utc(2026, 11, 8, 1);

final _calls = <String, int>{};
void _hit(String k) => _calls[k] = (_calls[k] ?? 0) + 1;

UserHomeReads _reads() {
  Future<List<ApplicationModel>>? last;
  return UserHomeReads(
    slotsForTO: (_) async {
      _hit('slotsForTO');
      return const <SlotModel>[];
    },
    myContracts: (_) async {
      _hit('myContracts');
      return completedContractsFor(await (last ?? Future.value(const <ApplicationModel>[])));
    },
    myApplications: (_) {
      _hit('myApplications');
      return last = Future.value(const <ApplicationModel>[]);
    },
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
      _hit('myMonthlyAttendances');
      return const [];
    },
    publishedTOs: () async {
      _hit('publishedTOs');
      return const [];
    },
    pendingIdCardRequests: (_) async {
      _hit('pendingIdCardRequests');
      return const [];
    },
    myRenewalProposals: () async {
      _hit('myRenewalProposals');
      return const <RenewalProposalModel>[];
    },
    businessById: (_) async {
      _hit('businessById');
      return BusinessModel(
          id: 'biz1', name: '강남 물류센터', ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
          category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime.utc(2026, 4, 22));
    },
    invalidatePublishedTOsCache: () => _hit('invalidatePublishedTOsCache'),
    documentCorrections: () async {
      _hit('documentCorrections');
      return DocumentCorrectionSurface.empty;
    },
    legalReadiness: () async {
      _hit('legalReadiness');
      return const LegalReadiness(status: LegalReadinessStatus.current);
    },
  );
}

// VQ _loadFonts 와 같은 등록(NotoSansKR · 'Roboto'/'FlutterTest' 이름 대체 · SDK MaterialIcons) — 같은 측정 환경
Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    final l = FontLoader(fam)
      ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf'));
    await l.load();
  }
  final testDefault = FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'));
  await testDefault.load();
  final icons = FontLoader('MaterialIcons')..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

const _title = '아직 표시할 수입 금액이 없어요';
const _guide = '확정 금액과 근무 예정 수입이 여기에 표시돼요';
final String _wjChar = String.fromCharCode(0x2060);
// WJ 를 넣은 변형(제품 TextLayout 미사용, 독립 구성): 공백으로 나눈 낱말의 글자 사이에 WJ
final String _guideWj = _guide.split(' ').map((w) => w.split('').join(_wjChar)).join(' ');

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '398';
final String _manifest = Platform.environment['DU398_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST', 'DU401_MANIFEST', 'DU398_MANIFEST', 'DU296_PHASE'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _wj = '\u2060';
const _zw = '\u200B';
const _nb = '\u00A0';
bool _visible(String ch) => ch != ' ' && ch != _nb && ch != '\n' && ch != _wj && ch != _zw;
String _hx(String s) => s.codeUnits.map((u) => u.toRadixString(16)).join('.');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

/// 로컬 조판 측정(DU400 과 같은 규칙). bad · glyphX 실패 목록, blankX · yOver 기록, 줄별 원문.
({int glyphs, int lines, int nl, int sp, List<String> bad, List<String> glyphX, List<String> blankX, double yOver, bool ell, List<String> rows}) _measure(
    RenderParagraph rp) {
  final s = rp.text.toPlainText();
  final w = rp.size.width;
  final h = rp.size.height;
  final tops = <double>[];
  final rows = <String>[];
  final bad = <String>[];
  final glyphX = <String>[];
  final blankX = <String>[];
  var glyphs = 0, nl = 0, sp = 0;
  var yOver = 0.0;
  int? prevI;
  double? prevTop;
  var cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final b = bx.first;
    if ((b.right - b.left).abs() < 0.01) continue;
    final xOut = b.right > w + 0.5 || b.left < -0.5;
    if (xOut && (ch == ' ' || ch == _nb)) blankX.add('$i:${_hx(ch)}:${b.left.toStringAsFixed(2)}-${b.right.toStringAsFixed(2)}');
    if (!_visible(ch)) {
      if (ch == ' ' || ch == _nb) cur.write(' ');
      continue;
    }
    if (xOut) glyphX.add('$i:${_hx(ch)}:${b.left.toStringAsFixed(2)}-${b.right.toStringAsFixed(2)}');
    yOver = math.max(yOver, math.max(-b.top, b.bottom - h));
    glyphs++;
    if (prevTop != null && (b.top - prevTop).abs() > 1.0) {
      rows.add(cur.toString());
      cur = StringBuffer();
      final between = s.substring(prevI! + 1, i);
      if (between.contains('\n')) {
        nl++;
      } else if (between.contains(' ')) {
        sp++;
      } else {
        bad.add('$i[${_hx(s[prevI])}→${_hx(ch)} 사이=${_hx(between)}]');
      }
    }
    cur.write(ch);
    if (!tops.any((x) => (x - b.top).abs() <= 1.0)) tops.add(b.top);
    prevI = i;
    prevTop = b.top;
  }
  rows.add(cur.toString());
  return (glyphs: glyphs, lines: tops.length, nl: nl, sp: sp, bad: bad, glyphX: glyphX, blankX: blankX, yOver: yOver, ell: rp.didExceedMaxLines, rows: rows);
}

Finder _vis(String text) => find.byWidgetPredicate(
    (w) => w is Text && visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') == text,
    skipOffstage: false);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'onboarding_completed_u1': true, 'tour_completed_user_home': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  for (final c in const [
    (id: 'B', w: 320.0, h: 640.0, s: 2.0, lines: 2, name: 'S080Z-B 0수입 안내 320x640@2.0 — 낱말·원문 의미·가로·말줄임·카드 보존'),
    (id: 'N', w: 390.0, h: 844.0, s: 1.0, lines: 1, name: 'S080Z-N 0수입 안내 390x844@1.0 — 낱말·원문 의미·가로·말줄임·카드 보존'),
  ]) {
    testWidgets(c.name, (t) async {
      final tok = 'S080Z-${c.id}';
      final mode = _before ? 'before' : 'strict';
      _out('D398 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
      _calls.clear();
      final sem = t.ensureSemantics();
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final screen = Offset.zero & Size(c.w, c.h);
      bool inRect(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
      void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      final key = GlobalKey();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: _Worker()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              locale: const Locale('ko', 'KR'),
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: UserHomeScreen(reads: _reads(), clock: () => _clock)),
        ),
      ));
      await settle(25);
      must('locale ko_KR', Localizations.localeOf(t.element(find.byType(UserHomeScreen))) == const Locale('ko', 'KR'));
      final titleF = _vis(_title);
      final guideF = _vis(_guide);
      must('0수입 제목 정확 1 · 안내 정확 1', titleF.evaluate().length == 1 && guideF.evaluate().length == 1,
          '${titleF.evaluate().length}/${guideF.evaluate().length}');
      must('표 행(근무 완료 · 예상 수입) 0 — 확정 0 · 예정 0', _vis('근무 완료').evaluate().isEmpty && _vis('예상 수입').evaluate().isEmpty);
      // 본문 세로 Scrollable(가장 큰 것) — 카드까지 실제 이동
      final all = find.byType(Scrollable);
      final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
          .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
          .toList()
        ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
      must('본문 세로 Scrollable', cands.isNotEmpty);
      final body = cands.first;
      final pos = t.state<ScrollableState>(body).position;
      final px0 = pos.pixels;
      await t.ensureVisible(guideF);
      await settle(6);
      final vp = t.getRect(body);
      final tr = t.getRect(titleF);
      final gr = t.getRect(guideF);
      _out('D398 $tok scroll from=${px0.toStringAsFixed(1)} to=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} vp=$vp');
      must('제목 · 안내 본문 viewport · 화면 안', inRect(vp, tr) && inRect(vp, gr) && inRect(screen, tr) && inRect(screen, gr), '$tr $gr $vp');
      final ov = tr.intersect(gr);
      must('제목 위 · 안내 아래 · 비겹침', tr.bottom <= gr.top + 0.5 && !(ov.width > 0.5 && ov.height > 0.5), '$tr / $gr');
      final gw = t.widget<Text>(guideF);
      final gStyle = gw.style;
      must('안내 글자 12 · textSecondary · 가운데', gStyle?.fontSize == 12 && gStyle?.color == AppColors.textSecondary && gw.textAlign == TextAlign.center,
          '${gStyle?.fontSize} ${gStyle?.color} ${gw.textAlign}');
      final shown = visibleText(gw.data ?? '');
      must('안내 표시 문자열(보이는 글자) = 원문', shown == _guide);
      if (_before) {
        must('before: 원 제품 — semanticsLabel 없음 · 원문 그대로', gw.semanticsLabel == null && gw.data == _guide);
      } else {
        must('strict: 원문 semanticsLabel · 표시는 낱말 묶기', gw.semanticsLabel == _guide && gw.data != _guide);
      }
      final semExact = find.bySemanticsLabel(_guide).evaluate().length;
      final semWj = find.bySemanticsLabel(_guideWj).evaluate().length;
      _out('D398 $tok semantics exact=$semExact wjVariant=$semWj label=${gw.semanticsLabel == null ? 'null' : 'set'} keep=${gw.data != _guide}');
      must('원문 semantics label 정확 1 · WJ 변형 label 0', semExact == 1 && semWj == 0, '$semExact/$semWj');
      final rp = t.renderObject<RenderParagraph>(find.descendant(of: guideF, matching: find.byType(RichText), matchRoot: true).first);
      final m = _measure(rp);
      final card = find.ancestor(of: guideF, matching: find.byType(Container)).first;
      final cr = t.getRect(card);
      _out('D398 $tok measure glyphs=${m.glyphs} lines=${m.lines} nl=${m.nl} sp=${m.sp} bad=${m.bad} glyphX=${m.glyphX} blankX=${m.blankX} '
          'yOver=${m.yOver.toStringAsFixed(3)} ell=${m.ell} rows=${m.rows.join('|')} para=${rp.size.width.toStringAsFixed(2)}x${rp.size.height.toStringAsFixed(2)}');
      _out('D398 $tok card h=${cr.height.toStringAsFixed(2)} w=${cr.width.toStringAsFixed(2)} rect=$cr guide=$gr title=$tr');
      must('가시 글자 가로 경계 안', m.glyphX.isEmpty, '${m.glyphX}');
      must('말줄임 0', !m.ell);
      must('줄 수 사전 기대 ${c.lines}', m.lines == c.lines, '${m.lines} ${m.rows}');
      if (_before && c.id == 'B') {
        must('before B: 낱말 분절 정확 1 = 수→입(raw=false)', m.bad.length == 1 && m.bad.first.contains('c218→c785'), '${m.bad}');
      } else {
        must('낱말 분절 0(raw=true)', m.bad.isEmpty, '${m.bad}');
      }
      await vqCapture(t, key, '${tok}_card', conditions: {
        'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'fixture': '2026-11-08 · 조회 성공 · 확정 0 · 예정 0', 'mode': mode,
        'run': vqRun, 'manifest': _manifest, 'state': '0수입 카드(안내 ${m.lines}줄 · 분절 ${m.bad.length})', 'card_h': cr.height.toStringAsFixed(2)});
      final callsStr = (_calls.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}:${e.value}').join(',');
      final exc = t.takeException();
      _out('D398 $tok done mode=$mode lines=${m.lines} bad=${m.bad.length} glyphX=${m.glyphX.length} ell=${m.ell} semExact=$semExact semWj=$semWj '
          'card_h=${cr.height.toStringAsFixed(2)} reads=$callsStr overflows=${overflows.length} exc=${exc != null}');
      sem.dispose();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tok 넘침');
    });
  }
}
