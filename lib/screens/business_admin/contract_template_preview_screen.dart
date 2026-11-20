import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';

/// 계약서 템플릿 미리보기 화면
///
/// 실제 근무자·사업장 데이터 대신 예시 값을 채워서
/// 완성된 계약서가 어떻게 보일지 확인할 수 있습니다.
class ContractTemplatePreviewScreen extends StatelessWidget {
  final ContractTemplateModel template;

  const ContractTemplatePreviewScreen({super.key, required this.template});

  static const String _kNotice = '예시 데이터로 보여주는 미리보기입니다.\n'
      '제1~3조(당사자·근무조건·임금)는 계약서 작성 시 실제 정보로 자동 채워집니다.';

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
        // [DU339] 예시 시급 10,030(2025 최저임금) → 10,320(2026 예시, 소급 감사 6 §3). 미리보기 전용 값이다.
        wage: 10320,
        wageType: 'hourly',
        wagePaymentDay: 25,
        baseHourlyWage: 10320,
      );

  /// [DU339] 예시 근무일 1일 — 예시 슬롯이 없어 '근무 형태 단기 (0일)' 로 보였다(소급 감사 6 §3).
  ///   미리보기 전용이다. 날짜는 계약 작성일(오늘, KST)과 같은 날, 시간 · 시급은 위 예시와 같다.
  List<ContractSlot> _exampleSlots(DateTime contractDate) {
    final d = FormatHelper.toKstDate(contractDate);
    String two(int v) => v.toString().padLeft(2, '0');
    return [
      ContractSlot(
        applicationId: 'preview-example',
        workDate: '${d.year}-${two(d.month)}-${two(d.day)}',
        startTime: '09:00',
        endTime: '18:00',
        wage: 10320,
        wageType: 'hourly',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final contractDate = DateTime.now();
    return AppPageScaffold(
      title: '미리보기',
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          color: AppColors.textSecondary,
          onPressed: () => NavigationHelper.goHome(context),
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            tooltip: '알림',
          ),
        ),
      ],
      body: Column(
        children: [
          // 계약서 본문
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 16),
                // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
                // 시각적 여백(16) + 기기 하단 인셋(홈 인디케이터/제스처 바)을 더해
                // 계약서 본문 하단이 시스템 내비게이션 영역에 가려지지 않도록 한다.
                ResponsiveHelper.spacing(context, 16) +
                    MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // [DU335] 안내 — 화면 위 고정 띠 → 본문 첫 카드. 320 · 2.0 에서 고정 띠가 5줄(화면 높이 약 41%)을
                  //   늘 차지해 계약서를 읽을 칸이 좁았다. 아이콘은 첫 줄에 맞추고 경고 진한색(warning 2.1:1 → warningDark),
                  //   문장은 그대로 두고 낱말 단위 · '·' 뒤에서도 줄을 바꿀 수 있게 한다(긴 괄호 낱말이 음절로 갈리지 않게).
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 10),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: AppColors.warningDark,
                            size: ResponsiveHelper.iconSize(context, 16)),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            TextLayout.phrases(_kNotice)
                                .replaceAll('·\u2060', '·\u200B'),
                            semanticsLabel: _kNotice,
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.warningDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  ContractTemplateWidget(
                    snapshot: _dummySnapshot,
                    contractDate: contractDate,
                    slots: _exampleSlots(contractDate),
                    articles: template.articles,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
