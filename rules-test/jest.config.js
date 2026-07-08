/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/src/rules/**/*.test.ts'],
  testTimeout: 30000,
  globalSetup: './src/helpers/global-setup.js',
  globalTeardown: './src/helpers/global-teardown.js',
  verbose: true,
};
