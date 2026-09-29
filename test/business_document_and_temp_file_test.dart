// [R7-P4.3B] 사업장 등록 — 서류 precheck + 첨부 수명 + 저장 무결성.
//
// ── 실기기에서 무엇이 보였나 ────────────────────────────────────────
//   ① 사업자등록증 자리에 **아무 이미지**를 골라도 다음 단계로 넘어갔다.
//   ② 최종 저장에서 죽었다:
//        PathNotFoundException: Cannot open file,
//        path='/data/user/0/com.alfit.app/cache/scaled_....webp' (errno = 2)
//
// ── 코드에서 확인한 것 ──────────────────────────────────────────────
//   ① 완료 조건이 `_businessLicenseImage == null && _url == null` 뿐이었다.
//      무엇이 찍힌 이미지인지는 아무도 보지 않았다.
//   ② `ImageHelper.compressImage` 가 **세 경로**에서 image_picker 소유
//      cache 파일(`scaled_*`)을 그대로 돌려줬다 — 200KB 이하 / 압축 null /
//      예외. 폼은 그 File 을 3단계 마법사 내내 들고 다니다 맨 마지막에야
//      연다. 그 사이 OS 가 cache 를 비우면 끝이다.
//
// ── 여기서 볼 수 없는 것 ────────────────────────────────────────────
//   실제 OCR(ML Kit)은 플랫폼 채널이라 단위 테스트에서 못 돈다. 그래서
//   **OCR 원문 → 판정** 부분만 실물 로직으로 돌린다. 실제 이미지 인식
//   품질은 DEVICE 다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/ocr_verification_helper.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _form = 'lib/screens/business_admin/business_form_screen.dart';
const _imageHelper = 'lib/utils/image_helper.dart';

// ── synthetic fixture (실제 사업자등록증·실제 사업자번호 아님) ──────
//
//   민감한 실제 서류를 fixture 에 넣지 않는다. 아래 번호는 형식만 맞춘
//   가짜이고, 문구는 공개된 서식 항목명이다.

const _kFakeNumber = '123-45-67890';

const _realisticLicense = '''
사업자등록증
( 법인사업자 )
등록번호 : 123-45-67890
법인명(단체명) : 주식회사 테스트물류
대표자 : 홍길동
개업연월일 : 2020 년 03 월 02 일
사업장 소재지 : 서울특별시 중구 세종대로 110
업태 : 서비스
종목 : 물류대행
2020 년 03 월 05 일
중부세무서장
''';

/// 풍경 사진 — OCR 이 간판 글자 몇 개만 주운 경우
const _landscape = '''
남산타워
전망대 안내
오늘도 좋은 하루 되세요
''';

/// 앱 스크린샷
const _screenshot = '''
설정
알림 켜기
계정 관리
로그아웃
버전 1.0.18
''';

/// 영수증 — **사업자등록번호가 찍혀 있다.** 번호만 보면 통과해 버린다.
const _receipt = '''
영수증
상호 : 테스트마트
대표자 : 홍길동
사업자등록번호 123-45-67890
합계 12,000원
카드승인 완료
감사합니다
''';

/// 읽을 수 없는 이미지 (초점 나감 / 어두움)
const _unreadable = '''
ㅁ
''';

