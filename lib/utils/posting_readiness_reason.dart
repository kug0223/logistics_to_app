// lib/utils/posting_readiness_reason.dart
//
// [R7-P4.4C] 서버가 거부한 **이유**를 준비 단계로 잇는다.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   `assertBusinessPostingReady` 는 다섯 축을 본다 — 승인 · 등록증 · 활성
//   업무 · 계약서 템플릿 · 고용주 날인. 예전에는 전부 `failed-precondition`
//   에 한국어 문장 하나로 내려왔고, 화면은 `e.message` 를 그대로 띄웠다.
//   그러면 (1) 어느 준비 단계로 보내야 하는지 코드가 알 수 없고
//   (2) 서버 문구가 바뀌면 화면이 조용히 따라 바뀐다.
//
//   그래서 서버가 `POSTING_NOT_READY:<REASON> <사람이 읽을 문장>` 형태로
//   내려주고, 이 파일이 그 REASON 을 **준비 단계**와 **문구**로 번역한다.
//   `MAX_ACTIVE_TO_LIMIT:N` 이 이미 쓰던 접두어 관례와 같은 모양이다.
//
//   raw 예외 문자열을 사용자에게 보여주지 않는다.

import '../services/business_posting_readiness.dart';

enum PostingNotReadyReason {
  businessNotApproved,
  businessLicenseNotReady,
  noActiveWorkType,
  noContractTemplate,
  noEmployerSeal,
}

class PostingNotReady {
  const PostingNotReady(this.reason);

  final PostingNotReadyReason reason;

  /// 이 이유를 해결하는 준비 단계. Home 체크리스트의 같은 칸이다.
  FirstPostingTask get task => switch (reason) {
        // 승인·등록증은 둘 다 '사업장' 칸이 owner 다(`businessReady`).
        PostingNotReadyReason.businessNotApproved ||
        PostingNotReadyReason.businessLicenseNotReady =>
          FirstPostingTask.business,
        PostingNotReadyReason.noActiveWorkType => FirstPostingTask.workType,
        PostingNotReadyReason.noContractTemplate =>
          FirstPostingTask.contractTemplate,
        PostingNotReadyReason.noEmployerSeal => FirstPostingTask.seal,
      };

  /// 사용자에게 보여줄 문장. **서버 문구를 그대로 쓰지 않는다** —
  /// 접두어가 새는 것을 막고, 문구 소유를 클라이언트가 갖는다.
  String get message => switch (reason) {
        PostingNotReadyReason.businessNotApproved =>
          '사업장 승인이 끝나면 공고를 등록할 수 있어요',
        PostingNotReadyReason.businessLicenseNotReady =>
          '사업자등록증을 먼저 등록해주세요',
        PostingNotReadyReason.noActiveWorkType => '업무를 먼저 등록해주세요',
        PostingNotReadyReason.noContractTemplate =>
          '계약서 템플릿을 먼저 등록해주세요\n확정된 근로자와 바로 계약할 수 있어야 해요',
        PostingNotReadyReason.noEmployerSeal =>
          '사업주 인감 또는 서명을 먼저 등록해주세요\n확정된 근로자와 바로 계약할 수 있어야 해요',
      };

  /// [R7-P4.4C.1] 예약 공개가 막혔을 때 **운영자에게** 보여줄 문장.
  ///
  ///   `message` 와 다른 이유: 저 문장은 "지금 등록하세요" 로 **행동을 지시**
  ///   한다. 그런데 예약 공개를 막은 준비의 책임은 `business.ownerId` 쪽이고,
  ///   SubAdmin 은 사업주 날인이나 사업장 승인을 스스로 해결할 수 없다.
  ///   그 사람에게 "인감을 등록하세요" 라고 하면 할 수 없는 일을 시키는 것이다.
  ///
  ///   [canSetUp] 이 false 면(= 호출자가 setup owner 가 아니면) 무엇이
  ///   모자란지는 알려 주되 해결은 사업장 관리자에게 넘긴다.
  ///
  ///   재시도는 자동이다 — scheduler 가 매 실행마다
  ///   `publishMode == scheduled && !isPublished && publishAt <= now` 를
  ///   다시 조회하므로, 준비가 끝나면 다음 처리에서 공개된다.
  String blockedNotice({required bool canSetUp}) {
    final what = switch (reason) {
      PostingNotReadyReason.businessNotApproved => '사업장 승인',
      PostingNotReadyReason.businessLicenseNotReady => '사업자등록증',
      PostingNotReadyReason.noActiveWorkType => '업무 등록',
      PostingNotReadyReason.noContractTemplate => '계약서 템플릿',
      PostingNotReadyReason.noEmployerSeal => '사업주 인감 또는 서명',
    };
    if (!canSetUp) {
      return '$what 준비가 끝나지 않아 예약 공개되지 않았어요\n'
          '사업장 관리자에게 확인해 주세요';
    }
    return '$what 준비가 끝나지 않아 예약 공개되지 않았어요\n'
        '준비를 완료하면 다음 예약 처리에서 다시 공개됩니다';
  }

