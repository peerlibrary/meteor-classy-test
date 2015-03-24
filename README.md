Classy Test
===========

Meteor package which provides a class-based wrapper around `tinytest`.

It has the following features:

 * Class-based test cases.
 * Common setUp/tearDown methods for test cases, separated for server and client side.
 * A single test can interleave client-side and server-side assertions.
 * Support for asynchronous tests.
 * Compatible with tinytest (all tests are actually registered via tinytest).

Installation
------------

```
meteor add peerlibrary:classy-test
```

Test cases
----------

Each test case is a class extending from `ClassyTestCase` as follows:

```coffeescript
class SimpleTestCase extends ClassyTestCase
  # Define the test case name (required).
  @testName: 'Simple'

  testThatTrueIsTrue: =>
    @assertTrue true, "True should be true."

  testThatFalseIsFalse: =>
    @assertFalse false, "False should be false."

# Register the test case.
ClassyTestCase.addTest new SimpleTestCase()
```

This simple test case definition will generate two tests via tinytest, the first will be called `Simple - ThatTrueIsTrue` and the second one `Simple - ThatFalseIsFalse`.

Assertions
----------

Classy test assertions are named slightly differently than in tinytest, but are otherwise equivalent with some additional assertions provided by default. Because test cases are class-based, assertions are methods which may be called in test context. The list of assertions is as follows:

 * `assertEqual(actual, expected, message)` asserts that `actual` is equal to `expected`.
 * `assertNotEqual(a, b, message)` asserts that `a` is not equal to `b`.
 * `assertInstanceOf(object, class)` asserts that `object` is an instance of `class`.
 * `assertNotInstanceOf(object, class)` asserts that `object` is not an instance of `class`.
 * `assertRegexpMatches(string, regexp, message)` asserts that `string` matches the regular expression `regexp`.
 * `assertNotRegexpMatches(string, regexp, message)` asserts that `string` does not match the regular expression `regexp`.
 * `assertThrows(function, exception)` asserts that `function` throws `exception`.
 * `assertTrue(value, message)` asserts that `value` is `true`.
 * `assertFalse(value, message)` asserts that `value` is `false`.
 * `assertIsNull(value, message)` asserts that `value` is `null`.
 * `assertIsNotNull(value, message)` asserts that `value` is not `null`.
 * `assertIsUndefined(value, message)` asserts that `value` is `undefined`.
 * `assertIsNotUndefined(value, message)` asserts that `value` is not `undefined`.
 * `assertIsNaN(value, message)` asserts that `value` is `NaN`.
 * `assertIsNotNaN(value, message)` asserts that `value` is not `NaN`.
 * `assertIn(value, collection)` asserts that `collection` contains an element `value`.
 * `assertNotIn(value, collection)` asserts that `collection` does not contain an element `value`.
 * `assertItemsEqual(actual, expected)` asserts that arrays `actual` and `expected` contain the same elements (disregarding their order).
 * `assertObjectContainsSubset(actual, expected)` asserts that the key/value pairs in an object `actual` are a (non-strict) superset of those in `expected`.
 * `assertLengthOf(array, length, message)` asserts that the length of `array` is `length`.
 * `assertSubscribeSuccessful(endpoint, args..., callback)` asserts that subscription to Meteor endpoint `endpoint` using arguments `args...` is successful. This is an async assertion where `callback` is called after evaluation is completed.
 * `assertSubscribeFails(endpoint, args..., callback)` asserts that subscription to Meteor endpoint `endpoint` using arguments `args...` fails with an error. This is an async assertion where `callback` is called after evaluation is completed.

As mentioned, all assertions are methods and may be called on `this`:

```coffeescript
  testFoo: =>
    @assertEqual foo, bar, "Foo must be equal to bar."
    @assertLengthOf [1,1,1], 3
    # ...
```

Set up and tear down methods
----------------------------

Usually multiple tests share some common initialization and cleanup code. Using classy tests such code should be placed into set up and tear down methods. There are multiple of each, based on where they are executed:

 * `setUp` runs both on the server and client side before each test.
 * `setUpServer` runs only on the server side before each test.
 * `setUpClient` runs only on the client side before each test.
 * `tearDown` runs both on the server and client side after each test.
 * `tearDownServer` runs on the server side after each test.
 * `tearDownClient` runs on the client side after each test.

Set up and tear down methods are actually specially named tests, so they may also invoke assertions. If we take the above `testFoo` example, the order of executed methods is as follows:

```coffeescript
# Test initialization.
@setUpServer()
@setUp()
@setUpClient()
# Test body.
@testFoo()
# Test cleanup.
@tearDownClient()
@tearDownServer()
@tearDown()
```

