/**
 * DEV 전용 지원자 테스트 계정 시드 — test1 ~ test6
 *
 *   목적: 회원가입 자체가 아니라, **지원 prerequisite 를 통과한 상태**의
 *   지원자를 빠르게 준비한다. 이후 공고 지원 → 확정 → 계약 → 출퇴근 →
 *   급여 흐름을 반복하기 위한 fixture 다.
 *
 *   ⚠ DEV(alfit-89567) 전용. PROD 에서 실행하지 않는다.
 *   ⚠ 재실행 가능(idempotent): 있으면 canonical 상태와 비교해 **부족한 것만** 보정한다.
 *
 * ── 이 스크립트가 따르는 canonical 구조 (모두 READ 로 확인) ──────────
 *
 *   Auth        `{username}@ALfit-system.com` + password
 *               (auth_service.dart signUp 의 systemEmail 규칙)
 *   프로필       `users/{uid}` — UserModel.toMap() 구조 그대로
 *   role        'USER' (관리자/SubAdmin 권한 부여 없음)
 *   지원 게이트  apply_prerequisites_screen.dart `meetsApplyPrerequisites` +
 *               CF callableApplyToTO 의 서버 게이트. 둘이 같은 것을 묻는다:
 *                 · accountStatus == 'active'
 *                 · !isBlacklisted && !isRestricted
 *                 · 내국인이면 passVerifiedAt 존재
 *                 · hasIdDocument (idCardImagePath | idCardImageUrl)
 *                 · 단기(슬롯) 공고면 isIdVerified == true
 *                 · hasBankAccount (bankName && accountNumber && accountHolder)
 *                 · hasBankbookDocument (bankbookImagePath | bankbookImageUrl)
 *                 · 세무 축: app_settings/tax_identity_collection.enabled 가
 *                   true 일 때만 막는다 — **현재 DEV 는 false** 이므로
 *                   taxIdentities 문서를 만들지 않는다(없는 상태를 지어내지 않는다).
 *   계좌 암호화  users.accountNumber 는 `EncryptionHelper.encrypt` 형식:
 *               base64(random IV 16B) + ":" + base64(AES-256-CBC ciphertext)
 *               키는 config/dev/dart_defines.json 의 ENCRYPT_KEY (앱 빌드와 동일)
 *   예금주       auth_service signUp 이 `accountHolder: name` 으로 넣는다
 *   Storage     `users/{uid}/idCard_{ms}.jpg`, `users/{uid}/bankbook_{ms}.jpg`
 *               (document_management_screen.dart 의 업로드 경로)
 *
 * ── 하지 않는 것 ────────────────────────────────────────────────
 *   · production validation/보안 규칙 변경 0
 *   · `if (id.startsWith('test')) bypass` 류의 우회 0
 *   · 실제 주민번호·실제 계좌·PASS/은행 API 호출 0
 *   · 공고·지원·확정·계약·출퇴근·급여 생성 0
 *   · 다른 fixture 삭제 0
 *
 * 사용법:
 *   node scripts/seed_dev_applicants.js --check   (읽기만, 변경 없음)
 *   node scripts/seed_dev_applicants.js --apply   (생성/보정)
 */

'use strict';

const path = require('path');
const crypto = require('crypto');
const fs = require('fs');

const ROOT = path.resolve(__dirname, '..');
const admin = require(path.join(ROOT, 'functions/node_modules/firebase-admin'));

// ── 안전장치: DEV 프로젝트가 아니면 실행하지 않는다 ────────────────
const EXPECTED_PROJECT = 'alfit-89567';
const SA_PATH = path.join(
    ROOT, 'functions/alfit-89567-firebase-adminsdk-fbsvc-4174a2458f.json');
const serviceAccount = require(SA_PATH);
if (serviceAccount.project_id !== EXPECTED_PROJECT) {
  console.error('중단: DEV 프로젝트가 아니다 — ' + serviceAccount.project_id);
  process.exit(1);
}

const MODE = process.argv.includes('--apply') ? 'apply' : 'check';

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: serviceAccount.project_id + '.firebasestorage.app',
});
const db = admin.firestore();
const auth = admin.auth();
const bucket = admin.storage().bucket();

