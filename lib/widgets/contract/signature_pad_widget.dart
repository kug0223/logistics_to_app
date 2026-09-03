import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

/// 손글씨 서명 패드 BottomSheet 위젯
///
/// 사용법:
///   final bytes = await showSignaturePad(context, title: '내 서명 등록');
///   if (bytes != null) { /* 서명 완료 */ }
class SignaturePadWidget extends StatefulWidget {
  final String title;
  final VoidCallback? onCancel;
  final void Function(Uint8List bytes) onConfirm;

  const SignaturePadWidget({
    super.key,
    this.title = '서명해주세요',
    this.onCancel,
    required this.onConfirm,
  });

  @override
  State<SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<SignaturePadWidget> {
  late final SignatureController _controller;
  bool _hasSignature = false;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _controller.addListener(() {
      final has = _controller.isNotEmpty;
      if (has != _hasSignature) setState(() => _hasSignature = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearPad() {
    _controller.clear();
    setState(() => _hasSignature = false);
  }

  Future<void> _confirm() async {
    if (!_hasSignature) return;
    // 점 하나만 찍은 경우(포인트 수 5 미만) 서명 거부
    if (_controller.points.length < 5) {
      ToastHelper.showWarning('서명이 너무 짧습니다. 다시 서명해 주세요.');
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null) return;
    if (!mounted) return;
    widget.onConfirm(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = ResponsiveHelper.spacing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 드래그 핸들 ────────────────────────────────────────────
        Container(
          width: 40,
          height: 4,
          margin: EdgeInsets.symmetric(vertical: spacing(context, 12)),
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // ── 헤더: 아이콘 + 제목 + 닫기 ────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing(context, 20)),
          child: Row(
            children: [
              Container(
                width: spacing(context, 36),
                height: spacing(context, 36),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.draw_outlined,
                  color: AppColors.infoDark,
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
              ),
              SizedBox(width: spacing(context, 10)),
              Expanded(
                child: Text(
                  widget.title,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: widget.onCancel ?? () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
                color: AppColors.grey600,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // ── 서브타이틀 ─────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.only(
            left: spacing(context, 20),
            right: spacing(context, 20),
            top: spacing(context, 2),
            bottom: spacing(context, 10),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '서명을 직접 그려주세요',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
            ),
          ),
        ),

        // ── Divider ────────────────────────────────────────────────
        const Divider(height: 1, color: AppColors.grey100),

        SizedBox(height: spacing(context, 12)),

        // ── 서명 캔버스 ────────────────────────────────────────────
        Container(
          margin: EdgeInsets.symmetric(horizontal: spacing(context, 20)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.grey200, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Signature(
                  controller: _controller,
                  height: spacing(context, 240),
                  backgroundColor: Colors.white,
                ),
                // placeholder — drawing 시작하면 자동으로 사라짐
                if (!_hasSignature)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          '여기에 서명',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.grey300,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── 지우기 — Pad 바로 아래 우측 ────────────────────────────
        Padding(
          padding: EdgeInsets.only(
            right: spacing(context, 20),
            top: spacing(context, 6),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _hasSignature ? _clearPad : null,
              icon: Icon(
                Icons.refresh_outlined,
                size: 13,
                color: _hasSignature ? AppColors.grey500 : AppColors.grey300,
              ),
              label: Text(
                '지우기',
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: _hasSignature ? AppColors.grey500 : AppColors.grey300,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                splashFactory: NoSplash.splashFactory,
              ),
            ),
          ),
        ),

        SizedBox(height: spacing(context, 10)),

        // ── 안내 문구 ──────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing(context, 20)),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.grey400),
              SizedBox(width: spacing(context, 4)),
              Expanded(
                child: Text(
                  '손가락으로 위 영역에 서명해주세요.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: spacing(context, 16)),

        // ── CTA 버튼 ───────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing(context, 20)),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel ?? () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: spacing(context, 14)),
                    side: const BorderSide(color: AppColors.grey300),
                    foregroundColor: AppColors.grey600,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('취소',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey600)),
                ),
              ),
              SizedBox(width: spacing(context, 12)),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _hasSignature ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    disabledBackgroundColor: AppColors.grey100,
                    padding: EdgeInsets.symmetric(
                        vertical: spacing(context, 14)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    '서명 완료',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: _hasSignature ? Colors.white : AppColors.grey400,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: spacing(context, 16)),
      ],
    );
  }
}

/// BottomSheet로 서명 패드 표시
///
/// [title]: '내 서명 등록' / '내 서명 변경' 등 컨텍스트에 맞게 전달
/// Returns: 완료 시 PNG bytes, 취소 시 null
///
/// useRootNavigator: true → BottomNavigationBar까지 dim 처리됨
Future<Uint8List?> showSignaturePad(
  BuildContext context, {
  String title = '서명해주세요',
}) async {
  Uint8List? result;
  await DialogHelper.showSheet(
    context,
    isScrollControlled: true,
    // rootNavigator: BottomNavBar가 아닌 앱 루트 위에 Sheet 표시
    useRootNavigator: true,
    builder: (_) => SignaturePadWidget(
      title: title,
      // [F-07-3 수정] useRootNavigator:true로 연 시트는 반드시 rootNavigator로 닫아야 함
      // Navigator.pop(context)는 nearest navigator를 pop → 중첩 네비게이터(탭 구조)에서
      // 시트 대신 ContractSignScreen 자체가 pop될 수 있어 result가 null로 반환되는 버그
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onConfirm: (bytes) {
        result = bytes;
        Navigator.of(context, rootNavigator: true).pop();
      },
    ),
  );
  return result;
}
