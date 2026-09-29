// [R7-P4.3A] 사업장 주소 → 좌표 — 실패를 하나로 뭉개지 않는다.
//
// ── 실기기에서 무엇이 보였나 ────────────────────────────────────────
//   BUSINESS_ADMIN 이 신규 사업장 등록에서 주소를 골랐는데
//   'GPS 위치 미확인' 이 계속 남아 있었다.
//
// ── 코드에서 확인한 사실 ────────────────────────────────────────────
//   1. 그 문구의 조건은 `_latitude == null` 하나였다. 기기 GPS 와 무관하다
//      — 이 폼은 기기 위치를 한 번도 읽지 않는다.
//   2. `GeocodingService` 가 **여섯 가지 실패를 전부 `null`** 로 돌려줬고,
//      이유를 적는 로그는 전부 `kDebugMode` 안에 있어 릴리스 기기에서는
//      아무 흔적도 남지 않았다.
//   3. 어느 단계 검증도 좌표를 보지 않았고, 저장 payload 는
//      `'latitude': _latitude` 를 **null 인 채로** 보냈다.
//      → 좌표 없는 사업장이 만들어질 수 있었고, 그 대가는 근무 당일
//        출근을 못 찍는 **근로자**가 치른다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/geocoding_service.dart';
import 'package:ALfit/utils/business_location_status.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _form = 'lib/screens/business_admin/business_form_screen.dart';
const _geo = 'lib/services/geocoding_service.dart';
const _dialog = 'lib/widgets/inputs/daum_address_search_mobile.dart';
const _attendance = 'lib/screens/user/attendance_check_screen.dart';

