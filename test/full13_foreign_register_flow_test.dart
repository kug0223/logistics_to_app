// [FULL13-REEVAL.3] 외국인 가입(복구 모드) 흐름 — 합성 fixture(LOCAL, 기기 아님).
//
//   실제 화면: 등록증 촬영 → OCR 근거 보관 → 확인 단계에서 이름·번호를 **직접 입력**
//   → 다음 → 가입 확정·업로드 판정 호출. 사진 선택·OCR·Storage·callable 만
//   ForeignRegisterHooks 로 바꾼다. 번호·이름은 합성값이다.

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'support/visible_text.dart'; // [DU1 구현47] keepWords 레이블은 보이는 글자로 찾는다

// 기존 시험(action_context_truth_test)과 같은 가짜 Firebase 앱.
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _ocrNum = '9001015000001';
const _sameFront7 = '9001015999999';
const _ocrName = 'NGUYEN VAN AN';

ForeignIdOcrResult _ocr({String? name = _ocrName, String source = 'LATIN_REGION', String? num = _ocrNum}) =>
    ForeignIdOcrResult(legalName: name, foreignIdRaw: num, visaType: 'E-9',
        legalNameFailed: name == null, foreignIdFailed: num == null, legalNameOcrSource: name == null ? 'NONE' : source);

class _Rec {
  final finalizes = <({String rawId, String legalName, Map<String, dynamic>? ev})>[];
  final marks = <Map<String, dynamic>>[];
  final uploads = <String>[];
}

_Rec _install({ForeignIdOcrResult? ocr, bool ocrThrows = false, bool on = true, Map<String, dynamic>? user}) {
  final r = _Rec();
  ForeignRegisterHooks.pickAndOcr = () async =>
      (path: '/tmp/full13_synthetic_not_exist.jpg', result: ocrThrows ? null : (ocr ?? _ocr()));
  ForeignRegisterHooks.reuseOcr = (_) async => ocr ?? _ocr();
  ForeignRegisterHooks.currentUid = () => 'u1';
  ForeignRegisterHooks.upload = (local, storage) async => r.uploads.add(storage);
  ForeignRegisterHooks.readUser = (_) async => user ?? <String, dynamic>{};
  ForeignRegisterHooks.finalize = (rawId, legalName, koreanName, visa, ev) async {
    r.finalizes.add((rawId: rawId, legalName: legalName, ev: ev));
    return null;
  };
  ForeignRegisterHooks.mark = (p) async => r.marks.add(p);
  ForeignRegisterHooks.collectionEnabled = () => on;
  return r;
}

Future<void> _open(WidgetTester tester, {String? existingPath}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  await tester.pumpWidget(MaterialApp(
      home: ForeignRegisterScreen(role: UserRole.USER, isResume: true, existingIdCardPath: existingPath)));
  await tester.pumpAndSettle();
}

Finder _field(int i) => find.byType(TextFormField).at(i); // 0 영문 이름 · 1 한글 이름 · 2 등록번호 · 3 체류자격
String _text(WidgetTester t, int i) => t.widget<TextFormField>(_field(i)).controller!.text;

Future<void> _pickAndConfirm(WidgetTester tester, {required String name, required String number}) async {
  await tester.tap(findVisibleText('갤러리에서 선택'));
  await tester.pumpAndSettle();
  expect(_text(tester, 0), isEmpty, reason: '영문 이름은 OCR 값으로 채우지 않는다');
  expect(_text(tester, 2), isEmpty, reason: '등록번호는 OCR 값으로 채우지 않는다');
  await _fill(tester, name: name, number: number);
}

Future<void> _fill(WidgetTester tester, {required String name, required String number}) async {
  await tester.enterText(_field(0), name);
  await tester.enterText(_field(2), number);
  if (_text(tester, 3).isEmpty) await tester.enterText(_field(3), 'E-9');
  await tester.pump();
  // 제출 뒤 임시 파일 정리는 실제 IO 다 — 진짜 시계에서 돌린다.
  //   다음 단계의 약관 로딩 표시는 가짜 Firebase 에서 끝나지 않으므로 pumpAndSettle 을 쓰지 않는다.
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(ElevatedButton, '다음'));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

