// ignore_for_file: depend_on_referenced_packages
// [DU1 후속127 C124-2] 초대 수락 확인창의 공통 AttendanceRuleGuideView '시간 예시 보기/접기' 토글 — 실제 소비처 장면 관측(LOCAL).
//   소비처: MyApplicationsScreen(reads: LOCAL) → 초대 카드 '수락하기' 실제 tap → 수락 확인창(_acceptInvite) 안 _attendancePolicyBlock(grey50 상자).
//   '수락하기' 는 확인창만 연다. 확인창의 수락/거절/저장 버튼은 누르지 않는다(writer 없음). 토글은 화면 안 상태(_showExamples)만 바꾼다.
//   fixture 는 test/disclosure_four_screen_render_test.dart 의 [F] 그룹과 같은 합성값을 옮겼다(원 줄: _FakeApp/_FakeCore 61~84, _standard 87~95,
//     _Worker 181~217, _kstInstant/_futureKstDay 219~227, _to 255~273, invite 555~582, reads 584~606). 실제 개인정보·DEV·원격 없음.
//   그 계약 시험과 달리 이 파일은 RepaintBoundary·workerTheme·ko_KR delegates·vqLoadFonts 근사로 PNG 를 남긴다(장면 관측용). 시계 주입 없음 —
//     초대 날짜는 실행일 기준 미래(_futureKstDay)라 수락 가능 상태가 유지된다.
//   단언은 확인창 도달·토글 1개·표시 영역 도달·tap 뒤 접기 1개·접기 tap 뒤 보기 1개(재접힘)·overflow 0·예외 없음뿐이다. 색·바탕·hit·rect 는 관측 줄이다.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
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
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 기본 설정 — 유예 5분 · 단위 30분(disclosure 시험 _standard 와 같은 값).
AttendanceRules _standard() => AttendanceRules.defaults().copyWith(
      earlyWindow: 30,
      earlyArrivalUnit: 30,
      lateGrace: 5,
      lateUnit: 30,
      lateWindow: 30,
      overtimeUnit: 30,
      earlyLeaveUnit: 30,
    );

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 1, 1),
        isIdVerified: true,
        idCardImagePath: 'users/u1/id.png',
        bankName: '테스트은행',
        accountNumber: '0000000000',
        accountHolder: '김근로',
        bankbookImagePath: 'users/u1/bankbook.png',
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

DateTime _kstInstant(int y, int mo, int d) => DateTime.utc(y, mo, d).subtract(const Duration(hours: 9));

DateTime _futureKstDay(int plusDays) {
  final k = DateTime.now().toUtc().add(Duration(hours: 9, days: plusDays));
  return _kstInstant(k.year, k.month, k.day);
}

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '중앙물류센터',
      type: 'flex',
      title: '냉장 분류 단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

ApplicationModel _invite(AttendanceRules policy) => ApplicationModel(
      id: 'inv1',
      uid: 'u1',
      toId: 'to1',
      slotId: 's1',
      businessId: 'biz1',
      businessName: '중앙물류센터',
      toTitle: '냉장 분류 단기 모집',
      selectedWorkType: '냉장 분류',
      wdId: 'wd1',
      startTime: '18:00',
      endTime: '22:30',
      wage: 53000,
      wageType: 'daily',
      status: 'INVITED',
      workDate: _futureKstDay(3),
      appliedAt: _futureKstDay(-5),
      invitedAt: _futureKstDay(-1),
      workInstanceCapacityState: InviteCapacityState.available,
      inviteAcceptReadiness: InviteAcceptReadiness.ready,
      attendancePolicySnapshot: policy,
    );

