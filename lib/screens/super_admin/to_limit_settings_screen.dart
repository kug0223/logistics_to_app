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
import '../../utils/text_layout.dart';
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

  // [DU597b · 판정119 N119-2] 두 탭 이름 — 한 줄 탭 · 줄바꿈 탭 · 높이 측정이 같은 글을 쓴다.
  static const _tabLabels = ['전역 기본값', '관리자별 한도'];

  /// [DU597b · 판정119 N119-2] 줄바꿈 탭 높이 — 이름 칸 폭 [labelWidth] 에서 낱말 단위로 줄을 바꾼 두 이름 중 높은 쪽 + 위아래 13씩
  ///   (기본 한 줄 탭 46 의 글 줄 20 위아래 여백과 같다). 렌더와 같은 글(keepWords) · 스타일 · 배율로 잰다(AppPageScaffold 제목 줄과 같은 방식).
  double _wrappedTabHeight(BuildContext context, TextStyle? style, double labelWidth) {
    var h = 0.0;
    for (final label in _tabLabels) {
      final painter = TextPainter(
        text: TextSpan(text: TextLayout.keepWords(label), style: style),
        textAlign: TextAlign.center,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: labelWidth);
      if (painter.height > h) h = painter.height;
      painter.dispose();
    }
    return h + 26;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DU495] 큰 글자 · 좁은 폭(B 320@2.0)에서 고정 두 탭의 이름이 잘렸다. 한 줄에 안 들어가면 가로 스크롤로
    //   (탭 이름은 줄이지 않는다 · DU430 · 근태 · 급여 대시보드와 같은 판정). perTab 120 = '관리자별 한도' 글자 + 좌우 여백.
    final width = MediaQuery.sizeOf(context).width;
    final tabsFit = TextLayout.tabsFit(context, width, 2, perTab: 120);
    // [DU597b · 판정119 N119-2] 가로 스크롤 탭은 고른 탭 쪽으로 밀려 B 에서 '전역 기본값' 이 '역 기본값' 처럼 반만 보였다(DU507 B 관측).
    //   한 줄에 안 들어가면 스크롤 대신 고정 두 탭 · 이름은 낱말 단위 줄바꿈 — 두 이름이 늘 전문으로 보이고 누르는 자리는 탭 반쪽 전체다.
    //   이름 축약 · 글자 축소 0. 한 줄에 들어가면(W · N) 예전과 같다(Tab(text:) · 기본 여백 · 기본 스타일).
    final tabPad = EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12));
    final tabStyle = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
    final tabH = tabsFit ? null : _wrappedTabHeight(context, tabStyle, width / 2 - tabPad.horizontal);
    return AppPageScaffold(
      title: '공고 등록 개수 제한',
      bottom: TabBar(
        controller: _tabController,
        labelPadding: tabsFit ? null : tabPad,
        labelStyle: tabsFit ? null : tabStyle,
        labelColor: theme.primaryColor,
        unselectedLabelColor: AppColors.textSecondary, // [DU495] grey500(2.68) → 보조 글자색(DU242 · DU429 와 같다)
        indicatorColor: theme.primaryColor,
        tabs: [
          for (final label in _tabLabels)
            tabsFit
                ? Tab(text: label)
                : Tab(height: tabH, child: Text(TextLayout.keepWords(label), semanticsLabel: label, textAlign: TextAlign.center)),
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
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 24),
                    color: AppColors.textSecondary),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    // [R7-P3-3 P33-X2] 단위와 적용 시점을 화면이 말하지 않았다.
                    //   둘 다 source 에서 확정된 정적 사실이다 —
                    //   scope 는 `ADMIN:{ownerUid}`(계정 단위 합산), 세는 대상은
                    //   `status in [ACTIVE, FULL]` 인 공고, 강제 지점은
                    //   `callableCreateTO` 의 생성 시점이다.
                    //   현재 사용량은 reader 에 없으므로 만들지 않는다.
                    // [DU496] B(320@2.0)에서 '계/정이' 처럼 음절에서 끊겼다 → 낱말 조판. 글자 infoDark/infoBg 4.03 → infoDeep(약관 관리 안내 띠와 같다).
                    TextLayout.keepWords(
                        '한도는 한 관리자 계정이 동시에 진행 중인 공고 수입니다.\n'
                        '그 계정의 모든 사업장을 합쳐서 셉니다 — 사업장 수가 아닙니다.\n'
                        '새 공고를 등록할 때만 적용되고, 이미 등록된 공고는 닫히지 않습니다.\n'
                        '관리자별 개별 한도가 설정되지 않은 경우 이 값이 적용됩니다.\n'
                        'draft 상태로는 제한 없이 저장 가능합니다.'),
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.textPrimary),
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
                        // [DU496] 낱말 조판(B 음절 끊김 방지).
                        TextLayout.keepWords('현재 기본 한도를 불러오지 못했습니다.\n'
                            '지금 값을 저장하면 실제 설정을 덮어씁니다.'),
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
                TextLayout.keepWords('관리자 목록을 불러오지 못했습니다'), // [DU496] 낱말 조판
                // [DU495] grey600(화면 바탕 위 4.5 미만) → 보조 글자색.
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                TextLayout.keepWords('등록된 관리자가 없다는 뜻이 아닙니다.'), // [DU496] B '뜻/이' 끊김 → 낱말 조판
                // [DU495] grey500(2.5 안팎) → 보조 글자색.
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textSecondary),
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
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
            ),
            // [DU496] 낱말 조판 · 글자 infoDark/infoBg 4.03 → infoDeep(전역 탭 안내 띠와 같다).
            child: Text(
              TextLayout.keepWords('한도는 동시에 진행 중인 공고 수입니다 — 사업장 수가 아닙니다.\n'
                  '그 관리자 계정의 모든 사업장을 합쳐서 셉니다.\n'
                  '새 공고를 등록할 때만 적용되고, 이미 등록된 공고는 닫히지 않습니다.'),
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.textPrimary),
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
          color: hasCustom ? AppColors.brand.withValues(alpha: 0.4) : AppColors.divider,
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
                      // [DU507] B(320 · 2.0)에서 '2개 사업장 관/리 중' 음절 끊김 → 낱말 조판(기존 시험은 findVisibleText 라 그대로 찾는다).
                      Text(TextLayout.keepWords('${admin.managedBizCount}개 사업장 관리 중'),
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
                      ? AppColors.brand.withValues(alpha: 0.1)
                      : AppColors.divider.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hasCustom ? '개별 ${admin.customLimit}개' : '전역 $_globalLimit개',
                  style: ResponsiveHelper.smallStyle(context,
                      // [DU496] info/info 10% 2.80 → infoDeep 7.74(면은 그대로).
                      color: hasCustom
                          ? AppColors.brand
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
                    // [DU507 r2] B 에서 힌트가 '비워두…'로 말줄임돼 무엇을 비우면 어떻게 되는지 읽히지 않았다 — 낱말 단위 최대 3줄.
                    //   괄호 '(7개)' 가 '전역값' 과 한 덩어리가 되어 B 가용폭을 넘었다(r1 정적 대조) — 띄어 써서 덩어리를 나눈다.
                    hintText: TextLayout.keepWords('비워두면 전역값 $_globalLimit개 사용'),
                    hintMaxLines: 3,
                    // [DU507 r3 · 후속117 N117-1] 값이 든 칸이 숨은 3줄 힌트의 높이를 그대로 잡아 B 에서 3줄 높이로 비었다
                    //   (InputDecoration.maintainHintSize 기본 true — SDK input_decorator.dart:1068–1071). 숨은 힌트는 크기를 남기지 않는다.
                    //   빈 칸에서는 힌트 전문이 그대로 보인다(글자 축소 · 배율 제한 · 잘라맞추기 없음).
                    maintainHintSize: false,
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
              // [DU597b · 판정119 N119-1] 관리자별 '저장' 고정 높이 42 → 48 — 누르는 자리 ≥ 48(앱 버튼 테마 최소 48 과 같다). 글 · 동작 · 색 그대로.
              SizedBox(
                height: 48,
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
