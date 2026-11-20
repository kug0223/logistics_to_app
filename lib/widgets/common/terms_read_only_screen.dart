import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import 'app_empty_state.dart';

/// 약관 읽기 전용 화면 — 설정 → 서비스 이용약관·개인정보 처리방침·위치정보 이용 동의.
///
/// [LEGAL-FIX 2026-08-10] 개인정보보호법 제35조 열람 요구권 대응. 동의 버튼 없이 읽기만 한다
/// (가입 화면의 동의용 뷰어와 다르다).
///
/// [DU263] 근로자 설정(user_settings_screen)과 관리자 설정(settings_screen)에 같은 비공개 사본이 둘 있었다
///   — 공용 하나로 합쳤다.
///   [loadFailed] 면 본문 자리에 실패 상태를 보인다. 이전에는 실패 문장을 약관 본문처럼 그렸다(ERROR ≠ 본문).
///   본문은 흰 카드 위에 둔다. SelectableText 를 유지하므로 복사에 결합 문자가 섞이지 않게 keepWords 는 넣지 않는다.
class TermsReadOnlyScreen extends StatelessWidget {
  final String title;
  final String content;
  final String? version;
  final bool loadFailed;

  const TermsReadOnlyScreen({
    super.key,
    required this.title,
    required this.content,
    this.version,
    this.loadFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: AppColors.grey700,
          tooltip: '닫기',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: ResponsiveHelper.bodyStyle(context,
              color: AppColors.grey900, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: loadFailed
            ? const AppEmptyState(
                icon: Icons.error_outline,
                title: '약관을 불러오지 못했습니다',
                subtitle: '잠시 후 다시 시도해주세요.',
              )
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 12),
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 24),
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.grey200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (version != null) ...[
                        Text(
                          '버전 $version',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textSecondary),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      ],
                      SelectableText(
                        content,
                        style: ResponsiveHelper.bodyStyle(context,
                                color: AppColors.textPrimary)
                            .copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