MyApplicationsReads _reads(List<ApplicationModel> apps) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (toId) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('C124-2-INV 초대 수락 확인창 390×844 ko_KR — 시간 예시 토글 접힘·펼침·접기 프레임·재접힘', (t) async {
    await t.runAsync(vqLoadFonts);
    final overflows = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prevOnError?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    final key = GlobalKey();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.workerTheme,
          locale: const Locale('ko', 'KR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          home: MyApplicationsScreen(reads: _reads([_invite(_standard())])),
        ),
      ),
    ));
    Future<void> settle([int n = 14]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    await settle(20);
    void log(String l) {
      // ignore: avoid_print
      print('C124-2-INV $l');
    }
    bool hits(Finder f, Offset p) {
      final r = HitTestResult();
      WidgetsBinding.instance.hitTestInView(r, p, t.view.viewId);
      return r.path.any((e) => e.target == t.renderObject(f));
    }
    String hex(Color? c) => c == null ? 'null' : '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final accept = find.text('수락하기');
    expect(accept, findsWidgets, reason: '초대 카드의 수락하기가 있다');
    log('[목록] 수락하기 ${accept.evaluate().length}개 · 첫 rect ${t.getRect(accept.first)}');
    await t.tap(accept.first);
    await settle(30);
    final dlg = find.byType(Dialog);
    expect(dlg, findsOneWidget, reason: '수락 확인창이 열린다');
    final dr = t.getRect(dlg);
    log('[확인창] Dialog $dr');
    final dScroll = find.descendant(of: dlg, matching: find.byType(Scrollable));
    final vp = dScroll.evaluate().isEmpty ? dr : t.getRect(dScroll.first);
    log('[확인창] 스크롤 ${dScroll.evaluate().length}개 · 표시 영역 $vp');
    bool inView(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    Color? bgOf(Finder f) {
      Color? c;
      t.element(f).visitAncestorElements((e) {
        final w = e.widget;
        if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null) {
          c = (w.decoration as BoxDecoration).color;
          return false;
        }
        if (w is ColoredBox) {
          c = w.color;
          return false;
        }
        return true;
      });
      return c;
    }
    void describe(String scene, String label) {
      final txt = find.text(label);
      if (txt.evaluate().isEmpty) {
        log('[$scene] "$label" 없음');
        return;
      }
      final btn = find.ancestor(of: txt, matching: find.byType(TextButton)).first;
      final br = t.getRect(btn);
      final tr = t.getRect(txt);
      final st = (t.renderObject(txt) as RenderParagraph).text.style;
      log('[$scene] "$label" TextButton $br ${br.width.toStringAsFixed(1)}×${br.height.toStringAsFixed(1)} hit=${hits(btn, br.center)}'
          ' · 글 $tr 색 ${hex(st?.color)} 명목 ${st?.fontSize} w${st?.fontWeight?.value} · 가장 가까운 칠한 바탕 ${hex(bgOf(txt))} · 표시영역 안=${inView(tr)}');
    }
    void paragraphs(String scene) {
      var n = 0;
      for (final p in t.renderObjectList<RenderParagraph>(find.descendant(of: dlg, matching: find.byType(RichText)))) {
        final txt = p.text.toPlainText().replaceAll('⁠', '').replaceAll('\n', '⏎');
        if (txt.trim().isEmpty) continue;
        final g = p.localToGlobal(Offset.zero);
        if (g.dy + p.size.height < vp.top || g.dy > vp.bottom) continue;
        n++;
        final st = p.text.style;
        final head = txt.length > 36 ? '${txt.substring(0, 36)}…' : txt;
        log('[$scene] P$n "$head" at=(${g.dx.toStringAsFixed(1)},${g.dy.toStringAsFixed(1)})'
            ' ${p.size.width.toStringAsFixed(1)}×${p.size.height.toStringAsFixed(1)} 색 ${hex(st?.color)} 명목 ${st?.fontSize} w${st?.fontWeight?.value}');
      }
      log('[$scene] 표시 영역 글 문단 $n');
    }
    Map<String, Object?> sidecar(String scene) => {
          'screen': 'MyApplicationsScreen(reads: LOCAL _reads([_invite(_standard())])) → 수락하기 실제 tap → 수락 확인창(_attendancePolicyBlock) — USER, 초대 snapshot 18:00~22:30',
          'locale': 'requested=ko_KR · Global delegates', 'theme': 'RoleTheme.workerTheme', 'viewport': '390x844', 'dpr': 1.0, 'textScaler': 1.0, 'inset': '0',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
          'clock': '주입 없음 — 초대 날짜는 실행일 기준 미래(_futureKstDay), 실행 ${DateTime.now().toUtc().toIso8601String()}',
          'baseDate(DU1_VQ_DATE)': Platform.environment['DU1_VQ_DATE'] ?? 'now', 'scene': scene};
    Future<int> dragUntil(Finder f) async {
      var k = 0;
      while (!inView(t.getRect(f)) && k < 40 && dScroll.evaluate().isNotEmpty) {
        await t.dragFrom(Offset(vp.center.dx, vp.center.dy + 60), const Offset(0, -120));
        await settle(8);
        k++;
      }
      return k;
    }
    final toggle = find.text('시간 예시 보기');
    expect(toggle, findsOneWidget, reason: 'snapshot 규칙·근무 시각이 있으면 접힌 사례 토글이 있다');
    final k = await dragUntil(toggle);
    expect(inView(t.getRect(toggle)), isTrue, reason: '확인창 안 실제 drag 로 토글이 표시 영역에 든다');
    log('[접힘] drag=$k');
    describe('접힘', '시간 예시 보기');
    paragraphs('접힘');
    await vqCapture(t, key, 'C124-2-INV_1_collapsed', conditions: sidecar('확인창 안 실제 dragFrom -120 × $k · 토글 접힘'));
    await t.tap(find.widgetWithText(TextButton, '시간 예시 보기'));
    await settle();
    expect(find.text('시간 예시 접기'), findsOneWidget, reason: '토글 tap 뒤 같은 자리에서 펼침');
    describe('펼침', '시간 예시 접기');
    paragraphs('펼침');
    await vqCapture(t, key, 'C124-2-INV_2_expanded', conditions: sidecar('토글 실제 tap 뒤 같은 스크롤 · 펼침'));
    final fold = find.text('시간 예시 접기');
    final e = await dragUntil(fold);
    log('[펼침 접기] drag=$e');
    describe('펼침 접기', '시간 예시 접기');
    paragraphs('펼침 접기');
    await vqCapture(t, key, 'C124-2-INV_3_expanded_fold', conditions: sidecar('펼침 뒤 실제 dragFrom -120 × $e · 접기 토글 표시 영역'));
    await t.tap(find.widgetWithText(TextButton, '시간 예시 접기'));
    await settle();
    expect(find.text('시간 예시 보기'), findsOneWidget, reason: '접기 tap 뒤 다시 접힘');
    describe('재접힘', '시간 예시 보기');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
