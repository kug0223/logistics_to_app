import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// 슈퍼관리자 — 공고 등록 개수 제한 설정
/// - 탭 1 (전역 기본값): settings/app_config.maxActiveTOPerBusiness
/// - 탭 2 (관리자별 한도): users/{uid}.maxActiveTOs (null이면 전역값 사용)
class TOLimitSettingsScreen extends StatefulWidget {
  const TOLimitSettingsScreen({super.key});

  @override
  State<TOLimitSettingsScreen> createState() => _TOLimitSettingsScreenState();
}

class _TOLimitSettingsScreenState extends State<TOLimitSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _service = FirestoreService();
  final _getAdminsCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableGetBusinessAdmins',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
  final _setLimitCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableSetAdminTOLimit',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
  late TabController _tabController;

  // ── 전역 기본값 탭 ──
  final _globalCtrl = TextEditingController();
  bool _isLoadingGlobal = true;
  bool _isSavingGlobal = false;
  int _globalLimit = 4;

  // ── 관리자별 한도 탭 ──
  List<_AdminItem> _admins = [];
  bool _isLoadingAdmins = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadGlobal();
      _loadAdmins();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _globalCtrl.dispose();
    for (final a in _admins) {
      a.ctrl.dispose();
    }
    super.dispose();
  }

  // ── 전역 기본값 로드/저장 ──

  Future<void> _loadGlobal() async {
    try {
      final doc =
          await _firestore.collection('settings').doc('app_config').get();
      final v =
          (doc.data()?['maxActiveTOPerBusiness'] as num?)?.toInt() ?? 4;
      if (mounted) {
        setState(() {
          _globalLimit = v;
          _globalCtrl.text = v.toString();
          _isLoadingGlobal = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _globalCtrl.text = '4';
          _isLoadingGlobal = false;
        });
        ToastHelper.showError('설정을 불러오는데 실패했습니다');
      }
    }
  }

  Future<void> _saveGlobal() async {
    final value = int.tryParse(_globalCtrl.text.trim());
    if (value == null || value < 1 || value > 50) {
      ToastHelper.showError('1~50 사이의 숫자를 입력해주세요');
      return;
    }
    setState(() => _isSavingGlobal = true);
    try {
      await _firestore.collection('settings').doc('app_config').set(
        {'maxActiveTOPerBusiness': value},
        SetOptions(merge: true),
      );
      _service.invalidateGlobalTOLimitCache();
      if (mounted) {
        setState(() => _globalLimit = value);
        ToastHelper.showSuccess('기본 한도가 $value개로 설정되었습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSavingGlobal = false);
    }
  }

  // ── 관리자별 한도 로드 ──

  Future<void> _loadAdmins() async {
    try {
      // [CF-MIGRATED] USER list CF 정책 — callableGetBusinessAdmins
      final result = await _getAdminsCF.call<Map<String, dynamic>>({});
      final rawList = (result.data['admins'] as List?) ?? [];
      final items = rawList.whereType<Map>().map((m) {
        final data = Map<String, dynamic>.from(m);
        final custom = (data['maxActiveTOs'] as num?)?.toInt();
        return _AdminItem(
          uid: data['uid'] as String? ?? '',
          name: data['name'] as String? ?? '이름 없음',
          businessName: data['businessName'] as String?,
          managedBizCount: (data['managedBizCount'] as num?)?.toInt() ?? 0,
          customLimit: custom,
          ctrl: TextEditingController(
              text: custom != null ? custom.toString() : ''),
        );
      }).where((a) => a.uid.isNotEmpty).toList();
      if (mounted) {
        setState(() {
          _admins = items;
          _isLoadingAdmins = false;
        });
      } else {
        for (final item in items) {
          item.ctrl.dispose();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAdmins = false);
        ToastHelper.showError('관리자 목록 조회에 실패했습니다');
      }
    }
  }

  Future<void> _saveAdminLimit(_AdminItem admin) async {
    final text = admin.ctrl.text.trim();

    // 빈 값 = 전역값으로 초기화
    if (text.isEmpty) {
      await _resetAdminLimit(admin);
      return;
    }

    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 50) {
      ToastHelper.showError('1~50 사이의 숫자를 입력해주세요');
      return;
    }

    setState(() => admin.isSaving = true);
    try {
      // [CF-MIGRATED] 타인 users/{uid} write CF 필수
      await _setLimitCF.call({'targetUid': admin.uid, 'value': value});
      _service.invalidateAdminTOLimitCache(admin.uid);
      if (mounted) {
        setState(() => admin.customLimit = value);
        ToastHelper.showSuccess(
            '${admin.name}의 한도가 $value개로 설정되었습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => admin.isSaving = false);
    }
  }

  Future<void> _resetAdminLimit(_AdminItem admin) async {
    setState(() => admin.isSaving = true);
    try {
      // [CF-MIGRATED] 타인 users/{uid} write CF 필수 (null = FieldValue.delete())
      await _setLimitCF.call({'targetUid': admin.uid, 'value': null});
      _service.invalidateAdminTOLimitCache(admin.uid);
      if (mounted) {
        setState(() {
          admin.customLimit = null;
          admin.ctrl.text = '';
        });
        ToastHelper.showSuccess(
            '${admin.name}의 한도가 전역 기본값으로 초기화되었습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('초기화에 실패했습니다');
    } finally {
      if (mounted) setState(() => admin.isSaving = false);
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '공고 등록 개수 제한',
      headerBottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(text: '전역 기본값'),
          Tab(text: '관리자별 한도'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGlobalTab(),
          _buildAdminTab(),
        ],
      ),
    );
  }

  Widget _buildGlobalTab() {
    if (_isLoadingGlobal) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 24),
                    color: AppColors.infoDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    '관리자별 개별 한도가 설정되지 않은 경우 이 값이 적용됩니다.\n'
                    'draft 상태로는 제한 없이 저장 가능합니다.',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.infoDark),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Text(
            '현재 기본 한도: $_globalLimit개',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextField(
            controller: _globalCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '새 기본 한도',
              hintText: '1 ~ 50',
              suffixText: '개',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
            ),
            style: ResponsiveHelper.bodyStyle(context),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSavingGlobal ? null : _saveGlobal,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 14)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSavingGlobal
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('저장',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTab() {
    if (_isLoadingAdmins) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_admins.isEmpty) {
      return Center(
        child: Text('등록된 사업장 관리자가 없습니다',
            style: ResponsiveHelper.bodyStyle(context,
                color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: _admins.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (context, index) => _buildAdminCard(_admins[index]),
    );
  }

  Widget _buildAdminCard(_AdminItem admin) {
    final hasCustom = admin.customLimit != null;
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCustom ? AppColors.info.withValues(alpha: 0.4) : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(admin.name,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.bold)),
                    if (admin.managedBizCount > 1)
                      Text('${admin.managedBizCount}개 사업장 관리 중',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textSecondary))
                    else if (admin.businessName != null)
                      Text(admin.businessName!,
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
                decoration: BoxDecoration(
                  color: hasCustom
                      ? AppColors.info.withValues(alpha: 0.1)
                      : AppColors.divider.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hasCustom ? '개별 ${admin.customLimit}개' : '전역 $_globalLimit개',
                  style: ResponsiveHelper.smallStyle(context,
                      color: hasCustom
                          ? AppColors.info
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: admin.ctrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '비워두면 전역값($_globalLimit개) 사용',
                    suffixText: '개',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 10),
                    ),
                  ),
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: admin.isSaving
                      ? null
                      : () => _saveAdminLimit(admin),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: admin.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('저장',
                          style: ResponsiveHelper.smallStyle(context,
                              color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminItem {
  final String uid;
  final String name;
  final String? businessName;
  final int managedBizCount;
  int? customLimit;
  final TextEditingController ctrl;
  bool isSaving = false;

  _AdminItem({
    required this.uid,
    required this.name,
    this.businessName,
    this.managedBizCount = 0,
    this.customLimit,
    required this.ctrl,
  });
}
