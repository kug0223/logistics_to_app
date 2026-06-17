import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/core/application_model.dart';
import '../models/core/business_model.dart';
import '../models/core/to_model.dart';
import '../models/core/contract_template_model.dart';
import '../models/core/employment_contract_model.dart';
import '../models/core/notification_model.dart';
import '../models/core/user_model.dart';
import '../models/core/work_detail_data.dart';
import '../utils/format_helper.dart';
import 'firestore_service.dart';

class ContractService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _firestoreService = FirestoreService();

  // ── 핵심: 번들링 생성/추가 ─────────────────────────────────────

  /// 확정 시 호출. 동일 (toId + workDetailId + workerId) 계약서가 있으면
  /// 슬롯 추가, 없으면 새 계약서 생성.
  /// 장기 근무는 기존처럼 단일 계약서 생성.
  ///
  /// [C01 동시성 설계]
  /// 두 관리자가 동시에 같은 근무자에게 계약서를 생성하는 경우:
  /// - 단기: _findBundle이 둘 다 null을 반환 → _createNew가 둘 다 isNewUnsaved:true 객체 반환.
  ///   이후 saveEmployerSignature에서 각자 다른 doc ref로 트랜잭션 set을 실행하므로
  ///   중복 계약서 2개가 생성될 수 있다 (TOCTOU).
  ///   방어책: saveEmployerSignature 진입 전 applicationId 기준으로 재조회하여 이미 존재하면
  ///   기존 계약에 슬롯 추가로 전환. 이 재조회-생성 사이도 race 가능하나, 실제로
  ///   두 관리자가 밀리초 단위로 동일 지원서에 계약서를 생성하는 빈도는 매우 낮으므로
  ///   last-write-wins 허용(의도된 설계). 중복 발생 시 UI에서 경고 표시.
  ///
  /// - 장기: 계약서가 근무자당 1개여야 하는 동일 문제. 마찬가지로 빈도 낮아 허용.
  ///
  /// 완전한 방어를 위해서는 Cloud Functions에서 트랜잭션으로 처리해야 하나,
  /// 현재 클라이언트 단계에서는 위 설계 수준으로 충분하다고 판단.
  Future<EmploymentContractModel> findOrCreateContract({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    List<ContractArticle> articles = const [],
    String? templateId,
  }) async {
    final isLong = application.isLongTermApplication;
    final toId = application.toId ?? '';
    final workDetailId = application.workDetailId ?? workDetail.id;

    if (!isLong) {
      // 단기: 기존 번들 계약서 탐색 (articles는 최초 생성 시에만 적용)
      final existing = await _findBundle(
        toId: toId,
        workDetailId: workDetailId,
        workerId: worker.uid,
        businessId: business.id,
      );
      // [K-001] pendingEmployer 상태에서만 슬롯 추가 허용
      // — pendingWorker 이상(사업주 서명 완료)은 슬롯 추가 불가: 서명 무결성 보호
      if (existing != null &&
          existing.status == ContractStatus.pendingEmployer) {
        return _addSlot(existing, application, workDetail);
      }
    }

    // 신규 생성 (장기 또는 첫 번째 단기 슬롯)
    return _createNew(
      application: application,
      business: business,
      worker: worker,
      workDetail: workDetail,
      toId: toId,
      workDetailId: workDetailId,
      articles: articles,
      templateId: templateId,
    );
  }

  /// 미리보기 전용 계약서 생성 — 번들 탐색 없이 항상 isNewUnsaved:true 반환.
  /// Firestore에 저장되지 않으므로 미리보기 후 버려도 안전하다.
  Future<EmploymentContractModel> buildPreviewContract({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    List<ContractArticle> articles = const [],
  }) async {
    return _createNew(
      application: application,
      business: business,
      worker: worker,
      workDetail: workDetail,
      toId: application.toId ?? '',
      workDetailId: application.workDetailId ?? workDetail.id,
      articles: articles,
    );
  }

  // ── 서명 저장 ────────────────────────────────────────────────

  /// 사업주 서명 → 근무자 서명 대기로 전환
  Future<EmploymentContractModel> saveEmployerSignature({
    required EmploymentContractModel contract,
    required Uint8List signatureBytes,
  }) async {
    if (contract.status == ContractStatus.voided) {
      throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
    }
    if (contract.status == ContractStatus.completed) {
      throw Exception('이미 완료된 계약서입니다');
    }
    if (contract.employerSignatureUrl != null && contract.employerSignatureUrl!.isNotEmpty) {
      throw Exception('이미 사업주 서명이 완료된 계약서입니다');
    }

    final url = await _uploadSignature(
      contractId: contract.id,
      role: 'employer',
      bytes: signatureBytes,
    );

    final now = DateTime.now(); // 로컬 변수로 분리 — nullable ! 방지
    final updated = contract.copyWith(
      status: ContractStatus.pendingWorker,
      employerSignatureUrl: url,
      employerSignedAt: now,
      updatedAt: now,
    );

    // Firestore 저장 — 동시 서명·중복 생성 방지를 위해 항상 트랜잭션 사용
    try {
      final ref = _db.collection('employment_contracts').doc(contract.id);
      final employerHash = sha256.convert(signatureBytes).toString();
      if (contract.isNewUnsaved) {
        // 신규 계약서: 동시 이중 제출 시 문서 중복 생성 방지
        final data = updated.toMap();
        data['createdAt'] = FieldValue.serverTimestamp();
        await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (snap.exists) {
            throw Exception('이미 계약서가 생성되었습니다');
          }
          data['employerSignatureHash'] = employerHash;
          tx.set(ref, data);
        });
      } else {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (snap.exists) {
            final currentStatus = snap.data()?['status'] as String?;
            if (currentStatus == ContractStatus.voided.value) {
              throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
            }
            if (currentStatus == ContractStatus.completed.value) {
              throw Exception('이미 완료된 계약서입니다');
            }
            if (snap.data()?['employerSignatureUrl'] != null) {
              throw Exception('이미 사업주 서명이 완료된 계약서입니다');
            }
          }
          // SHA-256 해시로 서명 무결성 기록
          tx.update(ref, {
            'status': updated.status.value,
            'employerSignatureUrl': url,
            'employerSignatureHash': employerHash,
            'employerSignedAt': Timestamp.fromDate(now),
            'updatedAt': Timestamp.fromDate(now),
          });
        });
      }
    } catch (e) {
      // Firestore 실패 → 업로드된 서명 파일 삭제 (고아 파일 방지)
      try {
        await _storage.ref()
            .child('contracts/${contract.id}/signature_employer.png')
            .delete();
      } catch (cleanupErr) {
        // [K-004] 서명 파일 삭제 실패 — 고아 파일 가능성, 수동 확인 필요
        debugPrint('⚠️ [K-004] 사업주 서명 파일 삭제 실패 (고아 파일 주의) — ${contract.id}: $cleanupErr');
      }
      rethrow;
    }

    // 근무자에게 서명 요청 알림
    try {
      await _firestoreService.createNotification(
        NotificationModel.createContractSignRequested(
          userId: contract.workerId,
          businessName: contract.snapshot.businessName,
          businessId: contract.businessId,
          contractId: contract.id,
          applicationId: contract.applicationId,
        ),
      );
    } catch (e) {
      debugPrint('계약서 알림 발송 실패: $e');
    }

    return updated;
  }

  /// 근무자 서명 → 완료 상태로 전환
  Future<EmploymentContractModel> saveWorkerSignature({
    required EmploymentContractModel contract,
    required Uint8List signatureBytes,
    required Uint8List pdfBytes,
  }) async {
    if (contract.status == ContractStatus.voided) {
      throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
    }
    if (contract.status == ContractStatus.completed) {
      throw Exception('이미 완료된 계약서입니다');
    }
    if (contract.workerSignatureUrl != null && contract.workerSignatureUrl!.isNotEmpty) {
      throw Exception('이미 근무자 서명이 완료된 계약서입니다');
    }

    // 서명 이미지 업로드
    final sigUrl = await _uploadSignature(
      contractId: contract.id,
      role: 'worker',
      bytes: signatureBytes,
    );

    // PDF 업로드 — 실패 시 서명 이미지 롤백
    String pdfUrl;
    try {
      pdfUrl = await _uploadPdf(contractId: contract.id, bytes: pdfBytes);
    } catch (e) {
      try {
        await _storage.ref()
            .child('contracts/${contract.id}/signature_worker.png')
            .delete();
      } catch (cleanupErr) {
        // [K-005] 서명 이미지 삭제 실패 — 고아 파일 가능성, 수동 확인 필요
        debugPrint('⚠️ [K-005] 근무자 서명 이미지 삭제 실패 (고아 파일 주의) — ${contract.id}: $cleanupErr');
      }
      rethrow;
    }

    final workerNow = DateTime.now(); // 로컬 변수 분리 — nullable ! 방지
    final updated = contract.copyWith(
      status: ContractStatus.completed,
      workerSignatureUrl: sigUrl,
      workerSignedAt: workerNow,
      pdfUrl: pdfUrl,
      updatedAt: workerNow,
    );

    // [C04 동시성 방어] 계약서 무효화(voided)와 근무자 서명의 race condition:
    // 트랜잭션 내에서 currentStatus를 재확인하여 voided이면 예외 발생 → 서명 실패.
    // Storage에 업로드된 서명+PDF는 아래 catch에서 즉시 삭제하여 고아 파일 방지.
    //
    // [C02] 사업주와 근무자가 동시에 서명 시도:
    // saveEmployerSignature: employerSignatureUrl 존재 여부 체크 후 set/update.
    // saveWorkerSignature: workerSignatureUrl 존재 여부 체크 — 둘 다 트랜잭션으로 원자 처리.
    // 중복 서명 시 두 번째 트랜잭션은 예외 발생 → 안전.
    try {
      final nowTs = Timestamp.fromDate(workerNow);
      // 동시 서명 방지 + application 상태 원자적 업데이트
      final contractRef = _db.collection('employment_contracts').doc(contract.id);
      final workerHash = sha256.convert(signatureBytes).toString();
      await _db.runTransaction((tx) async {
        final snap = await tx.get(contractRef);
        if (snap.exists) {
          final currentStatus = snap.data()?['status'] as String?;
          if (currentStatus == ContractStatus.voided.value) {
            throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
          }
          if (currentStatus == ContractStatus.completed.value) {
            throw Exception('이미 완료된 계약서입니다');
          }
          if (snap.data()?['workerSignatureUrl'] != null) {
            throw Exception('이미 근무자 서명이 완료된 계약서입니다');
          }
        }
        tx.update(contractRef, {
          'status': updated.status.value,
          'workerSignatureUrl': sigUrl,
          'workerSignatureHash': workerHash,
          'workerSignedAt': nowTs,
          'pdfUrl': pdfUrl,
          'updatedAt': nowTs,
        });
        // 계약서 + application 상태를 하나의 트랜잭션으로 원자적 처리
        // CONTRACT_PENDING 상태인 경우에만 업데이트 — 이미 CONFIRMED이면 rules 위반 방지
        for (final appId in contract.applicationIds) {
          final appRef = _db.collection('applications').doc(appId);
          final appSnap = await tx.get(appRef);
          if (appSnap.data()?['status'] == 'CONTRACT_PENDING') {
            tx.update(appRef, {
              'status': 'CONFIRMED',
              'statusHistory': FieldValue.arrayUnion([{
                'status': 'CONFIRMED',
                'at': nowTs,
                'by': 'SYSTEM',
                'action': 'CONTRACT_SIGNED',
              }]),
            });
          }
        }
      });
    } catch (e) {
      // Firestore 실패 → 서명 이미지 + PDF 삭제 (고아 파일 방지)
      for (final path in [
        'contracts/${contract.id}/signature_worker.png',
        'contracts/${contract.id}/contract.pdf',
      ]) {
        try {
          await _storage.ref().child(path).delete();
        } catch (cleanupErr) {
          // [K-006] Firestore 실패 후 Storage 롤백 실패 — 고아 파일 가능성, 수동 확인 필요
          debugPrint('⚠️ [K-006] 근무자 서명/PDF 삭제 실패 (고아 파일 주의) — $path: $cleanupErr');
        }
      }
      rethrow;
    }

    // [알림 흐름]
    // 1차) 근무자 지원 → 관리자에게 newApplication 알림 (application_firestore.dart)
    // 2차) 관리자 확정 + 계약서 발송 → 근무자에게 contractSignRequested 알림 (saveEmployerSignature)
    // 3차) 근무자 서명 완료 → 관리자(오너)에게 contractSigned 알림 (여기)
    try {
      final bizSnap = await _db.collection('businesses').doc(contract.businessId).get();
      final ownerId = bizSnap.data()?['ownerId'] as String?;
      if (ownerId != null) {
        await _firestoreService.createNotification(
          NotificationModel.createContractSigned(
            userId: ownerId,
            workerName: contract.snapshot.workerName,
            businessId: contract.businessId,
            contractId: contract.id,
            applicationId: contract.applicationId,
          ),
        );
      } else {
        debugPrint('⚠️ contractSigned: ownerId 없음 — businessId: ${contract.businessId}');
      }
    } catch (e) {
      debugPrint('⚠️ contractSigned 알림 발송 실패 (비치명적): $e');
    }

    return updated;
  }

  // ── 사용자 서명 저장/삭제 ─────────────────────────────────────

  /// Firestore users/{uid}에 signatureBase64 저장
  Future<void> saveUserSignature({
    required String uid,
    required String base64,
  }) async {
    await _db.collection('users').doc(uid).update({'signatureBase64': base64});
  }

  /// 저장된 서명 삭제
  Future<void> clearUserSignature(String uid) async {
    await _db.collection('users').doc(uid).update({'signatureBase64': null});
  }

  /// 기존 계약서에 템플릿 조항 적용 (articles가 비어있던 구 계약서용)
  ///
  /// [BUG-수정] completed/voided 상태의 계약서는 수정 불가 — StateError 발생.
  Future<void> updateArticles({
    required String contractId,
    required List<ContractArticle> articles,
    String? templateId,
  }) async {
    // [BUG-수정] 상태 체크: 서명 완료 또는 무효화된 계약서는 수정 금지
    final snap = await _db.collection('employment_contracts').doc(contractId).get();
    if (snap.exists) {
      final contract = EmploymentContractModel.fromFirestore(snap);
      if (contract.status == ContractStatus.completed ||
          contract.status == ContractStatus.voided) {
        throw StateError('서명 완료 또는 무효화된 계약서는 수정할 수 없습니다.');
      }
    }

    await _db.collection('employment_contracts').doc(contractId).update({
      'articles': articles.map((a) => a.toMap()).toList(),
      if (templateId != null) 'templateId': templateId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── 조회 ─────────────────────────────────────────────────────

  /// applicationId로 계약서 조회 (하위 호환 + 슬롯 포함 검색)
  ///
  /// 보안 규칙상 아래 중 하나를 반드시 전달해야 함:
  ///   [workerId] USER 컨텍스트 — 본인 uid (근무자가 자신의 계약서 조회)
  ///   [businessId] 관리자 컨텍스트 — 소속 사업장 id (관리자가 계약서 조회)
  Future<EmploymentContractModel?> getByApplication(
    String applicationId, {
    String? workerId,
    String? businessId,
  }) async {
    // assert 대신 throw — assert는 릴리스 빌드에서 무시되어 Firestore 보안 규칙 오류로 이어질 수 있음 (E-043)
    if (workerId == null && businessId == null) {
      throw ArgumentError('getByApplication: workerId 또는 businessId 중 하나는 필수입니다');
    }
    try {
      // 1) 기본 applicationId 매칭 (+ 소유권 앵커 필터)
      Query<Map<String, dynamic>> q = _db
          .collection('employment_contracts')
          .where('applicationId', isEqualTo: applicationId);
      if (businessId != null) {
        q = q.where('businessId', isEqualTo: businessId);
      } else if (workerId != null) {
        q = q.where('workerId', isEqualTo: workerId);
      }
      final snap = await q.orderBy('createdAt', descending: true).limit(1).get();
      if (snap.docs.isNotEmpty) {
        return EmploymentContractModel.fromFirestore(snap.docs.first);
      }
      // 2) applicationIds 배열에 포함된 경우 (단기 번들 슬롯)
      Query<Map<String, dynamic>> slotQ = _db
          .collection('employment_contracts')
          .where('applicationIds', arrayContains: applicationId);
      if (businessId != null) {
        slotQ = slotQ.where('businessId', isEqualTo: businessId);
      } else if (workerId != null) {
        slotQ = slotQ.where('workerId', isEqualTo: workerId);
      }
      final slotSnap = await slotQ.limit(1).get();
      if (slotSnap.docs.isNotEmpty) {
        return EmploymentContractModel.fromFirestore(slotSnap.docs.first);
      }
      return null;
    } on FirebaseException catch (e) {
      // FAILED_PRECONDITION: 복합 인덱스 미생성 → 개발자가 인지해야 하므로 rethrow
      if (e.code == 'failed-precondition') {
        debugPrint('🚨 [contract] 복합 인덱스 누락: ${e.message}');
        rethrow;
      }
      debugPrint('❌ 계약서 조회 실패 (Firebase): $e');
      return null;
    } catch (e) {
      debugPrint('❌ 계약서 조회 실패: $e');
      return null;
    }
  }

  /// 근무자 uid로 계약서 목록 조회 (페이지네이션 + 상태 필터)
  Future<({List<EmploymentContractModel> items, DocumentSnapshot? lastDoc, bool hasMore})>
      getByWorkerPaged(
    String workerId, {
    ContractStatus? statusFilter,
    DocumentSnapshot? startAfter,
    int pageSize = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('employment_contracts')
          .where('workerId', isEqualTo: workerId);
      if (statusFilter != null) {
        q = q.where('status', isEqualTo: statusFilter.value);
      }
      // pageSize+1로 쿼리해 hasMore 정확도 보장 — 마지막 페이지에서 빈 호출 없앰 (E-047)
      q = q.orderBy('createdAt', descending: true).limit(pageSize + 1);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return (
        items: docs.map(EmploymentContractModel.fromFirestore).toList(),
        lastDoc: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      return (items: <EmploymentContractModel>[], lastDoc: null, hasMore: false);
    }
  }

  /// 근무자 uid로 계약서 목록 조회 (하위 호환 - 내부 캐시용)
  ///
  /// 신규 사용 시 getByWorkerPaged() 를 사용할 것.
  Future<List<EmploymentContractModel>> getByWorker(String workerId) async {
    try {
      final snap = await _db
          .collection('employment_contracts')
          .where('workerId', isEqualTo: workerId)
          .orderBy('createdAt', descending: true)
          .limit(200) // 근무자당 계약서 상한 — 초과 시 getByWorkerPaged() 사용
          .get();
      return snap.docs.map(EmploymentContractModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      return [];
    }
  }

  /// 사업장 계약서 목록 조회 (페이지네이션 + 상태 필터)
  Future<({List<EmploymentContractModel> items, DocumentSnapshot? lastDoc, bool hasMore})>
      getByBusinessPaged(
    String businessId, {
    ContractStatus? statusFilter,
    DocumentSnapshot? startAfter,
    int pageSize = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('employment_contracts')
          .where('businessId', isEqualTo: businessId);
      if (statusFilter != null) {
        q = q.where('status', isEqualTo: statusFilter.value);
      }
      // pageSize+1로 쿼리해 hasMore 정확도 보장 — 마지막 페이지에서 빈 호출 없앰 (E-047)
      q = q.orderBy('createdAt', descending: true).limit(pageSize + 1);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return (
        items: docs.map(EmploymentContractModel.fromFirestore).toList(),
        lastDoc: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 사업장 계약서 조회 실패: $e');
      return (items: <EmploymentContractModel>[], lastDoc: null, hasMore: false);
    }
  }

  /// 사업장 계약서 목록 조회 (하위 호환)
  ///
  /// 호출자 없음. 신규 사용 시 getByBusinessPaged() 사용할 것.
  Future<List<EmploymentContractModel>> getByBusiness(
      String businessId) async {
    try {
      final snap = await _db
          .collection('employment_contracts')
          .where('businessId', isEqualTo: businessId)
          .orderBy('createdAt', descending: true)
          .limit(200) // 대량 읽기 방지 상한
          .get();
      return snap.docs.map(EmploymentContractModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 사업장 계약서 조회 실패: $e');
      return [];
    }
  }

  /// 계약서 무효화 (관리자 전용)
  ///
  /// [V-001] 실행 순서: 계약서 voided 먼저 → 알림 발송 → application 취소
  /// 이전 순서(앱 취소 → 계약서 voided)는 계약서 update 실패 시 앱은 CANCELED인데
  /// 계약서는 pendingWorker로 남는 Scenario A(상태 불일치)가 있었음.
  /// 순서 역전으로 Scenario A를 원천 차단: 계약서 voided update 실패 시 아무것도 변경되지 않아
  /// 관리자가 재시도 가능. 앱 취소 실패 시에는 계약서가 이미 voided이므로 근무자가 서명 불가.
  Future<void> voidContract(String contractId) async {
    final contractDoc = await _db.collection('employment_contracts').doc(contractId).get();
    if (!contractDoc.exists) return;

    final contract = EmploymentContractModel.fromFirestore(contractDoc);

    // 이미 voided 상태면 조기 반환 — 재호출 시 이미 취소된 지원서를 재취소 시도해
    // failedIds가 발생하고 오해의 소지 있는 에러 토스트가 뜨는 버그 방지 (BUG-E-01)
    if (contract.status == ContractStatus.voided) return;

    // 1단계: 계약서 voided 먼저 업데이트 (실패 시 아무것도 변경 안 됨 → 깨끗한 재시도 가능)
    await _db.collection('employment_contracts').doc(contractId).update({
      'status': ContractStatus.voided.value,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // 2단계: 근무자에게 무효화 알림 즉시 발송 (계약서 voided 직후 — 앱 취소 전)
    // [H-34] 앱 취소 실패와 무관하게 근무자가 즉시 인지하도록 순서 보장
    try {
      await _firestoreService.createNotification(
        NotificationModel.createContractVoided(
          userId: contract.workerId,
          businessName: contract.snapshot.businessName,
          businessId: contract.businessId,
          contractId: contractId,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [H-34] 계약서 무효화 알림 발송 실패 (비치명적): $e');
    }

    // 3단계: 연결된 application 취소 처리
    // [B-003] false 반환도 실패로 간주 — cancelConfirmedApplication은 내부 오류를
    // exception 대신 false로 반환하므로 반환값을 명시적으로 체크해야 함
    // [W-2] canceledBy: 'system' — voidContract는 시스템/관리자 취소이므로 ADMIN_CANCELED로 기록
    // null 전달 시 USER_CANCELED로 기록되어 감사 로그에서 혼동 발생
    final firestoreService = FirestoreService();
    final List<String> failedIds = [];
    for (final appId in contract.applicationIds) {
      try {
        final ok = await firestoreService.cancelConfirmedApplication(
          appId,
          canceledBy: 'system',
          cancelReason: '계약서가 무효화되었습니다',
        );
        if (!ok) {
          debugPrint('⚠️ voidContract: application 취소 실패 ($appId): false 반환');
          failedIds.add(appId);
        }
      } catch (e) {
        debugPrint('⚠️ voidContract: application 취소 실패 ($appId): $e');
        failedIds.add(appId);
      }
    }

    // 4단계: 실패한 appId 기록 — 관리자 화면 경고 배너로 노출, 재처리 버튼 제공
    if (failedIds.isNotEmpty) {
      try {
        await _db.collection('employment_contracts').doc(contractId).update({
          'voidFailedAppIds': failedIds,
        });
      } catch (e) {
        debugPrint('⚠️ voidFailedAppIds 기록 실패: $e');
      }
      throw Exception(
        '계약서가 무효화되었으나 ${failedIds.length}개 지원서 취소에 실패했습니다.\n'
        '계약서 카드에서 재처리하거나 직접 확인해주세요.');
    }
  }

  /// voidFailedAppIds에 기록된 application들을 재시도로 취소 처리.
  /// 성공한 항목은 voidFailedAppIds에서 제거하고, 전부 성공 시 필드를 삭제.
  Future<void> retryVoidFailedApps(EmploymentContractModel contract) async {
    if (contract.voidFailedAppIds.isEmpty) return;

    final firestoreService = FirestoreService();
    final List<String> stillFailedIds = [];

    for (final appId in contract.voidFailedAppIds) {
      try {
        final ok = await firestoreService.cancelConfirmedApplication(
          appId,
          canceledBy: 'system', // [W-2] 재처리도 시스템 취소 — ADMIN_CANCELED 기록 유지
          cancelReason: '계약서가 무효화되었습니다',
        );
        if (!ok) {
          debugPrint('⚠️ retryVoidFailedApps: application 취소 실패 ($appId): false 반환');
          stillFailedIds.add(appId);
        }
      } catch (e) {
        debugPrint('⚠️ retryVoidFailedApps: application 취소 실패 ($appId): $e');
        stillFailedIds.add(appId);
      }
    }

    // 성공한 항목 반영: 전부 성공 시 voidFailedAppIds 필드 삭제, 일부 실패 시 갱신
    await _db.collection('employment_contracts').doc(contract.id).update({
      'voidFailedAppIds': stillFailedIds.isEmpty
          ? FieldValue.delete()
          : stillFailedIds,
    });

    if (stillFailedIds.isNotEmpty) {
      throw Exception('${stillFailedIds.length}개 지원서 재처리 실패. 잠시 후 다시 시도해주세요.');
    }
  }

  // ── 내부: 번들 탐색 ──────────────────────────────────────────

  /// 단기 번들 계약서 탐색 (toId + workDetailId + workerId 조합으로 기존 번들 찾기)
  ///
  /// [businessId] 보안 규칙상 필수 — `isAdminOf(businessId)` 검증을 위해 반드시 전달.
  /// businessId 없이 호출하면 Firestore 권한 오류 발생 (크로스-사업장 방지 규칙).
  Future<EmploymentContractModel?> _findBundle({
    required String toId,
    required String workDetailId,
    required String workerId,
    required String businessId,
  }) async {
    try {
      final snap = await _db
          .collection('employment_contracts')
          .where('businessId', isEqualTo: businessId)
          .where('toId', isEqualTo: toId)
          .where('workDetailId', isEqualTo: workDetailId)
          .where('workerId', isEqualTo: workerId)
          .where('isLongTerm', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return EmploymentContractModel.fromFirestore(snap.docs.first);
    } catch (e) {
      debugPrint('❌ 번들 계약서 조회 실패: $e');
      return null;
    }
  }

  // ── 내부: 슬롯 추가 ──────────────────────────────────────────

  Future<EmploymentContractModel> _addSlot(
    EmploymentContractModel contract,
    ApplicationModel application,
    WorkDetailData workDetail,
  ) async {
    final newSlot = ContractSlot(
      applicationId: application.id,
      workDate: _fmtDate(application.workDate),
      startTime: workDetail.startTime,
      endTime: workDetail.endTime,
      wage: workDetail.wage,
      wageType: workDetail.wageType,
    );

    final now = DateTime.now();
    final contractRef = _db.collection('employment_contracts').doc(contract.id);

    // 트랜잭션으로 동시 확정 시 슬롯 유실 방지 (last-write-wins 방지)
    final updatedContract = await _db.runTransaction((tx) async {
      final snap = await tx.get(contractRef);
      if (!snap.exists) throw Exception('계약서를 찾을 수 없습니다: ${contract.id}');
      final current = EmploymentContractModel.fromFirestore(snap);

      // 멱등성 보호 — 동일 applicationId가 이미 등록된 경우 슬롯 중복 추가 방지
      // (이중 확정 또는 동시 호출 시 발생 가능)
      if (current.applicationIds.contains(application.id)) {
        return current;
      }

      final updatedSlots = [...current.slots, newSlot];
      final updatedIds = [...current.applicationIds, application.id];
      tx.update(contractRef, {
        'slots': updatedSlots.map((s) => s.toMap()).toList(),
        'applicationIds': updatedIds,
        'updatedAt': Timestamp.fromDate(now),
      });
      return current.copyWith(
        slots: updatedSlots,
        applicationIds: updatedIds,
        updatedAt: now,
      );
    });

    return updatedContract;
  }

  // ── 내부: 신규 생성 ──────────────────────────────────────────

  Future<EmploymentContractModel> _createNew({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    required String toId,
    required String workDetailId,
    List<ContractArticle> articles = const [],
    String? templateId,
  }) async {
    // ownerName이 없으면 ownerId로 users 컬렉션에서 조회
    BusinessModel effectiveBusiness = business;
    if (business.ownerName == null || business.ownerName!.trim().isEmpty) {
      try {
        final ownerDoc = await _db.collection('users').doc(business.ownerId).get();
        final data = ownerDoc.data();
        // 사업자등록증 대표자명(ceoName) 우선, 없으면 계정 이름
        final ceoName = data?['ceoName'] as String?;
        final accountName = data?['name'] as String?;
        final name = (ceoName?.trim().isNotEmpty == true) ? ceoName : accountName;
        if (name != null && name.trim().isNotEmpty) {
          effectiveBusiness = business.copyWith(ownerName: name);
        }
      } catch (e) {
        debugPrint('대표자 이름 조회 실패: $e');
      }
    }

    bool isLong = application.isLongTermApplication;
    // 기존 데이터(type 필드 미기록)를 위해 TO 타입으로 fallback
    if (!isLong && toId.isNotEmpty) {
      try {
        final toDoc = await _db.collection('tos').doc(toId).get();
        if (toDoc.exists && toDoc.data()?['type'] == TOType.contract) {
          isLong = true;
        }
      } catch (e) {
        debugPrint('TO 타입 조회 실패 (fallback): $e');
      }
    }
    final snapshot = _buildSnapshot(
      application: application,
      business: effectiveBusiness,
      worker: worker,
      workDetail: workDetail,
      isLongTermOverride: isLong,
    );

    // 단기: 첫 슬롯 생성
    final slots = isLong
        ? <ContractSlot>[]
        : [
            ContractSlot(
              applicationId: application.id,
              workDate: _fmtDate(application.workDate),
              startTime: workDetail.startTime,
              endTime: workDetail.endTime,
              wage: workDetail.wage,
              wageType: workDetail.wageType,
            ),
          ];

    final ref = _db.collection('employment_contracts').doc();
    final contract = EmploymentContractModel(
      id: ref.id,
      applicationId: application.id,
      businessId: business.id,
      workerId: worker.uid,
      isLongTerm: isLong,
      toId: toId,
      workDetailId: workDetailId,
      slots: slots,
      applicationIds: [application.id],
      status: ContractStatus.pendingEmployer,
      snapshot: snapshot,
      articles: articles,
      templateId: templateId,
      createdAt: DateTime.now(),
      isNewUnsaved: true,  // 서명 완료 시 최초 저장
    );

    // Firestore에 저장하지 않음 — 사업주 서명 시 최초 저장
    return contract;
  }

  // ── 스냅샷 생성 ──────────────────────────────────────────────

  ContractSnapshot _buildSnapshot({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    bool? isLongTermOverride,
  }) {
    final isLong = isLongTermOverride ?? application.isLongTermApplication;
    return ContractSnapshot(
      businessName: business.name,
      businessNumber: business.formattedBusinessNumber,
      businessAddress: [business.address, business.detailAddress]
          .whereType<String>()
          .join(' '),
      businessPhone: business.phone,
      ownerName: business.ownerName ?? '',
      workerName: worker.name,
      workerBirthDate:
          worker.birthDate != null ? _fmtDate(worker.birthDate) : null,
      workerPhone: worker.phone,
      workerAddress: [worker.address, worker.detailAddress]
              .whereType<String>()
              .join(' ')
              .trim()
              .isEmpty
          ? null
          : [worker.address, worker.detailAddress]
              .whereType<String>()
              .join(' ')
              .trim(),
      workType: workDetail.workType,
      workPlace: business.address,
      isLongTerm: isLong,
      // 희망 시작일 우선, 없으면 workDate(TO 시작일 or 지원일) 사용
      contractStart: isLong
          ? _fmtDate(application.desiredStartDate ?? application.workDate)
          : null,
      contractEnd: isLong ? _fmtDate(application.workEndDate) : null,
      workDays: application.workDays,
      startTime: workDetail.startTime,
      endTime: workDetail.endTime,
      breakMinutes: workDetail.breakMinutes,
      wage: workDetail.wage,
      wageType: workDetail.wageType,
      wagePaymentDay: business.wagePaymentDay,
      baseHourlyWage: workDetail.baseHourlyWage,
      payScheduleType: workDetail.payScheduleType,
      payScheduleDay: workDetail.payScheduleDay,
      payScheduleTime: workDetail.payScheduleTime,
      taxDeductionType: workDetail.taxDeductionType,
    );
  }

  // ── Storage 업로드 ────────────────────────────────────────────

  Future<String> _uploadSignature({
    required String contractId,
    required String role,
    required Uint8List bytes,
  }) async {
    try {
      final ref = _storage
          .ref()
          .child('contracts/$contractId/signature_$role.png');
      final task =
          await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      return await task.ref.getDownloadURL();
    } catch (e) {
      debugPrint('❌ 서명 이미지 업로드 실패: $e');
      throw Exception('서명 저장에 실패했습니다. 네트워크 연결을 확인해주세요.');
    }
  }

  Future<String> _uploadPdf({
    required String contractId,
    required Uint8List bytes,
  }) async {
    try {
      final ref =
          _storage.ref().child('contracts/$contractId/contract.pdf');
      final task = await ref.putData(
          bytes, SettableMetadata(contentType: 'application/pdf'));
      return await task.ref.getDownloadURL();
    } catch (e) {
      debugPrint('❌ 계약서 PDF 업로드 실패: $e');
      throw Exception('계약서 저장에 실패했습니다. 네트워크 연결을 확인해주세요.');
    }
  }

  // ── PDF 로컬 저장 (공유용) ────────────────────────────────────

  // 반환된 File은 호출자가 사용 후 delete() 책임
  Future<File> savePdfLocally({
    required String contractId,
    required Uint8List bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/contract_$contractId.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  String _fmtDate(DateTime? d) =>
      d == null ? '' : FormatHelper.formatDateISO(d);
}
