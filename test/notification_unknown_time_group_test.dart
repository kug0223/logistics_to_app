// [R7-P1.1] CORRECTION-NOTIFICATION-UNKNOWN-TIME-GROUP
//
//   UNKNOWN != OLD
//
// 시각을 모르는 알림은 `오늘`·`어제`·`이번 주`·`이전` 어디에도 임의로
// 귀속되지 않는다. 그 네 이름은 전부 **언제인지 안다**는 전제 위에 있다.
//
// 이 테스트는 소스에 어떤 글자가 있는지를 보지 않는다. 입력을 넣고
// 나온 그룹을 본다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/screens/common/notification_screen.dart'
    show buildNotificationGroups, kUnknownTimeGroup;
import 'package:ALfit/utils/notification_retention.dart';

/// 지금. 고정값이라 경계 테스트가 달력에 흔들리지 않는다.
final _now = DateTime(2026, 9, 23, 14, 30);

NotificationModel _known(String id, DateTime createdAt) => NotificationModel(
      id: id,
      userId: 'u1',
      type: NotificationType.other,
      title: 't',
      body: 'b',
      createdAt: createdAt,
      createdAtKnown: true,
    );

/// Firestore 문서에 `createdAt`이 없을 때 모델이 만들어지는 그대로.
NotificationModel _unknown(String id) => NotificationModel.fromMap(
      {'userId': 'u1', 'type': 'other', 'title': 't', 'body': 'b'},
      id,
    );

/// 그룹 헤더만 순서대로.
List<String> _headers(List<Object> grouped) =>
    grouped.whereType<String>().toList();

/// [label] 그룹에 속한 알림 id들.
List<String> _idsUnder(List<Object> grouped, String label) {
  final out = <String>[];
  var inside = false;
  for (final item in grouped) {
    if (item is String) {
      inside = item == label;
      continue;
    }
    if (inside) out.add((item as NotificationModel).id);
  }
  return out;
}