// ── 앱과 **같은** 암호화 (EncryptionHelper.encrypt) ────────────────
const defines = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'config/dev/dart_defines.json'), 'utf8'));
const ENCRYPT_KEY = Buffer.from(defines.ENCRYPT_KEY, 'base64');
if (ENCRYPT_KEY.length !== 32) {
  console.error('중단: ENCRYPT_KEY 가 32바이트가 아니다 — ' + ENCRYPT_KEY.length);
  process.exit(1);
}

/** 평문 → "base64(IV):base64(ciphertext)" (AES-256-CBC, PKCS7) */
function encryptField(plain) {
  if (plain === null || plain === undefined || plain === '') return null;
  const iv = crypto.randomBytes(16);
  const c = crypto.createCipheriv('aes-256-cbc', ENCRYPT_KEY, iv);
  const enc = Buffer.concat([c.update(String(plain), 'utf8'), c.final()]);
  return iv.toString('base64') + ':' + enc.toString('base64');
}

/** 앱의 decrypt 와 같은 방식으로 되읽어 자체 검증한다. */
function decryptField(stored) {
  if (!stored || typeof stored !== 'string' || !stored.includes(':')) return null;
  const i = stored.indexOf(':');
  const iv = Buffer.from(stored.slice(0, i), 'base64');
  const d = crypto.createDecipheriv('aes-256-cbc', ENCRYPT_KEY, iv);
  return Buffer.concat([d.update(Buffer.from(stored.slice(i + 1), 'base64')),
    d.final()]).toString('utf8');
}

// ── fixture 정의 ──────────────────────────────────────────────────
//   계좌번호는 DEV synthetic. 주민번호는 **저장하지 않는다**
//   (현재 세무 수집이 꺼져 있어 지원 게이트가 묻지 않는다 — 아래 검증에서 재확인).
// [R7-SECURITY-P0] 비밀번호는 **환경변수에서만** 온다.
//
//   공개 저장소다. 평문 기본값을 두면 그 값이 그대로 공개되고, 그 비밀번호로
//   만들어진 계정이 DEV 에 남는다. 빈 문자열 폴백도 안전하지 않다 — Firebase 가
//   거절하는 자리까지 가서야 실패하므로, 무엇이 빠졌는지 그때 알게 된다.
//   여기서 멈추고 무엇을 넣어야 하는지 말한다. 계정은 하나도 만들지 않는다.
const PASSWORD = process.env.SEED_PASSWORD || '';
if (PASSWORD.length < 8) {
  console.error(
    'SEED_PASSWORD 가 필요하다 (8자 이상). 저장소에 비밀번호를 적지 않는다.\n' +
    '  PowerShell:  $env:SEED_PASSWORD="..." ; node scripts/seed_dev_applicants.js\n' +
    '  bash      :  SEED_PASSWORD="..." node scripts/seed_dev_applicants.js');
  process.exit(1);
}
const ACCOUNTS = [
  {loginId: 'test1', name: '테스트하나', account: '000000000001'},
  {loginId: 'test2', name: '테스트둘', account: '000000000002'},
  {loginId: 'test3', name: '테스트셋', account: '000000000003'},
  {loginId: 'test4', name: '테스트넷', account: '000000000004'},
  {loginId: 'test5', name: '테스트다섯', account: '000000000005'},
  {loginId: 'test6', name: '테스트여섯', account: '000000000006'},
];
const BANK_NAME = '국민은행';
const HOME_REGION = {province: '서울특별시', city: '강남구', district: '역삼동'};

const mask = (s) => !s ? '-' : '*'.repeat(Math.max(0, s.length - 4)) + s.slice(-4);

// ── DEV placeholder 문서 이미지 (개인정보 0) ───────────────────────
//   1x1 회색 JPEG. 실명 신분증·실제 통장 사진을 쓰지 않는다.
const PLACEHOLDER_JPEG = Buffer.from(
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof' +
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB' +
    'AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==',
    'base64');

