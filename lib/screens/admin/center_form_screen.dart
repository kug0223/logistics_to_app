import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/center_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/daum_address_search.dart'; // ✅ 추가!

/// 센터 등록/수정 폼 화면
class CenterFormScreen extends StatefulWidget {
  final CenterModel? center; // null이면 신규 등록, 있으면 수정

  const CenterFormScreen({Key? key, this.center}) : super(key: key);

  @override
  State<CenterFormScreen> createState() => _CenterFormScreenState();
}

class _CenterFormScreenState extends State<CenterFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  // 컨트롤러들
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _addressController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  late TextEditingController _managerNameController;
  late TextEditingController _managerPhoneController;

  // 특징 리스트
  List<String> _features = [];
  final TextEditingController _featureController = TextEditingController();

  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    
    // 기존 센터 데이터가 있으면 불러오기
    if (widget.center != null) {
      final center = widget.center!;
      _nameController = TextEditingController(text: center.name);
      _codeController = TextEditingController(text: center.code);
      _addressController = TextEditingController(text: center.address);
      _latitudeController = TextEditingController(
        text: center.latitude?.toString() ?? '',
      );
      _longitudeController = TextEditingController(
        text: center.longitude?.toString() ?? '',
      );
      _descriptionController = TextEditingController(text: center.description ?? '');
      _notesController = TextEditingController(text: center.notes ?? '');
      _managerNameController = TextEditingController(text: center.managerName ?? '');
      _managerPhoneController = TextEditingController(text: center.managerPhone ?? '');
      _features = List.from(center.features);
      _isActive = center.isActive;
    } else {
      _nameController = TextEditingController();
      _codeController = TextEditingController();
      _addressController = TextEditingController();
      _latitudeController = TextEditingController();
      _longitudeController = TextEditingController();
      _descriptionController = TextEditingController();
      _notesController = TextEditingController();
      _managerNameController = TextEditingController();
      _managerPhoneController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _managerNameController.dispose();
    _managerPhoneController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  /// 주소 검색 ✅ 좌표까지 자동 입력!
  Future<void> _searchAddress() async {
    final result = await DaumAddressService.searchAddress(context);
    
    if (result != null) {
      setState(() {
        _addressController.text = result.fullAddress;
        
        // ✅ 좌표도 자동 입력!
        if (result.latitude != null && result.longitude != null) {
          _latitudeController.text = result.latitude!.toStringAsFixed(6);
          _longitudeController.text = result.longitude!.toStringAsFixed(6);
          ToastHelper.showSuccess('주소와 좌표가 입력되었습니다');
        } else {
          ToastHelper.showSuccess('주소가 입력되었습니다 (좌표는 수동 입력)');
        }
      });
    }
  }

  /// 특징 추가
  void _addFeature() {
    final feature = _featureController.text.trim();
    if (feature.isNotEmpty && !_features.contains(feature)) {
      setState(() {
        _features.add(feature);
        _featureController.clear();
      });
    }
  }

  /// 특징 제거
  void _removeFeature(String feature) {
    setState(() {
      _features.remove(feature);
    });
  }

  /// 센터 저장
  Future<void> _saveCenter() async {
    if (!_formKey.currentState!.validate()) {
      print('❌ 폼 검증 실패');
      return;
    }

    print('✅ 폼 검증 성공 - 저장 시작');

    setState(() {
      _isSaving = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        print('❌ UID null');
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다.');
        setState(() => _isSaving = false);
        return;
      }

      print('✅ UID: $uid');

      // 위도/경도 파싱
      double? latitude;
      double? longitude;
      if (_latitudeController.text.isNotEmpty) {
        latitude = double.tryParse(_latitudeController.text);
        print('위도: $latitude');
      }
      if (_longitudeController.text.isNotEmpty) {
        longitude = double.tryParse(_longitudeController.text);
        print('경도: $longitude');
      }

      final now = DateTime.now();
      final centerData = CenterModel(
        id: widget.center?.id,
        name: _nameController.text.trim(),
        code: _codeController.text.trim().toUpperCase(),
        address: _addressController.text.trim(),
        latitude: latitude,
        longitude: longitude,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        features: _features,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        managerName: _managerNameController.text.trim().isEmpty
            ? null
            : _managerNameController.text.trim(),
        managerPhone: _managerPhoneController.text.trim().isEmpty
            ? null
            : _managerPhoneController.text.trim(),
        isActive: _isActive,
        createdAt: widget.center?.createdAt ?? now,
        updatedAt: now,
        createdBy: widget.center?.createdBy ?? uid,
      );

      print('센터 데이터 생성 완료: ${centerData.name} (${centerData.code})');

      if (widget.center == null) {
        // 신규 등록
        print('🆕 신규 센터 등록 시작...');
        final result = await _firestoreService.createCenter(centerData);
        print('createCenter 결과: $result');
        
        if (result != null) {
          print('✅ 센터 등록 성공! ID: $result');
          if (mounted) {
            Navigator.pop(context, true);
          }
        } else {
          print('❌ 센터 등록 실패 - result is null');
          if (mounted) {
            ToastHelper.showError('센터 등록에 실패했습니다.');
          }
        }
      } else {
        // 수정
        print('✏️ 센터 수정 시작... ID: ${widget.center!.id}');
        final success = await _firestoreService.updateCenter(
          widget.center!.id!,
          centerData,
        );
        print('updateCenter 결과: $success');
        
        if (success) {
          print('✅ 센터 수정 성공!');
          if (mounted) {
            Navigator.pop(context, true);
          }
        } else {
          print('❌ 센터 수정 실패');
          if (mounted) {
            ToastHelper.showError('센터 수정에 실패했습니다.');
          }
        }
      }
    } catch (e, stackTrace) {
      print('❌ 센터 저장 중 예외 발생: $e');
      print('스택 트레이스: $stackTrace');
      if (mounted) {
        ToastHelper.showError('센터 저장에 실패했습니다: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        print('_isSaving = false 완료');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.center != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '센터 수정' : '센터 등록'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 기본 정보 섹션
                _buildSectionTitle('기본 정보'),
                const SizedBox(height: 16),

                // 센터명
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '센터명 *',
                    hintText: '송파 물류센터',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.business),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '센터명을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 센터 코드
                TextFormField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: '센터 코드 *',
                    hintText: 'CENTER_A',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.tag),
                    helperText: '영문 대문자와 언더바만 사용 가능 (예: CENTER_A)',
                    enabled: !isEdit,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '센터 코드를 입력해주세요';
                    }
                    if (!RegExp(r'^[A-Z_]+$').hasMatch(value.trim())) {
                      return '영문 대문자와 언더바만 사용 가능합니다';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ✅ 주소 검색 버튼 추가!
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: '주소 *',
                          hintText: '주소 검색 버튼을 눌러주세요',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '주소를 입력해주세요';
                          }
                          return null;
                        },
                        maxLines: 2,
                        readOnly: true, // 직접 입력 불가
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _searchAddress,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 20),
                            SizedBox(height: 2),
                            Text('주소검색', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 위치 정보 섹션
                _buildSectionTitle('위치 정보 (선택)'),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latitudeController,
                        decoration: const InputDecoration(
                          labelText: '위도',
                          hintText: '37.5665',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.map),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _longitudeController,
                        decoration: const InputDecoration(
                          labelText: '경도',
                          hintText: '126.9780',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.map),
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 상세 정보 섹션
                _buildSectionTitle('상세 정보 (선택)'),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    hintText: '센터에 대한 간단한 설명',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // 특징 입력
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _featureController,
                        decoration: const InputDecoration(
                          labelText: '특징 추가',
                          hintText: '예: 냉동창고',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.star),
                        ),
                        onFieldSubmitted: (_) => _addFeature(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      color: Colors.blue.shade700,
                      iconSize: 32,
                      onPressed: _addFeature,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 추가된 특징 목록
                if (_features.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _features.map((feature) {
                      return Chip(
                        label: Text(feature),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => _removeFeature(feature),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: '메모',
                    hintText: '추가 메모사항',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                // 담당자 정보 섹션
                _buildSectionTitle('담당자 정보 (선택)'),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _managerNameController,
                  decoration: const InputDecoration(
                    labelText: '담당자 이름',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _managerPhoneController,
                  decoration: const InputDecoration(
                    labelText: '담당자 연락처',
                    hintText: '010-1234-5678',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),

                // 활성화 상태
                if (isEdit) ...[
                  _buildSectionTitle('센터 상태'),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('센터 활성화'),
                    subtitle: const Text('비활성화 시 TO 생성에서 선택 불가'),
                    value: _isActive,
                    onChanged: (value) {
                      setState(() {
                        _isActive = value;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // 저장 버튼
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveCenter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEdit ? '수정하기' : '등록하기',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 섹션 타이틀
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.blue.shade700,
      ),
    );
  }
}