// [impl_64 · 판정296 P2] 근로자 탈퇴 — 서버 미리보기의 경고(warnings)를 근로자가 보고 탈퇴한다.
//   예전: 비밀번호 · 카카오 두 경로 모두 hardBlocks 만 읽고 warnings 를 버렸다(미서명 계약 무효 · 진행 중 장기 근무 안내 0).
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/screens/common/deletion_reauth_screen.dart';
import 'package:ALfit/services/auth/deletion_reauth_api.dart';
import 'package:ALfit/services/pass_verification_service.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/utils/withdraw_preview.dart';

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

class _DelApi implements DeletionReauthApi {
  int starts = 0;
  @override
  Future<DeletionReauthTicket> start() async {
    starts++;
    return const DeletionReauthTicket(requestId: 'del_req_1');
  }

  @override
  Future<DateTime?> verify(String impUid) async => DateTime.now().add(const Duration(minutes: 10));
}

String _code(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('미리보기 해석', () {
    test('경고 · 차단을 나누고 근로자 문구로 바꾼다', () {
      final p = WithdrawPreview.fromData({
        'hardBlocks': <Object?>[],
        'warnings': [
          {'type': 'UNSIGNED_CONTRACT', 'count': 1},
          {'type': 'CONFIRMED_WORK', 'count': 2},
        ],
      });
      expect(p.hardBlocks, isEmpty);
      expect(p.warningLines, [
        '서명하지 않은 계약서 1건 — 탈퇴하면 무효 처리되고 사업주에게 알려요',
        '진행 중인 장기 근무 2건 — 탈퇴 전에 관리자에게 퇴사 신청을 권장해요',
      ]);
    });

    test('모르는 경고 유형도 숨기지 않는다 · 차단 문구(PENDING_WAGES 포함)', () {
      expect(withdrawWarningLabel({'type': 'NEW_KIND', 'count': 3}), contains('3건'));
      expect(withdrawHardBlockMessage({'type': 'PENDING_WAGES', 'count': 2}), contains('받지 못한 급여(2건)'));
      expect(withdrawHardBlockMessage({'type': 'SUBADMIN_MEMBERSHIP', 'count': 1}), contains('직책 해제'));
      expect(WithdrawPreview.fromData(null).warnings, isEmpty);
    });
  });

  testWidgets('카카오(KG) 탈퇴 확인창에 서버 경고가 함께 보인다', (t) async {
    final api = _DelApi();
    await t.pumpWidget(MaterialApp(
      home: DeletionReauthScreen(
        intent: DeletionReauthIntent.withdraw,
        api: api,
        precheck: () async => null,
        warningsLoader: () async => ['서명하지 않은 계약서 1건 — 탈퇴하면 무효 처리되고 사업주에게 알려요'],
        kgLauncher: (id) async => const PassLaunchOutcome.canceled(),
        pipeline: () async => null,
        proofKey: 'uid-w',
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == '본인확인하고 탈퇴하기'));
    await t.pump(const Duration(milliseconds: 500));
    final texts = t
        .widgetList<Text>(find.byType(Text))
        .map((x) => TextLayout.plain(x.data ?? x.textSpan?.toPlainText() ?? ''))
        .join('\n');
    expect(texts, contains('탈퇴 전 확인'));
    expect(texts, contains('서명하지 않은 계약서 1건 — 탈퇴하면 무효 처리되고 사업주에게 알려요'));
    expect(api.starts, 0, reason: '확인 전에는 본인확인을 시작하지 않는다');
  });

  test('비밀번호 탈퇴 경로: 비밀번호 전에 미리보기 · 경고 확인창 · 차단 멈춤(원문 보조)', () {
    final c = _code('lib/screens/user/user_settings_screen.dart');
    final i = c.indexOf('Future<void> _handleDeleteAccount()');
    final body = c.substring(i, c.indexOf('// ── 빌드', i));
    final preview = body.indexOf('preview = await fetchWithdrawPreview();');
    final password = body.indexOf('builder: (ctx) => const _WithdrawPasswordDialog()');
    expect(preview, greaterThan(0));
    expect(password, greaterThan(preview), reason: '미리보기가 비밀번호보다 먼저');
    expect(body.contains("title: '탈퇴 전 확인'"), isTrue);
    expect(body.contains('ToastHelper.showError(withdrawHardBlockMessage(preview.hardBlocks.first));'), isTrue);
    expect(body.contains('preview.warnings.isNotEmpty'), isTrue);
  });
}