Map<String, dynamic> _sc(_Rec r) => Map<String, dynamic>.from(r.marks.single['selfCheck'] as Map);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(ForeignRegisterHooks.reset);

  testWidgets('01 이름·번호 직접 입력 = 사진 → 이름 MATCHED, 번호 후보 = OCR 값 · 확정에 입력값', (tester) async {
    final r = _install();
    await _open(tester);
    await _pickAndConfirm(tester, name: 'nguyen  van an', number: _ocrNum);
    expect(r.finalizes.single.rawId, _ocrNum);
    expect(r.finalizes.single.legalName, 'nguyen  van an', reason: '입력한 그대로 보낸다');
    expect(r.finalizes.single.ev, isNull, reason: '새 사진은 업로드 판정이 본다');
    expect(r.uploads.single, startsWith('users/u1/idCard_'));
    final sc = _sc(r);
    expect(sc['name'], 'MATCHED', reason: '대소문자·연속 공백만 기존 정규화로 맞춘다');
    expect(sc['identifierCandidates'], [_ocrNum]);
    expect(sc['identifier'], 'UNASSESSED', reason: '번호 판정은 서버가 한다');
    expect(findVisibleText('외국인등록번호 (13자리 숫자 직접 입력)'), findsNothing, reason: '다음 단계로 넘어갔다');
  });

  testWidgets('02 이름 다름(이름 영역에서 읽음) → MISMATCH · 순서 바꾼 이름도 일치가 아니다', (tester) async {
    final r = _install();
    await _open(tester);
    await _pickAndConfirm(tester, name: 'VAN AN NGUYEN', number: _ocrNum);
    expect(_sc(r)['name'], 'MISMATCH');
  });

  testWidgets('03 낮은 신뢰 OCR 이름(FULL_OCR)과 다름 → UNREADABLE(못 읽은 것을 다르다 하지 않음) · 확인 안내 표시', (tester) async {
    final r = _install(ocr: _ocr(name: 'NGUYEN VAM AN', source: 'FULL_OCR'));
    await _open(tester);
    await tester.tap(findVisibleText('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(find.text('카드에 적힌 영문 이름과 동일한지 확인해주세요'), findsOneWidget);
    await _fill(tester, name: _ocrName, number: _ocrNum);
    expect(_sc(r)['name'], 'UNREADABLE');
  });

  testWidgets('04 OCR 이 이름을 못 읽음 → 이름 UNREADABLE(미평가 아님)', (tester) async {
    final r = _install(ocr: _ocr(name: null));
    await _open(tester);
    await _pickAndConfirm(tester, name: _ocrName, number: _ocrNum);
    expect(_sc(r)['name'], 'UNREADABLE');
  });

  testWidgets('05 번호 앞7 같고 뒤6 다르게 입력 → 확정은 입력값, 후보는 사진 값(서버가 MISMATCH)', (tester) async {
    final r = _install();
    await _open(tester);
    await _pickAndConfirm(tester, name: _ocrName, number: _sameFront7);
    expect(r.finalizes.single.rawId, _sameFront7);
    expect(_sc(r)['identifierCandidates'], [_ocrNum]);
    expect(_sc(r)['identifierCandidates'], isNot(contains(_sameFront7)));
  });

  testWidgets('06 수집 OFF → 무판정만(후보·이름 판정 미전송)', (tester) async {
    final r = _install(on: false);
    await _open(tester);
    await _pickAndConfirm(tester, name: _ocrName, number: _ocrNum);
    final sc = _sc(r);
    expect(sc.containsKey('identifierCandidates'), isFalse);
    expect(sc['name'], 'UNASSESSED');
  });

  testWidgets('07 OCR 예외 → 직접 입력 계속, ocrFailed 근거', (tester) async {
    final r = _install(ocrThrows: true);
    await _open(tester);
    await _pickAndConfirm(tester, name: _ocrName, number: _ocrNum);
    final sc = _sc(r);
    expect(sc['ocrFailed'], isTrue);
    expect(sc.containsKey('identifierCandidates'), isFalse);
  });

  testWidgets('08 CASE C(업로드 없이 기존 사진) → 확정에 현재 버전 근거, 업로드 판정 호출 없음', (tester) async {
    final r = _install(user: {'idDocumentVersion': 2});
    await _open(tester, existingPath: 'users/u1/idCard_1700000000001.png');
    expect(_text(tester, 0), isEmpty);
    expect(_text(tester, 2), isEmpty);
    await _fill(tester, name: _ocrName, number: _ocrNum);
    final ev = r.finalizes.single.ev!;
    expect(ev['idDocumentVersion'], 2);
    expect(ev['name'], 'MATCHED');
    expect(ev['identifierCandidates'], [_ocrNum]);
    expect(r.marks, isEmpty);
    expect(r.uploads, isEmpty);
  });

  testWidgets('09 CASE C · 수집 OFF → 근거 미전송 / 문서 버전 모름 → 근거 미전송', (tester) async {
    final r = _install(on: false, user: {'idDocumentVersion': 2});
    await _open(tester, existingPath: 'users/u1/idCard_1700000000001.png');
    await _fill(tester, name: _ocrName, number: _ocrNum);
    expect(r.finalizes.single.ev, isNull);
  });

  testWidgets('10 CASE C · 문서 버전을 읽지 못함 → 근거 미전송', (tester) async {
    final r = _install(user: <String, dynamic>{});
    await _open(tester, existingPath: 'users/u1/idCard_1700000000001.png');
    await _fill(tester, name: _ocrName, number: _ocrNum);
    expect(r.finalizes.single.ev, isNull);
  });
  testWidgets('11 [DOC-LATE-DELETE.7] 가입 확정 거절 → 사유가 화면에 남고 같은 단계 · 같은 사진 재시도는 다시 올리지 않는다', (tester) async {
    final r = _install();
    var fails = 1;
    ForeignRegisterHooks.finalize = (rawId, legalName, koreanName, visa, ev) async {
      r.finalizes.add((rawId: rawId, legalName: legalName, ev: ev));
      if (fails-- > 0) return '가입이 제한된 계정입니다. 고객센터에 문의해주세요.';
      return null;
    };
    await _open(tester);
    await _pickAndConfirm(tester, name: _ocrName, number: _ocrNum);
    expect(find.byKey(const ValueKey('foreign-submit-error')), findsOneWidget, reason: '토스트가 사라져도 사유가 남는다');
    expect(find.text('가입이 제한된 계정입니다. 고객센터에 문의해주세요.'), findsOneWidget);
    expect(findVisibleText('외국인등록번호 (13자리 숫자 직접 입력)'), findsOneWidget, reason: '확인 단계에 남는다');
    expect(r.marks, isEmpty, reason: '거절되면 업로드 판정을 부르지 않는다');
    expect(r.uploads, hasLength(1));
    // 같은 사진으로 다시 시도 — 이미 올린 객체를 다시 쓴다(재업로드 0) · 이번엔 성공
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, '다음'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(r.uploads, hasLength(1), reason: '재시도는 같은 객체를 쓴다');
    expect(r.marks.single['storagePath'], r.uploads.single);
    expect(find.byKey(const ValueKey('foreign-submit-error')), findsNothing, reason: '새 시도는 이전 사유를 지운다');
  });
  testWidgets('12 [DOC-APP-CLOSEOUT.10] 탈퇴 동결 거절(늦은 응답) · 응답 전 반복 탭 → 확정 1회 · 나이 안내 아님 · 같은 단계 · 성공 시 사유 제거', (tester) async {
    final r = _install();
    var fails = 1;
    ForeignRegisterHooks.finalize = (rawId, legalName, koreanName, visa, ev) async {
      r.finalizes.add((rawId: rawId, legalName: legalName, ev: ev));
      await Future<void>.delayed(const Duration(milliseconds: 200)); // 늦은 응답
      if (fails-- > 0) return AuthService.finalizePreconditionMessage('탈퇴 처리 중인 계정입니다.');
      return null;
    };
    await _open(tester);
    await tester.tap(findVisibleText('갤러리에서 선택'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(0), _ocrName);
    await tester.enterText(_field(2), _ocrNum);
    if (_text(tester, 3).isEmpty) await tester.enterText(_field(3), 'E-9');
    await tester.pump();
    await tester.runAsync(() async {
      final next = find.widgetWithText(ElevatedButton, '다음');
      await tester.tap(next);
      await tester.pump();
      if (next.evaluate().isNotEmpty) await tester.tap(next, warnIfMissed: false); // 응답 전에 다시 누름
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(r.finalizes, hasLength(1), reason: '처리 중에는 다시 보내지 않는다');
    expect(find.text('탈퇴 처리 중에는 가입을 완료할 수 없어요.'), findsOneWidget);
    expect(find.textContaining('19세'), findsNothing);
    expect(findVisibleText('외국인등록번호 (13자리 숫자 직접 입력)'), findsOneWidget, reason: '같은 단계에 남는다(거짓 성공·이동 없음)');
    expect(r.marks, isEmpty);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, '다음'));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(r.finalizes, hasLength(2));
    expect(find.byKey(const ValueKey('foreign-submit-error')), findsNothing, reason: '성공하면 과거 사유가 사라진다');
  });
}
