Package.describe({
  name: 'peerlibrary:classy-test',
  summary: "Class-based wrapper around tinytest",
  version: '0.2.6',
  git: 'https://github.com/peerlibrary/meteor-classy-test.git'
});

Package.onUse(function (api) {
  api.versionsFrom('METEOR@1.0.3.1');

  // Core dependencies.
  api.use([
    'underscore',
    'coffeescript',
    'tinytest'
  ]);

  api.export('ClassyTestCase');

  // Client and server.
  api.addFiles([
    // TODO: This include is needed as test-helpers only export asyncMulti to tests.
    // See pull request: https://github.com/meteor/meteor/pull/3494
    'meteor/packages/test-helpers/async_multi.js',
    // TODO: This include is needed as Tinytest does not export TestCaseResults.
    // See pull request: https://github.com/meteor/meteor/pull/3541
    'meteor/packages/tinytest/tinytest.js',
    'restore_tinytest.js',
    // This file must be imported before server.
    'lib.coffee'
  ]);

  // Server.
  api.addFiles([
    'server.coffee'
  ], 'server');
});

