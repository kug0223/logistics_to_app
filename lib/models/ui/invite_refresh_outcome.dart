/// [ISG2-REFRESH] 초대 다이얼로그가 닫힌 뒤 무엇을 할지 — **식은 여기 하나다.**
///
/// 초대 다이얼로그(`InviteWorkerDialog`)는 [InviteDialogResult] 로 닫힌다
/// (sent / canceled / unconfirmed). `null` 은 바깥에서 닫힌 경우다.
///
/// 그래서 두 가지를 따로 정한다.
///   [InviteRefreshOutcome.propagate] 상위(공고 카드·홈)에 "바뀌었다"고
///     알릴 것인가 — **확인된 성공에서만** 한다. 모르는 것을 성공으로
///     표시하지 않는다.
///   [InviteRefreshOutcome.reload] 이 화면이 목록을 다시 읽을 것인가 —
///     취소를 제외하면 읽는다. 모르는 경우에 읽지 않으면, 실제로 저장된
///     초대가 화면에 영영 안 나타난다. 재조회는 읽기이고, 실패하면
///     목록 쪽이 자기 방식대로 말한다(조회 실패 ≠ 대기 0).
class InviteRefreshOutcome {
  const InviteRefreshOutcome(
      {required this.propagate, required this.reload, this.verify});

  /// 상위 화면에 변경을 알릴 것인가(= `_hasChanges`).
  final bool propagate;

  /// 이 화면이 목록을 다시 읽을 것인가(= `_load()`).
  final bool reload;

  /// [E1-AMBIGUOUS-INVITE] 저장을 시도했는데 성공을 확인하지 못한 채
  /// 닫혔다 — 이 대상의 지원서를 다시 읽어 확인한 뒤에만 전파한다.
  final InviteVerifyTarget? verify;

  @override
  bool operator ==(Object other) =>
      other is InviteRefreshOutcome &&
      other.propagate == propagate &&
      other.reload == reload &&
      other.verify == verify;

  @override
  int get hashCode => Object.hash(propagate, reload, verify);

  @override
  String toString() =>
      'InviteRefreshOutcome(propagate: $propagate, reload: $reload, verify: $verify)';
}

/// [E1-AMBIGUOUS-INVITE] 다시 읽어 확인할 초대의 자리.
class InviteVerifyTarget {
  const InviteVerifyTarget(
      {required this.toId, required this.targetUid, this.slotId});
  final String toId;
  final String targetUid;
  final String? slotId;

  @override
  bool operator ==(Object other) =>
      other is InviteVerifyTarget &&
      other.toId == toId &&
      other.targetUid == targetUid &&
      other.slotId == slotId;

  @override
  int get hashCode => Object.hash(toId, targetUid, slotId);

  @override
  String toString() => 'InviteVerifyTarget($toId/$slotId/$targetUid)';
}

/// [E1-AMBIGUOUS-INVITE] 초대 다이얼로그가 닫힌 이유.
///
///   sent        서버가 저장했다(응답을 받았거나, 다시 읽어 확인했다)
///   canceled    저장을 시도하지 않았거나, 시도가 **명확히 거절**됐다
///   unconfirmed 저장을 시도했는데 응답이 불명확했고 저장을 확인하지 못했다
///
/// 예전에는 `bool` 이었다. 저장 중 오류 뒤 사용자가 닫으면 `false`(=취소)가
/// 와서, 실제로 저장된 초대가 취소처럼 보이고 아무 데도 반영되지 않았다.
enum InviteDialogStatus { sent, canceled, unconfirmed }

class InviteDialogResult {
  const InviteDialogResult._(this.status, this.verify);
  const InviteDialogResult.sent() : this._(InviteDialogStatus.sent, null);
  const InviteDialogResult.canceled()
      : this._(InviteDialogStatus.canceled, null);
  const InviteDialogResult.unconfirmed(InviteVerifyTarget target)
      : this._(InviteDialogStatus.unconfirmed, target);

  final InviteDialogStatus status;
  final InviteVerifyTarget? verify;

  bool get isSent => status == InviteDialogStatus.sent;
}

/// 초대 다이얼로그의 반환값 → 할 일.
///
///   sent        → 전파 + 재조회
///   canceled    → 아무것도 하지 않는다
///   unconfirmed → 전파하지 않고 재조회, 그리고 **대상 지원서 확인**(verify)
///   null        → 바깥에서 닫혔다 — 전파하지 않고 재조회
InviteRefreshOutcome inviteDialogOutcome(InviteDialogResult? dialogResult) =>
    switch (dialogResult?.status) {
      InviteDialogStatus.sent =>
        const InviteRefreshOutcome(propagate: true, reload: true),
      InviteDialogStatus.canceled =>
        const InviteRefreshOutcome(propagate: false, reload: false),
      InviteDialogStatus.unconfirmed => InviteRefreshOutcome(
          propagate: false, reload: true, verify: dialogResult!.verify),
      null => const InviteRefreshOutcome(propagate: false, reload: true),
    };

/// 근무 가능일 시트(`AvailableWorkersBottomSheet`)의 결과 → 할 일.
///
/// 이쪽은 성공 콜백(`onInviteSucceeded`)으로 성공을 **직접** 알려 준다.
/// 시트를 그냥 닫은 경우는 취소와 같아 보이지만, 시트 안에서 여러 명을
/// 초대하다 일부만 성공했을 수 있으므로 **읽기는 한다**.
InviteRefreshOutcome inviteSheetOutcome({required bool anySucceeded}) =>
    InviteRefreshOutcome(propagate: anySucceeded, reload: true);
