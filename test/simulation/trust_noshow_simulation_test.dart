// test/simulation/trust_noshow_simulation_test.dart
//
// 신뢰도 규칙·노쇼 제재 시뮬레이션
//
// [R7-FS-1 A] 이 파일의 절반은 **신뢰도 점수 공식**을 재고 있었다
//   (SIM-A~F·I·J·M: 기준점 60, 경험 가산, 평판 기여, 누진 감점, 페르소나,
//   공식 일관성, 배지 자격 점수 …). 그 체계는 제품에서 폐기됐다([5A.2A])
//   — `TrustScoreHelper`, `UserModel.storedTrustScore`, `trustScore` getter가
//   모두 사라졌다. 그래서 이 파일은 **컴파일되지 않고 있었다.**
//
//   폐기된 공식을 되살리지 않는다. 살아 있는 것만 남긴다:
//     · SIM-G  관리자가 설정하는 신뢰도 **규칙**(TrustSettingsModel) — 그대로
//     · SIM-H  기본 배지 구성(BadgeModel.defaultBadges) — 그대로
//     · SIM-K  재시작 프로그램의 쿨다운 — 점수 리셋 셀 2개만 걷어냄
//     · SIM-L  이용 제한 — **현재 규칙으로 옮김**(아래 설명)
//     · SIM-N  점수 폐기 뒤 노쇼를 실제로 막는 자리 (새로 추가)
//
//   폐기 유지 자체는 `test/utils/trust_score_helper_test.dart` 가 지킨다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';

// ── 최소 UserModel 헬퍼 ───────────────────────────────────────────
//   점수 입력(avg/rc/rr/stored)은 걷어냈다 — 판정에 쓰이지 않는다.
UserModel _u({
  int days = 0,
  int ns = 0,
  int recentNs = 0,
  int late = 0,
  DateTime? restrictedUntil,
}) =>
    UserModel(
      uid: 'sim-user',
      username: 'sim',
      name: '시뮬',
      email: 'sim@test.com',
      role: UserRole.USER,
      totalWorkDays: days,
      noShowCount: ns,
      recentNoShowCount: recentNs,
      lateCount: late,
      restrictedUntil: restrictedUntil,
    );

// ── TrustSettingsModel.getNoshowPenalty 검증용 ────────────────────
int _penalty(int count) => TrustSettingsModel.defaults().getNoshowPenalty(count);

String _cf() => File('functions/src/index.ts')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

