// [RELEASE-CORRECTION-PRIVACY-INLINE-DISCLOSURE]
//   민감정보 화면 내 고지 계약.
//
//   지키는 문장은 셋이다.
//
//     달라고 하기 **전에** 말한다.
//     말한 내용이 실제 구현과 같다.
//     말하느라 동의를 한 번 더 받지 않는다.
//
//   순서가 핵심이다. 권한 팝업이 뜬 뒤에, 사진을 고른 뒤에, 번호를 다 친
//   뒤에 하는 설명은 고지가 아니라 사후 통보다. 그래서 이 파일은 문구가
//   있는지만 보지 않고 **어디에 있는지**를 본다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 걷어낸다 — 고지가 주석에만 있으면 사용자는 못 본다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// [start, end) 구간. end 를 못 찾으면 실패시킨다 — 경계가 흘러넘치면
/// 옆 메서드의 코드를 근거로 통과해 버린다.
String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

/// 고지 하나의 문장 목록을 원문에서 뽑는다.
List<String> _points(String noticeSrc, String name) {
  final decl = 'static const $name = PrivacyDisclosure(';
  final body = _slice(noticeSrc, decl, ');');
  final block = _slice(body, 'points: [', '],');
  return RegExp(r"'((?:[^'\\]|\\.)*)'")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  late String noticeSrc;
  late String attendanceSrc;
  late String documentSrc;

  setUpAll(() {
    noticeSrc = _codeOf(_read('lib/widgets/common/privacy_inline_notice.dart'));
    attendanceSrc =
        _codeOf(_read('lib/screens/user/attendance_check_screen.dart'));
    documentSrc =
        _codeOf(_read('lib/screens/common/document_management_screen.dart'));
  });

  // ══════════════════════════════════════════════════════════════
  // 위치
  // ══════════════════════════════════════════════════════════════

  group('ID-L 위치', () {
    late String gps;
    setUpAll(() {
      gps = _slice(attendanceSrc, '_verifyByGPS(', 'bool loadingDialogShown');
    });

    test('ID-L1 OS 권한 요청보다 **먼저** 고지한다', () {
      final notice = gps.indexOf('PrivacyDisclosure.location');
      final request = gps.indexOf('checkAndRequestPermissionDetailed');
      expect(notice, greaterThan(-1), reason: '위치 고지가 없다');
      expect(request, greaterThan(-1));
      expect(notice, lessThan(request),
          reason: '권한을 먼저 요청하고 나중에 설명하면 고지가 아니다');
    });

    test('ID-L2 팝업이 뜰 때만 한 번 — 매번 묻지 않는다', () {
      expect(gps, contains('willPromptForPermission'));
      expect(_codeOf(_read('lib/utils/location_helper.dart')),
          contains('LocationPermission.denied'));
      // 이미 허용/영구거부면 false 를 돌려주는 구조여야 한다.
      expect(_codeOf(_read('lib/utils/location_helper.dart')),
          contains('static Future<bool> willPromptForPermission()'));
    });

    test('ID-L3 물러나면 OS 팝업도 뜨지 않는다', () {
      // 고지에서 취소했는데 권한 팝업이 이어지면 dark pattern 이다.
      final after = gps.substring(gps.indexOf('PrivacyDisclosure.location'));
      expect(after, contains('if (!agreed) return null;'));
      expect(after.indexOf('if (!agreed) return null;'),
          lessThan(after.indexOf('checkAndRequestPermissionDetailed')));
    });

    test('ID-L4 문구가 목적·기록·수신자·백그라운드를 말한다', () {
      final p = _points(noticeSrc, 'location').join(' ');
      expect(p, contains('출근·퇴근'), reason: '언제 쓰는지');
      expect(p, contains('사업장 반경'), reason: '왜 필요한지');
      expect(p, contains('근무 기록에 함께 저장'), reason: '서버에 남는지');
      expect(p, contains('관리자'), reason: '누구에게 도달하는지');
      expect(p, contains('앱을 쓰지 않는 동안'), reason: '백그라운드 여부');
    });

    test('ID-L5 백그라운드 미수집 문구가 실제 구현과 맞는다', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml')
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
      expect(attendanceSrc, isNot(contains('getPositionStream')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 신분증
  // ══════════════════════════════════════════════════════════════

  group('ID-D 신분증', () {
    late String section;
    setUpAll(() {
      section = _slice(
          documentSrc, 'Widget _buildIdCardSection(', 'Widget _buildBankInfoSection(');
    });

    test('ID-D1 업로드 버튼보다 **위에** 고지가 있다', () {
      final notice = section.indexOf('PrivacyDisclosure.idDocument');
      final cta = section.indexOf("text: '신분증 등록하기'");
      expect(notice, greaterThan(-1), reason: '신분증 고지가 없다');
      expect(cta, greaterThan(-1));
      expect(notice, lessThan(cta),
          reason: '올린 뒤에 설명하면 고지가 아니다');
    });

    test('ID-D2 문구가 목적·처리방식·수신자를 말한다', () {
      final p = _points(noticeSrc, 'idDocument').join(' ');
      expect(p, contains('소득신고'), reason: '무엇에 쓰는지');
      expect(p, contains('기기 안에서'), reason: '대조가 어디서 이뤄지는지');
      expect(p, contains('관리자'), reason: '누가 볼 수 있는지');
      expect(p, contains('세무 확인을 누른 때에만'), reason: '언제 열리는지');
    });

    test('ID-D3 기기 내 처리 주장이 실제 구현과 맞는다', () {
      final ocr = _codeOf(_read('lib/utils/ocr_verification_helper.dart'));
      expect(ocr, contains('TextRecognizer'), reason: 'ML Kit 기기 내 인식');
      expect(ocr, contains('InputImage.fromFilePath'));
      expect(ocr, isNot(contains('http')),
          reason: '서버 OCR 이면 "기기 안에서"는 거짓이다');
    });

    test('ID-D4 사진을 안 보낸다고 말하지 않는다', () {
      // 대조는 기기 안에서 하지만 사진 자체는 Storage 에 올라간다.
      final p = _points(noticeSrc, 'idDocument').join(' ');
      expect(p, isNot(contains('서버로 보내지 않습니다')));
      expect(p, contains('저장'), reason: '저장된다는 사실을 말해야 한다');
      expect(documentSrc, contains('uploadImageNoUrl'),
          reason: '실제로 업로드하는 경로가 있다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 세무 식별정보
  // ══════════════════════════════════════════════════════════════

  group('ID-T 세무 식별정보', () {
    late String sheet;
    setUpAll(() {
      sheet = _slice(documentSrc, 'class _TaxIdentitySheetState',
          'Widget _digitField(');
    });

    test('ID-T1 입력 칸보다 **위에** 고지가 있다', () {
      final notice = sheet.indexOf('PrivacyDisclosure.taxIdentity');
      final input = sheet.indexOf('_digitField(_frontCtrl');
      expect(notice, greaterThan(-1), reason: '세무 고지가 없다');
      expect(input, greaterThan(-1));
      expect(notice, lessThan(input),
          reason: '번호를 다 받은 뒤 설명하면 고지가 아니다');
    });

    test('ID-T2 문구가 목적·민감성·관리자 접근 조건·범위를 말한다', () {
      final p = _points(noticeSrc, 'taxIdentity').join(' ');
      expect(p, contains('소득신고·원천징수'), reason: '세무·고용 목적');
      expect(p, contains('암호화'), reason: '민감정보 취급');
      expect(p, contains('관리자'), reason: '누가 볼 수 있는지');
      expect(p, contains('함께 일하는 사업장'), reason: '어떤 조건에서');
      expect(p, contains('기록에 남습니다'), reason: '열람 감사');
      expect(_points(noticeSrc, 'taxIdentity').first, contains('에만'),
          reason: '필요 범위 한정');
    });

    test('ID-T3 감사·암호화 주장이 서버 구현과 맞는다', () {
      final cf = _read('functions/src/index.ts');
      expect(cf, contains('srvEncryptTaxIdentifier'));
      expect(cf, contains('srvLogTaxIdentityAudit'));
      expect(cf, contains('failClosed: true'),
          reason: '기록 실패 시에도 번호가 나가면 "기록에 남습니다"가 거짓이다');
    });

    test('ID-T4 기존 동의 게이트를 대체하지 않는다', () {
      // 고지일 뿐이다 — 서버 게이트는 그대로 있어야 한다.
      final cf = _read('functions/src/index.ts');
      expect(cf, contains('srvHasCurrentTaxIdentityPurpose'));
      expect(cf, contains('srvAssertTaxIdentityAuthority'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 공통 — UX 원칙
  // ══════════════════════════════════════════════════════════════

  group('ID-X 고지 UX', () {
    test('ID-X1 고지 위젯은 동의를 받지 않는다', () {
      for (final banned in [
        'Checkbox',
        'ElevatedButton',
        'onPressed',
        'Switch(',
      ]) {
        expect(noticeSrc, isNot(contains(banned)),
            reason: '고지에 $banned 이(가) 있으면 이중 동의가 된다');
      }
    });

    test('ID-X2 방침 링크를 누르지 않아도 목적을 안다', () {
      for (final name in ['location', 'idDocument', 'taxIdentity']) {
        final pts = _points(noticeSrc, name);
        expect(pts.length, greaterThanOrEqualTo(3), reason: '$name 문장이 너무 적다');
        for (final p in pts) {
          expect(p.trim(), isNotEmpty);
          expect(p.length, lessThan(90),
              reason: '$name — 긴 법률문구를 화면에 붙이지 않는다: $p');
        }
        expect(pts.join(' '), isNot(contains('처리방침')),
            reason: '$name — 방침으로 미루지 않고 여기서 말한다');
      }
    });

    test('ID-X3 과장된 인증 표현을 쓰지 않는다', () {
      final all = ['location', 'idDocument', 'taxIdentity']
          .expand((n) => _points(noticeSrc, n))
          .join(' ');
      for (final banned in ['인증 완료', '진위', '정부', '검증 완료', '안전합니다']) {
        expect(all, isNot(contains(banned)), reason: '금지 표현: $banned');
      }
    });

    test('ID-X4 문구가 한 곳에만 있다', () {
      // 화면마다 복사되면 구현이 바뀔 때 한쪽만 낡는다.
      expect(attendanceSrc, isNot(contains('사업장 반경 안에서 출퇴근했는지')));
      expect(documentSrc, isNot(contains('소득신고·원천징수 처리에만')));
      expect(attendanceSrc, contains('PrivacyDisclosure.location'));
      expect(documentSrc, contains('PrivacyDisclosure.idDocument'));
      expect(documentSrc, contains('PrivacyDisclosure.taxIdentity'));
    });

    test('ID-X5 새 modal 을 만들지 않았다 — 기존 surface 재사용', () {
      expect(attendanceSrc, contains('DialogHelper.showConfirm'));
      expect(noticeSrc, isNot(contains('showDialog')));
      expect(noticeSrc, isNot(contains('showModalBottomSheet')));
    });

    test('ID-X6 데이터 안전 문서가 세 surface 를 모두 가리킨다', () {
      final ds = _read('docs/play-data-safety-final.md');
      expect(ds, contains('PrivacyDisclosure.location'));
      expect(ds, contains('PrivacyDisclosure.idDocument'));
      expect(ds, contains('PrivacyDisclosure.taxIdentity'));
      expect(ds, contains('privacy_inline_notice.dart'));
    });
  });
}