void main() {
  // ══════════════════════════════════════════════════════════════
  // GEO-01. 실패 원인이 살아서 올라온다
  // ══════════════════════════════════════════════════════════════
  group('GEO-01 geocoding outcome', () {
    test('GEO-01a 빈 주소는 조회하지 않는다', () async {
      final r = await GeocodingService.resolveAddress('   ');
      expect(r.status, GeocodeStatus.notFound);
      expect(r.isResolved, isFalse);
    });

    test('GEO-01b 키가 없는 빌드는 "못 찾았다"가 아니라 "설정 안 됨"이다',
        () async {
      // 이 구별이 이번 수정의 핵심이다. 예전에는 둘 다 null 이라 화면이
      // "주소 재검색" 을 권했고, 관리자는 영원히 안 될 일을 반복했다.
      if (GeocodingService.isConfigured) {
        // 키를 넣고 돌린 실행 — 이 셀이 검증하려는 조건이 아니다.
        return;
      }
      final r = await GeocodingService.resolveAddress('서울특별시 중구 세종대로 110');
      expect(r.status, GeocodeStatus.notConfigured);
      expect(r.isRetryable, isFalse,
          reason: '다시 눌러도 안 된다 — 재시도를 권하면 안 된다');
    });

    test('GEO-01c 재시도가 의미 있는 실패는 하나뿐이다', () {
      expect(const GeocodeResult(GeocodeStatus.unavailable).isRetryable, isTrue);
      for (final s in const [
        GeocodeStatus.notFound,
        GeocodeStatus.unauthorized,
        GeocodeStatus.notConfigured,
        GeocodeStatus.resolved,
      ]) {
        expect(const GeocodeResult(GeocodeStatus.notFound).isRetryable, isFalse,
            reason: '$s');
      }
    });

    test('GEO-01d 실패 원인이 릴리스에서도 로그로 남는다', () {
      // 예전에는 모든 debugPrint 가 kDebugMode 안에 있어 실기기에서 아무
      // 단서도 없었다. 성공 로그는 계속 debug 전용이어도 된다.
      final s = _src(_geo);
      for (final marker in const [
        "debugPrint('⚠️ [Geocoding] KAKAO_REST_API_KEY 미설정",
        "debugPrint('❌ [Geocoding] 키 거부",
        "debugPrint('❌ [Geocoding] 응답 ",
        "debugPrint('❌ [Geocoding] 실패: ",
      ]) {
        final i = s.indexOf(marker);
        expect(i, greaterThan(-1), reason: marker);
        // 그 줄 앞 200자 안에 kDebugMode 가드가 붙어 있지 않아야 한다.
        final before = s.substring((i - 200).clamp(0, i), i);
        expect(before.contains('if (kDebugMode)'), isFalse, reason: marker);
      }
    });

    test('GEO-01e 키 값을 로그에 남기지 않는다', () {
      final s = _src(_geo);
      // 예전에는 키 앞 6자리를 debugPrint 로 찍었다.
      expect(s.contains('_kakaoRestApiKey.substring'), isFalse);
      // 키는 Authorization 헤더 한 곳에서만 쓴다 — 로그 줄에는 없어야 한다.
      for (final line in s.split('\n')) {
        if (!line.contains('debugPrint')) continue;
        expect(line.contains('_kakaoRestApiKey'), isFalse, reason: line.trim());
      }
      expect(s.contains(r"'Authorization': 'KakaoAK $_kakaoRestApiKey'"),
          isTrue, reason: '키를 쓰는 곳은 헤더 하나뿐이다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // COPY-01. 원인마다 다른 말, 원인마다 다른 행동
  // ══════════════════════════════════════════════════════════════
  group('COPY-01 상태 문구', () {
    BusinessLocationCopy c({
      bool resolving = false,
      bool resolved = false,
      GeocodeStatus? failure,
    }) =>
        businessLocationCopy(
            resolving: resolving, resolved: resolved, failure: failure);

    test('COPY-01a 여섯 상태가 서로 다른 문장을 쓴다', () {
      final texts = {
        c().text,
        c(resolving: true).text,
        c(resolved: true).text,
        c(failure: GeocodeStatus.notFound).text,
        c(failure: GeocodeStatus.unavailable).text,
        c(failure: GeocodeStatus.unauthorized).text,
      };
      // unauthorized 와 notConfigured 는 사용자에게 같은 사실("앱 설정
      // 문제")이므로 의도적으로 같은 문장이다 — 그래서 6이 아니라 6개
      // 입력에 대해 최소 5개의 서로 다른 문장.
      expect(texts.length, greaterThanOrEqualTo(5));
      expect(c(failure: GeocodeStatus.unauthorized).text,
          c(failure: GeocodeStatus.notConfigured).text);
    });

    test('COPY-01b 재시도는 일시적 실패에만 권한다', () {
      expect(c(failure: GeocodeStatus.unavailable).action,
          LocationAction.retry);
      // 다시 눌러도 결과가 같은 것들은 재시도를 권하지 않는다.
      for (final s in const [
        GeocodeStatus.notFound,
        GeocodeStatus.unauthorized,
        GeocodeStatus.notConfigured,
      ]) {
        expect(c(failure: s).action, isNot(LocationAction.retry), reason: '$s');
      }
    });

    test('COPY-01c 막다른 실패에는 탈출구가 있다', () {
      // 지도에 없는 주소·앱 설정 문제로 등록 자체가 영영 막히면 안 된다.
      for (final s in const [
        GeocodeStatus.notFound,
        GeocodeStatus.unauthorized,
        GeocodeStatus.notConfigured,
      ]) {
        expect(c(failure: s).action, LocationAction.manual, reason: '$s');
      }
    });

    test('COPY-01d 조회 중에는 직전 실패 문구를 말하지 않는다', () {
      final copy = c(resolving: true, failure: GeocodeStatus.unavailable);
      expect(copy.text, '주소의 위치를 확인하고 있어요');
      expect(copy.action, LocationAction.none);
    });

    test('COPY-01e 확인된 뒤에는 누를 것이 없다', () {
      final copy = c(resolved: true, failure: GeocodeStatus.unavailable);
      expect(copy.text, '사업장 위치 확인됨');
      expect(copy.action, LocationAction.none);
    });

    test('COPY-01f 기기 GPS 를 말하지 않는다', () {
      // 이 값은 주소로 찾은 **사업장 위치**다. 'GPS' 라고 부르면 관리자가
      // 현장에 서 있어야 하는 줄 안다.
      for (final copy in [
        c(),
        c(resolving: true),
        c(resolved: true),
        c(failure: GeocodeStatus.notFound),
        c(failure: GeocodeStatus.unavailable),
        c(failure: GeocodeStatus.unauthorized),
      ]) {
        expect(copy.text.contains('GPS'), isFalse, reason: copy.text);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SAVE-01. 좌표 없는 사업장을 만들지 않는다
  // ══════════════════════════════════════════════════════════════
  group('SAVE-01 저장 게이트', () {
    late final String s;
    setUpAll(() => s = _src(_form));

    test('SAVE-01a 단계 검증이 위치를 본다', () {
      final i = s.indexOf('bool _validateStep2() {');
      expect(i, greaterThan(-1));
      final end = s.indexOf('bool _validateStep3() {', i);
      final body = s.substring(i, end);
      expect(body.contains('if (!_hasUsableLocation)'), isTrue);
      expect(body.contains('if (_isResolvingLocation)'), isTrue,
          reason: '조회 중에 통과시키면 좌표 없이 저장된다');
    });

    test('SAVE-01b writer 쪽에도 방어가 있다', () {
      final i = s.indexOf('Future<void> _saveBusiness() async {');
      final end = s.indexOf("'latitude': _latitude,", i);
      expect(end, greaterThan(i));
      final body = s.substring(i, end);
      expect(body.contains('if (_latitude == null || _longitude == null) {'),
          isTrue);
      expect(body.contains('return;'), isTrue);
    });

    test('SAVE-01c 0,0 이나 임의 좌표로 채우지 않는다', () {
      expect(s.contains('_latitude ?? 0'), isFalse);
      expect(s.contains('_longitude ?? 0'), isFalse);
      expect(s.contains("'latitude': 0"), isFalse);
      // 저장은 여전히 실제 값을 그대로 보낸다.
      expect(s.contains("'latitude': _latitude,"), isTrue);
      expect(s.contains("'longitude': _longitude,"), isTrue);
    });

    test('SAVE-01d 좌표는 **그 주소의 것**이어야 한다', () {
      // 주소만 고쳐 놓고 예전 좌표로 저장하면, 주소와 좌표가 서로 다른
      // 곳을 가리키는 사업장이 만들어진다.
      expect(
          s.contains('_resolvedAddress == _addressController.text.trim()'),
          isTrue);
      final i = s.indexOf('bool get _hasUsableLocation =>');
      final body = s.substring(i, i + 260);
      expect(body.contains('_latitude != null'), isTrue);
      expect(body.contains('_longitude != null'), isTrue);
    });

    test('SAVE-01e 수정 화면이 멀쩡한 사업장을 "미확인"으로 말하지 않는다', () {
      // 저장된 좌표는 저장된 주소의 것이다 — 그 사실을 같이 들고 온다.
      expect(s.contains('_resolvedAddress = business.address.trim();'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // RACE-01. 늦게 온 결과가 최신 주소를 덮지 않는다
  // ══════════════════════════════════════════════════════════════
  group('RACE-01 주소 재선택', () {
    late final String s;
    setUpAll(() => s = _src(_form));

    test('RACE-01a 요청마다 번호를 발급한다', () {
      expect(s.contains('int _geocodeRequestId = 0;'), isTrue);
      final i = s.indexOf('Future<void> _resolveCoordinates(String address)');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 1400);
      expect(body.contains('final requestId = ++_geocodeRequestId;'), isTrue);
      expect(body.contains('requestId != _geocodeRequestId'), isTrue,
          reason: 'A 가 늦게 끝나도 B 의 좌표를 덮으면 안 된다');
    });

    test('RACE-01b 조회를 시작하면 이전 좌표를 먼저 버린다', () {
      // 들고 있으면 조회 중에 저장 버튼을 눌렀을 때 예전 주소의 좌표가
      // 새 주소로 저장된다.
      final i = s.indexOf('Future<void> _resolveCoordinates(String address)');
      final guard = s.indexOf('requestId != _geocodeRequestId', i);
      final head = s.substring(i, guard);
      expect(head.contains('_latitude = null;'), isTrue);
      expect(head.contains('_longitude = null;'), isTrue);
      expect(head.contains('_resolvedAddress = null;'), isTrue);
    });

    test('RACE-01c 수기 입력도 진행 중 조회를 무효화한다', () {
      final i = s.indexOf('Future<void> _showManualAddressDialog() async {');
      final body = s.substring(i, i + 1400);
      expect(body.contains('_geocodeRequestId++;'), isTrue,
          reason: '직접 넣은 좌표를 늦게 온 조회 결과가 덮으면 안 된다');
    });

    test('RACE-01d 수기 입력에 좌표가 없으면 주소로 찾는다', () {
      final i = s.indexOf('Future<void> _showManualAddressDialog() async {');
      final body = s.substring(i, i + 1400);
      expect(body.contains('await _resolveCoordinates(result.address);'), isTrue,
          reason: '예전에는 좌표 칸을 비우면 그대로 좌표 없는 사업장이 됐다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // FLOW-01. 주소 선택과 좌표 확인은 다른 일이다
  // ══════════════════════════════════════════════════════════════
  group('FLOW-01 주소 검색 다이얼로그', () {
    test('FLOW-01a 다이얼로그가 좌표를 기다리지 않는다', () {
      // 예전에는 주소를 고른 직후 콜백 안에서 좌표 조회를 await 하고 그게
      // 끝나야 닫혔다 — 우편번호 WebView 를 보며 최대 10초를 아무 표시
      // 없이 기다렸고, 실패해도 조용히 좌표만 빈 채로 닫혔다.
      final s = _src(_dialog);
      expect(s.contains('GeocodingService'), isFalse);
      expect(s.contains('onAddressSelected: (selectedResult) {'), isTrue);
    });

    test('FLOW-01b 폼이 자기 화면에서 상태를 보여 주며 받는다', () {
      final s = _src(_form);
      expect(s.contains('await _resolveCoordinates(result.fullAddress);'),
          isTrue);
      expect(s.contains('bool _isResolvingLocation = false;'), isTrue);
    });

    test('FLOW-01c 등록 폼은 기기 위치를 읽지 않는다', () {
      // 본사에서 다른 지점을 등록할 수 있어야 한다. 현장에 서 있어야만
      // 등록되는 구조가 아니라는 것을 고정한다.
      final s = _src(_form);
      for (final banned in const [
        'getCurrentPosition',
        'Geolocator',
        'LocationHelper',
      ]) {
        expect(s.contains(banned), isFalse, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CONSUMER-01. 좌표를 실제로 쓰는 곳
  // ══════════════════════════════════════════════════════════════
  group('CONSUMER-01 downstream', () {
    test('CONSUMER-01a 출퇴근은 좌표가 없으면 fail-closed 다', () {
      // 0,0 폴백이나 "좌표 없으면 통과" 같은 fail-open 이 없는지 본다.
      final s = _src(_attendance);
      final i = s.indexOf('if (business.latitude == null || '
          'business.longitude == null) {');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 500);
      expect(block.contains('return null;'), isTrue,
          reason: '좌표가 없으면 GPS 판정 자체가 성립하지 않는다');
      expect(block.contains('사업장의 GPS 위치가 등록되어 있지 않습니다'), isTrue);
      // 반경 판정이 좌표를 단언(!)으로 쓰므로 위 가드가 유일한 방어다.
      expect(s.contains('businessLat: business.latitude!'), isTrue);
    });

    test('CONSUMER-01b 지도·길찾기도 좌표가 있을 때만 그린다', () {
      final s = _src('lib/screens/common/job_posting_screen.dart');
      expect(
          s.contains(
              'if (_business!.latitude != null && _business!.longitude != null)'),
          isTrue);
      expect(s.contains("ToastHelper.showError('위치 정보가 없습니다')"), isTrue);
    });
  });
}
