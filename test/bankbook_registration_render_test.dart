// [R7-APPLICANT-DOCUMENT-REGISTRATION.1 §6] 급여정보(통장사본) 카드 — **실제 렌더**.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   통장 등록 상태는 세 가지이고(미등록 / 계좌만 / 계좌+통장사본) 화면이
//   각각 **다른 문장**을 말한다. 그 문장이 좁은 화면과 큰 글씨에서 잘리면
//   지원자는 자기가 무엇을 더 해야 하는지 알 수 없다 — 특히 '계좌만' 상태는
//   "미등록"으로 보이면 이미 한 일을 또 하게 만든다(BANKBOOK-UX-01 이 그 사건).
//
//   그래서 소스 문자열 검사로 끝내지 않고 세 상태 × 320/360/411dp ×
//   textScale 1.0/1.3/2.0 을 모두 pump 해서 **넘침 없이 읽히는지** 본다.
//
// ── 이 테스트가 보지 않는 것 ────────────────────────────────────────
//   OCR 인식 정확도(실제 이미지)와 Storage 업로드는 범위 밖이다. 그쪽은
//   기존 E9A/E9C/E11 계약 테스트와 실기기 검증이 담당한다.
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/document_management_screen.dart';

// Firebase 플랫폼 double — 화면이 필드로 잡는 StorageService 때문에
//   storageBucket 이 반드시 있어야 본문이 빌드된다(DDT 하네스와 같은 이유).
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
        apiKey: 'k',
        appId: 'a',
        messagingSenderId: 's',
        projectId: 'p',
        storageBucket: 'p.appspot.com',
      );
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 등록 상태 세 가지.
enum _BankState {
  /// 은행·계좌·통장사본 모두 없음
  none,

  /// 계좌는 등록, 통장사본 미제출 — '미등록'으로 보이면 안 되는 상태
  accountOnly,

  /// 계좌 + 통장사본 모두 등록
  complete,
}

class _UserDouble extends UserProvider {
  _UserDouble(this.state);

  final _BankState state;

  @override
  UserModel? get currentUser {
    final hasAccount = state != _BankState.none;
    final hasBankbook = state == _BankState.complete;
    return UserModel(
      uid: 'u1',
      username: 'u1',
      name: '김근로',
      email: 'u1@alfit.local',
      role: UserRole.USER,
      accountStatus: 'active',
      isIdVerified: true,
      idCardImagePath: 'id_cards/u1/id.jpg',
      bankName: hasAccount ? '중소기업은행' : null,
      accountNumber: hasAccount ? '123456789012' : null,
      accountHolder: hasAccount ? '김근로' : null,
      bankbookImagePath: hasBankbook ? 'bankbooks/u1/bb.jpg' : null,
    );
  }

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

Future<void> _pump(
  WidgetTester tester, {
  required _BankState state,
  required double width,
  required double textScale,
}) async {
  // 높이는 넉넉히 — 세로 스크롤 가능 여부가 아니라 **가로 넘침**을 본다.
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: _UserDouble(state),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const DocumentManagementScreen(),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 넘침은 예외로 기록된다 — 조용히 지나가지 않게 모아서 본다.
void _expectNoOverflow(WidgetTester tester, String label) {
  final err = tester.takeException();
  expect(err, isNull, reason: '$label — 렌더 예외(넘침 포함): $err');
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
  });

  const widths = [320.0, 360.0, 411.0];
  const scales = [1.0, 1.3, 2.0];

  group('§6 급여정보 카드 렌더 — 세 상태 × 3폭 × 3배율', () {
    for (final state in _BankState.values) {
      for (final w in widths) {
        for (final s in scales) {
          testWidgets('${state.name} · ${w.toInt()}dp · x$s 넘침 없음',
              (tester) async {
            await _pump(tester, state: state, width: w, textScale: s);
            _expectNoOverflow(tester, '${state.name}/${w.toInt()}dp/x$s');
          });
        }
      }
    }
  });

  group('§3 상태별로 다른 문장을 말한다', () {
    testWidgets('계좌만 등록 — 통장사본이 남았다고 말한다 (미등록이라고 하지 않는다)',
        (tester) async {
      await _pump(tester,
          state: _BankState.accountOnly, width: 360, textScale: 1.0);
      _expectNoOverflow(tester, 'accountOnly/360dp/x1.0');
      expect(find.textContaining('통장사본 등록 필요'), findsWidgets,
          reason: '계좌만 등록된 상태는 남은 할 일을 말해야 한다');
      expect(find.textContaining('은행 · 계좌 · 예금주 · 통장사본'), findsNothing,
          reason: '이미 등록한 계좌가 있는데 처음부터 안내하면 한 일을 또 하게 된다');
    });

    testWidgets('미등록 — 무엇을 등록해야 하는지 모두 말한다', (tester) async {
      await _pump(tester, state: _BankState.none, width: 360, textScale: 1.0);
      _expectNoOverflow(tester, 'none/360dp/x1.0');
      expect(find.textContaining('은행 · 계좌 · 예금주 · 통장사본'), findsWidgets);
    });

    testWidgets('완료 — 은행명을 말하고 남은 할 일을 말하지 않는다', (tester) async {
      await _pump(tester,
          state: _BankState.complete, width: 360, textScale: 1.0);
      _expectNoOverflow(tester, 'complete/360dp/x1.0');
      expect(find.textContaining('통장사본 등록 필요'), findsNothing,
          reason: '제출을 마친 사람에게 남은 일이 있다고 말하면 안 된다');
      expect(find.textContaining('중소기업은행'), findsWidgets);
    });
  });

  group('§6 가장 좁고 가장 큰 글씨에서도 세로로 도달한다', () {
    testWidgets('320dp · x2.0 — 스크롤 가능한 본문', (tester) async {
      await _pump(tester,
          state: _BankState.accountOnly, width: 320, textScale: 2.0);
      _expectNoOverflow(tester, 'accountOnly/320dp/x2.0');
      expect(find.byType(Scrollable), findsWidgets,
          reason: '큰 글씨에서 내용이 길어지면 스크롤로 도달해야 한다');
    });
  });
}