async function ensureStorageObject(uid, kind) {
  const prefix = 'users/' + uid + '/' + kind + '_';
  const [existing] = await bucket.getFiles({prefix});
  if (existing.length > 0) return {path: existing[0].name, created: false};
  if (MODE !== 'apply') return {path: null, created: false};
  const p = prefix + Date.now() + '.jpg';
  await bucket.file(p).save(PLACEHOLDER_JPEG, {
    contentType: 'image/jpeg',
    metadata: {metadata: {devFixture: 'true', seededBy: 'seed_dev_applicants'}},
  });
  return {path: p, created: true};
}

// ── users 문서 — UserModel.toMap() 구조를 그대로 만든다 ─────────────
function buildUserDoc(a, uid, idPath, bankbookPath, now) {
  return {
    username: a.loginId,
    name: a.name,
    email: a.loginId + '@ALfit-system.com',
    phone: null,
    role: 'USER',
    businessId: null,
    managedBusinessIds: [],
    createdAt: now,
    lastLoginAt: now,
    authPhone: null,
    phoneVerificationLevel: null,
    contactPhone: null,
    gender: null,
    birthDate: null,
    // 주민번호는 저장하지 않는다 — 세무 수집 OFF 라 게이트가 묻지 않는다.
    residentNumber: null,
    address: null,
    detailAddress: null,
    ci: null,
    // 내국인 지원 게이트가 요구하는 값. PASS 를 호출하지 않고,
    // 이 계정이 DEV fixture 임은 별도 플래그로 남긴다.
    passVerifiedAt: now,
    foreignIdNumber: null,
    accountStatus: 'active',
    rejectionReason: null,
    legalName: null,
    koreanName: null,
    visaType: null,
    stayExpiryDate: null,
    idCardImageUrl: null,
    idCardImagePath: idPath,
    idCardVerifiedAt: now,
    isIdVerified: true,
    bankName: BANK_NAME,
    accountNumber: encryptField(a.account),
    accountHolder: a.name,
    bankbookImageUrl: null,
    bankbookImagePath: bankbookPath,
    bankbookVerifiedAt: null,
    bankVerificationStatus: null,
    bankbookUploadedAt: now,
    profileImageUrl: null,
    bio: null,
    skills: [],
    preferredWorkTypes: [],
    totalWorkDays: 0,
    totalWorkHours: 0,
    averageRating: 0.0,
    reviewCount: 0,
    noShowCount: 0,
    recentNoShowCount: 0,
    lateCount: 0,
    recentLateCount: 0,
    workTypeStats: {},
    isAvailable: true,
    unavailableReason: null,
    availableFrom: null,
    isBlacklisted: false,
    blacklistReason: null,
    businessNumber: null,
    businessName: null,
    businessLicenseImageUrl: null,
    businessLicenseImagePath: null,
    ceoName: null,
    rehireRate: 0.0,
    badges: [],
    lastRestartAt: null,
    signatureBase64: null,
    sealBase64: null,
    sealType: 'stamp',
    subAdminBusinessIds: [],
    restrictedUntil: null,
    notifPrefs: {
      workReminder: true,
      applicationUpdate: true,
      reviewAlert: true,
      contractAlert: true,
      wageAlert: true,
      toMatchAlert: true,
    },
    favoriteToIds: [],
    maxActiveTOs: null,
    homeRegion: HOME_REGION,
    preferredJobRegions: [],
    // fixture 표식 — production 코드가 읽지 않는다(우회 아님, 운영 식별용).
    devFixture: true,
    devFixtureNote: 'seed_dev_applicants.js — DEV 테스트 지원자',
  };
}

