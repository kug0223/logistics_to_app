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
      );
      if (existing != null && existing.status != ContractStatus.voided) {
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

    // Firestore 저장 — 동시 서명 방지를 위해 트랜잭션으로 현재 상태 검증
    try {
      final ref = _db.collection('employment_contracts').doc(contract.id);
      if (contract.isNewUnsaved) {
        final data = updated.toMap();
        data['createdAt'] = FieldValue.serverTimestamp();
        await ref.set(data);
      } else {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (snap.exists) {
            final currentStatus = snap.data()?['status'] as String?;
            if (currentStatus == ContractStatus.completed.value) {
              throw Exception('이미 완료된 계약서입니다');
            }
            if (snap.data()?['employerSignatureUrl'] != null) {
              throw Exception('이미 사업주 서명이 완료된 계약서입니다');
            }
          }
          // SHA-256 해시로 서명 무결성 기록
          final employerHash = sha256.convert(signatureBytes).toString();
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
      } catch (_) {}
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
      } catch (_) {}
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

    // Firestore 배치 커밋 — 실패 시 서명+PDF 롤백
    try {
      final nowTs = Timestamp.fromDate(workerNow);
      // 동시 서명 방지 + application 상태 원자적 업데이트
      final contractRef = _db.collection('employment_contracts').doc(contract.id);
      final workerHash = sha256.convert(signatureBytes).toString();
      await _db.runTransaction((tx) async {
        final snap = await tx.get(contractRef);
        if (snap.exists) {
          final currentStatus = snap.data()?['status'] as String?;
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
        for (final appId in contract.applicationIds) {
          tx.update(_db.collection('applications').doc(appId), {
            'status': 'CONFIRMED',
            'statusHistory': FieldValue.arrayUnion([{
              'status': 'CONFIRMED',
              'at': nowTs,
              'by': 'SYSTEM',
              'action': 'CONTRACT_SIGNED',
            }]),
          });
        }
      });
    } catch (e) {
      // Firestore 실패 → 서명 이미지 + PDF 삭제 (고아 파일 방지)
      for (final path in [
        'contracts/${contract.id}/signature_worker.png',
        'contracts/${contract.id}/contract.pdf',
      ]) {
        try { await _storage.ref().child(path).delete(); } catch (_) {}
      }
      rethrow;
    }

    // 근무자에게 계약 완료 알림
    try {
      await _firestoreService.createNotification(
        NotificationModel.createApplicationConfirmed(
          userId: contract.workerId,
          businessName: contract.snapshot.businessName,
          businessId: contract.businessId,
          workType: contract.snapshot.workType,
          workDate: contract.snapshot.contractStart != null
              ? DateTime.parse(contract.snapshot.contractStart!)
              : DateTime.now(),
          applicationId: contract.applicationId,
        ),
      );
    } catch (e) {
      debugPrint('계약 완료 알림 발송 실패: $e');
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
  Future<void> updateArticles({
    required String contractId,
    required List<ContractArticle> articles,
    String? templateId,
  }) async {
    await _db.collection('employment_contracts').doc(contractId).update({
      'articles': articles.map((a) => a.toMap()).toList(),
      if (templateId != null) 'templateId': templateId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── 조회 ─────────────────────────────────────────────────────

  /// applicationId로 계약서 조회 (하위 호환 + 슬롯 포함 검색)
  Future<EmploymentContractModel?> getByApplication(
      String applicationId) async {
    try {
      // 1) 기본 applicationId 매칭
      final snap = await _db
          .collection('employment_contracts')
          .where('applicationId', isEqualTo: applicationId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return EmploymentContractModel.fromFirestore(snap.docs.first);
      }
      // 2) applicationIds 배열에 포함된 경우 (단기 번들 슬롯)
      final slotSnap = await _db
          .collection('employment_contracts')
          .where('applicationIds', arrayContains: applicationId)
          .limit(1)
          .get();
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
      q = q.orderBy('createdAt', descending: true).limit(pageSize);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      return (
        items: snap.docs.map(EmploymentContractModel.fromFirestore).toList(),
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
        hasMore: snap.docs.length == pageSize,
      );
    } catch (e) {
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      return (items: <EmploymentContractModel>[], lastDoc: null, hasMore: false);
    }
  }

  /// 근무자 uid로 계약서 목록 조회 (하위 호환 - 내부 캐시용)
  Future<List<EmploymentContractModel>> getByWorker(String workerId) async {
    try {
      final snap = await _db
          .collection('employment_contracts')
          .where('workerId', isEqualTo: workerId)
          .orderBy('createdAt', descending: true)
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
      q = q.orderBy('createdAt', descending: true).limit(pageSize);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      return (
        items: snap.docs.map(EmploymentContractModel.fromFirestore).toList(),
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
        hasMore: snap.docs.length == pageSize,
      );
    } catch (e) {
      debugPrint('❌ 사업장 계약서 조회 실패: $e');
      return (items: <EmploymentContractModel>[], lastDoc: null, hasMore: false);
    }
  }

  /// 사업장 계약서 목록 조회 (하위 호환)
  Future<List<EmploymentContractModel>> getByBusiness(
      String businessId) async {
    try {
      final snap = await _db
          .collection('employment_contracts')
          .where('businessId', isEqualTo: businessId)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs.map(EmploymentContractModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 사업장 계약서 조회 실패: $e');
      return [];
    }
  }

  /// 계약서 무효화 (관리자 전용)
  ///
  /// 계약서 status를 voided로 변경하고,
  /// 연결된 모든 application을 CANCELED 상태로 전환한다.
  Future<void> voidContract(String contractId) async {
    final contractDoc = await _db.collection('employment_contracts').doc(contractId).get();
    if (!contractDoc.exists) return;

    final contract = EmploymentContractModel.fromFirestore(contractDoc);

    // 연결된 application들 취소 처리 (확정 상태인 것만)
    // 하나라도 실패하면 계약서 상태 변경을 중단해 부분 무효화 방지
    final firestoreService = FirestoreService();
    final List<String> failedIds = [];
    for (final appId in contract.applicationIds) {
      try {
        await firestoreService.cancelConfirmedApplication(
          appId,
          canceledBy: null,
          cancelReason: '계약서가 무효화되었습니다',
        );
      } catch (e) {
        debugPrint('⚠️ voidContract: application 취소 실패 ($appId): $e');
        failedIds.add(appId);
      }
    }
    if (failedIds.isNotEmpty) {
      throw Exception('${failedIds.length}개 지원서 취소 실패로 계약서 무효화가 중단되었습니다');
    }

    await _db.collection('employment_contracts').doc(contractId).update({
      'status': ContractStatus.voided.value,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── 내부: 번들 탐색 ──────────────────────────────────────────

  Future<EmploymentContractModel?> _findBundle({
    required String toId,
    required String workDetailId,
    required String workerId,
  }) async {
    try {
      final snap = await _db
          .collection('employment_contracts')
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