  /// [R7-P4.4C.2A] **확정이 막혔을 때** 관리자에게 보여줄 문장.
  ///
  ///   `message` 는 "지금 등록하세요" 로 행동을 지시하고, `blockedNotice` 는
  ///   예약 공개가 밀린 사실을 말한다. 이건 세 번째 상황이다 — 지원자를
  ///   확정하려는 순간에 막혔다.
  ///
  ///   §9 책임 owner: 사업주 날인·사업장 승인은 `business.ownerId` 몫이고
  ///   SubAdmin 은 스스로 해결할 수 없다. [canSetUp] 이 false 면 무엇이
  ///   모자란지만 알려 주고 해결은 사업장 관리자에게 넘긴다.
  ///
  ///   지원은 **취소되지 않는다** — 지원 = 관심이므로 PENDING 으로 남고,
  ///   준비가 복구되면 다시 확정할 수 있다. 문구가 그 사실을 말한다.
  String confirmBlockedNotice({required bool canSetUp}) {
    final what = switch (reason) {
      PostingNotReadyReason.businessNotApproved => '사업장 승인',
      PostingNotReadyReason.businessLicenseNotReady => '사업자등록증',
      PostingNotReadyReason.noActiveWorkType => '업무 등록',
      PostingNotReadyReason.noContractTemplate => '계약서 템플릿',
      PostingNotReadyReason.noEmployerSeal => '사업주 인감 또는 서명',
    };
    if (!canSetUp) {
      return '$what 준비가 완료되지 않아 확정할 수 없어요\n'
          '사업장 관리자에게 확인해 주세요 (지원은 그대로 유지됩니다)';
    }
    return '$what 준비가 완료되지 않아 확정할 수 없어요\n'
        '준비를 완료하면 다시 확정할 수 있어요 (지원은 그대로 유지됩니다)';
  }

  /// 서버 오류에서 이유를 뽑는다. 우리가 아는 형태가 아니면 null —
  /// **모르는 것을 특정 준비 단계로 단정하지 않는다.**
  static PostingNotReady? parse(Object error) {
    final text = error.toString();
    if (!text.contains('POSTING_NOT_READY:')) return null;
    final after = text.split('POSTING_NOT_READY:').last;
    // 코드 뒤에 공백 + 문장이 붙어 온다.
    return fromCode(after.split(RegExp(r'[\s"\)]')).first.trim());
  }

  /// [R7-P4.4C.1] 저장된 이유 코드(`tos.publishBlockedReason`)에서 만든다.
  /// 서버가 적은 값이지만 **모르는 코드를 특정 단계로 단정하지 않는다.**
  static PostingNotReady? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    return switch (code) {
      'BUSINESS_NOT_APPROVED' =>
        const PostingNotReady(PostingNotReadyReason.businessNotApproved),
      'BUSINESS_LICENSE_NOT_READY' =>
        const PostingNotReady(PostingNotReadyReason.businessLicenseNotReady),
      'NO_ACTIVE_WORK_TYPE' =>
        const PostingNotReady(PostingNotReadyReason.noActiveWorkType),
      'NO_CONTRACT_TEMPLATE' =>
        const PostingNotReady(PostingNotReadyReason.noContractTemplate),
      'NO_EMPLOYER_SEAL' =>
        const PostingNotReady(PostingNotReadyReason.noEmployerSeal),
      _ => null,
    };
  }
}