// ── 지원 게이트를 코드와 같은 순서로 재판정 ─────────────────────────
function evaluateGates(d, taxCollectionEnabled) {
  const r = {};
  r.accountActive = d.accountStatus === 'active';
  r.notBlacklisted = d.isBlacklisted !== true;
  r.notRestricted = !d.restrictedUntil ||
      d.restrictedUntil.toDate() <= new Date();
  const isForeign = !!(d.foreignIdentityFingerprint || d.foreignIdNumber);
  r.passVerified = isForeign || !!d.passVerifiedAt;
  r.hasIdDocument = !!(d.idCardImagePath || d.idCardImageUrl);
  r.isIdVerified = d.isIdVerified === true; // 단기(슬롯) 공고 전용
  r.hasBankAccount = !!(d.bankName && d.accountNumber && d.accountHolder);
  r.hasBankbookDocument = !!(d.bankbookImagePath || d.bankbookImageUrl);
  r.taxOk = !taxCollectionEnabled; // 켜져 있으면 taxIdentities 필요
  r.role = d.role;
  r.longTermReady = r.accountActive && r.notBlacklisted && r.notRestricted &&
      r.passVerified && r.hasIdDocument && r.hasBankAccount &&
      r.hasBankbookDocument && r.taxOk;
  r.shortTermReady = r.longTermReady && r.isIdVerified;
  return r;
}

