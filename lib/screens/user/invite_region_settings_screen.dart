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
import '../../utils/responsive_helper.dart';
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
      backgroundColor: AppColors.grey100,
      appBar: AppBar(
        title: const Text('근무 초대 받기'),
        backgroundColor: Colors.white,
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
                  _buildRegionCard(context, home),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                ],
                _buildExplain(context),
              ],
            ),
    );
  }

  /// ERROR != OFF — 못 읽었다는 사실을 숨기지 않는다.
  Widget _buildLoadError(BuildContext context) => Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Text(
                '현재 설정을 확인하지 못했어요. 저장하면 아래 내용으로 덮어써요.',
                style:
                    ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '근무 초대 받기',
                style: ResponsiveHelper.bodyStyle(context)
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

  Widget _buildRegionCard(BuildContext context, UserRegion? home) {
    // [§10] 거주지역은 **추천**일 뿐이다. 누르기 전에는 저장되지 않는다.
    final suggestHome = home != null && !_regions.contains(home);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '초대 받을 지역',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          if (_regions.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 8)),
              child: Text(
                '아직 선택한 지역이 없어요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
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

  Widget _buildRegionRow(BuildContext context, UserRegion r) => Padding(
        padding:
            EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, size: 18, color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Text(
                r.province == null ? r.city : '${r.province} ${r.city}',
                style: ResponsiveHelper.bodyStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.grey500,
              onPressed:
                  _saving ? null : () => setState(() => _regions.remove(r)),
              tooltip: '${r.city} 제거',
            ),
          ],
        ),
      );

  Widget _buildExplain(BuildContext context) => Padding(
        padding:
            EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
        child: Text(
          _enabled
              ? '선택한 지역의 사업장에서 근무 제안을 받을 수 있어요.\n'
                  '사는 곳과 달라도 괜찮아요. 직접 검색해서 지원하는 것은 이 설정과 상관없어요.'
              : '초대 받기를 끄면 사업장이 먼저 제안을 보낼 수 없어요.\n'
                  '일자리를 직접 검색하고 지원하는 것은 그대로 할 수 있어요.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
      );
}
