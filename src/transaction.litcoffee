Transaction 
============

Public interfact to transactions. Use as:

> transaction = require 'schematist/transaction'
> transaction().then (transaction)->
>    ...
    
Marking transaction requests so they can be identified.

Mark a function as a TransactionRequest, so that transaction progressed
handler can identify legitimate requests. 

    Promise = require 'bluebird'
    _ = require 'lodash'
    IMPLICIT = 'IMPLICIT'
    NEW = 'NEW'
    AUTO = 'AUTOCOMMIT'
    BASIC_INTERFACE = [
      'getClient', 'enableTransactions', 'disableTransactions'
      'openTransaction', 'commitTransaction', 'rollbackTransaction' ]
    SUBTRANSACTION_INTERFACE = [ 
      'openSubTransaction', 'commitSubTransaction', 'rollbackSubTransaction' ]

Represents transaction requensts and provides a static interface for responses.
To make a request, call `TransactionRequest.ask()`  Ask takes an optional hash;
if you want to request a transaction on a particular database adapter, call
``TransactionRequest.ask({adapter: adapter})`.

The transaction class itself, will call fulfillTransaction,
and pass in another hash. If objects under matching keys are
identical, the transaction request is fulfilled. 

The base implementation supports the `adapter` keyword, but
other implementers could override this.

When a transaction request receives no immediate response,
the global handler is called. By default, it passes back "null",
but the base implementation overrides this to wait further
if there are any outstanding transactions.

    class TransactionRequest 

Wrapper around `new Request`, then `getTransaction`

      @ask: (onWhat, name)->
        if !name?
          throw new Error('provide name')
        (new TransactionRequest onWhat, name).getTransaction()

      constructor: (@onWhat, @name)->

Returns a promise with the transaction.

      getTransaction: ()->
        self = this
        @deferred = d = Promise.defer()
        console.log("ASK", @name ? '')
        process.nextTick ->
          d.progress self
          process.nextTick ->
            if d.promise.isPending()
              TransactionRequest.handleUnanswered(self)
        err = new Error("cancelled")
        return d.promise.catch (cerr)->
          err.cancel = cerr
          throw err


Called by the transaction progress handler to pass back
the transaction.

      fulfill: (transaction)->
        if @deferred?.promise.isPending()
          console.log("FULFILL #{@name} by:", transaction?.name.slice(0,4))
          @deferred.resolve(transaction)
          delete @deferred

In case a progress handler wants to abort (e.g. stuck transaction timeout).

      reject: (reason)->
        if @deferred?.promise.isPending()
          @deferred.reject(reason)
          delete @deferred

Progres handler used by transaction to listen to and
fulfill requests. `transaction` should be the current transaction.
`promise` should be the promise we are wrapping in which
to fulfill transaction requests. `onWhat`, if passed,
will be used to match requests. 

      @handleRequest: (transaction, promise, onWhat)->
        console.log("HANDLE BY", transaction.name.slice(0,4))
        if !promise? or !promise.progressed?
          throw new Error("Cannot pass transaction: no promise; got #{promise}")

        promise.progressed (request)->
            # unwrap -- annoying oddity
          while request.value?
            request = request.value
          if !(request instanceof TransactionRequest)
            return
          if onWhat?
            for key, value of onWhat
              if request.onWhat?[key] == value
                request.fulfill(transaction)
                throw {name:'StopProgressPropagation'}
            console.log("REQ-#{request.name} NOT ON WHAT", transaction.name.slice(0,4))
            debugger
            return
          else
            request.fulfill(transaction)

          # undocumented; in bluebird/progress.js...
          throw {name:'StopProgressPropagation'}
        return promise

      @handleUnanswered = (request)->
        debugger
        request.fulfill(null)

Call callback with client from current transaction. (Convenience method.) 

If there is no transaction, callback is called with client from
adapter if optional adapter is provided, or `null` if not.c.
As a debugging aid, a request label (`name`) can be provided.

    useTransactionClient = (callback, adapter, name)->
      TransactionRequest.ask(adapter: adapter.toString(), name)
      .then (transaction)->
        if transaction?
          Promise.using( transaction.getClient(), callback )
        else if adapter?
          console.log('no transaction -- using adapter client')
          Promise.using( adapter.getClient(), callback )
        else
          console.log('no transaction & no adapter')
          callback(null)

    module.exports = _.extend TransactionRequest, {
      useTransactionClient, 
      NEW, AUTO, IMPLICIT, BASIC_INTERFACE, SUBTRANSACTION_INTERFACE
    }