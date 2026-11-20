// [FULL13-REEVAL.2] 세무 입력 시트 흐름 — 합성 fixture(LOCAL, 기기 아님).
//
//   Storage 다운로드·ML Kit OCR·callable 은 TaxIdentitySheetHooks 로 대체한다.
//   시트의 실제 상태 기계(입력 → 자동 대조 → 근거 → 제출 → 오류/성공)는 그대로 돈다.
//   번호는 합성 구조값이다.

import 'dart:io';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/screens/common/document_management_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/identity_identifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/visible_text.dart'; // [DU281] 시트 오류 문장이 낱말 묶기라 보이는 글자로 찾는다

const _num = '9001011000001';
const _path = 'users/u1/idCard_1700000000001.png';

UserModel _user({bool uploaded = true, int version = 3}) => UserModel(
      uid: 'u1',
      username: 'u1',
      name: '홍길동',
      email: 'u1@alfit.local',
      role: UserRole.USER,
      idCardImagePath: uploaded ? _path : null,
      idDocumentVersion: uploaded ? version : null,
      createdAt: DateTime(2026, 1, 1),
    );

class _Rec {
  final downloads = <String>[];
  final ocrCalls = <({String name, String expected, bool isForeign})>[];
  final submits = <({String kind, String value, DocFieldOutcome match, TaxIdDocumentEvidence? ev})>[];
  final tempFiles = <File>[];
}

