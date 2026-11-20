// [SYSTEM-INTEGRATION-R2.3] 초대 받을 지역 설정.
//
//   거주지역 ≠ 초대 받을 지역.
//   여기서 고른 지역의 사업장만 이 사람에게 먼저 근무를 제안할 수 있다.
//   직접 검색해서 지원하는 것은 이 설정과 무관하다(§2).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/invite_region_preference.dart';
import '../../models/core/user_region.dart';
import '../../providers/user_provider.dart';
import '../../services/invite_region_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/light_app_bar_style.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/inputs/home_region_picker_sheet.dart';

class InviteRegionSettingsScreen extends StatefulWidget {
  const InviteRegionSettingsScreen({super.key});

  @override
  State<InviteRegionSettingsScreen> createState() =>
      _InviteRegionSettingsScreenState();
}

class _InviteRegionSettingsScreenState
    extends State<InviteRegionSettingsScreen> {
  final InviteRegionService _svc = InviteRegionService();

  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;

  bool _enabled = false;
  List<UserRegion> _regions = [];

  /// 저장된 원본 — 변경 여부 판단용
  InviteRegionPreference _saved = const InviteRegionPreference();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final pref = await _svc.loadMine(uid);
    if (!mounted) return;
    setState(() {
      _saved = pref;
      _loadFailed = pref.state == InvitePreferenceState.unknown &&
          pref.loadFailed;
      _enabled = pref.enabled ?? false;
      _regions = List.of(pref.regions);
      _loading = false;
    });
  }

  bool get _dirty =>
      _enabled != (_saved.enabled ?? false) ||
      !_sameRegions(_regions, _saved.regions);

  static bool _sameRegions(List<UserRegion> a, List<UserRegion> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _addRegion() async {
    // [R2.3 FINAL §8] 상한은 **추가 시점에** 막는다. 21개를 고르게 해 놓고
    //   저장할 때 조용히 20개로 자르면, 사용자가 골랐다고 믿는 지역의 초대가
    //   영문 없이 오지 않는다.
    if (_regions.length >= InviteRegionPreference.maxRegions) {
      ToastHelper.showError(
          '초대 받을 지역은 최대 ${InviteRegionPreference.maxRegions}곳까지 선택할 수 있어요.');
      return;
    }
    final picked = await HomeRegionPickerSheet.show(context: context);
    if (picked == null || !mounted) return;
    if (_regions.contains(picked)) {
      ToastHelper.showInfo('이미 선택한 지역이에요.');
      return;
    }
    setState(() {
      _regions.add(picked);
      // 지역을 처음 고르면 자연스럽게 켠다. 끄고 싶으면 스위치로 끈다.
      if (_regions.length == 1) _enabled = true;
    });
  }

  Future<void> _save() async {
    // [§8] ON인데 지역 0개는 저장하지 않는다. 서버도 같은 검증을 한다.
    final candidate =
        InviteRegionPreference(enabled: _enabled, regions: _regions);
    final err = candidate.validationError();
    if (err != null) {
      ToastHelper.showError(err);
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _svc.save(enabled: _enabled, regions: _regions);
      if (!mounted) return;
      setState(() {
        _saved = result;
        _enabled = result.enabled ?? false;
        _regions = List.of(result.regions);
        _loadFailed = false;
        _saving = false;
      });
      ToastHelper.showSuccess('초대 받을 지역을 저장했어요.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ToastHelper.showError('저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = Provider.of<UserProvider>(context).currentUser?.homeRegion;
    return Scaffold(
      backgroundColor: AppColors.background, // [DU259] 앱 화면 바탕(이전 grey100)
      appBar: AppBar(
        title: const Text('근무 초대 받기'),
        backgroundColor: Colors.white,
        // [E2-APPBAR-ON-LIGHT] 흰 배경 — 테마의 흰 제목·아이콘을 이 화면만 덮는다.
        titleTextStyle: LightAppBarStyle.title(context),
        iconTheme: LightAppBarStyle.iconTheme,
        elevation: 0,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          child: ElevatedButton(
            onPressed: (_saving || !_dirty) ? null : _save,
            child: Text(_saving ? '저장 중…' : '저장'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              children: [
                if (_loadFailed) _buildLoadError(context),
                _buildToggleCard(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                if (_enabled) ...[
                  // [DU259] 섹션 제목은 카드 위(S082·S045 와 같은 16 bold 본문색)
                  _buildSectionTitle(context, '초대 받을 지역'),
                  _buildRegionCard(context, home),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                ],
                _buildExplain(context),
              ],
            ),
    );
  }

  static const _loadErrorText = '현재 설정을 확인하지 못했어요. 저장하면 아래 내용으로 덮어써요.';

  /// ERROR != OFF — 못 읽었다는 사실을 숨기지 않는다.
  ///   [DU259] 면 grey100 이 화면 바탕과 같아 상자가 보이지 않았다(글자 4.23).
  ///   주의 의미색 면(warningBg)·반경 12, 아이콘·글자 warningDark(4.81), 낱말 단위 줄바꿈.
  Widget _buildLoadError(BuildContext context) => Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 16, color: AppColors.warningDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Text(
                TextLayout.keepWords(_loadErrorText),
                semanticsLabel: _loadErrorText,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
              ),
            ),
          ],
        ),
      );

  Widget _buildToggleCard(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        // [DU259] 흰·grey200 선, 반경 12 → 16. 행 제목은 본문색 명시(이전 bodyStyle 기본 #616161).
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '근무 초대 받기',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: _enabled,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _enabled = v),
            ),
          ],
        ),
      );

  /// [DU259] 섹션 제목 — S082·S045·S040 과 같은 16 bold 본문색, 카드 위.
  Widget _buildSectionTitle(BuildContext context, String title) => Padding(
        padding: EdgeInsets.only(
          left: ResponsiveHelper.spacing(context, 4),
          bottom: ResponsiveHelper.spacing(context, 8),
        ),
        child: Text(
          TextLayout.keepWords(title),
          semanticsLabel: title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      );

  Widget _buildRegionCard(BuildContext context, UserRegion? home) {
    // [§10] 거주지역은 **추천**일 뿐이다. 누르기 전에는 저장되지 않는다.
    final suggestHome = home != null && !_regions.contains(home);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      // [DU259] 흰·grey200 선, 반경 12 → 16. 카드 안 제목은 카드 위 섹션 제목으로 옮겼다.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_regions.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 8)),
              child: Text(
                '아직 선택한 지역이 없어요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textSecondary), // [DU259] grey500(2.68)
              ),
            ),
          ..._regions.map((r) => _buildRegionRow(context, r)),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 8),
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _addRegion,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('지역 추가'),
              ),
              if (suggestHome)
                ActionChip(
                  avatar: const Icon(Icons.home_outlined, size: 16),
                  label: Text('${home.city} 추가'),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _regions.add(home)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _regionLabel(UserRegion r) =>
      r.province == null ? r.city : '${r.province} ${r.city}';

  // [DU259] 장소·삭제 아이콘 grey600·grey500(2.68) → textSecondary.
  //   지역명은 말줄임 없이 낱말 단위로 줄을 바꾼다(B320 에서 잘렸다), 본문색 명시.
  Widget _buildRegionRow(BuildContext context, UserRegion r) => Padding(
        padding:
            EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, size: 18, color: AppColors.textSecondary),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Text(
                TextLayout.keepWords(_regionLabel(r)),
                semanticsLabel: _regionLabel(r),
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.textSecondary,
              onPressed:
                  _saving ? null : () => setState(() => _regions.remove(r)),
              tooltip: '${r.city} 제거',
            ),
          ],
        ),
      );

  Widget _buildExplain(BuildContext context) {
    final msg = _enabled
        ? '선택한 지역의 사업장에서 근무 제안을 받을 수 있어요.\n'
            '사는 곳과 달라도 괜찮아요. 직접 검색해서 지원하는 것은 이 설정과 상관없어요.'
        : '초대 받기를 끄면 사업장이 먼저 제안을 보낼 수 없어요.\n'
            '일자리를 직접 검색하고 지원하는 것은 그대로 할 수 있어요.';
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
      // [DU259] grey600(바탕 위 4.23) → textSecondary, 낱말 단위 줄바꿈
      child: Text(
        TextLayout.keepWords(msg),
        semanticsLabel: msg,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
      ),
    );
  }
}
