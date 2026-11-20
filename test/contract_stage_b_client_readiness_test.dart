// [STAGE-B-CLIENT-READINESS] 새 클라이언트는 **영구 다운로드 URL 없이** 계약
//   PDF 와 서명 이미지를 본다.
//
//   고정하는 문장 셋.
//
//     영구 bearer URL 은 네트워크 소스가 아니다 — 열람은 그때마다 서버가 낸다.
//     보안 API 실패는 **영구 URL 로 내려앉지 않는다**(fallback 금지).
//     구버전 앱이 쓰는 응답 필드는 단계 A 동안 **그대로 남는다**.
//
//   이 파일은 소비 경로를 **전수 스캔**한다. 특정 화면만 보면 다음에 새로
//   생기는 화면이 다시 영구 URL 을 쓴다 — 그것이 단계 C 를 막는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 지운다 — 왜 바꿨는지 적은 문장에 옛 표현이 그대로 남아 있다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j < 0) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

/// `lib/` 의 모든 Dart 파일 — 주석 제거본.
Iterable<({String path, String code})> _allDart() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => (path: f.path, code: _codeOf(f.readAsStringSync())));

void main() {
  final svc = _codeOf(_read('lib/services/contract_service.dart'));
  final sign = _codeOf(_read('lib/screens/contract/contract_sign_screen.dart'));
  final hist = _codeOf(
      _read('lib/screens/business_admin/historical_contract_detail_screen.dart'));
  final builder =
      _codeOf(_read('lib/screens/contract/contract_pdf_builder.dart'));
  final fn = _read('functions/src/index.ts');

  group('SB-1 — 영구 URL 을 네트워크 소스로 쓰는 곳이 없다 (전수)', () {
    test('SB-01 계약 URL 필드를 http 로 직접 열지 않는다', () {
      // `http.get(... pdfUrl ...)` / `imageUrl: ...SignatureUrl` 같은 모양.
      final offenders = <String>[];
      final bad = RegExp(
          r'(http\.get|imageUrl:|NetworkImage\(|CachedNetworkImageProvider\()'
          r'[^\n;]*(pdfUrl|employerSignatureUrl|workerSignatureUrl)');
      for (final f in _allDart()) {
        if (bad.hasMatch(f.code)) offenders.add(f.path);
      }
      // 과거 계약 상세의 `pdfUrl` 은 **CF 가 만든 15분 Signed URL** 이다
      //   (필드 이름만 레거시와 같다) — 아래 SB-20 이 그 근거를 고정한다.
      offenders.removeWhere((p) => p.endsWith('historical_contract_detail_screen.dart'));
      expect(offenders, isEmpty,
          reason: '영구 bearer URL 을 직접 여는 소비자가 생겼다: $offenders');
    });

    test('SB-02 계약 PDF·서명 열람은 Signed URL callable 로만 간다', () {
      final callers = <String>[];
      for (final f in _allDart()) {
        if (f.code.contains('callableGetContractPdfSignedUrl') ||
            f.code.contains('callableGetContractSignatureUrl')) {
          callers.add(f.path);
        }
      }
      // 서비스 한 곳만 호출한다 — 화면마다 정책을 복제하지 않는다.
      expect(callers.length, 1, reason: '호출부가 흩어졌다: $callers');
      expect(callers.single.endsWith('contract_service.dart'), isTrue);
    });

    test('SB-03 PDF 빌더는 순수 렌더러다 — 네트워크를 모른다', () {
      expect(builder.contains('http.get'), isFalse);
      expect(builder.contains('callableGet'), isFalse);
      expect(builder.contains('SignatureUrl'), isFalse,
          reason: '서명은 bytes 로 받는다 — URL 을 빌더가 알면 캐시·만료가 흩어진다');
      expect(_flat(builder), contains('employerSignatureBytes'));
    });

    test('SB-04 서명 이미지 렌더러는 **그때 받은 링크**만 쓴다', () {
      final img = _slice(sign, 'class _ContractSignatureImage', 'Widget _retry(');
      expect(_flat(img), contains('imageUrl: link.url'));
      expect(img.contains('SignatureUrl'), isFalse);
      // 링크를 저장하지 않는다 — 위젯 상태로만 들고 있다.
      expect(img.contains('SharedPreferences'), isFalse);
    });

    test('SB-05 Signed URL 을 어디에도 **영속 저장**하지 않는다', () {
      final offenders = <String>[];
      for (final f in _allDart()) {
        if (!f.code.contains('SharedPreferences') &&
            !f.code.contains('setString(')) {
          continue;
        }
        if (RegExp(r'(signedUrl|SignedUrl|pdfUrl|signatureUrl)').hasMatch(f.code)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '만료되는 링크를 저장했다: $offenders');
    });
  });

  group('SB-2 — 실패는 영구 URL 로 내려앉지 않는다', () {
    test('SB-10 PDF 공유 실패에 legacy fallback 이 없다', () {
      final share = _slice(sign, 'Future<void> _sharePdf() async {', 'Future<void> _sign()');
      expect(_flat(share), contains('_service.fetchContractPdfUrl(widget.contract.id)'));
      expect(share.contains('widget.contract.pdfUrl'), isFalse,
          reason: '보안 API 실패를 영구 URL 로 우회하면 단계 C 가 영구히 막힌다');
      // 실패를 "문서 없음"으로 바꾸지 않는다.
      expect(_flat(share), contains('PDF를 불러오지 못했습니다'));
    });

    test('SB-11 서명 바이트 조회는 한 번만 재발급하고 멈춘다', () {
      final f = _slice(svc, 'Future<Uint8List> fetchContractSignatureBytes',
          'Future<void> voidContract(String contractId)');
      // 401/403 → 재발급 1회. 무한 재시도도, legacy 폴백도 아니다.
      expect(_flat(f), contains('fetchContractSignature(contractId, role)'));
      expect(f.contains('pdfUrl'), isFalse);
      expect(f.contains('SignatureUrl'), isFalse);
      expect(RegExp(r'while\s*\(').hasMatch(f), isFalse, reason: '재시도 루프 금지');
    });

    test('SB-12 과거 계약 PDF 는 만료 시 **상세를 다시 읽어** 링크를 받는다', () {
      final share = _slice(hist, 'Future<void> _sharePdf() async {', 'Widget build(');
      expect(_flat(share), contains('await _loadDetail();'));
      expect(_flat(share), contains('PDF를 불러오지 못했습니다'));
      // 재시도는 한 번이다.
      expect(RegExp(r'while\s*\(').hasMatch(share), isFalse);
    });

    test('SB-13 권한 오류와 네트워크 오류를 구분한다 (서비스 경계)', () {
      final f = _slice(svc, 'Future<String> fetchContractPdfUrl',
          'Future<ContractSignatureLink> fetchContractSignature');
      // 서버 코드를 그대로 올려 보낸다 — 클라이언트가 임의로 뭉개지 않는다.
      expect(f.contains('catch'), isFalse,
          reason: 'permission-denied 와 unavailable 을 한 덩어리로 삼키면 안 된다');
    });
  });

  group('SB-3 — 캐시는 **판**으로 하고, 인가는 매번 받는다', () {
    test('SB-20 캐시 키에 서명 판(version)이 들어간다', () {
      final img = _slice(sign, 'class _ContractSignatureImage', 'Widget _retry(');
      expect(_flat(img), contains("cacheKey: 'contract_sig_"));
      expect(_flat(img), contains(r'${link.version}'),
          reason: '판이 없으면 재서명 후에도 옛 서명이 보인다');
      // URL 자체를 키로 쓰지 않는다(15분마다 바뀌어 매번 다시 받는다).
      expect(img.contains('cacheKey: link.url'), isFalse);
    });

    test('SB-21 링크는 매번 서버에서 받는다 — 들고 있지 않는다', () {
      expect(_flat(svc), contains('class ContractSignatureLink'));
      final link = _slice(svc, 'class ContractSignatureLink', '}');
      expect(link.contains('static'), isFalse, reason: '전역 캐시를 두지 않는다');
      // 서비스가 URL 을 필드로 보관하지 않는다.
      expect(svc.contains('String? _cachedPdfUrl'), isFalse);
      expect(svc.contains('_signedUrlCache'), isFalse);
    });

    test('SB-22 계정이 바뀌면 이전 링크로 볼 수 없다 (인가가 매번 선다)', () {
      // 렌더는 `_link != null` 일 때만 일어나고, `_link` 는 resolve 성공의 결과다.
      final img = _slice(sign, 'class _ContractSignatureImage', 'Widget _retry(');
      expect(_flat(img), contains('if (_failed || link == null) return _retry(context);'));
      // 거부되면 그림이 아니라 재시도 UI 다 — 캐시된 bytes 로 새지 않는다.
      expect(_flat(img), contains('_resolve()'));
    });
  });

  group('SB-4 — 구버전 호환 계약은 그대로 남는다 (단계 A)', () {
    test('SB-30 목록 응답은 **경로를 지우고 URL 은 남긴다**', () {
      final strip = _slice(fn, 'function srvStripContractPdfUrl', '\n}\n');
      for (final p in ['pdfStoragePath', 'employerSignatureStoragePath',
        'workerSignatureStoragePath']) {
        expect(strip, contains('delete data["$p"]'), reason: '$p 가 새어 나간다');
      }
      // 구버전 앱이 그리는 필드는 남는다.
      expect(strip.contains('delete data["pdfUrl"]'), isFalse,
          reason: '단계 A 에서 지우면 구버전 앱이 PDF 를 못 본다');
      expect(strip.contains('delete data["employerSignatureUrl"]'), isFalse);
      // 새 앱이 쓰는 boolean 세 개를 더한다.
      for (final k in ['pdfAvailable', 'employerSignatureAvailable',
        'workerSignatureAvailable']) {
        expect(strip, contains('$k'), reason: '$k 가 없다');
      }
    });

    test('SB-31 새 앱은 **boolean** 으로 판단한다 — URL 유무가 아니다', () {
      final model = _codeOf(_read('lib/models/core/employment_contract_model.dart'));
      expect(_flat(model), contains('bool get hasPdf'));
      expect(_flat(model), contains('bool get hasEmployerSignature'));
      expect(_flat(model), contains('bool get hasWorkerSignature'));
      // 관리자 진행 막대도 URL 로 판정하지 않는다.
      final mgmt = _codeOf(
          _read('lib/screens/business_admin/admin_contract_management_screen.dart'));
      expect(_flat(mgmt), contains('contract.employerSignedAt != null || contract.hasEmployerSignature'));
      expect(mgmt.contains('employerSignatureUrl != null'), isFalse);
    });

    test('SB-32 두 서명 callable 이 응답에 **경로**를 함께 돌려준다', () {
      // 단계 C 에서 URL 발급이 멈춰도 서명이 끝나야 한다.
      expect(fn, contains('employerSignatureStoragePath: storagePath,'));
      expect(fn, contains('workerSignatureStoragePath: sigStoragePath,'));
      expect(_flat(svc), contains("cfMap?['employerSignatureStoragePath']"));
      expect(_flat(svc), contains("cfData?['workerSignatureStoragePath']"));
    });

    test('SB-33 과거 계약 CF 가 Signed URL 을 만들어 준다', () {
      final cf = _slice(fn, 'export const callableGetHistoricalContractById',
          '\n);');
      expect(cf, contains('srvHistoricalContractPdfSignedUrl'));
      expect(cf, contains('if (!request.auth)'));
      expect(cf, contains('enforceAppCheck: true'));
    });
  });

  group('SB-5 — 버전 게이트 구조 (단계 C 전제)', () {
    // [VERSION-GATE 이후] 게이트 구조가 바뀌었다 — 세 상태 판정 + 라우트 대체.
    //   자세한 경계는 `app_version_gate_test.dart` 가 고정한다. 여기서는
    //   **단계 C 전제조건으로서** 필요한 사실만 본다.
    test('SB-40 최소 버전 판정이 한 곳에서 돈다', () {
      final v = _codeOf(_read('lib/services/app_version_service.dart'));
      expect(_flat(v), contains("_rc.getValue('min_version')"));
      expect(_flat(v), contains('VersionGateStatus.updateRequired'));
      // 진입 게이트 호출부는 스플래시 하나다(resume 재확인은 별도 신호).
      final callers = <String>[];
      for (final f in _allDart()) {
        if (f.code.contains('AppVersionService.evaluate') &&
            !f.path.endsWith('app_version_service.dart')) {
          callers.add(f.path);
        }
      }
      expect(
          callers.where((p) => p.endsWith('splash_screen.dart')).length, 1,
          reason: '스플래시가 진입 게이트다: $callers');
    });

    test('SB-41 역할에 따라 게이트가 갈리지 않는다', () {
      final v = _codeOf(_read('lib/services/app_version_service.dart'));
      expect(v.contains('BUSINESS_ADMIN'), isFalse);
      expect(v.contains('UserRole'), isFalse,
          reason: '지원자·관리자에게 같은 최소 버전을 적용한다');
    });

    test('SB-42 차단 화면은 우회할 수 없다', () {
      final fu = _codeOf(_read('lib/screens/common/forced_update_screen.dart'));
      expect(_flat(fu), contains('canPop: false'));
      // 다이얼로그가 아니라 라우트다 — 뒤 화면이 살아 있으면 딥링크가 올라온다.
      final sp = _codeOf(_read('lib/screens/common/splash_screen.dart'));
      final gate = _slice(sp, 'void _showGateScreen(', '\n  }');
      expect(_flat(gate), contains('Navigator.pushReplacement'));
      expect(gate.contains('showDialog('), isFalse,
          reason: '차단을 다이얼로그로 하면 뒤 화면이 살아 있다');
      // 남은 showDialog 는 **권장** 업데이트 하나뿐이다(차단 아님).
      // [DU316] 권장 업데이트 창이 공용 확인창 셸(DialogHelper.showConfirm)로 옮겨 갔다 — 같은 뜻으로 둘을 함께 센다.
      expect('showDialog('.allMatches(sp).length + 'DialogHelper.show'.allMatches(sp).length, 1);
      expect(sp.contains('barrierDismissible: false'), isFalse);
    });
  });
}
