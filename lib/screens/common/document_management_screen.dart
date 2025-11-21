import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/core/user_model.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/common_widgets.dart';
import '../../utils/document_upload_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import 'package:intl/intl.dart';

/// 📄 내 서류 관리 화면 (지원자 전용)
class DocumentManagementScreen extends StatefulWidget {
  const DocumentManagementScreen({super.key});

  @override
  State<DocumentManagementScreen> createState() => _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 통장 정보 입력 컨트롤러
  final TextEditingController _accountNumberController = TextEditingController();
  String? _selectedBank;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserDocuments();
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    super.dispose();
  }

  /// 사용자 서류 정보 로드
  Future<void> _loadUserDocuments() async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    
    if (user != null) {
      setState(() {
        _selectedBank = user.bankName;
        _accountNumberController.text = user.accountNumber ?? '';
      });
    }
  }

  /// 신분증 업로드
  Future<void> _uploadIdCard() async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    
    if (user == null) return;
    
    // 주민번호 앞 7자리 조합
    String? residentNumber;
    if (user.residentNumber != null && user.residentNumber!.length >= 8) {
      residentNumber = user.residentNumber!.substring(0, 8); // "990101-1"
    }
    
    final imagePath = await DocumentUploadHelper.pickAndVerifyIdCard(
      context,
      user.name,
      expectedResidentNumber: residentNumber,
    );
    
    if (imagePath != null && mounted) {
      setState(() => _isLoading = true);
      
      try {
        // TODO: Firebase Storage에 업로드 후 URL 받기
        // 지금은 로컬 경로만 저장
        await _firestoreService.updateUserDocument(
          user.uid,
          {
            'idCardImageUrl': imagePath,
            'idCardVerifiedAt': DateTime.now().toIso8601String(),
            'isIdVerified': true,
          },
        );
        
        // UserProvider 갱신
        await userProvider.refreshCurrentUser();
        
        ToastHelper.showSuccess('신분증이 등록되었습니다');
      } catch (e) {
        ToastHelper.showError('신분증 등록에 실패했습니다');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 통장 정보 저장
  Future<void> _saveBankInfo() async {
    if (_selectedBank == null || _accountNumberController.text.trim().isEmpty) {
      ToastHelper.showWarning('은행과 계좌번호를 입력해주세요');
      return;
    }
    
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    
    if (user == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'bankName': _selectedBank,
          'accountNumber': _accountNumberController.text.trim(),
          'accountHolder': user.name, // 예금주는 본인 이름
        },
      );
      
      await userProvider.refreshCurrentUser();
      
      ToastHelper.showSuccess('통장 정보가 저장되었습니다');
    } catch (e) {
      ToastHelper.showError('통장 정보 저장에 실패했습니다');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 신분증 삭제
  Future<void> _deleteIdCard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('신분증 삭제'),
        content: Text('등록된 신분증을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    
    if (user == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'idCardImageUrl': null,
          'idCardVerifiedAt': null,
          'isIdVerified': false,
        },
      );
      
      await userProvider.refreshCurrentUser();
      
      ToastHelper.showSuccess('신분증이 삭제되었습니다');
    } catch (e) {
      ToastHelper.showError('신분증 삭제에 실패했습니다');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 통장 정보 삭제
  Future<void> _deleteBankInfo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('통장 정보 삭제'),
        content: Text('등록된 통장 정보를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    
    if (user == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _firestoreService.updateUserDocument(
        user.uid,
        {
          'bankName': null,
          'accountNumber': null,
          'accountHolder': null,
        },
      );
      
      await userProvider.refreshCurrentUser();
      
      setState(() {
        _selectedBank = null;
        _accountNumberController.clear();
      });
      
      ToastHelper.showSuccess('통장 정보가 삭제되었습니다');
    } catch (e) {
      ToastHelper.showError('통장 정보 삭제에 실패했습니다');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.currentUser;
    final theme = Theme.of(context);
    
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('내 서류 관리')),
        body: Center(child: Text('사용자 정보를 불러올 수 없습니다')),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text('내 서류 관리'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: ResponsiveHelper.cardPadding(context),
              children: [
                // 📢 안내 카드
                CommonWidgets.infoCard(
                  context: context,
                  message: '본인 명의의 서류만 등록 가능합니다.\n'
                      '신분증과 통장의 이름이 일치해야 합니다.',
                  icon: Icons.info_outline,
                  color: Colors.blue[700],
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                
                // 📄 신분증 섹션
                CommonWidgets.sectionHeader(
                  context: context,
                  title: '신분증',
                  icon: Icons.badge,
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                _buildIdCardSection(user),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                
                // 💳 통장 정보 섹션
                CommonWidgets.sectionHeader(
                  context: context,
                  title: '통장 정보',
                  icon: Icons.account_balance_wallet,
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                _buildBankInfoSection(user),
              ],
            ),
    );
  }

  /// 📄 신분증 섹션
  Widget _buildIdCardSection(UserModel user) {
    final hasIdCard = user.idCardImageUrl != null;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasIdCard) ...[
            // 등록된 신분증 정보
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green[700],
                    size: ResponsiveHelper.iconSize(context, 32),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '신분증 등록 완료',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      if (user.idCardVerifiedAt != null)
                        Text(
                          '등록일: ${DateFormat('yyyy.MM.dd HH:mm').format(user.idCardVerifiedAt!)}',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 버튼들
            Row(
              children: [
                Expanded(
                  child: CommonWidgets.outlineButton(
                    context: context,
                    text: '재업로드',
                    onPressed: _uploadIdCard,
                    icon: Icons.refresh,
                    color: Colors.blue[700],
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: CommonWidgets.outlineButton(
                    context: context,
                    text: '삭제',
                    onPressed: _deleteIdCard,
                    icon: Icons.delete,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ] else ...[
            // 신분증 미등록
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              width: double.infinity, 
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,     // ⭐ 이거 추가
                crossAxisAlignment: CrossAxisAlignment.center,   // ⭐ 이거 추가
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: ResponsiveHelper.iconSize(context, 64),
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    '신분증이 등록되지 않았습니다',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '주민등록증 또는 운전면허증 앞면',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            CommonWidgets.primaryButton(
              context: context,
              text: '신분증 업로드',
              onPressed: _uploadIdCard,
              icon: Icons.camera_alt,
            ),
          ],
        ],
      ),
    );
  }

  /// 💳 통장 정보 섹션
  Widget _buildBankInfoSection(UserModel user) {
    final hasBankInfo = user.bankName != null && user.accountNumber != null;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasBankInfo) ...[
            // 등록된 통장 정보
            _buildInfoRow(
              icon: Icons.account_balance,
              label: '은행',
              value: user.bankName!,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.credit_card,
              label: '계좌번호',
              value: user.accountNumber!,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.person,
              label: '예금주',
              value: user.accountHolder ?? user.name,
            ),
            
            // ⭐ 여기에 통장사본 이미지 추가!
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 통장사본 표시
            if (user.bankbookImageUrl != null) ...[
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green[700],
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '통장사본 등록 완료',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.green[900],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Colors.orange[700],
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '통장사본 미등록',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _uploadBankbookImage,
                      child: Text('업로드'),
                    ),
                  ],
                ),
              ),
            ],
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 버튼들
            Row(
              children: [
                Expanded(
                  child: CommonWidgets.outlineButton(
                    context: context,
                    text: '수정',
                    onPressed: () {
                      setState(() {
                        _selectedBank = user.bankName;
                        _accountNumberController.text = user.accountNumber ?? '';
                      });
                      _showBankEditDialog();
                    },
                    icon: Icons.edit,
                    color: Colors.blue[700],
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: CommonWidgets.outlineButton(
                    context: context,
                    text: '삭제',
                    onPressed: _deleteBankInfo,
                    icon: Icons.delete,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ] else ...[
            // 통장 정보 미등록
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              width: double.infinity, 
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,     // ⭐ 이거 추가
                crossAxisAlignment: CrossAxisAlignment.center,   // ⭐ 이거 추가
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: ResponsiveHelper.iconSize(context, 64),
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    '통장 정보가 등록되지 않았습니다',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Colors.grey[600],                      
                    ),
                    textAlign: TextAlign.center, 
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '급여 수령을 위한 통장 정보',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center, 
                  ),
                ],
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            CommonWidgets.primaryButton(
              context: context,
              text: '통장 정보 등록',
              onPressed: _showBankEditDialog,
              icon: Icons.add,
            ),
          ],
        ],
      ),
    );
  }

  /// 정보 행 위젯
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: Theme.of(context).primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 통장 정보 수정 다이얼로그
  Future<void> _showBankEditDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text('통장 정보 입력'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 은행 선택
              DropdownButtonFormField<String>(
                value: _selectedBank,
                decoration: InputDecoration(
                  labelText: '은행',
                  prefixIcon: Icon(Icons.account_balance),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  'KB국민은행', '신한은행', 'NH농협은행', '우리은행', '하나은행',
                  'IBK기업은행', 'SC제일은행', '씨티은행', '카카오뱅크', '토스뱅크',
                  'KEB하나은행', '경남은행', '광주은행', '대구은행', '부산은행',
                  '전북은행', '제주은행', '케이뱅크', '새마을금고', '신협',
                  '저축은행', '우체국',
                ].map((bank) => DropdownMenuItem(
                  value: bank,
                  child: Text(bank),
                )).toList(),
                onChanged: (value) {
                  setState(() => _selectedBank = value);
                },
              ),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // 계좌번호
              CommonWidgets.textField(
                context: context,
                controller: _accountNumberController,
                label: '계좌번호',
                hint: '- 없이 숫자만 입력',
                icon: Icons.credit_card,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveBankInfo();
            },
            child: Text('저장'),
          ),
        ],
      ),
    );
  }
  /// 통장사본 업로드
  Future<void> _uploadBankbookImage() async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    
    if (user == null) return;
    
    final imagePath = await DocumentUploadHelper.pickAndVerifyBankbook(
      context,
      user.name,
    );
    
    if (imagePath != null && mounted) {
      setState(() => _isLoading = true);
      
      try {
        // TODO: Firebase Storage에 업로드 후 URL 받기
        await _firestoreService.updateUserDocument(
          user.uid,
          {
            'bankbookImageUrl': imagePath,
          },
        );
        
        await userProvider.refreshCurrentUser();
        
        ToastHelper.showSuccess('통장사본이 등록되었습니다');
      } catch (e) {
        ToastHelper.showError('통장사본 등록에 실패했습니다');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }
}