Wrap asynchronous database calls in transactions, using
nodejs and promises.

# Installation

npm install xwrap

# What it does

XWrap allows you to use promise-using database tools with transactions
without having to pass a transaction object around.

If you use a database tool that does not itself use transactions, but:

#. depends on a database connection package that keeps a pool of clients (such 
  as [node postgres](https://github.com/brianc/node-postgres)), 

#. Which uses promises that support the progress interface.

xwrap will let you wrap calls that tool in transactions (and savepoints, if
supported by the backend) without having to modify the tools.

If the tools use xwrap themselves, any transactions they create will
automatically be converted into savepoints if wrapped by your transactions.

# Quick Start

    Promise = require 'bluebird'
    {XRequest, initialize} = require 'xwrap'
    xwrap = initialize(
      'pg', { url: 'postgres://username:password@localhost/database'})


The promise chain in this callback will be wrapped in a transaction
the three transactions will proceed in parallel on different
clients, or be serialized when the pool runs out of clients.
    
    Promise.map [1..3], ->
      xwrap ->
        foo().then (rows)->
          Promise.map rows, (row, i)->
            bar(row, i)
        .then ->
          # this creates savepoint and then causes error
          baz().catch (err)->
            # error handled here -- savepoint rolled back,
            # but not transaction.

`foo` can get the appropriate client automatically. `foo` might not be  written
by you and/or the need for the client could be deeply buried, making explicit
passing of client undesirable.

    foo = ->
      XRequest.client().then (client)->
        client.queryAsync('select * from foo')
      .then ({rows})->
        return rows

Within a transaction, calls to `bar` are in parallel, but the client request serializes them. The calls in other transactions proceed unimpeded (modulo
the database itself, if the transactions hold locks).

    bar = ->
      XRequest.client().then (client)->

    baz = ->
      xwrap ->
        # this creates a savepoint; if called outside a transaction
        # it would create a top-level transaction.
        XRequest().client().then (client)->
          ...
          throw new Error('Baz!')

# Motivation

Suppose you have been using a package that provides a reporting interface,
or an ORM, etc. If these packages don't use transactions, but use promises
which support the progress interface, you can continue using them without 
change.

# API Documentation

In the following, we assume

    xwrap = require 'xwrap'

### xwrap(options) -> xtransaction()

Initializes an xwrap session, passing back function used to wrap promise-
returning callbacks in  transactions. Xwrap supprts the following options:

* `adapter`: an adapter or the identifier for an adapter, which   wraps a
database connection. If `adapter` is an object with the `xwrap-adapter`
attribute,  then it is accepted as an adapter. If `adapter` is a string,
`xwrap` tries to load `adapter` package if `adapter` starts with
a "/", or the `xwrap-adapter` package otherwise. 

* `settings`: settings to initialize the adapter with. If the adapter
is already defined, these are ignored.

* `id`: optional identifier for the xwrap session. If passed, 
then requests for transactions can also pass `id` to request 
ID on right session. This mechanism allows multiple xwrap 
sessions (say, to multiple databases) to be active 
simultaneously.

* `wrap`: if `true` (default), and the adapter supports wrapping, the
underlying database connection will be wrapped. Calls using the database in
third-party code will retrieve proxies to clients in transactions if there is
a wrapping transaction in the call stack above them.

If `id` is specified, and there has already been an adapter by
that `id` defined, the other options are ignored.

The module initializer returns the `xtransaction` function, which provides
an interface to transaction for that adapter.

### xtransaction( [type], callback ) or xtransaction({type, callback, name})

The function passed back by `initialize` can be used to wrap
the activity of a promise-returning callback in a transaction.

Used without `type`, xwrap will create a top-level
transaction if there are no wrapping transactions (belonging
to the same session). Valid types are `xwrap.NEW` or `xwrap.SUB`
for explicit new and subtransactions.

The callback receives a `Transaction` object, which supports `client`
and `takeClient` calls directly.

Passing a hash allows specification of a name for the transaction,
which can be useful for logging and debugging.

For convenience, `transaction()` also contains the xwrap interface,
specialized to the particular adapter. For instance, `transaction.client()`
is the same as `xwrap.client(id)`.

### xwrap.client([id])

Returns promise of a shared client in the current transaction, if any is open.
If there are multiple databases open, `id` can be passed to specify which
database to use.

Note: a shared client is just a proxy around the client; to serialize
queries, use `then()` to wait for results before issuing a new query. Parallel use may result in interleaved queries. For example:

    Promise.map ['A', 'B'], (channel)->
      xwrap.client().then (client)->
        client.query("#{channel}1").then ->
          client.query("#{channel}2")

May result in either:

    A1
    A2
    B1
    B2

Or 

    A1
    B1
    A2
    B2

being executed. Of course (if the database driver is implemented correctly),
the right results should be returned to the right callbacks.

A shared client is useful for calls to third-party

### xwrap.takeClient([id]) -> Promise with client

This will checkout the client any the enclosing transaction

### xwrap.disconnect([id]) -> Promise

Instruct adapter to shut down and free underlying resources. Calls
to the xwrap interface after this completes may throw errors. What
happens to any open transactions is adapter dependent, but most
probably they will be rolled back.

### xwrap.wrap([id]) -> Promise

If the adapter supports wrapping, the underlying database connection
is wrapped, so that calls to retrieve database clients in 3rd party
code will retrieve client proxies in any wrapping transaction.

# Adapters

`xwrap` depends on a thin adapter around the underlying database,
which controls connecting to the database driver, and issuing transaction
start and stop commands.

All adapters must support the basic API, below. The "subtransaction"
extension, if present, allows xwrap to create subtransactions. The "wrap"
extension, if present, allows xwrap to inject a wrapper to allow all calls
in connected promise chains below xwrap transactions to participate
in transactions.

## Basic interface

### initialize(adapterSettings) -> adapter

The adapter module should include an `initialize` function,
which creates an adapter for the given settings and passes it back
synchronously.

After creation, xwrap sets the `id` and `xtransaction` attributes
of the adapter.

### Adapter.features

A hash, contain the features supported by the adapter. It should have
key "xwrap"; itself a hash containing keys:

* basic: true if supports basic interface
* subtransactions: true if supports subtransactions
* wrap: true if supports the wrap interface.
* clientMethods: list of method names of clients.
* clientDataAttributes: list of data attributes of clients.

On initialization, if or any of the keys first three keys are absent, 
`xwrap` will introspect the adapter and guess whether
it supports an API, and set the key itself. `clientMethods` and
`clientDataAttributes` are required in order to create proxies
for clients for shared access inside of transactions.

### Adapter.getClient() -> Promise of client

Returns a [disposer][1] with a checked out database client
for exclusive use of xwrap.

[1]: https://github.com/petkaantonov/bluebird/blob/master/API.md#disposerfunction-disposer---disposer)

### Adapter.openTransaction(client, name) -> Promise of adapter

Issue command to open a transaction on the client. `xwrap` will pass through a name given by a client, or use a random base64 string if
no name is given. Database adapters often don't need a name to
open a transaction, but if used, it should be quoted appropriately.

### Adapter.commitTransaction(client, name) -> Promise of adapter

Issue command to commit transaction on the client.

### Adapter.rollbackTransaction(client, name) -> Promise of adapter

Issue command to rollback transaction on the client.

### Adapter.disconnect() -> Promise

Disconnect client and free underlying resources. After this
is called, the adapter may return an error on any other call.

## Subtransaction Interface

### Adapter.openSubTransaction(client, name) -> Promise of adapter

Issue command to open subtransaction with given name on client. `xwrap` will pass through a name given by a client, or use a random base64 string if
no name is given. The command should quote the name appropriately.

### Adapter.commitSubTransaction(client, name) -> Promise of adapter

Issue command to commit subtransaction with given name on client. Name
should be quoted appropriately.

### Adapter.rollbackSubTransaction(client, name) -> Promise of adapter

Issue command to rollback subtransaction with given name on client. Name
should be quoted appropriately.

## Wrap interface

### Adapter.wrap(getClientCallback)  -> Promise of adapter

Wraps the underlying client retrieval methods in the database driver,
calling `getClientCallback` to get a transacction client instead. After
wrapping, other code will be able to participate in transactions opened
above them in the call stack without needing to interact with `xwrap`,
**as long as they (thuroughly) use transactions.** 

**Warning:** `xwrap` gets its clients from `adapter.getClient()` which
should maintain its connection to the underlying database regardless of
wrapping.


# Promises and Progress

## OH NO! Progress might be going away! Learn how xwrap works, and why progress is such a good idea.

# Testing

    npm test

will run mocha on the test files. `test-transactions-stub.litcoffee` tests that `xwrap` wraps
transactions successfully. `test-transactions.litcoffee` is conceived of as a test that allows
you to check that your adapter is correctly implemented, and your transactions are really ACID.
It needs a lot of work to be functional, still -- in particular it needs abstract methods
(instatiated per adapter) to test "doing something" with the database, and checking the
database state afterwards.

# Source Documentation

* [xwrap](./docs/xwrap.html)