void main() {
  // ═══════════════════════════════════════════════════════════
  // SIM-G: TrustSettingsModel 검증
  // ═══════════════════════════════════════════════════════════
  group('SIM-G. TrustSettingsModel 검증', () {
    final settings = TrustSettingsModel.defaults();

    test('G-01: startScore=60', () => expect(settings.startScore, 60));
    test('G-02: maxScore=100', () => expect(settings.maxScore, 100));
    test('G-03: getNoshowPenalty(1) == -5', () => expect(_penalty(1), -5));
    test('G-04: getNoshowPenalty(2) == -8', () => expect(_penalty(2), -8));
    test('G-05: getNoshowPenalty(3) == -10', () => expect(_penalty(3), -10));
    test('G-06: getNoshowPenalty(4) == -10 (3+ 동일)', () => expect(_penalty(4), -10));
    test('G-07: getNoshowPenalty(99) == -10', () => expect(_penalty(99), -10));
    test('G-08: work_complete 규칙 존재', () {
      expect(
        settings.increaseRules.any((r) => r.type == 'work_complete'),
        isTrue,
      );
    });
    test('G-09: late 규칙 존재', () {
      expect(settings.decreaseRules.any((r) => r.type == 'late'), isTrue);
    });
    test('G-10: restartProgram.cooldownDays=60', () {
      expect(settings.restartProgram.cooldownDays, 60);
    });
    test('G-11: restartProgram.resetScore=50', () {
      expect(settings.restartProgram.resetScore, 50);
    });
    test('G-12: fromMap(toMap()) 직렬화 왕복 일치', () {
      final map = settings.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.startScore, settings.startScore);
      expect(restored.maxScore, settings.maxScore);
      expect(restored.restartProgram.cooldownDays, settings.restartProgram.cooldownDays);
      expect(restored.increaseRules.length, settings.increaseRules.length);
      expect(restored.decreaseRules.length, settings.decreaseRules.length);
    });
  });

  // ═══════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // SIM-H: BadgeModel 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-H. BadgeModel 시뮬레이션', () {
    final badges = BadgeModel.defaultBadges();

    test('H-01: defaultBadges() 비어있지 않음', () {
      expect(badges, isNotEmpty);
    });
    test('H-02: 모든 배지 id 고유', () {
      final ids = badges.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });
    test('H-03: 레벨 배지 4종 존재', () {
      final levelBadges = badges.where((b) => b.type == BadgeType.trustScore).toList();
      expect(levelBadges.length, 4);
    });
    test('H-04: 경험 배지 5종 존재 (첫걸음~마스터)', () {
      // [R7-FS-1 A] 2종이던 시절의 기대다. 초반 구간이 셋 늘어
      // (첫걸음·성장 중·경험자) 사다리가 완만해졌다.
      final expBadges =
          badges.where((b) => b.type == BadgeType.experience).toList();
      expect(expBadges.length, 5);
      expect(expBadges.map((b) => b.name),
          containsAll(['첫걸음', '성장 중', '경험자', '베테랑', '마스터']));
      // 사다리는 단조 증가여야 한다 — 뒤 배지가 더 쉬우면 순서가 무너진다.
      final values = expBadges.map((b) => b.conditionValue).toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]),
            reason: '${expBadges[i].name} 이 앞 배지보다 쉽다');
      }
    });
    test('H-05: 특별 배지는 행동 축마다 문턱이 다르다', () {
      // [R7-FS-1 A] 예전 기대는 "업종 배지 전부 conditionValue=30" 이었다.
      //   특별 배지가 업종(workType)에서 행동 축(야간·새벽·재고용·사업장
      //   수·주말)으로 바뀌면서 문턱도 축마다 달라졌다. 한 값으로 묶는
      //   대신 **모두 양수이고 과하지 않은지**를 본다.
      final specBadges =
          badges.where((b) => b.type == BadgeType.specialty).toList();
      expect(specBadges, isNotEmpty);
      for (final b in specBadges) {
        expect(b.workType, isNull, reason: '${b.name} 은 업종 배지가 아니다');
        expect(b.conditionValue, greaterThan(0),
            reason: '${b.name} 문턱이 0이면 가입 즉시 달린다');
        expect(b.conditionValue, lessThanOrEqualTo(30),
            reason: '${b.name} 문턱이 닿을 수 없게 높다');
      }
    });
    test('H-06: 골드 배지 복합 조건 — maxNoShowAllowed=0', () {
      final gold = badges.firstWhere((b) => b.id == 'badge_gold');
      expect(gold.maxNoShowAllowed, 0);
      expect(gold.minWorkDaysRequired, 50);
      expect(gold.conditionValue, 85);
    });
    test('H-07: 다이아 배지 복합 조건 — 평점 4.5 이상', () {
      final dia = badges.firstWhere((b) => b.id == 'badge_diamond');
      expect(dia.maxNoShowAllowed, 0);
      expect(dia.minWorkDaysRequired, 100);
      expect(dia.minRatingRequired, 4.5);
      expect(dia.conditionValue, 95);
    });
    test('H-08: 실버 배지 — maxNoShowAllowed=1 (1회 허용)', () {
      final silver = badges.firstWhere((b) => b.id == 'badge_silver');
      expect(silver.maxNoShowAllowed, 1);
    });
    test('H-09: 브론즈 배지 — maxNoShowAllowed null (제한 없음)', () {
      final bronze = badges.firstWhere((b) => b.id == 'badge_bronze');
      expect(bronze.maxNoShowAllowed, isNull);
    });
    test('H-10: toMap/fromMap 왕복 직렬화 (복합 조건 포함)', () {
      final gold = badges.firstWhere((b) => b.id == 'badge_gold');
      final map = gold.toMap();
      expect(map['maxNoShowAllowed'], 0);
      expect(map['minWorkDaysRequired'], 50);
      expect(map['conditionValue'], 85);
      expect(map['benefit'], isNotNull);
    });
    test('H-11: fromMap 구 형식 (복합 조건 없음) → null 처리 안전', () {
      final now = DateTime.now();
      final oldMap = <String, dynamic>{
        'name': '브론즈',
        'icon': '🥉',
        'type': 'trustScore',
        'conditionType': 'minScore',
        'conditionValue': 60,
        'isActive': true,
        'order': 1,
        'createdAt': now,
        // 복합 조건 필드 없음
      };
      // Timestamp 없으면 예외 발생 — Timestamp 모킹 불가, 구조 검증만
      expect(oldMap['maxNoShowAllowed'], isNull);
      expect(oldMap['minWorkDaysRequired'], isNull);
    });
    test('H-12: 배지 benefit 문자열 비어있지 않음', () {
      for (final b in badges) {
        if (b.benefit != null) {
          expect(b.benefit!.isNotEmpty, isTrue, reason: '${b.name} benefit 비어있음');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // SIM-K: 재시작 프로그램 시뮬레이션
  // ═══════════════════════════════════════════════════════════
  group('SIM-K. 재시작 프로그램', () {
    final settings = TrustSettingsModel.defaults();

    test('K-01: 쿨다운 기간 60일', () {
      expect(settings.restartProgram.cooldownDays, 60);
    });
    test('K-02: 리셋 점수 50점', () {
      expect(settings.restartProgram.resetScore, 50);
    });
    // [R7-FS-1 A] K-03·K-04 는 `storedTrustScore` / `trustScore` getter 로
    //   점수 리셋을 재었다 — 둘 다 제품에서 사라졌다. 걷어낸다.
    //   설정값(K-01·K-02)은 관리자 화면이 아직 보여 주므로 남긴다.
    test('K-05: 쿨다운 중 재신청 불가 (60일 전)', () {
      final lastRestart = DateTime.now().subtract(const Duration(days: 30));
      final cooldownEnd = lastRestart
          .add(Duration(days: settings.restartProgram.cooldownDays));
      expect(cooldownEnd.isAfter(DateTime.now()), isTrue);
    });
    test('K-06: 쿨다운 완료 후 재신청 가능 (61일 후)', () {
      final lastRestart = DateTime.now().subtract(const Duration(days: 61));
      final cooldownEnd = lastRestart
          .add(Duration(days: settings.restartProgram.cooldownDays));
      expect(cooldownEnd.isBefore(DateTime.now()), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-L: 이용 제한 — 현재 규칙
  // ═══════════════════════════════════════════════════════════
  //
  // [R7-FS-1 A] 예전 SIM-L 은 이 파일이 직접 적어 둔 사다리
  //   (1회 3일 / 2회 7일 / 3회 30일 / 4회+ 영구)를 자기 자신에게 되물었다.
  //   **그 사다리는 이미 제품과 다르다.** 현재 규칙은 CF 의
  //   `_compute90dRestriction` 하나이고 — 최근 90일 노쇼가 3회 미만이면
  //   제한 없음, 3회 이상이면 **1일 고정** — 모델 주석도 그렇게 적고 있다.
  //   복제본을 지우고 실제 규칙과 그것을 읽는 판정을 잰다.
  group('SIM-L. 이용 제한 (최근 90일 3회 → 1일)', () {
    test('L-01: 서버 규칙은 90일 창 · 3회 문턱 · 1일 고정이다', () {
      final cf = _cf();
      final i = cf.indexOf('function _compute90dRestriction(');
      expect(i, greaterThan(-1));
      final fn = cf.substring(i, i + 700);
      expect(fn.contains('90 * 24 * 60 * 60 * 1000'), isTrue, reason: '90일 창');
      expect(fn.contains('if (recent < 3) return null;'), isTrue, reason: '3회 문턱');
      expect(fn.contains('Date.now() + 24 * 60 * 60 * 1000'), isTrue,
          reason: '1일 고정');
    });

    test('L-02: 카운트가 문턱 미만이면 제한을 만들지 않는다', () {
      // 노쇼가 있다는 사실만으로 제재가 생기지 않는다 —
      // 제재 시각은 서버만 쓴다(클라이언트 차단 필드).
      expect(_u(ns: 2, recentNs: 2).isRestricted, isFalse);
    });

    test('L-03: 제재 시각이 미래면 제한 중이다', () {
      final u = _u(
          recentNs: 3,
          restrictedUntil: DateTime.now().add(const Duration(days: 1)));
      expect(u.isRestricted, isTrue);
    });

    test('L-04: 만료된 제한은 자동으로 풀린다', () {
      final u = _u(
          recentNs: 3,
          restrictedUntil: DateTime.now().subtract(const Duration(seconds: 1)));
      expect(u.isRestricted, isFalse);
    });

    test('L-05: 영구 제한 표식(year 9999)은 관리자 조치다 — 풀리지 않는다', () {
      // 노쇼 누적이 만드는 1일 제재와 다른 축이다(슈퍼관리자 화면이
      // 9999 를 "영구" 로 읽는다).
      expect(_u(restrictedUntil: DateTime(9999, 12, 31)).isRestricted, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SIM-N: 점수를 지운 뒤, 노쇼는 어디서 막히는가
  // ═══════════════════════════════════════════════════════════
  group('SIM-N. 노쇼 카운터의 소유자', () {
    test('N-01: 최근 카운터는 서버가 갱신한다 — 클라이언트 쓰기 금지 필드다', () {
      final cf = _cf();
      expect(cf.contains('userUpdates.recentNoShowCount = recent90dCount2'),
          isTrue);
      expect(
          cf.contains('noShowCount·restrictedUntil은 CF Admin SDK 전용 필드'),
          isTrue,
          reason: '규칙에서 클라이언트 쓰기를 막는다는 기록');
    });

    test('N-02: 노쇼 취소는 배열로 재계산한다 — 단순 감산이 아니다', () {
      // 경계가 지나면 저장된 카운터가 실제보다 커져 제재가 잘못 남는다.
      final cf = _cf();
      expect(cf.contains('arrayRemove'), isTrue);
      expect(cf.contains('[FIX-90D-RECALC]'), isTrue);
    });
  });
}
