const admin = require('../functions/node_modules/firebase-admin');
const path = require('path');

const serviceAccount = require(path.join(__dirname, 'alfit-89567-firebase-adminsdk-fbsvc-d22e7faef3.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'alfit-89567',
});

const db = admin.firestore();

async function createSuperAdminFirestoreDoc() {
  // Authentication에서 이미 생성된 UID
  const uid = 'SjBcMmpV6pPbehJqHfQVjs13Dpm2';
  const username = 'super_admin';
  const email = `${username}@ALfit-system.com`;
  const now = new Date();

  try {
    await db.collection('users').doc(uid).set({
      uid,
      username,
      name: '슈퍼관리자',
      email,
      phone: null,
      role: 'SUPER_ADMIN',
      accountStatus: 'active',
      isBlacklisted: false,
      isPassVerified: true,
      trustScore: 100,
      badges: [],
      noShowCount: 0,
      lateCount: 0,
      totalWorkDays: 0,
      averageRating: 0.0,
      businessId: null,
      createdAt: admin.firestore.Timestamp.fromDate(now),
      lastLoginAt: admin.firestore.Timestamp.fromDate(now),
      gender: null,
      birthDate: null,
      residentNumber: null,
      ci: null,
      address: null,
      detailAddress: null,
    });
    console.log('✅ Firestore 문서 생성 완료');
    console.log(`UID: ${uid}`);
    console.log(`아이디: ${username}`);
    console.log(`이메일: ${email}`);
    console.log(`비밀번호: super_admin123!@#`);
  } catch (e) {
    console.error('❌ 오류:', e.message);
  }

  process.exit(0);
}

createSuperAdminFirestoreDoc();
