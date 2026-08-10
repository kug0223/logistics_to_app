import 'package:flutter/material.dart';
import '../../services/pass_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/common_widgets.dart';

/// PASS 인증 결과 표시 위젯 (읽기 전용)
///
/// 가입 화면에서 PASS 인증 후 이름/성별/생년월일/전화번호를 표시할 때 사용.
/// 모든 필드는 수정 불가 (PASS에서 확정된 값).
class PassResultDisplay extends StatelessWidget {
  final PassAuthResult result;

  const PassResultDisplay({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final birthStr =
        '${result.birthDate.year}년 ${result.birthDate.month}월 ${result.birthDate.day}일';
    final phoneFormatted = _formatPhone(result.phone);

    return Container(
      decoration: CommonWidgets.compactCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user, color: AppColors.success, size: 16),
              const SizedBox(width: 6),
              Text(
                '본인인증 완료',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: AppColors.successDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(context, '이름', result.name),
          _infoRow(context, '성별', result.gender),
          _infoRow(context, '생년월일', birthStr),
          _infoRow(context, '휴대폰', phoneFormatted),
          const SizedBox(height: 4),
          Text(
            '위 정보는 본인인증으로 확정되어 수정할 수 없습니다.',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return phone;
  }
}
