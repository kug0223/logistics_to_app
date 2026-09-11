import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import 'styled_dialog.dart';

/// 근무 형태(templateType) 선택 시트가 불린 목적.
///
/// [F-02] 같은 daily/period 선택인데 경로마다 실제 효과가 다르다.
///   · defaultCreation      → 선택한 유형의 참고용 기본 조항이 편집기에 로드된다
///   · importClassification → 붙여넣은 조항이 그대로 쓰이고, 유형은 분류에만 쓰인다
///   · blankClassification  → 조항 없이 시작하고, 유형은 분류에만 쓰인다
///
/// 이전에는 시트가 두 벌 있었고 각각 한 경로만 기준으로 쓴 문구를
/// 세 경로가 공유했다. 한쪽(관리 화면)은 포함될 법률 조항을 목록으로
/// 약속했고, 다른 쪽(Selector)은 기본 조항을 불러오는 경로에까지
/// "나중에 목록에서 구분할 용도"라고 안내했다. 목적을 인자로 받아
/// 각 경로의 실제 효과만 말한다.
enum ContractTemplateTypePurpose {
  defaultCreation,
  importClassification,
  blankClassification,
}

/// 근무 형태 선택 바텀시트 — `Navigator.pop`으로 templateType(String)을 반환한다.
///
/// [F-01] 어떤 법률 조항이 포함되는지 약속하지 않는다.
///   이전 관리 화면 버전은 '4대보험 조건', '주휴수당 적용 조건', '연차유급휴가',
///   '퇴직급여', '수습기간 감액', '5인 이상/미만 분기 가이드' 등을 체크리스트로
///   내걸었으나 해당 조항들은 reference core에서 제거된 상태였다.
///   ALfit은 계약 내용이나 법적 적용 여부를 대신 확정하지 않으므로
///   "어떤 근무 형태인가"와 "무엇이 로드되는가"만 말한다.
///
/// reference core는 앞으로도 조정될 수 있으므로 조항 제목 목록을
/// 파생시켜 보여주지도 않는다 — 유형 선택 단계에서 조항 목록을 나열하면
/// 그 자체가 "완성된 계약 구성"처럼 읽힌다.
class ContractTemplateTypeSelectorSheet extends StatelessWidget {
  final ContractTemplateTypePurpose purpose;

  const ContractTemplateTypeSelectorSheet({super.key, required this.purpose});

  bool get _isDefaultCreation =>
      purpose == ContractTemplateTypePurpose.defaultCreation;

  String get _heading => _isDefaultCreation
      ? '어떤 근무 형태의 기본 조항으로 시작할까요?'
      : '이 템플릿을 어떤 근무 형태로 분류할까요?';

  String get _subheading {
    switch (purpose) {
      case ContractTemplateTypePurpose.defaultCreation:
        return '선택한 근무 형태에 맞는 참고용 기본 조항을 불러옵니다.\n'
            '이후 사업장에 맞게 자유롭게 수정할 수 있어요.';
      case ContractTemplateTypePurpose.importClassification:
        return '가져온 내용은 바뀌지 않으며, 목록에서 구분하는 데 사용됩니다.';
      case ContractTemplateTypePurpose.blankClassification:
        return '조항은 비어 있는 상태로 시작하며, 목록에서 구분하는 데 사용됩니다.';
    }
  }

  /// 분류 목적일 때는 "기본 조항"이라는 말을 쓰지 않는다 —
  /// 그 경로에서는 기본 조항이 로드되지 않기 때문이다.
  String _typeSubtitle(String type) {
    if (_isDefaultCreation) return ContractTemplateType.description(type);
    switch (type) {
      case ContractTemplateType.daily:
        return '하루~수주 단기 근무';
      case ContractTemplateType.period:
        return '1개월~2년 기간제 근무';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 드래그 핸들
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: EdgeInsets.only(
                        bottom: ResponsiveHelper.spacing(context, 20)),
                    decoration: BoxDecoration(
                      color: AppColors.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text(
                  _heading,
                  style: ResponsiveHelper.titleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Text(
                  _subheading,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                _TypeRow(
                  icon: Icons.calendar_today_outlined,
                  iconColor: AppColors.info,
                  bgColor: AppColors.infoBg,
                  title: ContractTemplateType.label(ContractTemplateType.daily),
                  subtitle: _typeSubtitle(ContractTemplateType.daily),
                  onTap: () =>
                      Navigator.pop(context, ContractTemplateType.daily),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                _TypeRow(
                  icon: Icons.date_range_outlined,
                  iconColor: AppColors.success,
                  bgColor: AppColors.successBg,
                  title: ContractTemplateType.label(ContractTemplateType.period),
                  subtitle: _typeSubtitle(ContractTemplateType.period),
                  onTap: () =>
                      Navigator.pop(context, ContractTemplateType.period),
                ),
                // [V1 SCOPE] 업무위탁(도급)은 신규 생성 대상이 아니다 —
                //   renderer가 templateType을 받지 않아 약속을 지킬 수 없다.

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('취소',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.grey500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeRow({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.grey200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: iconColor,
                    size: ResponsiveHelper.iconSize(context, 22)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                      Text(subtitle,
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.grey500)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 20)),
            ],
          ),
        ),
      ),
    );
  }
}
