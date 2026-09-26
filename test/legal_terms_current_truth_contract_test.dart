// [PII-B4-R1.3B] 활성 처리방침은 "지금 실제로 하는 처리"만 말한다
//
// 이 파일이 고정하는 것:
//
//   INV-1  현재 수집하는 것이 고지에 있다
//   INV-2  현재 하지 않는 것이 고지에 없다
//   INV-3  로드맵(R1.4 세무 identity)이 현재 수집항목 자리에 없다
//   INV-4  하지 않는 판정을 한다고 말하지 않는다
//   INV-5  코드 기본값 · 웹 고지 · 런타임 문서가 같은 현재 진실이다
//
// INV-5의 런타임 축은 실제 DEV 문서를 실제 reader 로 파싱해서 본다.
// 덤프 경로가 주어지지 않으면 그 그룹만 skip 한다 — 저장소 테스트는
// 언제나 돌아야 하고, 런타임 증거는 있을 때만 검사한다.

import 'dart:convert';
import 'dart:io';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _termsPath = 'lib/models/core/legal_terms_model.dart';
const _htmlPath = 'public/privacy.html';

/// 현재 실제로 수집·처리하는 것. 코드에서 확인된 것만 넣는다.
const _mustAppear = <String, String>{
  '외국인등록번호': '외국인등록번호 13자리',
  '외국인등록증 이미지': '외국인등록증 사진',
  '공식 이름(legalName)': '외국인등록증에 기재된 공식 이름',
  '체류자격(visaType)': '체류자격(비자 종류)',
  '세무 처리 목적': '급여 공제 계산 및 소득신고·원천징수 등 법정 세무 처리',
  '정합성 확인 목적': '본인 및 제출 서류 정보의 정합성 확인',
  'OCR 서버 전송': '외국인등록번호는 동일인 식별을 위해 서버로 전송되며',
};

/// 지금 하지 않는 것 / 과장. 활성 방침에 있으면 안 된다.
const _mustNotAppear = <String>[
  // 존재하지 않는 입력 UI
  '주민등록번호 — 근로계약서 작성 시 입력',
  // 이메일 가입은 PASS 전환으로 사라졌다
  '이메일 주소, 비밀번호',
  // 앞 7자리도 저장하지 않는다 — birthDate/gender 에서 만들어 쓴다
  '주민등록번호 앞 7자리',
  // 수집하지 않는 항목
  '체류기간만료일',
  '체류 기간 만료일',
  // 하지 않는 판정
  '취업자격 인증',
  '취업 자격 인증',
  '체류자격 검증',
  '정부 인증 완료',
  // 없는 기능
  '홈택스',
  '지급명세서를 제출합니다',
  // 위탁이 실제로 있는데 없다고 하던 옛 문구
  '현재 개인정보 처리를 외부에 위탁하는 업체는 없습니다',
];