Server-side and client-side tests
---------------------------------

By default all tests run both on client and server. It is possible to specify that some should only be executed on either the server-side or the client-side. This is done through a method naming convention which is as follows:

 * If a method name begins with `testServer` then the test will only be executed on the server side.
 * If a method name begins with `testClient` then the test will only be executed on the client side.

Asynchronous tests
------------------

Tests can be specified in two ways:

 * A single test method as in the above examples. When such a test method finishes, the test is deemed complete and the respective tear down methods will run.
 * Test containing multiple steps where each step is only deemed complete after certain callbacks get called. This is similar to `testAsyncMulti` from `test-helpers` (actually `testAsyncMulti` is used in the background to make this work).

In the second case, the test should not be defined as a method, but rather as an array of functions like in the following example:

```coffeescript
  testClientFoo:
    [
      ->
        # Call the first method.
        Meteor.call 'first', 'argument', @expect (error, result) =>
          @assertFalse error, "Error while calling first: #{ error }"
    ,
      ->
        # Call the second method.
        Meteor.call 'second', 'argument', @expect (error, result) =>
          @assertFalse error, "Error while calling second: #{ error }"
    ]
```

This defines a chain of sub-tests where the next case will only get executed once all the *expected* callbacks are run. In order to define which callbacks are expected one should use the `@expect(fun)` method which takes a function argument and returns a wrapper function that will mark the callback as called. When all expected callbacks are called, the execution will proceed to the next sub-test in the chain.

Note that in this case set up and tear down methods are only called once for the whole test and not in-between sub-tests.

Interleaving client-side and server-side assertions
--------------------------------------------------

Sometimes it can be useful to first run some tests on the client, then after those are done, run some tests on the server to check whether the client calls correctly affected the backend storage. This can be done by interleaving client-side sub-tests with server-side sub-tests. We take the previous async test example and add a server-side sub-test between the existing two using the `@runOnServer` decorator:

```coffeescript
  testClientFoo:
    [
      ->
        # Call the first method.
        Meteor.call 'first', 'argument', @expect (error, result) =>
          @assertFalse error, "Error while calling first: #{ error }"
    ,
      @runOnServer ->
        # Check if the first method really cleared everything in Foo collection.
        @assertEqual Foo.find().count(), 0
    ,
      ->
        # Call the second method.
        Meteor.call 'second', 'argument', @expect (error, result) =>
          @assertFalse error, "Error while calling second: #{ error }"
    ]
```

After the `first` method call completes, the second sub-test will be executed on the server and all assertions will be propagated back to the client.

Another similar decorator is `@runOnBoth` which will behave the same as `@runOnServer` but will additionally also run the code on the client (in client-side tests) once it finishes executing on the server.

Passing variables from server-side tests to client-side tests
-------------------------------------------------------------

Sometimes there is the need of passing variables from server-side tests for use in client-side tests, usually when defining fixtures in `setUp` methods. Consider this *non-working example*:

```coffeescript
  setUpServer: =>
    # Initialize the database.
    Foo.remove {}

    # Create a test document.
    @testDocumentId = Foo.insert
      bar: true

  testClientRemoval: =>
    Meteor.call 'remove', @testDocumentId, @expect (error, result) =>
      @assertFalse error, "Error while remove: #{ error }"
```

So before the test starts we create a test fixture on the server and would then like to reference its `_id` on the client. The problem is that this will not work as the test case instance on the server differs from the one on the client and `@testDocumentId` will not be available there. In order to address this, classy tests support passing specific variables from server-side tests to client-side tests using `@get` and `@set` methods. In order to fix the above example we can do:

```coffeescript
  setUpServer: =>
    # Initialize the database.
    Foo.remove {}

    # Create a test document.
    testDocumentId = Foo.insert
      bar: true

    # Pass variable to client-side tests.
    @set 'testDocumentId', testDocumentId

  testClientRemoval: =>
    Meteor.call 'remove', @get('testDocumentId'), @expect (error, result) =>
      @assertFalse error, "Error while remove: #{ error }"
```

In the background, the test framework will seamlessly transfer the variables between the tests. Note that as variables are transferred via DDP, they must be EJSON serializable.

Currently the variables may only be transferred from server-side tests to client-side tests and not vice-versa. In the future this limitation might be lifted.

Miscellaneous methods
---------------------

You can use `@subscribe` to subscribe to Meteor publish endpoint in a way which automatically unsubscribes on test tear down. You can use `@unsubscribeAll` to force unsubscribing all subscriptions immediatelly.
