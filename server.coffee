Future = Npm.require 'fibers/future'

# Prevent parallel setup requests.
isInTestControl = false
testControl = null

# Define server-side methods.
Meteor.methods
  'classyTest.testCallable': (callableId) ->
    check callableId, Number

    # This flag and future are needed because methods may be called multiple times
    # while another method is already running on the server. See the following
    # Meteor issue: https://github.com/meteor/meteor/issues/1285.
    if isInTestControl
      testControl.wait()
      return testControl.get()

    callable = ClassyTestCase._serverCallables[callableId]
    throw new Meteor.Error 'callable-not-found', "Server callable #{ callableId } cannot be found." unless callable

    # Create a virtual test case.
    testCase =
      name: 'callable'
      groupPath: ''
      shortName: 'callable'

    # Create a new instance of TestCaseResults so we can perform asserts on the server
    # and transfer results to the client test that is executing.
    test = new TestCaseResults testCase,
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
      # There is no need to bind 'this' here as it has already been bound when registering.
      callable test
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
class ClassyTestCase extends ClassyTestCase
  asyncWait: (timeout, handler) =>
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

  asyncWaitCursorChange: (timeout, cursor, predicate) =>
    @asyncWait timeout, (future) ->
      handle = cursor.observe
        changed: (newDocument) ->
          if predicate newDocument
            # Resolve the future.
            future.return() unless future.isResolved()

      # Ensure that we stop observing the cursor for changes once the future is resolved.
      return ->
        handle.stop()
