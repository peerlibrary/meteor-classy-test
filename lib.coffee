class ExpectationManager
  constructor: (@test, @onComplete) ->
    @closed = false
    @dead = false
    # The number of outstanding expect calls.
    @outstanding = 0
    @exceptionAlreadyCanceled = false

  expect: ->
    expected = if typeof arguments[0] is 'function' then arguments[0] else _.toArray arguments
    throw new Error "Too late to add more expectations to the test." if @closed
    @outstanding++

    # Return an expectation handler.
    Meteor.bindEnvironment =>
      return if @dead

      if typeof expected is 'function'
        try
          expected.apply {}, arguments
        catch error
          @exception error
      else
        @test.equal _.toArray(arguments), expected

      # One less outstanding call, check if we are done.
      @outstanding--
      @_checkComplete()
    ,
      'expect'

  done: ->
    @closed = true
    @_checkComplete()

  exception: (error) ->
    if @cancel()
      @exceptionAlreadyCanceled = true
      @test.exception error

  cancel: (exception=false) ->
    unless @dead
      @dead = true
      return true

    exception and @exceptionAlreadyCanceled

  _checkComplete: ->
    if not @outstanding and @closed and not @dead
      @dead = true
      @onComplete()

class ClassyTestCase
  ### Test case configuration ###

  # Number of milliseconds after which the test case must complete. Otherwise it will be aborted.
  @testTimeout: 200000

  ### Internals ###

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
    ClassyTestCase.runOnBoth @setUp
    ClassyTestCase.runOnServer @tearDownServer
    ClassyTestCase.runOnBoth @tearDown

    # Test-local internal variables.
    @_internal = {}

    if Meteor.isClient
      # Capture uncaught exceptions.
      originalOnError = window.onerror
      window.onerror = (args...) =>
        @_onError args...
        originalOnError.apply @, args if originalOnError

      @_internal.capturedErrors = []
      @_internal.currentErrors = 0

  @hasTests: ->
    ClassyTestCase._hasTests

  @getTest: (name) ->
    ClassyTestCase._testRegistry[name]

  @addTest: (testCase, options={}) ->
    # Check if the test has a name defined.
    throw new Error "Test case must have a name defined." unless testCase.getTestName()

    throw new Error "Test case name must be unique." if ClassyTestCase._testRegistry[testCase.getTestName()]

    # Set a flag so that we know whether any tests have been defined.
    ClassyTestCase._hasTests = true
    ClassyTestCase._testRegistry[testCase.getTestName()] = testCase

    testCase._internal.options = options

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
        testCase._processTestFunction testChain, ->
          # Initialize exported variables.
          @exportedVariables = {}

          # Override event reporting in case the test suite must fail.
          if @_internal.options.mustFail
            @_internal.hasFailures = false
            @_internal.test.originalOnException = @_internal.test.onException
            @_internal.test.originalOnEvent = @_internal.test.onEvent

            @_internal.test.onException = (exception) =>
              # We must suppress exceptions. Report them as expected test failures.
              @_internal.hasFailures = true
              @_internal.test.originalOnEvent
                type: 'expected_fail'
                details:
                  type: 'exception'
                  message: "Exception raised: #{exception}"

              # Force the test to complete immediately.
              if @_internal.expectationManager.cancel true
                @_internal.complete()

            @_internal.test.onEvent = (event) =>
              # Report all failures as expected failures.
              if event.type is 'fail'
                event.type = 'expected_fail'
                @_internal.hasFailures = true

              @_internal.test.originalOnEvent event

        # Prepare uncaught exceptions capture.
        if Meteor.isClient
          testCase._processTestFunction testChain, ->
            @_internal.currentErrors = @_internal.capturedErrors.length

        testCase._processTestFunction testChain, testCase.setUpServer
        testCase._processTestFunction testChain, testCase.setUp
        testCase._processTestFunction testChain, testCase.setUpClient if Meteor.isClient
        testCase._processTestFunction testChain, testCase._getTestFunction testFunction
        testCase._processTestFunction testChain, testCase.tearDownClient if Meteor.isClient
        testCase._processTestFunction testChain, testCase.tearDownServer
        testCase._processTestFunction testChain, testCase.tearDown
        testCase._processTestFunction testChain, ->
          if Meteor.isClient
            # Check if there were any uncaught exceptions while testing.
            for {errorMessage, url, lineNumber, columnNumber, errorObject} in @_internal.capturedErrors[@_internal.currentErrors..]
              @_internal.test.fail
                type: 'uncaught_exception'
                message: errorMessage
                stack: errorObject?.stack

          # Ensure that the test failed if it was registered as a failing test.
          if @_internal.options.mustFail
            # Restore exception and event handlers.
            @_internal.test.onException = @_internal.test.originalOnException
            @_internal.test.onEvent = @_internal.test.originalOnEvent

            @assertTrue @_internal.hasFailures, "Test suite completed without failures. Expected it to fail."
            @_internal.hasFailures = null

          # Unsubscribe from everything the test cases subscribed to.
          @unsubscribeAll()
          # Stop all reactive computations.
          computation.stop() for computation in @_internal.computations ? []
          @_internal.computations = []

        # Skip test cases that are not feasible in the current context.
        return unless testCase._isTestFeasible name

        # Execute the test.
        Tinytest.addAsync "#{ testCase.getTestName() } - #{ name.slice(4) }", (test, onComplete) ->
          # Based on testAsyncMulti from Meteor's test-helpers package.
          remaining = testChain
          currentAsyncBlock = 0

          # Initialize the local test instance.
          testCase._internal.complete = onComplete
          testCase._internal.test = test
          # TODO: Move _test to _internal.test.
          testCase._test = test

          runNext = =>
            nextFunction = remaining.shift()
            unless nextFunction
              # Cleanup.
              testCase._internal.complete = null
              testCase._internal.test = null
              testCase._test = null
              test.extraDetails.asyncBlock = null
              # Test case has completed.
              onComplete()
              return

            # Create a new expectation manager with a specific completion handler.
            expectationManager = new ExpectationManager test, =>
              Meteor.clearTimeout timer
              # Each function is assigned a new expectation manager, so we clear the current one.
              testCase._internal.expectationManager = null
              # Run next function.
              runNext()
            # Bind the expectation handler.
            testCase._internal.expectationManager = expectationManager

            # Ensure that tests time out if they run for too long.
            timer = Meteor.setTimeout =>
              if expectationManager.cancel()
                test.fail
                  type: 'timeout'
                  message: 'Test case timed out.'
                # Abort the test immediately.
                onComplete()
            ,
              testCase.constructor.testTimeout

            # Run the next function.
            test.extraDetails.asyncBlock = currentAsyncBlock++
            try
              nextFunction.call testCase
            catch error
              expectationManager.exception error
              Meteor.clearTimeout timer
              # Since we called test.exception, we must not call onCompleted.
              return

            expectationManager.done()

          runNext()

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
        boundItem = =>
          # Ensure that all tests execute non-reactively.
          Tracker.nonreactive =>
            testItem.call @

        boundItem.testCase = @

        if testItem.runOnServer
          if Meteor.isServer
            # Register callable on the server.
            callables = ClassyTestCase._serverCallables[@getTestName()] ?= {}
            callables[testItem.serverCallableId] = boundItem
            testChain.push boundItem
          else
            # Call the callable via a method on the client.
            testChain.push =>
              exportedVariables = @exportedVariables ? {}

              Meteor.call 'classyTest.testCallable', @getTestName(), testItem.serverCallableId, exportedVariables, @_internal.expectationManager.expect (error, result) =>
                # Handle internal errors.
                @assertIsUndefined error, "Server-side callable test failed: #{ error }"
                return unless _.isUndefined error

                # Replay test results on the client.
                for event in result
                  switch event.type
                    when 'fail' then @_internal.test.fail event.details
                    when 'ok' then @_internal.test.ok event.details
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

  # Process uncaught exceptions.
  _onError: (errorMessage, url, lineNumber, columnNumber, errorObject) ->
    @_internal.capturedErrors.push {errorMessage, url, lineNumber, columnNumber, errorObject}

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
    @_internal.test.equal actual, expected, message

  assertNotEqual: (actual, expected, message) =>
    @_internal.test.notEqual actual, expected, message

  assertInstanceOf: (obj, klass) =>
    @_internal.test.instanceOf obj, klass

  assertNotInstanceOf: (obj, klass) =>
    if obj not instanceof klass
      @_internal.test.ok()
    else
      @_internal.test.fail
        type: 'instanceOf'
        not: true

  assertRegexpMatches: (actual, regexp, message) =>
    @_internal.test.matches actual, regexp, message

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
    @_internal.test.throws func, expected

  assertTrue: (value, msg) =>
    @_internal.test.isTrue value, msg

  assertFalse: (value, msg) =>
    @_internal.test.isFalse value, msg

  assertIsNull: (value, msg) =>
    @_internal.test.isNull value, msg

  assertIsNotNull: (value, msg) =>
    @_internal.test.isNotNull value, msg

  assertIsUndefined: (value, msg) =>
    @_internal.test.isUndefined value, msg

  assertIsNotUndefined: (value, msg) =>
    if value isnt undefined
      @_internal.test.ok()
    else
      @_internal.test.fail
        type: 'undefined'
        message: msg
        not: true

  assertIsNaN: (value, msg) =>
    @_internal.test.isNaN value, msg

  assertIsNotNaN: (value, msg) =>
    if not isNaN v
      this.ok()
    else
      this.fail
        type: 'NaN'
        message: msg
        not: true

  assertIn: (value, collection=[]) =>
    @_internal.test.include collection, value

  assertNotIn: (value, collection=[]) =>
    # Same as @_internal.test.include implementation, just negated.

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
      @_internal.test.ok()
    else
      @_internal.test.fail
        type: 'itemsEqual'
        actual: JSON.stringify actual
        expected: JSON.stringify expected

  assertObjectContainsSubset: (actual, expected) =>
    subset = ->
      for key, value of expected
        return false unless _.isEqual actual[key], value
      true

    if subset()
      @_internal.test.ok()
    else
      @_internal.test.fail
        type: 'objectContainsSubset'
        actual: JSON.stringify actual
        expected: JSON.stringify expected

  assertLengthOf: (obj=[], expected, msg) =>
    @_internal.test.length obj, expected, msg

  assertFail: (doc) =>
    @_internal.test.fail doc

  assertSubscribeSuccessful: (endpoint, args..., callback) =>
    # Try subscribing to the endpoint.
    @subscribe endpoint, args...,
      onReady: =>
        @assertTrue true
        callback?()
      onError: (error) =>
        @assertFail
          type: 'subscribe'
          message: "Subscrption to endpoint failed, but should have succeeded: #{error}"
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

  assertNextTestFails: =>
    @_internal.test.expect_fail()

  exception: (error) =>
    @_internal.test.exception error

  expect: (args...) =>
    throw new Error "Cannot call expect outside a test case." unless @_internal.expectationManager

    @_internal.expectationManager.expect args...

  expectWithTimeout: (timeout, message, callback) ->
    next = @expect (ok) =>
      Meteor.clearTimeout handle if handle
      @assertTrue ok, "Expectation timed out: #{message}"

    handle = Meteor.setTimeout next, timeout

    ->
      next true
      callback.apply @, arguments if callback

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
    @exportedVariables?[name]

  subscribe: (args...) =>
    subscription = Meteor.subscribe args...

    # Store subscription so we can unsubscribe from everything on tear down.
    @_internal.subscriptions ?= []
    @_internal.subscriptions.push subscription

    subscription

  unsubscribeAll: =>
    # Unsubscribe from everything the test cases subscribed to.
    subscription.stop() for subscription in @_internal.subscriptions ? []
    @_internal.subscriptions = []

  autorun: (handler) =>
    computation = Tracker.autorun _.bind handler, @

    @_internal.computations ?= []
    @_internal.computations.push computation

    computation
