'use strict';
const {db} = require('./r7-fixture-lib');
(async () => {
  const d = (await db.collection('users').doc('n5QtJIiJIeXBNQvbWxAOqOHyCcs2').get()).data();
  process.exit(0);
})().catch(e => { console.error(e.message); process.exit(1); });
