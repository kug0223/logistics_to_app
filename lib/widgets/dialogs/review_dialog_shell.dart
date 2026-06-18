// lib/widgets/dialogs/review_dialog_shell.dart
//
// 리뷰 작성 다이얼로그 공통 뼈대.
// 핵심 원칙: 버튼을 스크롤 안에 포함시켜 키보드가 올라와도 버튼이 따라오지 않게 함.
//
// Scaffold 없이 viewInsets.bottom 패딩으로 키보드 대응.
// showDialog의 배리어·트랜지션 페이드와 다이얼로그 내용이 함께 애니메이션됨.

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import 'styled_dialog.dart';

class ReviewDialogShell extends StatelessWidget {
  final Widget header;
  final List<Widget> body;

  /// 취소/제출 버튼 — 스크롤 하단에 포함 (키보드가 올라와도 버튼은 따라오지 않음)
  final Widget actions;

  const ReviewDialogShell({
    super.key,
    required this.header,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () {
        if (ModalRoute.of(context)?.barrierDismissible ?? true) {
          Navigator.of(context).maybePop();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // 키보드 높이만큼 하단 패딩 → 다이얼로그가 키보드 위로 올라감
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, AppDialogSize.insetH),
                vertical: AppDialogSize.insetV,
              ),
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppDialogSize.borderRadius),
                  elevation: 6,
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        header,
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              ResponsiveHelper.spacing(context, 16),
                              ResponsiveHelper.spacing(context, 14),
                              ResponsiveHelper.spacing(context, 16),
                              ResponsiveHelper.spacing(context, 16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...body,
                                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                actions,
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
