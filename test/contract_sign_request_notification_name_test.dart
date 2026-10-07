// [R7-GOLDEN-PATH-DEV-E2E §D] 서명 요청 알림이 어느 사업장인지 말하지 않았다
//
// DEV 실측. 사업주가 계약서를 발송하면 근로자에게
// `contractSignRequested` 알림이 간다. 본문은 사업장 이름이 있을 때
// `[사업장명] 근로계약서를 확인하고 서명해 주세요.` 가 되도록 쓰여 있었다.
// 그런데 실제로 받은 본문은 늘 사업장 이름 없는 쪽이었다.
//
//   읽는 쪽: callableFinalizeEmployerSignature 가 계약서 문서의
//            **top-level** `businessName` 을 읽었다.
//   쓰는 쪽: EmploymentContractModel.toMap() 에는 top-level businessName
//            이 없다. ContractService 는 사업장 이름을 `snapshot` 안에만 쓴다.
//
// 즉 아무도 쓰지 않는 자리를 읽고 있었다. 여러 사업장에서 일하는 근로자에게
// 이 한 줄은 "어느 계약서를 열어야 하는가" 그 자체다.
//
// 고정하는 것
//   CSN-1  writer: 모델 직렬화에 top-level businessName 이 없다(결함의 전제)
//   CSN-2  writer: 사업장 이름은 snapshot 안에 쓰인다
//   CSN-3  reader: CF 가 snapshot.businessName 까지 본다
//   CSN-4  reader: 빈 문자열을 이름으로 쓰지 않는다(`[] 근로계약서…` 방지)
//   CSN-5  본문 분기 자체는 그대로다 — 이름이 없으면 일반 문구
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 지운 소스 — 내 설명문이 내 검사에 걸리지 않게 한다.
String _stripComments(String s) => s
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// `name` 함수 본문 — 다음 top-level `export const` 앞에서 멈춘다.
String _cfBlock(String src, String name) {
  final start = src.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('CF 를 찾지 못했다: $name');
  final next = src.indexOf('\nexport const ', start + 10);
  return src.substring(start, next < 0 ? src.length : next);
}

void main() {
  final cf = _stripComments(_src('functions/src/index.ts'));
  final model =
      _stripComments(_src('lib/models/core/employment_contract_model.dart'));
  final service = _stripComments(_src('lib/services/contract_service.dart'));
  final block = _cfBlock(cf, 'callableFinalizeEmployerSignature');

  group('계약서 서명 요청 알림 — 사업장 이름', () {
    test('CSN-1 모델 직렬화에 top-level businessName 이 없다', () {
      // toMap() 의 키 목록. 여기에 businessName 이 생기면 결함의 전제가
      // 바뀌므로 이 테스트가 먼저 알려준다.
      final toMapStart = model.indexOf('Map<String, dynamic> toMap() => {',
          model.indexOf('class EmploymentContractModel'));
      expect(toMapStart, greaterThan(0), reason: 'toMap() 을 찾지 못했다');
      final toMapEnd = model.indexOf('};', toMapStart);
      final toMap = model.substring(toMapStart, toMapEnd);
      expect(toMap.contains("'businessName'"), isFalse,
          reason: 'top-level businessName 이 생겼다면 reader 쪽도 다시 본다');
      expect(toMap.contains("'snapshot': snapshot.toMap()"), isTrue);
    });

    test('CSN-2 사업장 이름은 snapshot 안에 쓰인다', () {
      expect(service.contains('businessName: business.name'), isTrue,
          reason: 'ContractService 가 snapshot 에 사업장 이름을 넣는다');
      final snapToMap = model.substring(
          model.indexOf('Map<String, dynamic> toMap() => {',
              model.indexOf('class ContractSnapshot')));
      expect(snapToMap.substring(0, snapToMap.indexOf('};'))
          .contains("'businessName': businessName"), isTrue);
    });

    test('CSN-3 CF 가 snapshot.businessName 까지 본다', () {
      expect(block.contains('nd["snapshot"]'), isTrue,
          reason: '계약서 문서의 snapshot 을 읽어야 한다');
      expect(
          block.contains('notifSnapshot?.["businessName"]'),
          isTrue,
          reason: 'writer 가 쓰는 자리를 읽어야 한다');
    });

    test('CSN-4 빈 문자열을 사업장 이름으로 쓰지 않는다', () {
      // `[] 근로계약서…` 같은 본문이 나가지 않게 길이를 본다.
      final i = block.indexOf('const notifBizName =');
      expect(i, greaterThan(0));
      final decl = block.substring(i, block.indexOf(';', i));
      expect(decl.contains('length > 0'), isTrue,
          reason: '빈 문자열은 이름이 아니다');
      expect(decl.contains('typeof'), isTrue,
          reason: '문자열이 아닌 값이 본문에 끼어들지 않게 한다');
    });

    test('CSN-5 이름이 없으면 일반 문구로 남는다', () {
      expect(block.contains('body:    notifBizName'), isTrue,
          reason: '분기 자체는 그대로다');
      expect(block.contains('"근로계약서를 확인하고 서명해 주세요."'), isTrue,
          reason: '이름을 모를 때의 문구가 남아 있어야 한다');
    });
  });
}
