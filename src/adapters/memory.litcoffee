Memory Adapter
==============

A local memory adapter for testing.

The adapter stores a hash of objects and a hash of transactions. Each
transaction is another memory adapter. When an object is used in the
transaction, the object is locked by having its key changed to point to the
transaction rather than the object, and the object is put in the transactions
objects. 

When an object is set that is already in a transaction, the
call blocks, and its promise is put in a queue to be released
when that transaction continues.

When the transaction commits or rolls back, the queue is released. 

    Promise = require 'bluebird'
    AsyncPool = require 'async-pool'

    label = ->
      psbytes(9).then (bytes)->bytes.toString('base64')

    class Deadlock
      constructor: (@message) ->
        @name = "Deadlock"
        Error.captureStackTrace(this, Deadlock)

Memory adapter represents both underlying key/value store, and a transaction.
Aside from transaction public interface is just `get` and `set`. A memory
adapter should be given a unique name. The 

    class MemoryAdapter

      constructor: (@options, @insideOf)->
        @name = options?.name ? 'memory'
        @objects = {}
        @nclients = @options?.nclients ? 2
        @waiting = []
        @transactionsWaiting = {}
        @clients = AsyncPool (
          new MemoryClient(this, i) for i in [1..@nclients])

Get the value for `key`, or `undefined` if it hasn't been set.

If it is inside the transaction already, it may have been taken by a sub-
transaction. If so, wait for it, and return when that commits.

If it is not in transaction check for it from super transaction, and return
that value (after possibly having waited for it), including it in the
transaction as well.

      get: (key)->
        current = @objects[key]
        current = @objects[key]
        if current instanceOf MemoryAdapter
          return current._addWaiting {
            op: 'set', transaction: this,
            key: key
          }
        if @insideOf?
          return insideOf.get(key).bind(this).then (value)->
            @objects[key] = value
            return value
        return Promise.resolve().delay().then -> undefined

Set `value` for `key`.

If we are inside another transaction, lock key in that transaction first,
then set in this transaction, possibly after waiting for subtransaction.

      set: (key, value)->
        Promise.resolve().bind(this).then ->
          if @insideOf?
            @insideOf.set(key, this)
        .then ->
          current = @objects[key]
          if current instanceOf MemoryAdapter
            return current._addWaiting {
              op: 'set', transaction: this,
              key: key, value: value
            }
          else
            @objects[key] = value
            return Promise.resolve().delay().then ->this

Add an operation waiting for this transaction to commit. Besides putting
on the queue, we compile the complete list of transactions waiting
and check if we aren't waiting on ourselves indirectly. If we are, return
a rejected promise (deadlock). Otherwise return promise that resolves
to the result of the operation, to be triggered when we commit.

      _addWaiting: (opHash)->
        transaction = opHash.transaction
        _deadlock = ->
          Promise.throws new Deadlock(
            "#{transaction.name} and #{@name} wait for each other")
        if transaction.name == @name
          return _deadlock()
        for name of transaction.transactionsWaiting
          if name == @name
            _deadlock()
        # merge as separate pass so state clean if deadlock handled
        for name of transaction.transactionsWaiting
          @transactionsWaiting[name] = true
        @waiting.push opHash
        return Promise.resolve().delay().then ->this

      _releaseWaiting: ()->
        Promise.resolve(opHash).bind(this).map ({op, key, value, transaction})->
          transaction[op](key, value)
        .then ->
          return this

---------------------------------

## Transaction interface

      getRawClient: ()->
        return @clients.use()

      openTransaction: (client, name)->
        name ?= "#{@name}-#{client.name}"
        @transactions.push = transaction = new MemoryAdapter({name: name})
        client.transactions.push transaction
        return Promise.resolve(this)

      commitTransaction: (client)->
        transaction = client.transactions.pop()
        return Promise.resolve(this) if !transaction?
        Promise.resolve(Object.keys(transaction)).bind(this).map (k)->
          @set k, transaction[k]
        .then ->
          transaction._releaseWaiting()

      rollbackTransaction: (client)->
        transaction = client.transactions.pop()
        return Promise.resolve(this) unless transaction?
        return transaction._releaseWaiting()

## Subtransaction interface

      openSubTransaction: (client, name)->
        @openTransaction(client, name)

      commitSubTransaction: (client, name)->
        @commitTransaction(client, name)

      rollbackSubTransaction: (client, name)->
        @commitTransaction(client, name)

## Wrapping interface

      wrap: ()->
        @get = (key)->
          Promise.using xwrap.client(), (client)->
            client.get(key)

        @set = (key, value)->
          Promise.using xwrap.client(), (client)->
            client.set(key, value)

    class MemoryClient

      constructor: (@adapter, @n)->
        @transactions = []

      get: (key)->
        transaction = @transactions.slice(-1)[0]
        if transaction?
          value = transaction.get(key)


      set: (key, value)->
        transaction = @transactions.slice(-1)[0] ? @adapater
        transaction.set(key, value)

Build and return an adapter asynchronously.

    initialize = (options)->
      return Promise.resolve new MemoryAdapter(options)
    exports.initialize = initialize
