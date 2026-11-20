import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_version_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';

/// [VERSION-GATE] 버전 게이트가 막은 사용자가 보는 **유일한** 화면.
///
///   두 상태를 **다르게** 말한다 — 같은 화면에 섞으면 네트워크가 끊겼을 뿐인
///   사용자에게 "업데이트하라"고 거짓말을 하게 된다.
///
///     `updateRequired` — 정책을 확인했고 기준 미만이다 → 업데이트하기
///     `unknown`        — 정책을 확인하지 못했다 → 다시 확인
///
///   Dialog 가 아니라 **화면**이다. 다이얼로그는 라우트 위에 떠 있어서
///   뒤의 화면이 살아 있고, 알림 딥링크 같은 다른 push 가 그 위로 올라온다.
///   막아야 할 때는 라우트 자체를 대체한다.
class ForcedUpdateScreen extends StatefulWidget {
  final VersionGateResult result;

  /// 다시 확인. **새 판정을 돌려준다.** 통과(supported)하면 호출자가 다음 화면으로 보낸다(이 라우트를 대체).
  ///   [DU313 r3] 막힌 그대로면 그 새 판정으로 이 화면의 상태 · 안내 · 행동을 바꾼다(최초 result 에 묶어 두지 않는다).
  final Future<VersionGateResult> Function() onRetry;

  const ForcedUpdateScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  @override
  State<ForcedUpdateScreen> createState() => _ForcedUpdateScreenState();
}

class _ForcedUpdateScreenState extends State<ForcedUpdateScreen> {
  bool _busy = false;

  /// [DU313 r3] 지금 화면이 말하는 판정 — 처음엔 호출자가 준 result, 다시 확인하면 그 새 결과.
  late VersionGateResult _result = widget.result;

  /// [DU313 r2] 다시 확인했는데도 막혀 있을 때 화면 안에 남기는 결과 안내.
  String? _retryNote;

  /// [DU313 r2b] 결과 안내가 큰 글자 · 좁은 화면에서 스크롤 영역 아래로 잘리지 않게 보이는 곳까지 스크롤한다.
  final GlobalKey _noteKey = GlobalKey();

  bool get _isUpdate => _result.status == VersionGateStatus.updateRequired;

