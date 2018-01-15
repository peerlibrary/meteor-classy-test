Package.describe({
  name: 'peerlibrary:classy-test',
  summary: "Class-based wrapper around tinytest",
  version: '0.3.0',
  git: 'https://github.com/peerlibrary/meteor-classy-test.git'
});

Package.onUse(function (api) {
  api.versionsFrom('METEOR@1.4.4.5');

  // Core dependencies.
  api.use([
    'coffeescript@2.0.3_3',
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