void main() {
  // ══════════════════════════════════════════════════════════════
  // DOC-01. 아무 이미지나 통과하지 않는다 — 실기기 반례 고정
  // ══════════════════════════════════════════════════════════════
  group('DOC-01 문서 판별', () {
    String check(String text, [String? expected = _kFakeNumber]) =>
        OcrVerificationHelper.businessLicenseCheckFromText(text, expected);

    test('DOC-01a 정상 사업자등록증은 통과한다', () {
      expect(check(_realisticLicense), OcrVerificationHelper.checkPassed);
      expect(OcrVerificationHelper.looksLikeBusinessLicense(_realisticLicense),
          isTrue);
    });

    test('DOC-01b 풍경 사진은 통과하지 않는다', () {
      expect(check(_landscape), isNot(OcrVerificationHelper.checkPassed));
      expect(check(_landscape), OcrVerificationHelper.checkNotDocument);
    });

    test('DOC-01c 앱 스크린샷은 통과하지 않는다', () {
      expect(check(_screenshot), OcrVerificationHelper.checkNotDocument);
    });

    test('DOC-01d 영수증은 번호가 맞아도 통과하지 않는다', () {
      // 이 셀이 이번 수정의 핵심이다. 영수증에도 사업자등록번호가 찍힌다 —
      // 번호 일치만 보면 영수증이 사업자등록증으로 통과한다.
      expect(check(_receipt), OcrVerificationHelper.checkNotDocument);
      expect(OcrVerificationHelper.looksLikeBusinessLicense(_receipt), isFalse,
          reason: '업태·종목·개업연월일·세무서장이 없다');
    });

    test('DOC-01e 읽을 수 없는 이미지는 "다른 문서"가 아니라 재촬영이다', () {
      // 사용자가 할 일이 다르다 — 다시 찍으라는 말과 다른 서류를 내라는
      // 말을 섞으면 안 된다.
      expect(check(_unreadable), OcrVerificationHelper.checkUnreadable);
    });

    test('DOC-01f 글자 수로 통과시키지 않는다', () {
      // "길면 서류" 같은 판정을 넣지 않았다는 반례.
      final long = List.filled(80, '오늘 날씨가 참 좋습니다').join('\n');
      expect(long.length, greaterThan(_realisticLicense.length));
      expect(check(long), OcrVerificationHelper.checkNotDocument);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // DOC-02. 입력값과 서류 번호 대조
  // ══════════════════════════════════════════════════════════════
  group('DOC-02 번호 대조', () {
    test('DOC-02a 번호가 다르면 통과하지 않는다', () {
      final r = OcrVerificationHelper.businessLicenseCheckFromText(
          _realisticLicense, '999-88-77777');
      expect(r, OcrVerificationHelper.checkNumberMismatch);
    });

    test('DOC-02b 하이픈·공백 차이는 불일치가 아니다', () {
      for (final input in const ['1234567890', '123-45-67890', ' 123 45 67890 ']) {
        expect(
            OcrVerificationHelper.businessLicenseCheckFromText(
                _realisticLicense, input),
            OcrVerificationHelper.checkPassed,
            reason: input);
      }
    });

    test('DOC-02c 서류는 맞는데 번호를 못 읽으면 재촬영이다', () {
      const noNumber = '''
사업자등록증
상호 : 테스트물류
대표자 : 홍길동
업태 : 서비스
종목 : 물류대행
중부세무서장
''';
      expect(
          OcrVerificationHelper.businessLicenseCheckFromText(
              noNumber, _kFakeNumber),
          OcrVerificationHelper.checkNumberUnread);
    });

    test('DOC-02d 대조할 입력이 없으면 서류 판별까지만 한다', () {
      // 번호를 아직 입력하지 않았다고 해서 "불일치" 라고 말하지 않는다.
      expect(
          OcrVerificationHelper.businessLicenseCheckFromText(
              _realisticLicense, null),
          OcrVerificationHelper.checkPassed);
      expect(
          OcrVerificationHelper.businessLicenseCheckFromText(_receipt, null),
          OcrVerificationHelper.checkNotDocument,
          reason: '입력이 없어도 다른 문서는 여전히 막는다');
    });

    test('DOC-02e OCR 실패를 통과로 바꾸지 않는다', () {
      // precheckBusinessLicense 의 catch 는 checkUnreadable 을 돌려준다.
      final s = _src('lib/utils/ocr_verification_helper.dart');
      final i = s.indexOf('static Future<Map<String, dynamic>> '
          'precheckBusinessLicense(');
      expect(i, greaterThan(-1));
      final body = s.substring(i, s.indexOf('static Future<Map<String, '
          'dynamic>> verifyBusinessLicense(', i));
      final ci = body.indexOf('} catch (e) {');
      expect(ci, greaterThan(-1));
      final catchBody = body.substring(ci);
      expect(catchBody.contains('checkUnreadable'), isTrue);
      expect(catchBody.contains('checkPassed'), isFalse);
    });

    test('DOC-02f OCR 원문·전체 번호를 밖으로 내보내지 않는다', () {
      final s = _src('lib/utils/ocr_verification_helper.dart');
      final i = s.indexOf('static Future<Map<String, dynamic>> '
          'precheckBusinessLicense(');
      final body = s.substring(i, s.indexOf('static Future<Map<String, '
          'dynamic>> verifyBusinessLicense(', i));
      expect(body.contains("'rawText'"), isFalse,
          reason: '사업정보 원문을 state 로 넘기지 않는다');
      expect(body.contains("substring(0, 3)"), isTrue,
          reason: '불일치 안내에는 앞 3자리만 쓴다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // FORM-01. 폼이 그 판정을 실제로 쓴다
  // ══════════════════════════════════════════════════════════════
  group('FORM-01 폼 연결', () {
    late final String s;
    setUpAll(() => s = _src(_form));

    test('FORM-01a 선택 즉시 확인한다', () {
      expect(s.contains('await _precheckLicense(image);'), isTrue);
      expect(s.contains('type: ImageType.document,'), isTrue,
          reason: '서류는 글자가 읽혀야 한다 — general 압축을 쓰지 않는다');
    });

    test('FORM-01b 통과하지 못하면 다음 단계로 못 간다', () {
      final i = s.indexOf('bool _validateStep2() {');
      final body = s.substring(i, s.indexOf('bool _validateStep3() {', i));
      expect(body.contains('if (!_licenseCheckPassed)'), isTrue);
      expect(body.contains('if (_isCheckingLicense)'), isTrue,
          reason: '확인 중에 통과시키면 안 본 채로 넘어간다');
    });

    test('FORM-01c 확인한 파일과 올릴 파일이 같아야 한다 (§15)', () {
      expect(
          s.contains('_precheckedLicensePath == _businessLicenseImage?.path'),
          isTrue);
      // 저장 직전에도 한 번 더 맞춘다.
      final i = s.indexOf('Future<void> _saveBusiness() async {');
      final body = s.substring(i, s.indexOf('final missing =', i));
      expect(body.contains('!_licenseCheckPassed'), isTrue);
    });

    test('FORM-01d 재선택하면 이전 통과가 무효가 된다', () {
      final i = s.indexOf('Future<void> _precheckLicense(File image) async {');
      expect(i, greaterThan(-1));
      final guard = s.indexOf('checkId != _licenseCheckId', i);
      final head = s.substring(i, guard);
      expect(head.contains('_licenseCheckStatus = null;'), isTrue);
      expect(head.contains('_precheckedLicensePath = null;'), isTrue);
    });

    test('FORM-01e 늦게 끝난 OCR 이 새 이미지를 덮지 않는다', () {
      expect(s.contains('int _licenseCheckId = 0;'), isTrue);
      final i = s.indexOf('Future<void> _precheckLicense(File image) async {');
      final body = s.substring(i, i + 1400);
      expect(body.contains('final checkId = ++_licenseCheckId;'), isTrue);
      expect(body.contains('checkId != _licenseCheckId'), isTrue);
    });

    test('FORM-01f 결과마다 다른 안내를 준다', () {
      final i = s.indexOf('_licenseCheckCopy() {');
      final body = s.substring(i, s.indexOf('// ── [P4.3B-SAVE-02]', i));
      for (final st in const [
        'checkPassed',
        'checkNotDocument',
        'checkUnreadable',
        'checkNumberMismatch',
      ]) {
        expect(body.contains(st), isTrue, reason: st);
      }
      // 공식 진위 확인으로 오해할 표현을 쓰지 않는다.
      //   주석에는 "진위 확인이 아니다" 같은 설명이 있으므로, **사용자에게
      //   나가는 문자열**만 본다 — `text:` 로 시작하는 줄.
      final userText = body
          .split('\n')
          .where((l) => l.trimLeft().startsWith('text:') || l.contains("'사업자등록증"))
          .join('\n');
      expect(userText.contains('사업자등록증 정보를 확인했어요'), isTrue);
      for (final banned in const ['인증되었습니다', '인증 완료', '진위', '검증 완료']) {
        expect(userText.contains(banned), isFalse, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // TEMP-01. 첨부 수명 — 남의 cache 파일을 들고 다니지 않는다
  // ══════════════════════════════════════════════════════════════
  group('TEMP-01 첨부 수명', () {
    late final String s;
    setUpAll(() => s = _src(_imageHelper));

    test('TEMP-01a 세 경로 모두 앱 소유 사본을 돌려준다', () {
      final i = s.indexOf('static Future<File?> compressImage(');
      expect(i, greaterThan(-1));
      final full = s.substring(i, s.indexOf('static const String '
          '_stagingFolder', i));
      // 웹에는 dart:io 파일 경로 개념이 없어 staging 대상이 아니다.
      // 그 분기 **이후**만 본다.
      final web = full.indexOf('if (kIsWeb) {');
      expect(web, greaterThan(-1));
      final body = full.substring(full.indexOf('}', web));
      // 예전에는 세 군데 모두 `return file;` 이었다 — picker 소유 경로다.
      expect(body.contains('return file;'), isFalse,
          reason: 'picker 소유 cache 경로를 넘기면 저장 시점에 사라질 수 있다');
      expect('return _stage(file);'.allMatches(body).length,
          greaterThanOrEqualTo(3),
          reason: '압축 불필요 · 압축 null · 예외 — 세 경로 전부');
    });

    test('TEMP-01b staging 은 OS cache 디렉터리가 아니다', () {
      // Android 에서 getTemporaryDirectory() == cache 디렉터리다.
      // 그곳에 복사해 봐야 같은 이유로 사라진다.
      final i = s.indexOf('static Future<Directory> _stagingDir() async {');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 400);
      expect(body.contains('getApplicationSupportDirectory()'), isTrue);
      expect(body.contains('getTemporaryDirectory()'), isFalse);
    });

    test('TEMP-01c 자동으로 안 지워지므로 우리가 치운다', () {
      expect(s.contains('_sweepStaging'), isTrue);
      expect(s.contains('static const Duration _stagingTtl'), isTrue);
      // 청소 실패가 이미지 선택을 막으면 안 된다.
      final i = s.indexOf('static Future<void> _sweepStaging(');
      final body = s.substring(i, i + 500);
      expect(body.contains('} catch (e) {'), isTrue);
    });

    test('TEMP-01d 복사에 실패하면 null 이다 — 사라질 경로를 주지 않는다', () {
      final i = s.indexOf('static Future<File?> _stage(File source) async {');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 700);
      final ci = body.indexOf('} catch (e) {');
      expect(ci, greaterThan(-1));
      expect(body.substring(ci).contains('return null;'), isTrue);
      expect(body.substring(ci).contains('return source;'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SAVE-01. 저장 무결성
  // ══════════════════════════════════════════════════════════════
  group('SAVE-01 저장', () {
    late final String s;
    setUpAll(() => s = _src(_form));

    test('SAVE-01a 업로드 전에 첨부가 읽히는지 본다', () {
      final i = s.indexOf('Future<void> _saveBusiness() async {');
      final upload = s.indexOf('final uploadFutures = <Future<String?>>[];', i);
      final gate = s.indexOf('final missing = await _firstMissingAttachment();', i);
      expect(gate, greaterThan(-1));
      expect(gate, lessThan(upload),
          reason: '하나라도 없으면 아무것도 올리지 않는다 — 고아 객체를 만들지 않는다');
    });

    test('SAVE-01b 모든 첨부를 본다', () {
      final i = s.indexOf('Future<String?> _firstMissingAttachment() async {');
      final body = s.substring(i, i + 800);
      for (final f in const [
        '_businessLicenseImage',
        '_mainImage',
        '_additionalImages',
        '_transportImages',
      ]) {
        expect(body.contains(f), isTrue, reason: f);
      }
      expect(body.contains('await file.exists()'), isTrue);
    });

    test('SAVE-01c raw 예외를 사용자에게 보여주지 않는다', () {
      expect(s.contains(r"ToastHelper.showError('저장에 실패했습니다: $e')"), isFalse,
          reason: 'PathNotFoundException·errno 는 제품 메시지가 아니다');
      expect(s.contains('e is PathNotFoundException'), isTrue);
      expect(s.contains('첨부한 파일을 불러올 수 없습니다'), isTrue);
      // 기술 진단은 로그로 남는다.
      expect(s.contains(r"debugPrint('❌ 사업장 저장 실패: $e')"), isTrue);
    });

    test('SAVE-01d 첨부 문제면 고칠 수 있는 자리로 되돌린다', () {
      expect(s.contains('void _focusAttachmentSection() {'), isTrue);
      expect('_focusAttachmentSection()'.allMatches(s).length,
          greaterThanOrEqualTo(3),
          reason: '선검사 · precheck 불일치 · 예외 경로');
    });

    test('SAVE-01e 좌표 게이트(P4.3A)를 깨지 않았다', () {
      expect(s.contains('if (!_hasUsableLocation)'), isTrue);
      expect(s.contains('if (_latitude == null || _longitude == null) {'), isTrue);
    });

    test('SAVE-01f 업로드 실패 후에도 다시 저장할 수 있다', () {
      // 예전에는 finally 에서 성공·실패 무관하게 첨부를 지웠다. 네트워크로
      // 한 번 실패하면 파일이 사라져, "다시 저장" 을 눌러도 올릴 것이
      // 없었다 — 이미지를 다시 고르는 것 말고는 길이 없었다.
      final i = s.indexOf('Future<String?> _uploadImage(');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 1200);
      expect(body.contains('if (url != null) {'), isTrue,
          reason: '올라간 것이 확인됐을 때만 치운다');
      expect(body.contains('} finally {'), isFalse);
    });

    test('SAVE-01g 사업장 문서와 소유 관계는 한 batch 다', () {
      // 하나만 남는 상태(사업장은 있는데 관리 목록에는 없음)를 만들지 않는다.
      final i = s.indexOf('final batch = FirebaseFirestore.instance.batch();');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 700);
      expect(body.contains('batch.set(bizRef, businessData);'), isTrue);
      expect(body.contains("'managedBusinessIds': FieldValue.arrayUnion"), isTrue);
      expect(body.contains('batch.commit()'), isTrue);
    });
  });
}
