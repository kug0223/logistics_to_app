// [E1-CORRECTION-1 / E1-RESTRICT] 두 가지를 고정한다.
//
// ── Part A — 지역 온보딩에서 나가는 문 ────────────────────────────────
//   `AuthWrapper` 는 `homeRegion == null` 인 USER 에게
//   `_HomeRegionRecoveryScreen` 을 **루트로** 반환한다. Navigator 스택이
//   비어 있고 AppBar·건너뛰기도 없어서, 지역을 저장하기 전까지 그 계정에서
//   빠져나올 방법이 전혀 없었다(앱 데이터 삭제 외). 다른 QA 계정으로
//   전환할 수도 없었다.
//
//   고친 것은 **나가는 문 하나**다 — 기존 `UserProvider.signOut()` 을
//   그대로 호출하는 보조 버튼. 지역 필수 정책은 그대로 두고, 건너뛰기도
//   기본 지역 자동 저장도 추가하지 않았다.
//
// ── Part B — 제재 해제 시각 안내 ──────────────────────────────────────
//   판정은 절대 시각 비교라 정확했지만, 안내 문구가
//   `restrictedUntil.toLocal()` 의 **성분**을 써서 기기 시간대에 따라 날짜가
//   달라졌다(GMT 기기에서는 전날). 해제 시각(그 날 오전 6시)도 말하지
//   않아 "…일까지" 를 다음 날부터 가능하다고 읽을 수 있었다.
//
//   `FormatHelper.formatKstDateTimeKorean` 하나를 지나게 해서, 어느
//   시간대에서도 같은 KST 날짜·시각을 말한다.
//
// 이 파일은 KST 기본 환경과 `TZ=UTC` 양쪽에서 통과해야 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/format_helper.dart';

String _src(String p) =>
    File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// 주석 줄을 뺀 코드 — 설명문이 자기 자신을 잡지 않도록.
String _code(String p) => _src(p)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 제재 만료 fixture: 2026-10-15 06:00 KST == 2026-10-14 21:00 UTC.
final DateTime _expiry = DateTime.utc(2026, 10, 14, 21, 0);
const String _expected = '2026년 10월 15일 오전 6시';

