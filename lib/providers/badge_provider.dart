import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/settings/trust_settings_model.dart';

/// Firestore `badges` 컬렉션을 스트리밍하는 Provider.
/// 로그인 상태에서만 스트림을 유지하고, 로그아웃 시 defaultBadges()로 복귀.
/// 슈퍼관리자가 badge_settings_screen에서 수정하면 실시간 반영됨.
class BadgeProvider extends ChangeNotifier {
  List<BadgeModel> _badges = BadgeModel.defaultBadges();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _badgesSub;
  StreamSubscription<User?>? _authSub;
  bool _isLoggedIn = false;

  BadgeProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _isLoggedIn = true;
        _startStream();
      } else {
        _isLoggedIn = false;
        _stopStream();
        _badges = BadgeModel.defaultBadges();
        notifyListeners();
      }
    });
  }

  List<BadgeModel> get badges => _badges;

  void _startStream() {
    _badgesSub?.cancel();
    _badgesSub = FirebaseFirestore.instance
        .collection('badges')
        .orderBy('order')
        .snapshots()
        .listen(
      (snap) {
        if (snap.docs.isEmpty) {
          _badges = BadgeModel.defaultBadges();
        } else {
          final parsed = snap.docs
              .map((d) {
                try {
                  return BadgeModel.fromMap(d.data(), d.id);
                } catch (e) {
                  debugPrint('[BadgeProvider] 배지 파싱 실패 (${d.id}): $e');
                  return null;
                }
              })
              .whereType<BadgeModel>()
              .toList();
          _badges = parsed.isEmpty ? BadgeModel.defaultBadges() : parsed;
        }
        notifyListeners();
      },
      onError: (e) {
        // 로그인 직후 권한 준비 전 PERMISSION_DENIED 등 — defaultBadges()로 폴백
        // 스트림은 에러 후 종료되므로 5초 뒤 재연결 시도
        debugPrint('[BadgeProvider] 스트림 에러 (defaultBadges 폴백, 5초 후 재연결): $e');
        _badges = BadgeModel.defaultBadges();
        _badgesSub = null;
        notifyListeners();
        Future.delayed(const Duration(seconds: 5), _maybeReconnect);
      },
    );
  }

  void _maybeReconnect() {
    // 로그인 상태이고 스트림이 끊긴 경우에만 재연결
    if (_isLoggedIn && _badgesSub == null) _startStream();
  }

  void _stopStream() {
    _badgesSub?.cancel();
    _badgesSub = null;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _badgesSub?.cancel();
    super.dispose();
  }
}
