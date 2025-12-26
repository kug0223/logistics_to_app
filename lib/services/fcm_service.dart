import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/common/notification_screen.dart';

/// FCM 푸시 알림 서비스
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _currentUserId;
  bool _isInitialized = false;
  
  /// 전역 Navigator Key (main.dart에서 설정)
  GlobalKey<NavigatorState>? _navigatorKey;
  
  /// Navigator Key 설정
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// FCM 초기화 (로그인 후 호출)
  Future<void> initialize(String userId) async {
    if (_isInitialized && _currentUserId == userId) {
      print('ℹ️ FCM 이미 초기화됨: $userId');
      return;
    }

    _currentUserId = userId;

    // 1. 알림 권한 요청
    await _requestPermission();

    // 2. 로컬 알림 초기화 (포그라운드용)
    await _initializeLocalNotifications();

    // 3. FCM 토큰 저장
    await _saveToken();

    // 4. 토큰 갱신 리스너
    _messaging.onTokenRefresh.listen((newToken) {
      _updateToken(newToken);
    });

    // 5. 포그라운드 메시지 리스너
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. 백그라운드 메시지 클릭 리스너
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    _isInitialized = true;
    print('✅ FCM 초기화 완료: $userId');
  }

  /// 알림 권한 요청
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    print('📱 알림 권한 상태: ${settings.authorizationStatus}');
  }

  /// 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android 알림 채널 생성
    const androidChannel = AndroidNotificationChannel(
      'alfit_notifications',
      'ALfit 알림',
      description: 'ALfit 앱 알림',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation
            <AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// FCM 토큰 저장
  Future<void> _saveToken() async {
    if (_currentUserId == null) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await _updateToken(token);
    }
  }

  /// FCM 토큰 업데이트
  Future<void> _updateToken(String token) async {
    if (_currentUserId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ FCM 토큰 저장 완료');
    } catch (e) {
      print('❌ FCM 토큰 저장 실패: $e');
    }
  }

  /// 포그라운드 메시지 처리
  void _handleForegroundMessage(RemoteMessage message) {
    print('📩 포그라운드 메시지 수신: ${message.notification?.title}');

    final notification = message.notification;
    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: message.data.toString(),
      );
    }
  }

  /// 로컬 알림 표시
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'alfit_notifications',
      'ALfit 알림',
      channelDescription: 'ALfit 앱 알림',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 알림 탭 처리
  void _onNotificationTap(NotificationResponse response) {
    print('🔔 알림 탭: ${response.payload}');
    _navigateToNotificationScreen();
  }

  /// 백그라운드 메시지 클릭 처리
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('📩 백그라운드 메시지 클릭: ${message.data}');
    _navigateToNotificationScreen();
  }
  
  /// 알림 화면으로 이동
  void _navigateToNotificationScreen() {
    if (_navigatorKey?.currentState == null) {
      print('⚠️ Navigator가 아직 준비되지 않음');
      return;
    }
    
    _navigatorKey!.currentState!.push(
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
  }

  /// 로그아웃 시 토큰 삭제
  Future<void> clearToken() async {
    if (_currentUserId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .update({
        'fcmToken': FieldValue.delete(),
      });
      print('✅ FCM 토큰 삭제 완료');
    } catch (e) {
      print('❌ FCM 토큰 삭제 실패: $e');
    }

    _currentUserId = null;
    _isInitialized = false;
  }
}