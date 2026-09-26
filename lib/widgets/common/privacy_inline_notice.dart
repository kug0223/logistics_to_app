import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// [RELEASE-CORRECTION-PRIVACY-INLINE-DISCLOSURE]
///
///   민감한 정보를 요구하는 화면에서, 요구하기 **전에** 무엇을 왜 받는지
///   짧게 말한다. 개인정보 처리방침을 열어봐야만 알 수 있는 상태로 두지
///   않는다 — 방침은 전체를 적는 곳이고, 여기는 지금 이 화면에서 벌어지는
///   일만 적는 곳이다.
///
///   ── 문구는 source가 증명하는 것만 적는다 ──────────────────────
///
///   각 항목 옆의 근거 주석이 그 문장의 출처다. 구현이 바뀌면 문구도
///   함께 바뀌어야 하고, 그 일치는 계약 테스트가 지킨다.
///   (`test/privacy_inline_disclosure_contract_test.dart`)
///
///   ── 동의를 다시 받는 화면이 아니다 ────────────────────────────
///
///   기존 약관 동의·권한 게이트를 대체하거나 중복하지 않는다. 고지일 뿐이다.
class PrivacyDisclosure {
  const PrivacyDisclosure({required this.title, required this.points});

  final String title;
  final List<String> points;

  /// 다이얼로그 message 처럼 문자열 하나가 필요한 자리에서 쓴다.
  String get asMessage => points.join('\n\n');

  // ══════════════════════════════════════════════════════════════
  // 위치 — 출퇴근 체크
  // ══════════════════════════════════════════════════════════════

  /// 근거:
  /// - 수집 시점: `attendance_check_screen._verifyByGPS` 가 출근·퇴근을
  ///   누른 뒤에만 `LocationHelper.getCurrentPosition()` 을 부른다.
  /// - 사용 목적: `callableCheckIn` 의 haversine 반경 검증.
  /// - 서버 저장: attendance 문서의 `checkInLat/checkInLng`,
  ///   `checkOutLat/checkOutLng`.
  /// - 사업장 도달: `callableGetAdminAttendances` 가 근무 기록을 관리자에게
  ///   돌려준다(좌표를 화면에 그리지는 않지만 기록에는 들어 있다).
  /// - 백그라운드 없음: `ACCESS_BACKGROUND_LOCATION` 미선언이고
  ///   `LocationHelper.getPositionStream()` 은 어디에서도 호출되지 않는다.
  static const location = PrivacyDisclosure(
    title: '위치를 이렇게 사용합니다',
    points: [
      '출근·퇴근 버튼을 누른 그때만 현재 위치를 한 번 확인합니다.',
      '사업장 반경 안에서 출퇴근했는지 확인하는 데 씁니다.',
      '확인한 위치는 해당 근무 기록에 함께 저장되고, 그 사업장의 관리자가 근무 기록으로 확인할 수 있습니다.',
      '앱을 쓰지 않는 동안에는 위치를 수집하지 않습니다.',
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // 신분증 업로드
  // ══════════════════════════════════════════════════════════════

  /// 근거:
  /// - 저장 위치: `users/{uid}/idCard_*.jpg` (Firebase Storage).
  /// - 열람 조건: `callableGetTaxIdentityIdCardUrl` 이
  ///   `srvAssertTaxIdentityAuthority` + `srvHasCurrentTaxIdentityPurpose`
  ///   를 통과할 때만 1시간 만료 URL 을 연다.
  /// - OCR: `google_mlkit_text_recognition` — `InputImage.fromFilePath`,
  ///   기기 안에서만 처리하고 대조를 위해 서버로 보내는 이미지가 없다.
  /// - 사진 자체는 업로드된다 — `uploadImageNoUrl(storagePath)`.
  static const idDocument = PrivacyDisclosure(
    title: '신분증은 이렇게 쓰입니다',
    points: [
      '본인 확인과 소득신고에 쓸 이름·생년월일 대조에 사용합니다.',
      '사진 속 글자를 읽어 등록 정보와 맞는지 보는 과정은 기기 안에서 끝납니다.',
      '사진은 등록을 위해 저장되며, 함께 일하는 사업장의 관리자가 세무 확인을 누른 때에만 열립니다.',
    ],
  );

  // ══════════════════════════════════════════════════════════════
  // 세무 식별정보 (주민등록번호 / 외국인등록번호)
  // ══════════════════════════════════════════════════════════════

  /// 근거:
  /// - 목적: `callableRegisterTaxIdentity` — 소득신고·원천징수.
  /// - 민감정보 취급: `srvEncryptTaxIdentifier` 로 암호화 저장하고,
  ///   `callableGetTaxIdentityStatus` 응답에 번호를 싣지 않는다.
  /// - 관리자 열람 조건: `callableGetTaxIdentityNumber` 가 권한·현재
  ///   세무 처리 사유·화면이 보고 있는 버전을 모두 확인할 때만 연다.
  /// - 열람 기록: `srvLogTaxIdentityAudit(..., {failClosed: true})` —
  ///   기록에 실패하면 번호를 내보내지 않는다.
  static const taxIdentity = PrivacyDisclosure(
    title: '민감한 정보입니다',
    points: [
      '소득신고·원천징수 처리에만 사용합니다.',
      '암호화해 보관하고, 등록한 뒤에는 앱 어디에서도 다시 표시하지 않습니다.',
      '지금 함께 일하는 사업장의 관리자가 소득신고 정보를 대조할 때만 열 수 있고, 열어본 사실은 기록에 남습니다.',
    ],
  );
}

/// 민감정보를 요구하기 직전에 놓는 짧은 고지 박스.
///
///   새 modal 을 만들지 않는다 — 기존 화면의 흐름 안에 들어간다.
class PrivacyInlineNotice extends StatelessWidget {
  const PrivacyInlineNotice({
    super.key,
    required this.disclosure,
    this.icon = Icons.privacy_tip_outlined,
  });

  final PrivacyDisclosure disclosure;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disclosure.title,
                  style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.infoDark)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                for (final p in disclosure.points)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: ResponsiveHelper.spacing(context, 2)),
                    child: Text(
                      '· $p',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey600),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