(async () => {
  console.log('프로젝트: ' + serviceAccount.project_id + ' | 모드: ' + MODE);

  const taxSnap = await db.collection('app_settings')
      .doc('tax_identity_collection').get();
  const taxEnabled = taxSnap.exists && taxSnap.get('enabled') === true;
  console.log('세무 수집(app_settings/tax_identity_collection.enabled): ' + taxEnabled);
  if (taxEnabled && MODE === 'apply') {
    console.error('중단: 세무 수집이 켜져 있다. taxIdentities 는 CF 전용 암호화' +
        ' authority 이므로 이 스크립트가 만들지 않는다. 요청자에게 보고할 것.');
    process.exit(2);
  }

  const rows = [];
  for (const a of ACCOUNTS) {
    const email = a.loginId + '@ALfit-system.com';
    const row = {loginId: a.loginId, name: a.name, actions: []};

    // 1. Auth
    let userRecord = null;
    try {
      userRecord = await auth.getUserByEmail(email);
      row.actions.push('auth:기존');
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
      if (MODE === 'apply') {
        if (!PASSWORD) {
          console.error('중단: SEED_PASSWORD 환경변수가 없다.');
          process.exit(3);
        }
        userRecord = await auth.createUser({
          email, password: PASSWORD, displayName: a.name, emailVerified: false,
        });
        row.actions.push('auth:생성');
      } else {
        row.actions.push('auth:없음');
      }
    }
    if (!userRecord) { row.uid = null; rows.push(row); continue; }
    row.uid = userRecord.uid;

    // 2. 기존 users 문서 — 다른 실제 계정이면 중단
    const ref = db.collection('users').doc(userRecord.uid);
    const snap = await ref.get();
    if (snap.exists) {
      const d = snap.data();
      const isFixture = d.devFixture === true ||
          (typeof d.username === 'string' && /^test[1-6]$/.test(d.username));
      if (!isFixture) {
        console.error('중단: ' + a.loginId + ' 의 users 문서가 테스트 fixture 가' +
            ' 아니다(username=' + d.username + '). 사람이 확인해야 한다.');
        process.exit(4);
      }
      if (d.role && d.role !== 'USER') {
        console.error('중단: ' + a.loginId + ' 의 role 이 USER 가 아니다 — ' + d.role);
        process.exit(5);
      }
      row.actions.push('profile:기존');
    } else {
      row.actions.push('profile:없음');
    }

    // 3. Storage 문서 이미지
    const idObj = await ensureStorageObject(userRecord.uid, 'idCard');
    const bbObj = await ensureStorageObject(userRecord.uid, 'bankbook');
    if (idObj.created) row.actions.push('storage:idCard 생성');
    if (bbObj.created) row.actions.push('storage:bankbook 생성');

    // 4. users 문서 생성/보정
    if (MODE === 'apply') {
      const now = admin.firestore.Timestamp.now();
      const desired = buildUserDoc(a, userRecord.uid, idObj.path, bbObj.path, now);
      if (!snap.exists) {
        await ref.set(desired);
        row.actions.push('profile:생성');
      } else {
        // 있으면 **부족한 것만** 보정한다 — 기존 값을 덮어쓰지 않는다.
        const cur = snap.data();
        const patch = {};
        const need = (k, v) => {
          const c = cur[k];
          const empty = c === undefined || c === null || c === '' ||
              (Array.isArray(c) && c.length === 0);
          if (empty && v !== null && v !== undefined) patch[k] = v;
        };
        need('accountStatus', 'active');
        need('role', 'USER');
        need('passVerifiedAt', now);
        need('idCardImagePath', idObj.path);
        need('idCardVerifiedAt', now);
        need('bankName', BANK_NAME);
        need('accountHolder', a.name);
        need('bankbookImagePath', bbObj.path);
        need('bankbookUploadedAt', now);
        need('homeRegion', HOME_REGION);
        need('notifPrefs', desired.notifPrefs);
        need('devFixture', true);
        if (cur.isIdVerified !== true) patch.isIdVerified = true;
        if (cur.isBlacklisted === true) patch.isBlacklisted = false;
        if (cur.restrictedUntil) patch.restrictedUntil = null;
        // 계좌번호: 복호화해 값이 다르면만 다시 쓴다(IV 가 매번 달라 단순 비교 불가).
        const curAcc = decryptField(cur.accountNumber);
        if (curAcc !== a.account) patch.accountNumber = encryptField(a.account);
        if (Object.keys(patch).length > 0) {
          await ref.update(patch);
          row.actions.push('profile:보정(' + Object.keys(patch).join(',') + ')');
        } else {
          row.actions.push('profile:변경없음');
        }
      }
    }

    // 5. 최종 상태 재조회 + 게이트 재판정
    const finalSnap = await ref.get();
    if (!finalSnap.exists) {
      row.gates = null;
      rows.push(row);
      continue;
    }
    const fd = finalSnap.data();
    row.gates = evaluateGates(fd, taxEnabled);
    row.accountCheck = decryptField(fd.accountNumber) === a.account
        ? 'OK(복호화 일치)' : 'FAIL';
    row.accountMasked = mask(decryptField(fd.accountNumber) || '');
    row.idPath = fd.idCardImagePath || '-';
    row.bankbookPath = fd.bankbookImagePath || '-';
    // 보완 요청 존재 여부
    const corr = await db.collection('documentCorrectionRequests')
        .where('workerUid', '==', userRecord.uid).where('status', '==', 'OPEN')
        .limit(1).get().catch(() => ({empty: true, size: 0}));
    row.openCorrections = corr.empty ? 0 : corr.size;
    const tax = await db.collection('taxIdentities').doc(userRecord.uid).get();
    row.taxDoc = tax.exists ? '존재' : '없음';
    rows.push(row);
  }

  // ── 결과표 ────────────────────────────────────────────────────
  console.log('');
  console.log('loginId | uid | 이름 | role | Auth | profile | ID문서 | 통장문서 |' +
      ' 계좌 | Tax문서 | 보완요청 | 장기지원 | 단기지원');
  for (const r of rows) {
    const g = r.gates || {};
    console.log([
      r.loginId,
      r.uid ? r.uid.slice(0, 6) + '…' : '-',
      r.name,
      g.role || '-',
      r.uid ? 'O' : 'X',
      r.gates ? 'O' : 'X',
      g.hasIdDocument ? 'O' : 'X',
      g.hasBankbookDocument ? 'O' : 'X',
      (g.hasBankAccount ? 'O ' : 'X ') + (r.accountMasked || ''),
      r.taxDoc || '-',
      r.openCorrections === undefined ? '-' : r.openCorrections,
      g.longTermReady ? 'READY' : 'BLOCKED',
      g.shortTermReady ? 'READY' : 'BLOCKED',
    ].join(' | '));
  }
  console.log('');
  for (const r of rows) {
    console.log(r.loginId + ' 조치: ' + (r.actions.join(' / ') || '-') +
        ' | 계좌복호화: ' + (r.accountCheck || '-'));
  }
  process.exit(0);
})().catch((e) => {
  console.error('실패: ' + (e && e.message ? e.message : e));
  process.exit(1);
});