void main() {
  group('[OX-A] 지역 온보딩에서 나갈 수 있다', () {
    test('OX-1 로그아웃 경로가 있다', () {
      final c = _code('lib/main.dart');
      expect(c.contains("const Text('로그아웃',"), isTrue,
          reason: '라벨은 뒤로가기와 혼동되지 않게 "로그아웃" 이어야 한다');
      expect(c.contains('Future<void> _signOut() async'), isTrue);
    });

    test('OX-2 기존 UserProvider.signOut 을 그대로 쓴다', () {
      final c = _code('lib/main.dart');
      expect(c.contains('context.read<UserProvider>().signOut()'), isTrue,
          reason: '인증 종료 로직을 복제하지 않는다');
      // 이 화면이 FirebaseAuth 를 직접 만지지 않는다.
      final start = c.indexOf('class _HomeRegionRecoveryScreenState');
      final end = c.indexOf('class ', start + 10);
      final screen = c.substring(start, end == -1 ? c.length : end);
      expect(screen.contains('FirebaseAuth'), isFalse,
          reason: '별도 인증 로직을 복제하면 상태가 둘로 갈린다');
      expect(screen.contains('Navigator.push'), isFalse,
          reason: '화면 전환은 AuthWrapper 가 한다 — 스택을 직접 조작하지 않는다');
      expect(screen.contains('pushAndRemoveUntil'), isFalse);
    });

    test('OX-3 연속 탭으로 signOut 을 두 번 부르지 않는다', () {
      final c = _code('lib/main.dart');
      expect(c.contains('bool _isSigningOut = false;'), isTrue);
      expect(c.contains('if (_isLoading || _isSigningOut) return;'), isTrue);
      expect(
          c.contains('onPressed: (_isLoading || _isSigningOut) ? null : _signOut'),
          isTrue,
          reason: '진행 중에는 버튼이 비활성이어야 한다');
    });

    test('OX-4 로그아웃 실패는 안내하고 다시 시도할 수 있다', () {
      final c = _code('lib/main.dart');
      final start = c.indexOf('Future<void> _signOut() async');
      final body = c.substring(start, start + 700);
      expect(body.contains('catch'), isTrue);
      expect(body.contains('_isSigningOut = false'), isTrue,
          reason: '실패하면 버튼이 다시 눌려야 한다');
      expect(body.contains('ToastHelper.showError'), isTrue);
    });

    test('OX-5 지역 필수 정책은 그대로다 — 건너뛰기를 만들지 않았다', () {
      final c = _code('lib/main.dart');
      final start = c.indexOf('class _HomeRegionRecoveryScreenState');
      final end = c.indexOf('class ', start + 10);
      final screen = c.substring(start, end == -1 ? c.length : end);
      for (final banned in ['건너뛰기', '나중에 하기', 'skip']) {
        expect(screen.contains(banned), isFalse,
            reason: '우회 경로를 추가하지 않는다 ($banned)');
      }
      // 사용자가 고르지 않은 지역을 대신 저장하지 않는다.
      expect(screen.contains('_selected == null || _isLoading'), isTrue,
          reason: '선택 전에는 저장 버튼이 비활성이다');
    });

    test('OX-6 AuthWrapper 의 필수 온보딩 분기는 유지된다', () {
      final c = _code('lib/main.dart');
      expect(c.contains('if (user.homeRegion == null)'), isTrue);
      expect(c.contains('_HomeRegionRecoveryScreen()'), isTrue);
    });

    test('OX-7 작은 화면·큰 배율에서 잘리지 않도록 스크롤한다', () {
      final c = _code('lib/main.dart');
      final start = c.indexOf('class _HomeRegionRecoveryScreenState');
      final end = c.indexOf('class ', start + 10);
      final screen = c.substring(start, end == -1 ? c.length : end);
      expect(screen.contains('SingleChildScrollView'), isTrue,
          reason: '버튼이 하나 늘었다 — 320dp·배율 2.0 에서 넘칠 수 있다');
    });
  });

  group('[OX-B] 제재 해제 시각은 KST 로 말한다', () {
    test('OX-8 2026-10-14 21:00 UTC → 2026년 10월 15일 오전 6시', () {
      expect(FormatHelper.formatKstDateTimeKorean(_expiry), _expected);
    });

    test('OX-9 기기 시간대와 무관하다 — 같은 instant, 같은 문구', () {
      // 같은 순간을 어느 시간대 표현으로 주어도 결과가 같아야 한다.
      final asLocal = _expiry.toLocal();
      final asUtc = _expiry.toUtc();
      expect(FormatHelper.formatKstDateTimeKorean(asLocal), _expected);
      expect(FormatHelper.formatKstDateTimeKorean(asUtc), _expected);
      expect(
          FormatHelper.formatKstDateTimeKorean(
              DateTime.fromMillisecondsSinceEpoch(
                  _expiry.millisecondsSinceEpoch)),
          _expected);
    });

    test('OX-10 KST 자정 경계 — UTC 로는 전날이어도 KST 날짜를 말한다', () {
      // KST 2026-10-15 00:00 == UTC 2026-10-14 15:00
      expect(FormatHelper.formatKstDateTimeKorean(DateTime.utc(2026, 10, 14, 15)),
          '2026년 10월 15일 오전 12시');
      // KST 2026-10-14 23:59
      expect(
          FormatHelper.formatKstDateTimeKorean(
              DateTime.utc(2026, 10, 14, 14, 59)),
          '2026년 10월 14일 오후 11시 59분');
    });

    test('OX-11 오전·오후·정오·자정 표기', () {
      // KST 12:00 (정오) == UTC 03:00
      expect(FormatHelper.formatKstDateTimeKorean(DateTime.utc(2026, 10, 15, 3)),
          '2026년 10월 15일 오후 12시');
      // KST 13:30 == UTC 04:30
      expect(
          FormatHelper.formatKstDateTimeKorean(DateTime.utc(2026, 10, 15, 4, 30)),
          '2026년 10월 15일 오후 1시 30분');
      // KST 09:05 == UTC 00:05
      expect(
          FormatHelper.formatKstDateTimeKorean(DateTime.utc(2026, 10, 15, 0, 5)),
          '2026년 10월 15일 오전 9시 5분');
    });

    test('OX-12 분이 0이면 분을 붙이지 않는다', () {
      expect(FormatHelper.formatKstDateTimeKorean(_expiry).endsWith('6시'),
          isTrue);
    });

    test('OX-13 로그인 차단 문구가 그 formatter 를 쓴다', () {
      final c = _code('lib/services/auth_service.dart');
      expect(c.contains('FormatHelper.formatKstDateTimeKorean'), isTrue);
      expect(c.contains('(한국시간)까지 이용이 제한돼요.'), isTrue);
      // 기기 local 성분으로 날짜를 만들던 옛 문구는 없어야 한다.
      expect(
          c.contains(r'${restrictedDate.year}년 ${restrictedDate.month}월'),
          isFalse,
          reason: '기기 시간대에 따라 날짜가 달라지던 표기');
    });

    test('OX-14 판정식은 바꾸지 않았다 — 절대 시각 비교 그대로', () {
      final c = _code('lib/services/auth_service.dart');
      expect(c.contains('restrictedDate.isAfter(DateTime.now())'), isTrue,
          reason: '표시만 고친다. 차단 조건은 기존 계약이다');
      expect(c.contains('await _auth.signOut();'), isTrue);
    });

    test('OX-15 영구 제한 안내는 그대로 유지된다', () {
      final c = _code('lib/services/auth_service.dart');
      expect(c.contains('restrictedDate.year >= 9999'), isTrue);
      expect(c.contains('이용 제한(기한 없음) 상태예요.'), isTrue);
    });

    test('OX-16 restrictedUntil 이 없거나 형식이 다르면 안내를 만들지 않는다', () {
      final c = _code('lib/services/auth_service.dart');
      expect(c.contains('if (restrictedUntilTs is Timestamp)'), isTrue,
          reason: '형식이 아니면 제재 분기 자체에 들어가지 않는다');
    });

    test('OX-17 서버 writer·정책은 건드리지 않았다', () {
      final c = _code('lib/services/auth_service.dart');
      for (final banned in [
        'restrictedUntil:',
        'noShowCount',
        'recentNoShowCount',
      ]) {
        expect(c.contains(banned), isFalse,
            reason: '클라이언트가 제재 상태를 쓰지 않는다 ($banned)');
      }
    });
  });
}
