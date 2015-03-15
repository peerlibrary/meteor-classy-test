class ClassyTestCase
  # Flag whether there are any tests defined.
  @_hasTests: false
  # Unique callable identifier.
  @_serverCallableId: 0
  # Callables.
  @_serverCallables: {}
  # Test registry.
  @_testRegistry: {}

  constructor: ->
    # Tag server-specific setup/tear down methods so they always run on the server.
    ClassyTestCase.runOnServer @setUpServer
    ClassyTestCase.runOnServer @setUp
    ClassyTestCase.runOnServer @tearDownServer
    ClassyTestCase.runOnServer @tearDown

    # Initialize current test/expect instances.
    @_test = null
    @_expect = null

  @hasTests: ->
    ClassyTestCase._hasTests

  @getTest: (name) ->
    ClassyTestCase._testRegistry[name]

  @addTest: (testCase) ->
    # Check if the test has a name defined.
    throw new Error "Test case must have a name defined." unless testCase.getTestName()

    throw new Error "Test case name must be unique." if ClassyTestCase._testRegistry[testCase.getTestName()]

    # Set a flag so that we know whether any tests have been defined.
    ClassyTestCase._hasTests = true
    ClassyTestCase._testRegistry[testCase.getTestName()] = testCase

    # Register the test case.
    keys = (keys for keys, method of testCase)
    for name in _.sortBy(keys, (name) -> testCase?[name]?.order ? 100)
      testFunction = testCase[name]
      delete testFunction?.order

      do (name, testFunction) =>
        return unless name.slice(0, 4) is 'test'
        return unless _.isFunction(testFunction) or _.isArray(testFunction)

        # Extract server-side callables from client functions.
        testChain = []
        testCase._processTestFunction testChain, testCase.setUpServer
        testCase._processTestFunction testChain, testCase.setUp
        testCase._processTestFunction testChain, testCase.setUpClient
        testCase._processTestFunction testChain, testCase._getTestFunction testFunction
        testCase._processTestFunction testChain, testCase.tearDownClient
        testCase._processTestFunction testChain, testCase.tearDownServer
        testCase._processTestFunction testChain, testCase.tearDown
        testCase._processTestFunction testChain, ->
          # Reset test/expect instances.
          @_test = null
          @_expect = null

          # Unsubscribe from everything the test cases subscribed to.
          @unsubscribeAll()

        # Skip test cases that are not feasible in the current context.
        return unless testCase._isTestFeasible name

        # Execute the test.
        testAsyncMulti "#{ testCase.getTestName() } - #{ name.slice(4) }", testChain

  _isTestFeasible: (testName) =>
    # Check for client- or server-only tests.
    return false if testName.slice(0, 10) is 'testClient' and not Meteor.isClient
    return false if testName.slice(0, 10) is 'testServer' and not Meteor.isServer

    true

  _getTestFunction: (testFunction) =>
    # May be used to change what actually gets executed when running a test.
    testFunction

  _processTestFunction: (testChain, testFunction) =>
    if _.isArray testFunction
      testBody = testFunction
    else
      testBody = [testFunction]

    for testItem in testBody
      do (testItem) =>
        boundItem = (test, expect) =>
          @_test = test
          @_expect = expect

          testItem.call @

        boundItem.testCase = @

        if testItem.runOnServer
          if Meteor.isServer
            # Register callable on the server.
            ClassyTestCase._serverCallables[testItem.serverCallableId] = boundItem
            testChain.push boundItem
          else
            # Call the callable via a method on the client.
            testChain.push (test, expect) =>
              Meteor.call 'classyTest.testCallable', testItem.serverCallableId, expect (error, result) =>
                # Handle internal errors.
                test.isUndefined error, "Server-side callable test failed: #{ error }"
                return unless _.isUndefined error

                # Replay test results on the client.
                for event in result
                  switch event.type
                    when 'fail' then test.fail event.details
                    when 'ok' then test.ok event.details
                    when 'export'
                      # Export variables.
                      for name, value of event.details
                        @set name, value
                    else
                      # Ignore all unhandled event types.

            # If the callable is marked to run on both client and server, push another client-side version.
            if testItem.runOnBoth
              testChain.push boundItem
        else
          testChain.push boundItem

  @getTestName: ->
    @testName

  getTestName: =>
    @constructor.getTestName()

  @runOnServer: (callable) ->
    # Mark the callable for running on the server.
    callable.runOnServer = true
    callable.serverCallableId = ++ClassyTestCase._serverCallableId
    callable

  @runOnBoth: (callable) ->
    # Mark the callable for running on the server and on the client.
    callable.runOnBoth = true
    @runOnServer callable

  assertEqual: (actual, expected, message) =>
    @_test.equal actual, expected, message

  assertNotEqual: (actual, expected, message) =>
    @_test.notEqual actual, expected, message

  assertInstanceOf: (obj, klass) =>
    @_test.instanceOf obj, klass

  assertNotInstanceOf: (obj, klass) =>
    if obj not instanceof klass
      @_test.ok()
    else
      @_test.fail
        type: 'instanceOf'
        not: true

  assertRegexpMatches: (actual, regexp, message) =>
    @_test.matches actual, regexp, message

  assertNotRegexpMatches: (actual, regexp, message) =>
    if not regexp.test actual
      this.ok()
    else
      this.fail
        type: 'matches'
        message: message
        actual: actual
        regexp: regexp.toString()
        not: true

  assertThrows: (func, expected) =>
    @_test.throws func, expected

  assertTrue: (value, msg) =>
    @_test.isTrue value, msg

  assertFalse: (value, msg) =>
    @_test.isFalse value, msg

  assertIsNull: (value, msg) =>
    @_test.isNull value, msg

  assertIsNotNull: (value, msg) =>
    @_test.isNotNull value, msg

  assertIsUndefined: (value, msg) =>
    @_test.isUndefined value, msg

  assertIsNotUndefined: (value, msg) =>
    if value isnt undefined
      @_test.ok()
    else
      @_test.fail
        type: 'undefined'
        message: msg
        not: true

  assertIsNaN: (value, msg) =>
    @_test.isNaN value, msg

  assertIsNotNaN: (value, msg) =>
    if not isNaN v
      this.ok()
    else
      this.fail
        type: 'NaN'
        message: msg
        not: true

  assertIn: (value, collection=[]) =>
    @_test.include collection, value

  assertNotIn: (value, collection=[]) =>
    # Same as @_test.include implementation, just negated.

    pass = false
    if collection instanceof Array
      pass = _.any collection, (it) -> _.isEqual value, it
    else if typeof collection is 'object'
      pass = value in collection
    else if typeof collection is 'string'
      pass = collection.indexOf value > -1

    if not pass
      @ok()
    else
      @fail
        type: 'include'
        sequence: collection
        should_contain_value: value
        not: true

  assertItemsEqual: (actual, expected) =>
    actual ||= []
    expected ||= []

    intersectionObjects = (array, rest...) ->
      _.filter _.uniq(array), (item) ->
        _.every rest, (other) ->
          _.any other, (element) -> _.isEqual element, item

    if actual.length is expected.length and intersectionObjects(actual, expected).length is actual.length
      @_test.ok()
    else
      @_test.fail
        type: 'itemsEqual'
        actual: JSON.stringify actual
        expected: JSON.stringify expected

  assertObjectContainsSubset: (actual, expected) =>
    subset = ->
      for key, value of expected
        return false unless _.isEqual actual[key], value
      true

    if subset()
      @_test.ok()
    else
      @_test.fail
        type: 'objectContainsSubset'
        actual: JSON.stringify actual
        expected: JSON.stringify expected

  assertLengthOf: (obj=[], expected, msg) =>
    @_test.length obj, expected, msg

  assertFail: (doc) =>
    @_test.fail doc

  assertSubscribeSuccessful: (endpoint, args..., callback) =>
    # Try subscribing to the endpoint.
    @subscribe endpoint, args...,
      onReady: =>
        @assertTrue true
        callback?()
      onError: =>
        @assertFail
          type: 'subscribe'
          message: "Subscrption to endpoint failed, but should have succeeded."
        callback?()

  assertSubscribeFails: (endpoint, args..., callback) =>
    # Try subscribing to the endpoint.
    @subscribe endpoint, args...,
      onReady: =>
        @assertFail
          type: 'subscribe'
          message: "Subscription to endpoint was successful, but shouldn't be."
        callback?()
      onError: =>
        @assertTrue true
        callback?()

  expect: (args...) =>
    @_expect args...

  switchUser: (username, password, callback) =>
    # Stop all subscriptions to prevent errors while switching users.
    @unsubscribeAll()

    # Log the current user out.
    Meteor.logout (error) =>
      @assertIsUndefined error, "User logout failed: #{ error }"

      # Switch to the other user.
      Meteor.loginWithPassword username, password, (error) =>
        @assertIsUndefined error, "User login failed: #{ error }"
        callback?()

  setUp: =>
    # Default implementation does nothing.

  setUpServer: =>
    # Default implementation does nothing.

  setUpClient: =>
    # Default implementation does nothing.

  tearDown: =>
    # Default implementation does nothing.

  tearDownServer: =>
    # Default implementation does nothing.

  tearDownClient: =>
    # Default implementation does nothing.

  set: (name, value) =>
    # Exports the variable to other tests.
    @exportedVariables ?= {}
    @exportedVariables[name] = value

  get: (name) =>
    # Retrieves a previously set variable.
    @exportedVariables[name]

  subscribe: (args...) =>
    # Store subscription so we can unsubscribe from everything on tear down.
    @subscriptions ?= []
    @subscriptions.push Meteor.subscribe args...

  unsubscribeAll: =>
    return unless _.isArray @subscriptions

    # Unsubscribe from everything the test cases subscribed to.
    subscription.stop() for subscription in @subscriptions

    @subscriptions = []
