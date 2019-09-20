Package.describe({
  name: 'peerlibrary:classy-test',
  summary: "Class-based wrapper around tinytest",
  version: '0.4.0',
  git: 'https://github.com/peerlibrary/meteor-classy-test.git'
});

Package.onUse(function (api) {
  api.versionsFrom('METEOR@1.8.1');

  // Core dependencies.
  api.use([
    'coffeescript@2.4.1',
    'ecmascript',
    'underscore',
    'tinytest',
    'tracker',
    'ddp',
    'check',
    'random',
    'ejson'
  ]);

  api.export('ClassyTestCase');

  api.mainModule('client.coffee', 'client');
  api.mainModule('server.coffee', 'server');
});