_Rec _install({
  Map<String, dynamic> Function()? ocrResult,
  bool downloadThrows = false,
  String? submitError,
}) {
  final r = _Rec();
  TaxIdentitySheetHooks.download = (p) async {
    r.downloads.add(p);
    if (downloadThrows) throw const FileSystemException('합성 다운로드 실패');
    final f = File('${Directory.systemTemp.path}/full13_${DateTime.now().microsecondsSinceEpoch}.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    r.tempFiles.add(f);
    return f;
  };
  TaxIdentitySheetHooks.ocr = (img, name, expected, isForeign) async {
    r.ocrCalls.add((name: name, expected: expected, isForeign: isForeign));
    return ocrResult?.call() ?? <String, dynamic>{};
  };
  TaxIdentitySheetHooks.submit = (kind, value, match, ev) async {
    r.submits.add((kind: kind, value: value, match: match, ev: ev));
    return submitError;
  };
  return r;
}

Map<String, dynamic> _matched() => {
      'identifierOutcome': DocFieldOutcome.matched,
      'nameOutcome': DocFieldOutcome.matched,
      'identifierCandidates': <String>[_num],
    };

Future<void> _open(WidgetTester tester, UserModel user, {bool isUpdate = false, bool recovery = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<bool>(
              builder: (_) => Scaffold(
                body: SingleChildScrollView(
                  child: debugTaxIdentitySheet(
                      user: user, isUpdate: isUpdate, isForeignRecovery: recovery),
                ),
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String n) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), n.substring(0, 6));
  await tester.enterText(fields.at(1), n.substring(6));
  await tester.pump();
}

/// 실제 파일 IO 가 있으므로 진짜 시계에서 제출을 끝까지 돌린다.
Future<void> _submit(WidgetTester tester, String label) async {
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(ElevatedButton, label));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  tearDown(TaxIdentitySheetHooks.reset);

  testWidgets('01 국내 입력 → 현재 업로드 신분증 자동 대조 → 근거와 함께 등록 → 닫힘', (tester) async {
    final r = _install(ocrResult: _matched);
    await _open(tester, _user());
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    expect(r.downloads, [_path], reason: '새 사진이 아니라 현재 업로드 경로를 받는다');
    expect(r.ocrCalls.single.name, '홍길동');
    expect(r.ocrCalls.single.isForeign, isFalse);
    final s = r.submits.single;
    expect(s.kind, 'register');
    expect(s.ev, isNotNull);
    expect(s.ev!.idDocumentVersion, 3);
    expect(s.ev!.identifierCandidates, [_num]);
    expect(s.ev!.name, DocFieldOutcome.matched);
    expect(r.tempFiles.every((f) => !f.existsSync()), isTrue, reason: '받은 임시 파일은 지운다');
    expect(find.text('등록하기'), findsNothing, reason: '성공하면 시트가 닫힌다');
  });

  testWidgets('02 OCR 시간 초과(결과 없음) → 근거 없이 등록(판정 안 함 ≠ 못 읽음)', (tester) async {
    final r = _install(ocrResult: () => <String, dynamic>{});
    await _open(tester, _user());
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    expect(r.submits.single.ev, isNull);
    expect(r.submits.single.match, DocFieldOutcome.unassessed);
    expect(r.tempFiles.every((f) => !f.existsSync()), isTrue);
  });

  testWidgets('03 번호를 못 읽음(빈 후보) → 빈 후보 근거(서버가 OCR_UNCERTAIN 으로 적는다)', (tester) async {
    final r = _install(ocrResult: () => {
          'identifierOutcome': DocFieldOutcome.unreadable,
          'nameOutcome': DocFieldOutcome.matched,
          'identifierCandidates': <String>[],
        });
    await _open(tester, _user());
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    expect(r.submits.single.ev!.identifierCandidates, isEmpty);
  });

  testWidgets('04 다운로드 실패 → 근거 없음, 등록은 계속, 오류 문구 없음', (tester) async {
    final r = _install(downloadThrows: true);
    await _open(tester, _user());
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    expect(r.ocrCalls, isEmpty);
    expect(r.submits.single.ev, isNull);
  });

  testWidgets('05 서버 거절 → 문구 표시·시트 유지 · 입력을 바꾸면 근거를 버리고 다시 대조', (tester) async {
    final r = _install(ocrResult: _matched, submitError: '주민등록번호 앞자리가 본인인증 생년월일과 다릅니다.');
    await _open(tester, _user());
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    expect(findVisibleText('주민등록번호 앞자리가 본인인증 생년월일과 다릅니다.'), findsOneWidget);
    expect(find.text('등록하기'), findsOneWidget);
    expect(r.downloads.length, 1);
    await _enter(tester, '9001011000002');
    await _submit(tester, '등록하기');
    expect(r.downloads.length, 2, reason: '입력이 바뀌면 옛 근거로 보내지 않는다');
    expect(r.ocrCalls.last.expected, '9001011000002');
    expect(r.submits.last.ev, isNotNull);
  });

  testWidgets('06 재제출(같은 입력) → 이미 있는 근거를 다시 쓴다(다운로드 1회)', (tester) async {
    final r = _install(ocrResult: _matched, submitError: '잠시 후 다시 시도해주세요.');
    await _open(tester, _user());
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    await _submit(tester, '등록하기');
    expect(r.downloads.length, 1);
    expect(r.submits.length, 2);
    expect(r.submits.every((s) => s.ev != null), isTrue);
  });

  testWidgets('07 올라간 신분증 없음 → 다운로드·자동 대조 없음, 근거 없음', (tester) async {
    final r = _install(ocrResult: _matched);
    await _open(tester, _user(uploaded: false));
    await _enter(tester, _num);
    await _submit(tester, '등록하기');
    expect(r.downloads, isEmpty);
    expect(r.submits.single.ev, isNull);
  });

  testWidgets('08 수정 → kind=update, 근거 포함', (tester) async {
    final r = _install(ocrResult: _matched);
    await _open(tester, _user(), isUpdate: true);
    await _enter(tester, _num);
    await _submit(tester, '수정하기');
    expect(r.submits.single.kind, 'update');
    expect(r.submits.single.ev, isNotNull);
  });

  // [FULL13-REEVAL.3] 외국인 복구: 가입과 같은 등록증 OCR 로 읽고, 이번에 직접 입력한 영문 이름과 비교한다.
  Future<_Rec> recovery(WidgetTester tester, {required String typedName, String? ocrName = 'NGUYEN VAN AN',
      String source = 'LATIN_REGION', String number = '9001015000001'}) async {
    final r = _install();
    TaxIdentitySheetHooks.foreignOcr = (_) async => ForeignIdOcrResult(legalName: ocrName, foreignIdRaw: '9001015000001',
        legalNameFailed: ocrName == null, legalNameOcrSource: ocrName == null ? 'NONE' : source);
    await _open(tester, _user(), recovery: true);
    await _enter(tester, number);
    if (typedName.isNotEmpty) {
      await tester.enterText(find.widgetWithText(TextField, '영문 이름 (등록증 기재대로)'), typedName);
      await tester.pump();
    }
    await _submit(tester, '등록하기');
    return r;
  }

  testWidgets('09 외국인 복구 · 이름 직접 입력 = 사진 → 이름 MATCHED, 번호 후보 = 사진 값', (tester) async {
    final r = await recovery(tester, typedName: 'nguyen van an');
    expect(r.ocrCalls, isEmpty, reason: '국내 OCR 경로가 아니다');
    expect(r.submits.single.kind, 'recoverForeign');
    expect(r.submits.single.ev!.name, DocFieldOutcome.matched);
    expect(r.submits.single.ev!.identifierCandidates, ['9001015000001']);
    expect(r.tempFiles.every((f) => !f.existsSync()), isTrue);
  });

  testWidgets('10 외국인 복구 · 이름 다름 → MISMATCH / 이름 미입력 → UNASSESSED', (tester) async {
    final r = await recovery(tester, typedName: 'VAN AN NGUYEN');
    expect(r.submits.single.ev!.name, DocFieldOutcome.mismatch);
  });

  testWidgets('11 외국인 복구 · 이름 미입력 → UNASSESSED(MATCHED 불가)', (tester) async {
    final r = await recovery(tester, typedName: '');
    expect(r.submits.single.ev!.name, DocFieldOutcome.unassessed);
  });

  testWidgets('12 외국인 복구 · 번호 앞7 같고 뒤6 다름 → 후보는 사진 값(서버 MISMATCH)', (tester) async {
    final r = await recovery(tester, typedName: 'NGUYEN VAN AN', number: '9001015999999');
    expect(r.submits.single.value, '9001015999999');
    expect(r.submits.single.ev!.identifierCandidates, ['9001015000001']);
  });
}
