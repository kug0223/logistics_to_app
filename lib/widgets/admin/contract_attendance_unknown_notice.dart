import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// [NOSHOW-CONTRACT-GUARD] 근태를 확인하지 못해 `계약서 작성` 을 내지 않았다는 안내.
///
///   근태 조회 실패·조회 상한 도달은 "근태 없음"이 아니다. 그렇다고 버튼만 조용히
///   사라지면 관리자는 왜 발행할 수 없는지 모른다. 이유와 재시도 경로를 함께 보인다.
///   (조회 성공·근태 문서 없음은 서버와 같이 발행 가능 — 이 안내를 띄우지 않는다.)
class ContractAttendanceUnknownNotice extends StatelessWidget {
  const ContractAttendanceUnknownNotice({
    super.key,
    required this.onRetry,
    this.retrying = false,
  });

  static const String message = '근태를 확인하지 못해 계약 발행을 잠시 중단했습니다';

  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('contract-attendance-unknown'),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: ResponsiveHelper.spacing(context, 8),
        runSpacing: ResponsiveHelper.spacing(context, 4),
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.warning),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Flexible(
                child: Text(
                  message,
                  softWrap: true,
                  style: ResponsiveHelper.bodyStyle(context,
                      fontWeight: FontWeight.w600, color: AppColors.grey800),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: retrying ? null : onRetry,
            child: Text(retrying ? '확인 중…' : '다시 시도'),
          ),
        ],
      ),
    );
  }
}
