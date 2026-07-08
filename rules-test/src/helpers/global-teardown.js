// rules-test/src/helpers/global-teardown.js
module.exports = async function() {
  // 에뮬레이터는 외부에서 기동했으므로 여기서 종료하지 않음
  console.log('\n✅ 테스트 완료\n');
};
