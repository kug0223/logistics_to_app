// ignore_for_file: depend_on_referenced_packages
// [DU434 · 자체 판정 셀 · 표시만] S073 내 일정 — 근무 가능일 수정 화면 하단 '{n}일 저장' 채움 info(흰 글자 3.12) → brand(5.58).
//   같은 화면 머리 행동 '가능일 설정'이 이미 brand 다([DU311 B3] info 계열 아님). DU311 은 편집 바 '저장 · 취소'를 무변경으로 남겼다(V10).
//   before = 현재 A(my_schedule_screen c123df13 = DU311 AB3) / strict = 후보(001222f0, 채움 색 1줄).
//   host: production MyScheduleScreen(reads: LOCAL MyScheduleReads)(du1_c3_s073 시험과 같은 seam).
//     - 가능일 {Q = KST 내일, U = 모레} 정상 응답 → '가능일 설정' 탭 → 수정 화면 → 하단 바 측정.
//     - 저장은 누르지 않는다. Functions/Firestore 채널은 전부 차단 · 계수해 쓰기 0 을 단언한다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du434-tb/DU_BEFORE_OBSERVE=434 · TA after/du434-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

const kUid = 'worker-local-434';

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid, username: 'worker', name: 'QA 근로자', email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '434';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du434-tb' && _env['DU_BEFORE_OBSERVE'] == '434') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du434-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f2(double v) => v.toStringAsFixed(2);

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'brand': AppColors.brand, 'info': AppColors.info, 'infoDark': AppColors.infoDark,
  'textSecondary': AppColors.textSecondary, 'grey300': AppColors.grey300,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
}

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 글자 뒤 채움색 — 가장 가까운 불투명 Material(버튼 면) · BoxDecoration 색.
Color? _fillBehind(Element e) {
  Color? c;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Material && w.color != null && w.color!.a > 0) {
      c = w.color;
      return false;
    }
    if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
      c = (w.decoration! as BoxDecoration).color;
      return false;
    }
    return true;
  });
  return c;
}

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── KST 날짜 고정(du1_c3_s073 과 같은 식) ──
  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  DateTime kstMidnight(int plus) => DateTime.utc(kNow.year, kNow.month, kNow.day + plus).subtract(const Duration(hours: 9));
  final qKey = WorkerAvailabilityModel.dateKeyFrom(kstMidnight(1));
  final uKey = WorkerAvailabilityModel.dateKeyFrom(kstMidnight(2));

  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          inc('myApplications');
          return const <ApplicationModel>[];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          inc('myMonthlyAttendances');
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          inc('myAvailability');
          return WorkerAvailabilityModel(uid: uid, dates: [qKey, uKey], city: '송파구');
        },
        invitePreference: (uid) async {
          inc('invitePreference');
          return const InviteRegionPreference(enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );
  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      inc('BLOCKED functions ${args['functionName']}');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du434-blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete',
      'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        inc('BLOCKED firestore $op');
        return null;
      });
    }
  }

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S073SF-${v.id}-EDIT 근무 가능일 수정 — 하단 저장 버튼 채움 · 글자 대비 · 취소 유지 · 쓰기 0', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S073SF-${v.id}-EDIT';
        final mode = _before ? 'before' : 'strict';
        _out('D434 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        calls.clear();
        stubChannels();
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

        final key = GlobalKey();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: MyScheduleScreen(reads: reads()),
            ),
          ),
        ));
        for (var r = 0; r < 4; r++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D434 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'EDIT',
            'state': state,
          });
          shots++;
        }

        // ── 수정 화면으로 ──
        final cta = find.text('가능일 설정');
        must('가능일 설정 행동 1', cta.evaluate().length == 1, '${cta.evaluate().length}개');
        await t.tap(cta.first);
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final editTitle = find.text('근무 가능일 선택');
        final saveF = find.text('2일 저장');
        final cancelF = findVisibleText('취소');
        must('수정 화면 · 저장 · 취소', editTitle.evaluate().length == 1 && saveF.evaluate().length == 1 && cancelF.evaluate().length == 1,
            '제목 ${editTitle.evaluate().length} 저장 ${saveF.evaluate().length} 취소 ${cancelF.evaluate().length}');
        await shot('1edit', 'edit-mode');

        // ── 하단 바 측정(값은 즉시) ──
        final saveRich = find.descendant(of: saveF, matching: find.byType(RichText), matchRoot: true);
        final saveText = (t.widget(saveRich.first) as RichText).text.style?.color;
        final saveFill = _fillBehind(saveRich.evaluate().first);
        final saveCr = _cr(saveText, saveFill);
        final saveR = t.getRect(find.ancestor(of: saveF, matching: find.byType(ElevatedButton)).first);
        final cancelR = t.getRect(find.ancestor(of: cancelF, matching: find.byType(OutlinedButton)).first);
        final cancelText = (t.widget(find.descendant(of: cancelF, matching: find.byType(RichText), matchRoot: true).first) as RichText).text.style?.color;
        final inView = saveR.bottom <= v.h + 0.5 && cancelR.bottom <= v.h + 0.5 && saveR.top >= 0 && cancelR.top >= 0;
        final sameRow = (saveR.center.dy - cancelR.center.dy).abs() <= 0.5;
        final writes = calls.keys.where((k) => k.startsWith('BLOCKED')).toList();
        _out('D434 $tok att save fill=${_tok(saveFill)} text=${_tok(saveText)} cr=${_f2(saveCr)} h=${_f2(saveR.height)} w=${_f2(saveR.width)} '
            'cancelText=${_tok(cancelText)} cancelH=${_f2(cancelR.height)} inView=$inView sameRow=$sameRow writes=${writes.length}');

        must('하단 바 화면 안 · 한 줄', inView && sameRow, '$inView $sameRow');
        must('쓰기 0(저장 미탭 · 채널 차단)', writes.isEmpty, '쓰기 $writes');
        if (_before) {
          // 음성 기대 — base 저장 채움은 info(#2196F3) · 흰 글자 3.12(코드 확정 · DU311 V10 무변경).
          must('before 저장 대비 미달 검출', saveFill == AppColors.info && saveCr < 4.5, '${_tok(saveFill)} ${_f2(saveCr)}');
        } else {
          must('strict 저장 brand · 흰 글자 · 대비 ≥ 4.5', saveFill == AppColors.brand && saveText == const Color(0xFFFFFFFF) && saveCr >= 4.5,
              '${_tok(saveFill)} ${_tok(saveText)} ${_f2(saveCr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D434 $tok done state=EDIT mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
