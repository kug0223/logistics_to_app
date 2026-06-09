import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 손글씨 서명 패드
/// 사용법:
///   final bytes = await showSignaturePad(context);
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

  Future<void> _confirm() async {
    if (!_hasSignature) return;
    final bytes = await _controller.toPngBytes();
    if (bytes == null) return;
    if (!mounted) return;
    widget.onConfirm(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 타이틀
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 20),
            vertical: ResponsiveHelper.spacing(context, 16),
          ),
          child: Row(
            children: [
              Icon(Icons.draw_outlined,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 22)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                widget.title,
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _controller.clear();
                  setState(() => _hasSignature = false);
                },
                child: Text(
                  '지우기',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
              ),
            ],
          ),
        ),

        // 서명 캔버스
        Container(
          margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hasSignature
                  ? theme.primaryColor.withValues(alpha: 0.4)
                  : AppColors.grey300,
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Signature(
              controller: _controller,
              height: 180,
              backgroundColor: Colors.white,
            ),
          ),
        ),

        if (!_hasSignature)
          Padding(
            padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
            child: Text(
              '위 공간에 서명해주세요',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey400),
            ),
          ),

        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // 버튼 행
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 20),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel ?? () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14)),
                    side: const BorderSide(color: AppColors.grey300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('취소',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey600)),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _hasSignature ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    disabledBackgroundColor: AppColors.grey200,
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14)),
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
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
      ],
    );
  }
}

/// 바텀시트로 서명 패드 표시
/// Returns null if cancelled
Future<Uint8List?> showSignaturePad(
  BuildContext context, {
  String title = '서명해주세요',
}) async {
  Uint8List? result;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SignaturePadWidget(
      title: title,
      onCancel: () => Navigator.pop(context),
      onConfirm: (bytes) {
        result = bytes;
        Navigator.pop(context);
      },
    ),
  );
  return result;
}
