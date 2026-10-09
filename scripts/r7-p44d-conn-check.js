'use strict';
const {db} = require('./r7-fixture-lib');
(async () => {
  for (const c of ['tos', 'businesses', 'users', 'applications']) {
    const s = await db.collection(c).limit(5).get();
    console.log(c, '표본:', s.size);
  }
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