/// 이 알림이 들어간 그룹 이름. 어디에도 없으면 null.
String? _groupOf(List<Object> grouped, String id) {
  String? current;
  for (final item in grouped) {
    if (item is String) {
      current = item;
      continue;
    }
    if ((item as NotificationModel).id == id) return current;
  }
  return null;
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // 01. 지시된 5가지 입력
  // ══════════════════════════════════════════════════════════════
  group('01. 시간 그룹 분류', () {
    test('01-a known today → 오늘', () {
      // 같은 날 이른 시각도 `오늘`이다 — 시:분이 아니라 날짜로 가른다.
      final g = buildNotificationGroups(
          [_known('n', DateTime(2026, 9, 23, 0, 5))], _now);
      expect(_groupOf(g, 'n'), '오늘');
    });

    test('01-b known yesterday → 어제', () {
      final g = buildNotificationGroups(
          [_known('n', DateTime(2026, 9, 22, 23, 59))], _now);
      expect(_groupOf(g, 'n'), '어제');
    });

    test('01-c known earlier within 90d → 이번 주 / 이전', () {
      // 3일 전 — 7일 안이므로 `이번 주`
      expect(
        _groupOf(
            buildNotificationGroups(
                [_known('w', DateTime(2026, 9, 20, 9))], _now),
            'w'),
        '이번 주',
      );
      // 40일 전 — 90일 창 안이지만 7일 밖이므로 `이전`
      expect(
        _groupOf(
            buildNotificationGroups(
                [_known('o', _now.subtract(const Duration(days: 40)))], _now),
            'o'),
        '이전',
      );
    });

    test('01-d unknown timestamp → 시간 그룹 어디에도 들어가지 않는다', () {
      final n = _unknown('u');
      expect(n.createdAtKnown, false);

      final g = buildNotificationGroups([n], _now);
      final group = _groupOf(g, 'u');

      expect(group, kUnknownTimeGroup);
      // 핵심: 네 시간 그룹 중 어느 것도 아니다.
      expect(['오늘', '어제', '이번 주', '이전'].contains(group), false);
      // 그리고 사라지지 않았다 — UNKNOWN != EMPTY
      expect(_idsUnder(g, kUnknownTimeGroup), ['u']);
    });

    test('01-e 90d boundary — 창 판정과 그룹 분류는 다른 축이다', () {
      // 창 안(90일)과 창 밖(91일)을 가르는 것은 NotificationRetention이고,
      // 그룹핑은 들어온 것을 나눌 뿐이다. 둘을 섞지 않는다.
      final d89 = _now.subtract(const Duration(days: 89));
      final d90 = _now.subtract(const Duration(days: 90));
      final d91 = _now.subtract(const Duration(days: 91));

      expect(NotificationRetention.isVisible(d89, _now), true);
      expect(NotificationRetention.isVisible(d90, _now), true);
      expect(NotificationRetention.isVisible(d91, _now), false);

      // 창을 통과한 것은 전부 `이전`으로 모인다(7일 밖이므로).
      final g = buildNotificationGroups(
          [_known('a', d89), _known('b', d90)], _now);
      expect(_idsUnder(g, '이전'), ['a', 'b']);

      // 시각을 모르는 알림은 창이 막지 않는다 — 나이를 모르기 때문이다.
      expect(NotificationRetention.isVisible(null, _now), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 그룹 배치 계약
  // ══════════════════════════════════════════════════════════════
  group('02. 배치', () {
    test('02-a 모르는 것은 맨 아래 — 최근 알림과 자리를 다투지 않는다', () {
      final g = buildNotificationGroups([
        _unknown('u'),
        _known('t', _now),
        _known('y', _now.subtract(const Duration(days: 1))),
        _known('o', _now.subtract(const Duration(days: 30))),
      ], _now);

      expect(_headers(g), ['오늘', '어제', '이전', kUnknownTimeGroup]);
      expect(g.last, isA<NotificationModel>());
      expect((g.last as NotificationModel).id, 'u');
    });

    test('02-b 모르는 것이 없으면 그 그룹도 없다 — 빈 헤더를 만들지 않는다', () {
      final g = buildNotificationGroups([_known('t', _now)], _now);
      expect(_headers(g), ['오늘']);
      expect(_headers(g).contains(kUnknownTimeGroup), false);
    });

    test('02-c 모르는 것만 있으면 그 그룹 하나만 선다', () {
      final g = buildNotificationGroups([_unknown('u1'), _unknown('u2')], _now);
      expect(_headers(g), [kUnknownTimeGroup]);
      expect(_idsUnder(g, kUnknownTimeGroup), ['u1', 'u2']);
    });

    test('02-d 라벨이 시간을 주장하지 않는다', () {
      for (final word in ['오늘', '어제', '주', '이전', '전', '일']) {
        expect(kUnknownTimeGroup.contains(word), false, reason: word);
      }
    });

    test('02-e 빈 입력은 빈 결과 — 헤더만 남기지 않는다', () {
      expect(buildNotificationGroups([], _now), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. createdAtKnown이 살아남는가
  // ══════════════════════════════════════════════════════════════
  group('03. createdAtKnown 보존', () {
    test('03-a Timestamp가 아닌 값은 `있다`로 치지 않는다', () {
      // 문자열·숫자로 저장된 createdAt은 Timestamp가 아니므로 UNKNOWN이다.
      for (final bad in [null, 'anything', 123, <String, dynamic>{}]) {
        final m = NotificationModel.fromMap({
          'userId': 'u',
          'type': 'other',
          'title': 't',
          'body': 'b',
          if (bad != null) 'createdAt': bad,
        }, 'x');
        expect(m.createdAtKnown, false, reason: '$bad');
      }
    });

    test('03-b 읽음 처리가 UNKNOWN을 지우지 않는다', () {
      // markAsRead는 copyWith(isRead: true)로 새 인스턴스를 만든다.
      // 거기서 플래그가 기본값 true로 되돌아가면, 그 알림은 읽는 순간
      // `날짜 확인 불가`에서 시간 그룹으로 이동한다.
      final n = _unknown('u').copyWith(isRead: true);
      expect(n.createdAtKnown, false);
      final g = buildNotificationGroups([n], _now);
      expect(_groupOf(g, 'u'), kUnknownTimeGroup);
    });
  });
}
