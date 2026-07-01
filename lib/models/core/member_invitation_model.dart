import 'package:cloud_firestore/cloud_firestore.dart';
import 'business_member_model.dart';

enum InvitationStatus { pending, accepted, rejected, cancelled }

/// member_invitations/{invitationId}
class MemberInvitationModel {
  final String id;
  final String businessId;
  final String businessName;
  final String targetUid;
  final String targetName;
  final String? targetPhone;
  final String invitedBy;
  final String invitedByName;
  final MemberPermissions permissions;
  final InvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const MemberInvitationModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.targetUid,
    required this.targetName,
    this.targetPhone,
    required this.invitedBy,
    required this.invitedByName,
    required this.permissions,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  static MemberInvitationModel? tryFromFirestore(DocumentSnapshot doc) {
    try { return MemberInvitationModel.fromFirestore(doc); } catch (_) { return null; }
  }

  factory MemberInvitationModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) throw ArgumentError('Document ${doc.id} has no data');
    final d = raw as Map<String, dynamic>;
    final createdAtTs = d['createdAt'] as Timestamp?;
    if (createdAtTs == null) throw ArgumentError('Document ${doc.id} missing required field: createdAt');
    return MemberInvitationModel(
      id: doc.id,
      businessId: d['businessId'] ?? '',
      businessName: d['businessName'] ?? '',
      targetUid: d['targetUid'] ?? '',
      targetName: d['targetName'] ?? '',
      targetPhone: d['targetPhone'],
      invitedBy: d['invitedBy'] ?? '',
      invitedByName: d['invitedByName'] ?? '',
      permissions: MemberPermissions.fromMap(
          (d['permissions'] as Map<String, dynamic>?) ?? {}),
      status: _statusFromString(d['status'] ?? 'pending'),
      createdAt: createdAtTs.toDate().toLocal(),
      respondedAt: (d['respondedAt'] as Timestamp?)?.toDate().toLocal(),
    );
  }

  Map<String, dynamic> toMap() => {
        'businessId': businessId,
        'businessName': businessName,
        'targetUid': targetUid,
        'targetName': targetName,
        'targetPhone': targetPhone,
        'invitedBy': invitedBy,
        'invitedByName': invitedByName,
        'permissions': permissions.toMap(),
        'status': _statusToString(status),
        'createdAt': Timestamp.fromDate(createdAt),
        'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      };

  bool get isPending => status == InvitationStatus.pending;

  static InvitationStatus _statusFromString(String s) {
    switch (s) {
      case 'accepted':
        return InvitationStatus.accepted;
      case 'rejected':
        return InvitationStatus.rejected;
      case 'cancelled':
        return InvitationStatus.cancelled;
      default:
        return InvitationStatus.pending;
    }
  }

  static String _statusToString(InvitationStatus s) {
    switch (s) {
      case InvitationStatus.accepted:
        return 'accepted';
      case InvitationStatus.rejected:
        return 'rejected';
      case InvitationStatus.cancelled:
        return 'cancelled';
      case InvitationStatus.pending:
        return 'pending';
    }
  }
}
