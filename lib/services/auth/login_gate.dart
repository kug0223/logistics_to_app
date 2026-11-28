// lib/services/auth/login_gate.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §2.8 · K7] 로그인 허용 판정 — 순수 함수.
//
//   아이디 로그인(`AuthService.signIn`)이 users 문서를 읽은 뒤 하는 판정
//   (AS:113-158 — 이용 차단 → 가입 미완료 → 거절 → 기간 제한)을 **같은 순서·같은 문구**로
//   옮겨 둔 것이다. 카카오(custom token) 로그인과 자동 복원(`UserProvider._loadUserData`)이
//   이 판정을 함께 쓴다.
//
//   signIn 본문은 고치지 않았다 — 문구 원문을 소스 그대로 대조하는 시험(DU582b LGBL 등)이
//   signIn 안의 리터럴을 핀으로 잡고 있다. 대신 `login_gate_parity_test.dart` 가 두 판정의
//   결과·문구가 같은지 대조한다.
//
//   `deleting` 은 막지 않는다 — 삭제 재개 화면으로 보내야 한다(B277-06). 호출자가 kind 로 가른다.
//   업무 gate(지원·확정 등)는 여기서 하지 않는다(서버 gate 별도 유지).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/core/user_model.dart';
import '../auth_service.dart';

enum LoginGateKind {
  /// 로그인해도 된다.
  ok,

  /// 계정 이용 차단(블랙리스트).
  blacklisted,

  /// 옛 가입 미완료(pending / registration_pending) — 옛 아이디 계정에서만 생긴다.
  incompleteLegacy,

  /// 가입 거절.
  rejected,

  /// 기간 이용 제한 중.
  restricted,

  /// 탈퇴 진행 중 — 막지 않고 삭제 재개로 보낸다.
  deleting,
}

class LoginGateVerdict {
  const LoginGateVerdict(this.kind, [this.message]);

  final LoginGateKind kind;

  /// 사용자에게 보일 문장(ok·deleting·incompleteLegacy 는 null).
  final String? message;

  bool get allowed => kind == LoginGateKind.ok;

  /// 세션을 끊어야 하는 판정인가(아이디 로그인과 같은 규칙).
  bool get signsOut =>
      kind == LoginGateKind.blacklisted ||
      kind == LoginGateKind.rejected ||
      kind == LoginGateKind.restricted;

  @override
  String toString() => 'LoginGateVerdict($kind, $message)';
}

class LoginGate {
  LoginGate._();

  /// 판정 본체. [now] 는 시험용(기본 = 기기 현재 시각, signIn 과 같다).
  static LoginGateVerdict evaluate({
    required bool isBlacklisted,
    String? blacklistReason,
    required String accountStatus,
    String? rejectionReason,
    DateTime? restrictedUntil,
    String? restrictionSource,
    DateTime? now,
  }) {
    // [판정280 B280-02] deleting 을 **이용 차단보다 먼저** 본다(서버 srvAccountStateVerdict 와 같은 순서 —
    //   signup_core.ts:399). 차단된 계정이 탈퇴 중이면 일반 홈은 열리지 않고 삭제 재개 화면만 열린다.
    //   예전처럼 차단 판정으로 세션을 끊으면 그 계정은 탈퇴를 끝낼 길을 잃는다.
    if (accountStatus == 'deleting') {
      return const LoginGateVerdict(LoginGateKind.deleting);
    }
    if (isBlacklisted) {
      final reason = (blacklistReason == null) ? '이용 정책 위반' : blacklistReason;
      return LoginGateVerdict(
        LoginGateKind.blacklisted,
        '계정 이용 차단 상태라 해제 전까지 로그인할 수 없어요.\n사유: $reason\n고객센터에 문의해주세요.',
      );
    }
    if (accountStatus == 'registration_pending' || accountStatus == 'pending') {
      return const LoginGateVerdict(LoginGateKind.incompleteLegacy);
    }
    if (accountStatus == 'rejected') {
      return LoginGateVerdict(
        LoginGateKind.rejected,
        rejectionReason != null
            ? '가입이 거절되었습니다.\n사유: $rejectionReason'
            : '가입이 거절되었습니다.\n고객센터에 문의해주세요.',
      );
    }
    if (restrictedUntil != null) {
      final local = restrictedUntil.toLocal();
      if (local.isAfter(now ?? DateTime.now())) {
        return LoginGateVerdict(
          LoginGateKind.restricted,
          AuthService.restrictionLoginMessage(restrictedUntil, restrictionSource),
        );
      }
    }
    return const LoginGateVerdict(LoginGateKind.ok);
  }

  /// users 문서 원본으로 판정(아이디 로그인과 같은 입력).
  static LoginGateVerdict fromMap(Map<String, dynamic> data, {DateTime? now}) {
    final ts = data['restrictedUntil'];
    return evaluate(
      isBlacklisted: data['isBlacklisted'] == true,
      blacklistReason: data['blacklistReason'] as String?,
      accountStatus: data['accountStatus'] as String? ?? 'active',
      rejectionReason: data['rejectionReason'] as String?,
      // signIn 과 같다 — Timestamp 가 아니면 제한 없음으로 읽는다.
      restrictedUntil: ts is Timestamp ? ts.toDate() : null,
      restrictionSource: data['restrictionSource'] as String?,
      now: now,
    );
  }

  /// 이미 읽은 모델로 판정(자동 복원 경로). 모델에는 restrictionSource 가 없어 출처 문구는 일반형이다.
  static LoginGateVerdict fromUser(UserModel u, {DateTime? now}) => evaluate(
        isBlacklisted: u.isBlacklisted,
        blacklistReason: u.blacklistReason,
        accountStatus: u.accountStatus,
        rejectionReason: u.rejectionReason,
        restrictedUntil: u.restrictedUntil,
        now: now,
      );
}
