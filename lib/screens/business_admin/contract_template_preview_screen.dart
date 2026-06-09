import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// 계약서 템플릿 미리보기 화면
///
/// 실제 근무자·사업장 데이터 대신 예시 값을 채워서
/// 완성된 계약서가 어떻게 보일지 확인할 수 있습니다.
class ContractTemplatePreviewScreen extends StatelessWidget {
  final ContractTemplateModel template;

  const ContractTemplatePreviewScreen({super.key, required this.template});

  /// 예시 스냅샷 — 자동 입력 영역이 어떻게 채워지는지 보여줌
  ContractSnapshot get _dummySnapshot => ContractSnapshot(
        businessName: '○○○ 사업장',
        businessNumber: '000-00-00000',
        businessAddress: '서울시 ○○구 ○○로 123',
        businessPhone: '02-0000-0000',
        ownerName: '홍길동',
        workerName: '김근로',
        workerBirthDate: '1990-01-01',
        workerPhone: '010-0000-0000',
        workerAddress: '서울시 ○○구 ○○동 456',
        workType: '분류·포장 작업',
        workPlace: '서울시 ○○구 ○○로 123',
        isLongTerm: false,
        startTime: '09:00',
        endTime: '18:00',
        breakMinutes: 60,
        wage: 10030,
        wageType: 'hourly',
        wagePaymentDay: 25,
        baseHourlyWage: 10030,
      );

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '미리보기',
      body: Column(
        children: [
          // 안내 배너
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            color: AppColors.warning.withValues(alpha: 0.12),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.warning,
                    size: ResponsiveHelper.iconSize(context, 16)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '예시 데이터로 보여주는 미리보기입니다.\n'
                    '제1~3조(당사자·근무조건·임금)는 계약서 작성 시 실제 정보로 자동 채워집니다.',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.warningDark),
                  ),
                ),
              ],
            ),
          ),

          // 계약서 본문
          Expanded(
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
              child: ContractTemplateWidget(
                snapshot: _dummySnapshot,
                contractDate: DateTime.now(),
                articles: template.articles,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
