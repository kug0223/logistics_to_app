// rules-test/src/helpers/global-setup.js
// Jest globalSetup — 에뮬레이터가 실행 중인지 확인 (자동 기동은 하지 않음)
// 테스트 실행 전 별도 터미널에서:
//   firebase emulators:start --only firestore --project alfit-89567

const http = require('http');

const EMULATOR_HOST = '127.0.0.1';
const EMULATOR_PORT = 6060;
const MAX_RETRIES = 3;

function checkEmulator(retries = 0) {
  return new Promise((resolve, reject) => {
    const req = http.get(
      `http://${EMULATOR_HOST}:${EMULATOR_PORT}/`,
      (res) => { resolve(true); }
    );
    req.on('error', () => {
      if (retries < MAX_RETRIES) {
        setTimeout(() => checkEmulator(retries + 1).then(resolve).catch(reject), 2000);
      } else {
        reject(new Error(
          `\n\n⚠️  Firestore 에뮬레이터가 실행되지 않았습니다.\n` +
          `   먼저 다음 명령을 실행하세요:\n` +
          `   firebase emulators:start --only firestore --project alfit-89567\n\n`
        ));
      }
    });
    req.setTimeout(2000, () => { req.destroy(); });
  });
}

module.exports = async function() {
  await checkEmulator();
  console.log('\n✅ Firestore 에뮬레이터 연결 확인 (port 6060)\n');
};
