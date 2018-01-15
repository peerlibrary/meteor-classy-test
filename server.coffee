import Future from 'fibers/future'

import {ClassyTestCase, ExpectationManager} from './lib'

# Prevent parallel setup requests.
isInTestControl = false
testControl = null

# Define server-side methods.
Meteor.methods
  'classyTest.testCallable': (testName, callableId, exportedVariables) ->
    check testName, String
    check callableId, Number
    check exportedVariables, Object

    # If there are no tests defined on the server-side, then maybe the entire test
    # definition has been limited to the client. In this case, we simply ignore
    # all the server-only methods.
    return [] unless ClassyTestCase.getTest testName

    # This flag and future are needed because methods may be called multiple times
    # while another method is already running on the server. See the following
    # Meteor issue: https://github.com/meteor/meteor/issues/1285.
    if isInTestControl
      testControl.wait()
      return testControl.get()

    callable = ClassyTestCase._serverCallables?[testName]?[callableId]
    throw new Meteor.Error 'callable-not-found', "Server callable #{ callableId } cannot be found." unless callable

    # Create a virtual test case.
    testCase =
      name: 'callable'
      groupPath: ''
      shortName: 'callable'

    # Create a new instance of TestCaseResults so we can perform asserts on the server
    # and transfer results to the client test that is executing.
    test = new Tinytest._TestCaseResults testCase,
      (event) ->
        # Store events so they can be replayed on the client.
        test.events.push event
    ,
      (exception) ->
        # TODO: onException
    ,
      null

    test.events = []

    # Call the server-side callable.
    try
      isInTestControl = true
      testControl = new Future()
      # Set exported variables when defined.
      callable.testCase.exportedVariables = exportedVariables
      # There is no need to bind 'this' here as it has already been bound when registering.
      originalTest = callable.testCase._internal.test
      callable.testCase._internal.test = test

      # Create a new expectation manager with a specific completion handler.
      expectationFuture = new Future()
      expectationManager = new ExpectationManager test, =>
        Meteor.clearTimeout timer
        # Each function is assigned a new expectation manager, so we clear the current one.
        callable.testCase._internal.expectationManager = null
        # Resolve the future.
        expectationFuture.return()
      # Bind the expectation handler.
      callable.testCase._internal.expectationManager = expectationManager

      # Ensure that tests time out if they run for too long.
      timer = Meteor.setTimeout =>
        if expectationManager.cancel()
          test.fail
            type: 'timeout'
            message: 'Test case timed out.'
          # Abort the test immediately.
          expectationFuture.return()
      ,
        callable.testCase.constructor.testTimeout

      try
        callable()
        expectationManager.done()
        expectationFuture.wait() unless expectationManager.dead
      finally
        callable.testCase._internal.test = originalTest
      # If any variables have been exported, send them to the client.
      if callable.testCase.exportedVariables
        exportEvent =
          type: 'export'
          details: callable.testCase.exportedVariables

        test.events = [exportEvent].concat test.events
    finally
      isInTestControl = false
      testControl.return test.events

    # Return test results.
    test.events

# Extend server-side test case with additional methods.
ClassyTestCase::asyncWait = (timeout, handler) ->
  throw new Error "You may only use 'asyncWait' in server-side tests." unless Meteor.isServer

  future = new Future()

  # Install a timeout handler so that we always unblock.
  Meteor.setTimeout ->
    future.return() unless future.isResolved()
  ,
    timeout

  # Invoke the handler and pass it the future we are waiting on. The handler should
  # resolve the future before the timeout expires.
  cleanupHandler = handler future

  try
    future.wait()
  finally
    cleanupHandler?()

  return

ClassyTestCase::asyncWaitCursorChange = (timeout, cursor, predicate) ->
  @asyncWait timeout, (future) ->
    handle = cursor.observe
      changed: (newDocument) ->
        if predicate newDocument
          # Resolve the future.
          future.return() unless future.isResolved()

    # Ensure that we stop observing the cursor for changes once the future is resolved.
    return ->
      handle.stop()

export {ClassyTestCase}