void main() {
  final terms = _src(_termsPath);
  final html = _src(_htmlPath);
  final both = {_termsPath: terms, _htmlPath: html};

  group('INV-1 — 하는 것을 말한다', () {
    for (final e in _mustAppear.entries) {
      test('01 ${e.key}', () {
        for (final f in both.entries) {
          expect(f.value, contains(e.value), reason: f.key);
        }
      });
    }
  });

  group('INV-2 — 하지 않는 것을 말하지 않는다', () {
    test('02 금지 문구 전수', () {
      for (final f in both.entries) {
        for (final banned in _mustNotAppear) {
          expect(f.value, isNot(contains(banned)), reason: '"$banned" in ${f.key}');
        }
      }
    });

    test('03 주민등록번호는 "현재 수집하지 않음"으로만 적혀 있다', () {
      for (final f in both.entries) {
        expect(f.value, contains('주민등록번호 — 현재 수집하지 않습니다'), reason: f.key);
      }
    });
  });

  group('INV-3 — 로드맵이 수집항목 자리에 없다 (§5)', () {
    test('04 R1.4 예정을 현재 수집으로 적지 않았다', () {
      for (final f in both.entries) {
        for (final banned in [
          '수집할 예정이며',
          '지원자 서류 등록 단계에서 수집',
          '향후 소득신고·원천징수 등 법정 세무 처리를 위해',
        ]) {
          expect(f.value, isNot(contains(banned)), reason: '"$banned" in ${f.key}');
        }
      }
    });

    test('05 변경은 일반 개정 조항으로만 말한다', () {
      for (final f in both.entries) {
        expect(f.value, contains('■ 처리방침의 개정'), reason: f.key);
        expect(f.value,
            contains('변경 내용과 시행일을\n사전에 고지하고'), reason: f.key);
      }
    });

    test('06 시행일이 개정본과 같다', () {
      // [PRIVACY-REWRITE.1] 외부 계정삭제 경로 고지로 개정됐다.
      //   이전 시행일도 본문에 남겨 어떤 판이 바뀌었는지 알 수 있게 한다.
      for (final f in both.entries) {
        expect(f.value, contains('본 처리방침은 2026년 9월 26일부터 적용됩니다'),
            reason: f.key);
      }
    });
  });

  group('INV-4 — 판정하지 않는 것을 판정한다고 하지 않는다 (§17·§18)', () {
    test('07 취업 가능 여부 심사 부인이 명시돼 있다', () {
      for (final f in both.entries) {
        expect(f.value, contains('취업 가능 여부나 체류 자격의 적법성을 심사·판정하지 않습니다'),
            reason: f.key);
      }
    });

    test('08 내국인 OCR을 서버 전송처럼 쓰지 않았다', () {
      // 현재 내국인 OCR은 기기 내 판정 → enum 4종만 서버로 간다.
      for (final f in both.entries) {
        expect(f.value, contains('기기 내에서 처리하며 인식된 원문은 서버에 저장하지 않습니다'),
            reason: f.key);
      }
    });
  });

  group('INV-5a — 코드 기본값 메타데이터', () {
    test('09 개정 항목만 version이 올라갔다', () {
      final pp = _sliceOf(terms, "id: 'privacy_policy'", 'order: 2');
      // [PRIVACY-REWRITE.1] 개정 번호는 상수 한 곳에만 둔다.
      expect(pp, contains('version: kPrivacyPolicyRevision'));
      expect(terms, contains("const kPrivacyPolicyRevision = '2026-09-26';"));
      for (final other in ['service_terms', 'privacy_third_party',
        'location_terms', 'marketing_consent']) {
        final s = _sliceOf(terms, "id: '$other'", 'updatedAt: now');
        expect(s, contains("version: '2026.08'"), reason: other);
      }
    });

    test('10 항목은 5개 그대로다', () {
      expect("id: '".allMatches(_sliceOf(
          terms, 'static LegalTerms defaultTerms()', 'const _default')).length, 5);
    });
  });

  group('INV-5b — 런타임 문서를 실제 reader 로 읽는다', () {
    final dumpPath = Platform.environment['ALFIT_LEGAL_DUMP'];
    final hasDump = dumpPath != null && File(dumpPath).existsSync();

    test('11 런타임 문서가 현재 진실을 말한다', () {
      if (!hasDump) {
        markTestSkipped('ALFIT_LEGAL_DUMP 미지정 — 런타임 증거 없음');
        return;
      }
      final raw = jsonDecode(File(dumpPath).readAsStringSync())
          as Map<String, dynamic>;

      // ── 실제 reader 경로 — LegalTermsItem.fromMap → LegalTerms.activeItems
      final parsed = (raw['items'] as List<dynamic>).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final ms = m.remove('updatedAtMs') as int?;
        return LegalTermsItem.fromMap({
          ...m,
          'updatedAt':
              ms == null ? null : Timestamp.fromMillisecondsSinceEpoch(ms),
        });
      }).toList();
      final resolved = LegalTerms(items: parsed);

      expect(resolved.activeItems.length, 5, reason: '활성 항목');
      final pp = resolved.activeItems.firstWhere((i) => i.id == 'privacy_policy');

      expect(pp.version, '2026.09');
      for (final e in _mustAppear.entries) {
        expect(pp.content, contains(e.value), reason: '런타임: ${e.key}');
      }
      for (final banned in _mustNotAppear) {
        expect(pp.content, isNot(contains(banned)), reason: '런타임: "$banned"');
      }
      expect(pp.content, contains('■ 처리방침의 개정'));
      expect(pp.content, contains('2026년 9월 20일부터 적용됩니다'));
    });

    test('12 런타임 본문이 코드 기본값과 같다 (§11 parity)', () {
      if (!hasDump) {
        markTestSkipped('ALFIT_LEGAL_DUMP 미지정');
        return;
      }
      final raw = jsonDecode(File(dumpPath).readAsStringSync())
          as Map<String, dynamic>;
      final runtimePp = (raw['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['id'] == 'privacy_policy')['content'] as String;
      final embeddedPp = LegalTerms.defaultTerms()
          .items.firstWhere((i) => i.id == 'privacy_policy').content;
      expect(runtimePp, embeddedPp,
          reason: '런타임 문서와 코드 기본값이 갈라지면 fallback 이 다른 말을 한다');
    });
  });
}
