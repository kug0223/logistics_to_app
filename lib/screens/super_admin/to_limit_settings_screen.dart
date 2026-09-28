import 'package:flutter/material.dart';
// [R7-P1-7 P17-A] GradientScaffold → AppPageScaffold(D0 flat admin shell).
//   이 화면은 헤더에 TabBar 가 있고 라벨·인디케이터가 흰색이었다 — 파란 그라디언트
//   위에서만 읽히는 색이다. 밝은 app bar 에 그대로 두면 라벨이 보이지 않으므로
//   같은 전환에서 **대비까지 함께** 옮긴다(계약 관리 화면이 쓰는 flat TabBar 계약).
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import 'to_limit_reads.dart';

/// 슈퍼관리자 — 공고 등록 개수 제한 설정
/// - 탭 1 (전역 기본값): settings/app_config.maxActiveTOPerBusiness
/// - 탭 2 (관리자별 한도): users/{uid}.maxActiveTOs (null이면 전역값 사용)
class TOLimitSettingsScreen extends StatefulWidget {
  /// [R7-P3-2 P32-X2] 값을 읽는 경계. production 은 null.
  final ToLimitReads? reads;

  const TOLimitSettingsScreen({super.key, this.reads});

  @override
  State<TOLimitSettingsScreen> createState() => _TOLimitSettingsScreenState();
}

class _TOLimitSettingsScreenState extends State<TOLimitSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final ToLimitReads _reads = widget.reads ?? ToLimitReads.of();
  final _firestore = FirebaseFirestore.instance;
  final _service = FirestoreService();
  final _setLimitCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableSetAdminTOLimit',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
  late TabController _tabController;

  // ── 전역 기본값 탭 ──
  final _globalCtrl = TextEditingController();
  bool _isLoadingGlobal = true;
  bool _isSavingGlobal = false;
  int _globalLimit = 4;
  bool _globalLoadFailed = false;

  // ── 관리자별 한도 탭 ──
  List<_AdminItem> _admins = [];
  bool _isLoadingAdmins = true;
  bool _adminsLoadFailed = false;

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
    if (mounted) setState(() => _globalLoadFailed = false);
    try {
      final data = await _reads.globalConfigRaw();
      final v = (data?['maxActiveTOPerBusiness'] as num?)?.toInt() ?? 4;
      if (mounted) {
        setState(() {
          _globalLimit = v;
          _globalCtrl.text = v.toString();
          _isLoadingGlobal = false;
        });
      }
    } catch (e) {
      // [R7-P3-2 P32-X2] 못 읽은 값을 확정 숫자로 말하지 않는다.
      //   전에는 실패해도 `현재 기본 한도: 4개` 가 그대로 남고 입력칸에 `4` 가
      //   미리 채워졌다 — 그대로 저장하면 실제 값을 4로 덮어쓴다.
      if (mounted) {
        setState(() {
          _globalCtrl.text = '';
          _globalLoadFailed = true;
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
    if (mounted) setState(() => _adminsLoadFailed = false);
    try {
      // [CF-MIGRATED] USER list CF 정책 — callableGetBusinessAdmins
      final rawList = await _reads.businessAdminsRaw();
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
      // [R7-P3-2 P32-X2] 조회 실패를 **관리자 없음**으로 말하지 않는다.
      if (mounted) {
        setState(() {
          _adminsLoadFailed = true;
          _isLoadingAdmins = false;
        });
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
    final theme = Theme.of(context);
    return AppPageScaffold(
      title: '공고 등록 개수 제한',
      bottom: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: AppColors.grey500,
        indicatorColor: theme.primaryColor,
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
                    // [R7-P3-3 P33-X2] 단위와 적용 시점을 화면이 말하지 않았다.
                    //   둘 다 source 에서 확정된 정적 사실이다 —
                    //   scope 는 `ADMIN:{ownerUid}`(계정 단위 합산), 세는 대상은
                    //   `status in [ACTIVE, FULL]` 인 공고, 강제 지점은
                    //   `callableCreateTO` 의 생성 시점이다.
                    //   현재 사용량은 reader 에 없으므로 만들지 않는다.
                    '한도는 한 관리자 계정이 동시에 진행 중인 공고 수입니다.\n'
                    '그 계정의 모든 사업장을 합쳐서 셉니다 — 사업장 수가 아닙니다.\n'
                    '새 공고를 등록할 때만 적용되고, 이미 등록된 공고는 닫히지 않습니다.\n'
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
          // [R7-P3-2 P32-X2] 모르는 값을 아는 값처럼 말하지 않는다.
          _globalLoadFailed
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: AppColors.errorDark),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '현재 기본 한도를 불러오지 못했습니다.\n'
                        '지금 값을 저장하면 실제 설정을 덮어씁니다.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.errorDark),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadGlobal,
                      child: const Text('다시 시도'),
                    ),
                  ],
                )
              : Text(
                  '현재 기본 한도: $_globalLimit개',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextField(
            controller: _globalCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
    if (_adminsLoadFailed) {
      // [R7-P3-2 P32-X2] 못 읽은 것은 없는 것이 아니다.
      return Center(
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: ResponsiveHelper.iconSize(context, 40),
                  color: AppColors.grey400),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '관리자 목록을 불러오지 못했습니다',
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.grey600),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                '등록된 관리자가 없다는 뜻이 아닙니다.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: _loadAdmins,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    if (_admins.isEmpty) {
      return Center(
        child: Text('등록된 사업장 관리자가 없습니다',
            style: ResponsiveHelper.bodyStyle(context,
                color: AppColors.textSecondary)),
      );
    }
    // [R7-P3-3 P33-X2] 카드 한 줄에 `2개 사업장 관리 중` 과 `개별 3개` 가 나란히
    //   놓인다. 둘 다 숫자 + `개` 라서 무엇의 수인지 문맥이 없었다.
    //   배지를 길게 만들어 320dp 를 위협하는 대신, 목록 앞에서 단위를 못박는다.
    return ListView.separated(
      padding: ResponsiveHelper.listPadding(context),
      itemCount: _admins.length + 1,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '한도는 동시에 진행 중인 공고 수입니다 — 사업장 수가 아닙니다.\n'
              '그 관리자 계정의 모든 사업장을 합쳐서 셉니다.\n'
              '새 공고를 등록할 때만 적용되고, 이미 등록된 공고는 닫히지 않습니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.infoDark),
            ),
          );
        }
        return _buildAdminCard(_admins[index - 1]);
      },
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
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
