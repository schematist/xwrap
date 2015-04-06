# XWrap Request

A `Request` transaction requensts and provides a static interface for responses.
To make a request, call `Request.ask()`  Ask takes an optional hash;
if you want to request a transaction on a particular database adapter, call
``Request.ask({adapter: adapter})`.

The transaction class itself, will call fulfillTransaction,
and pass in another hash. If objects under matching keys are
identical, the transaction request is fulfilled. 

The base implementation supports the `adapter` keyword, but
other implementers could override this.

When a transaction request receives no immediate response,
the global handler is called. By default, it passes back "null",
but the base transaction implementation overrides this to wait further
if there are any outstanding transactions.

    Promise = require 'bluebird'
    __requestNumber = 0

    class Request 

Wrapper around `new Request`, then `getTransaction`

      @ask: (id, name)->
        (new Request id, name).getTransaction()

Get a shared client in a transaction.

      @client: (id, name)->
        return Request.ask(id, name).then (transaction)-> 
          transaction.client()

Checkout client from transaction.

      @takeClient: (id, name)->
        return Request.ask(id, name.then) (transaction)->
          transaction.takeClient()

      constructor: (@id, @name)->
        __requestNumber += 1
        @name = "?#{__requestNumber}" if !@name?

Returns a promise with the transaction.

Sends self as progress; transaction will call `fulfill` where the 
a progress handler handles and resolves the promise with the transaction.

The call to `fulfill` takes place after `getTransaction`, but is
still synchronous. So if we delay one tick we should be assured of
receiving transaction if it exists. Thus, if we wait one tick more
and still haven't got a transaction, we assume there is no wrapper.

      getTransaction: ->
        self = this
        @deferred = d = Promise.defer()
        Request.logger.debug("ASK #{@name}")
        process.nextTick ->
          Request.logger.debug("(ASK UP)")
          d.progress self
          process.nextTick ->
            Request.logger.debug("(ASK UNA)")
            if d.promise.isPending()
              Request.handleUnanswered(self)

        # create error so we can capture the "getTransaction"
        # stack trace in case handler causes us to reject.
        err = new Error("cancelled")
        return d.promise.catch (cerr)->
          err.cancel = cerr
          throw err

Called by the transaction progress handler to pass back
the transaction.

      fulfill: (transaction)->
        if @deferred?.promise.isPending()
          Request.logger.debug(
            "FULFILL #{@name} by:", transaction?.name.slice(0,4))
          @deferred.resolve(transaction)
          delete @deferred

In case a progress handler wants to abort (e.g. deadlock stuck transaction
timeout). Currently not used, but could be useful as the transaction
manager might be able to detect some resource contention that the database
might not be aware of.

      reject: (reason)->
        if @deferred?.promise.isPending()
          @deferred.reject(reason)
          delete @deferred

Progres handler used by transaction to listen to and
fulfill requests. `transaction` should be the current transaction.
`promise` should be the promise we are wrapping in which
to fulfill transaction requests. `id`, if passed,
will be used to match requests. 

      @handle: (transaction, promise, id)->
        Request.logger.debug("HANDLE BY", transaction.name.slice(0,4))
        if !promise? or !promise.progressed?
          throw new Error("Cannot pass transaction: no promise; got #{promise}")

        promise.progressed (request)->
          # unwrap -- annoying oddity
          while request.value?
            request = request.value
          if !(request instanceof Request)
            return
          if !id? or !request.id? or request.id == id
             request.fulfill(transaction)
             throw {name:'StopProgressPropagation'}

          Request.logger.debug(
            "REQ-#{request.name} doesn't match", transaction.name.slice(0,4))
          return
        return promise

Handle unanswered by passing a null transaction. This could be a useful
default, but currently is overridden by the transaction manager.

      @handleUnanswered = (request)->
        debugger
        request.fulfill(null)

    module.exports = Request

[**Home**](./index.html)