  Future<void> _openStore() async {
    final raw = _result.updateUrl;
    if (raw == null || raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      final uri = Uri.parse(raw);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ToastHelper.showError('스토어를 열지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('스토어를 열지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _retryNote = null;
    });
    try {
      VersionGateResult again;
      try {
        again = await widget.onRetry();
      } catch (e) {
        // [DU313 r3] 다시 확인이 실패하면 '모르는 것은 모른다' — 확인 실패로 말하고 차단은 그대로다.
        debugPrint('⚠️ [ForcedUpdate] 다시 확인 실패: $e');
        again = VersionGateResult(
          status: VersionGateStatus.unknown,
          source: VersionPolicySource.localDefault,
          fromCache: true,
          currentVersion: _result.currentVersion,
          minVersion: _result.minVersion,
        );
      }
      // [DU313 r2] 통과하면 호출자가 이 라우트를 대체한다(더는 현재 라우트가 아니다) — isCurrent 는 그 수명 guard 다.
      // [DU313 r3] 아직 이 화면이 현재이고 새 판정도 막힘이면, 그 새 판정으로 상태 · 안내 · 행동을 바꾼다.
      if (mounted &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          again.blocksEntry) {
        setState(() {
          _result = again;
          _retryNote = _isUpdate
              ? '아직 업데이트가 필요해요. 업데이트한 뒤 앱을 다시 열어 주세요.'
              : '아직 버전을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.';
        });
        // [DU313 r2b] 320·2.0 에서 안내 셋째 줄이 스크롤 영역 아래 끝에 반쯤 걸렸다(r2 캡처 열람) — 끝까지 보이게.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _noteKey.currentContext;
          if (ctx == null) return;
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 200),
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUrl = (_result.updateUrl ?? '').isNotEmpty;
    // 업데이트가 필요한데 목적지가 없을 수 있다(설정 누락).
    //   그때도 **아무것도 못 하는 화면**으로 두지 않는다 — 다시 확인을 준다.
    final primaryIsStore = _isUpdate && hasUrl;

    final title = _isUpdate ? '앱 업데이트가 필요합니다' : '앱 버전을 확인하지 못했습니다';
    final body = _isUpdate
        ? 'ALfit을 계속 사용하려면 최신 버전으로 업데이트해 주세요.'
        : '네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
    const storeNote = '스토어 주소를 불러오지 못했습니다. 앱 스토어에서 ALfit을 직접 검색해 주세요.';
    final primaryLabel =
        _busy ? '잠시만 기다려 주세요' : (primaryIsStore ? '업데이트하기' : '다시 확인');
    // [DU313 ②] 상태 아이콘은 옅은 색 원에 담는다 — S003 본인인증 복구 화면과 같은 형식(80 · 아이콘 40 · alpha .12).
    final tone = _isUpdate ? theme.primaryColor : AppColors.grey600;
    final hPad = ResponsiveHelper.spacing(context, 24);

    return PopScope(
      // 뒤로 가기로 우회할 수 없다.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          // [DU313 ④] 행동 버튼은 하단에 고정하고 내용만 스크롤한다 — 큰 글자 · 좁은 화면에서
          //   안내가 길어져도 '업데이트하기' / '다시 확인'이 첫 화면에 남는다(S005 복구 화면과 같은 구조).
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final vPad = ResponsiveHelper.spacing(context, 24);
                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                          horizontal: hPad, vertical: vPad),
                      child: ConstrainedBox(
                        // 남는 높이 안에서 가운데 — 내용이 짧으면 지금처럼 화면 가운데에 놓인다.
                        constraints: BoxConstraints(
                            minHeight: (box.maxHeight - vPad * 2)
                                .clamp(0.0, double.infinity)),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: ResponsiveHelper.spacing(context, 80),
                                height: ResponsiveHelper.spacing(context, 80),
                                decoration: BoxDecoration(
                                  color: tone.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isUpdate
                                      ? Icons.system_update_alt
                                      : Icons.wifi_tethering_off,
                                  size: ResponsiveHelper.iconSize(context, 40),
                                  color: tone,
                                ),
                              ),
                              SizedBox(
                                  height: ResponsiveHelper.spacing(context, 24)),
                              // [DU313 ①②] 제목 19 bold(S003 과 같은 titleStyle) · 낱말 단위 줄바꿈('필요 / 합니다' 방지)
                              Text(
                                TextLayout.keepWords(title),
                                semanticsLabel: title,
                                textAlign: TextAlign.center,
                                style: ResponsiveHelper.titleStyle(context,
                                    color: AppColors.textPrimary),
                              ),
                              SizedBox(
                                  height: ResponsiveHelper.spacing(context, 12)),
                              // [DU313 ①③] 안내 grey600 → textSecondary(흰 면 5.92) · 낱말 단위 줄바꿈
                              Text(
                                TextLayout.keepWords(body),
                                semanticsLabel: body,
                                textAlign: TextAlign.center,
                                style: ResponsiveHelper.bodyStyle(context,
                                    color: AppColors.textSecondary),
                              ),
                              if (_isUpdate && !hasUrl) ...[
                                SizedBox(
                                    height:
                                        ResponsiveHelper.spacing(context, 8)),
                                Text(
                                  TextLayout.keepWords(storeNote),
                                  semanticsLabel: storeNote,
                                  textAlign: TextAlign.center,
                                  style: ResponsiveHelper.smallStyle(context,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                              // [DU313 r2] 다시 확인 결과(여전히 막힘) — 버튼 바로 위, 화면 읽기에도 바로 알린다
                              if (_retryNote case final note?) ...[
                                SizedBox(
                                    height:
                                        ResponsiveHelper.spacing(context, 12)),
                                Semantics(
                                  key: _noteKey,
                                  liveRegion: true,
                                  child: Text(
                                    TextLayout.keepWords(note),
                                    semanticsLabel: note,
                                    textAlign: TextAlign.center,
                                    style: ResponsiveHelper.smallStyle(context,
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    hPad,
                    ResponsiveHelper.spacing(context, 8),
                    hPad,
                    ResponsiveHelper.spacing(context, 16)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // 비활성 버튼으로 방치하지 않는다 — 목적지가 없으면
                        //   `다시 확인`이 primary 가 된다.
                        onPressed: _busy
                            ? null
                            : (primaryIsStore ? _openStore : _retry),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          // [DU313 ⑤] 진행 중 라벨이 읽히게 — 면 grey200 + 글자 textSecondary(5.1)
                          disabledBackgroundColor: AppColors.grey200,
                          disabledForegroundColor: AppColors.textSecondary,
                          // [DU313 r3] 주요 버튼 시각 최소 52(공통 주 버튼) — 1.0 실측 48.2 였다. 큰 배율에서는 그대로 늘어난다.
                          minimumSize: const Size.fromHeight(52),
                          padding: EdgeInsets.symmetric(
                              vertical: ResponsiveHelper.spacing(context, 14)),
                        ),
                        // [DU313 ①⑤] 두 줄이 되면 가운데 · 낱말 단위('주세 / 요' 방지)
                        child: Text(
                          TextLayout.keepWords(primaryLabel),
                          semanticsLabel: primaryLabel,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    if (primaryIsStore) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _busy ? null : _retry,
                          // [DU313 r2] '업데이트를 마쳤어요' → '다시 확인' — 완료 선언이 아니라 정책을 다시 받아 판정한다(우회 아님)
                          child: const Text('다시 확인'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
