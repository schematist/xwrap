Transaction
===========

Wrap database usage in a transaction.

The callback is wrapped in a function that sets transaction on 
promise excepting thenable returned by callback.

The callback is passed a transaction object, which can be used
as a database client for low-level operations.

The function can be used in one of three ways:

1. Implicit transaction: call with only callback. If this is
outer level, a new transaction will be created.

2. Explicit transaction: call with (tranaction, callback) --
callback will be executed in context of transaction.

3. Explicit NEW transaction: call with (NEW, callback)

4. Explicit NO transaction (autocommit): call with (AUTO, callback).
  Note: (undefined, callback) will be interpreted
  as implicit transaction.


## Implementation of nested transactions

When one call to open a transaction is nested inside another, the inner
call should not open a new transaction, but should reuse the same
transaction as the outer. (In the future, we may implement issuing
savepoint open/close for nested transaction calls.)

To facilitate this, we keep a list of open transactions. If a
transaction is opened when another is already opened, we do not
send transaction via "progressed" in case it is being sent by
outer transaction.

This means that transactions that are not explicitly top-level
will be serialized. **WARNING** If there is some other mechanism 
that prevents the first transaction from finishing until a subsequent
implicit transaction a deadlock will ensue. Better to use
explicit transactions where possible. If every chain is headed
by an explicit transaction (possibly an explicitly null transaction),
then all will be well.

---

    Promise = require 'bluebird'
    _ = require 'lodash'
    psbytes = Promise.promisify(require('crypto').pseudoRandomBytes)
    _ENCLOSING = ->
    TransactionRequest = require './transaction'
    { NEW, AUTO, IMPLICIT, 
      BASIC_INTERFACE, SUBTRANSACTION_INTERFACE} = TransactionRequest
    GLOBAL_TIMEOUT = null #10000
    MAX_REQUEST_IN_TRANSACTION = 1000 * 10
    TICKER_REPEAT = 1000 * 5

    AsyncPool = require 'async-pool'

    makeWithTransaction = (adapter)->

      if !supportsTransactions(adapter)
        return ->
          debugger
          throw new Error("Adapter #{adapter.name} does not support transactions.")

Transaction provides an interface to interact with the database
within a database transaction block.

Transactions have five states:

  * implicit: may or may not be included in another enclosing transaction.

  * prepared: is outer transaction; doesn't have client allocated.

  * merged: inner transaction, waiting with outer to give it client

  * executing: is executing with client

  * complete: is finished execution.

When an implicit transaction is created, it is unknown whether its
inside another transaction. 

## Implementation

**TODO**

## WARNING

**TODO** "autocommit" is not currently implemented.

---

      class Transaction

List of explicit transactions currently processing.

        @processing = {}

List of implicit transactions waiting to see if enclosed.

        @implicit = []

List of unanswered transaction requests waiting to see if enclosed.

        @unanswered = []

        constructor: (callback)->
          @state = 'initial'
          @subtransactions = []
          @callback = callback
          @client = null
          @isSubtransaction = false
          @adapter = adapter

Start the transaction up -- depending on the type.

        start: (transactionType, options)->
          self = this
          Promise.resolve(options.name).then (name)->
            return name if name
            psbytes(12).then (buf)->buf.toString('base64')
          .then (name)->
            console.log("START", name.slice(0, 4))
            self.name = name

            switch transactionType
              when IMPLICIT then self.startImplicit()
              when NEW then self.create()
              when AUTO then self.createAutocommit()
              when transactionType instanceof Transaction
                self.merge(transactionType)
              else
                throw new Error("unknown transaction type #{transactionType}")

Start an implicit transaction. 

If there are no processing transactions, we convert to an explicit top-level
transaction. Otherwise, we wait to be told what our enclosing transaction is --
either some other transaction, in which case we become a sub-transaction, or
nothing, in which case we become a top-level transaction.

We save implicit transactions on a queue, so that first waiter can be
promoted when all top-level transactions have finished processing.

        startImplicit: ()->
          if _.size(Transaction.processing) == 0
            @create()
          else
            @state = 'implicit'
            self = this
            Transaction.implicit.push self
            @promise = TransactionRequest.ask({adapter}, self.name)
            .finally ->
              return unless self.state == 'implicit'
              Transaction.implicit.splice(
                Transaction.implicit.indexOf(self), 1)
            .then (transaction)->
              return unless self.state == 'implicit'
              return self.merge(transaction) if transaction?
              self.create()
            return @promise

Start top-level transaction.

Put ourselves on the global processing list so new implicit transactions
know they might be told they are subordinate. Then we get a client
from the adapter and execute the transaction.

**TODO** The Following Still Not Working (code in comment)

Also check that we aren't wrapped by another transaction: we listen
for an enclosing transaction and reject if one replies. In theory
this mechanism might not be successful, as reply could come after
we have completed. In practice, however, the only delay in getting
a transaction is a `process.nexttick` call to allow enclosing (but
synchronous) time to register `progressed` handler. If we do any
asynchronous operation at all, we should receive word of enclosing
transaction before we complete.

        create: ()->
          @state = 'prepared'
          self = this
          Transaction.processing[self.name] = self
          return Promise.using adapter.getClient(), (client)->
              self.execute(client)
          ###
          return Promise.any([
            (Promise.using adapter.getClient(), (client)->
              self.execute(client)),
            requestTransaction(self.name).then (transaction)->
              _ENCLOSING.name = tranaction.name
              return _ENCLOSING
          ]).then (res)->
            if res == _ENCLOSING
              delete Transaction.processing[self.name]
              name = _ENCLOSING.name
              throw new Error(
                "Cannot start top-level transaction in enclosing transaction #{name}")
            return res
          ###

Start subordinate transaction. *** We need to wait for enclosing
to be in right state!

        merge: (enclosingTransaction)->
          @state = 'merged'
          #console.log("#{@name.slice(0,4)} MERGE WITH #{enclosingTransaction.name.slice(0.4)}")
          self = this
          @isSubtransaction = true
          Promise.using enclosingTransaction.getClient(), (client)->
            self.execute(client)

Execute the transaction.             

        execute: (client)->
          @state = 'executing'
          self = this
          @client = new AsyncPool([client])
          self.openTransaction().then ->
            TransactionRequest.handleRequest(
              self, self.callback(self), {adapter: adapter.toString()})
          .catch (err)->
            # NB: either way this throws an error so commit() not called
            self.rollback().then ->
              throw err
          .then (res)->
            self.commit().then ->
              return res

On completion, take self off stack of processing transactions.
If there are no transactions currently processing, then first
implicit transaction must in fact not be wrapped, so tell it so.

**TODO** this assumes that outer must be created before inner, which
is probably correct but seems suspicious. Also, many transactions
may have to wait unnecessarily as we don't know relation between implicit.

        complete: ()->
          @state = 'completed'
          delete Transaction.processing[@name]
          @client = null          
          if _.size(Transaction.processing) > 0
            return

          implicit = Transaction.implicit.shift()
          if implicit?
            TransactionRequest.handleRequest null, implicit.promise,
              adapter: adapter
          else
            while Transaction.unanswered.length > 0
              request = Transaction.unanswered.pop()
              request.fulfill(null)
          
Open transaction or subtransaction on adapter. 

If this is a subtransaction and the adapter does not support subtransactions,
this is a noop.

        openTransaction: ()->
          Promise.using @getClient(), (client)=>
            if @isSubtransaction
              if adapter.features.transactions.subtransactions
                adapter.openSubTransaction(client, @name)
            else
              adapter.openTransaction(client)

Commit transaction or sub-transaction on adapter.

If this is a subtransaction and the adapter does not support subtransactions,
this is a noop.

        commit: ()->
          Promise.using( @getClient(), (client)=>
            if @isSubtransaction
              if adapter.features.transactions.subtransactions
                adapter.commitSubTransaction(client, @name)
            else
              adapter.commitTransaction(client)
          ).finally =>
            @complete()

Commit transaction or sub-transaction on adapter.

If this is a subtransaction and the adapter does not support subtransactions,
this is a noop.

        rollback: ()->
          Promise.using( @getClient(), (client)=>
            if @isSubtransaction
              if adapter.features.transactions.subtransactions
                adapter.rollbackSubTransaction(client, @name)
            else
              adapter.rollbackTransaction(client)
          ).finally =>
            @complete()

Get the transaction client. Wrap in `Promise.using` to ensure that
transaction gets client back when you are through!

        getClient: (name)->
          if @state != 'executing'
            return Promise.reject new Error(
              'Cannot get client from non-executing transaction.')
          console.log('taking client:', name)
          return @client.use()

Main interface -- see above.

      transaction = (transactionType, options, callback)->
        if !callback?
          if !options?
            callback = transactionType
            transactionType = IMPLICIT
            options = {}
          else 
            callback = options
            if typeof options == 'object'
              options = transactionType
              transactionType = options.type ? IMPLICIT
            else
              options = {}

        newTransaction = new Transaction(callback)
        return newTransaction.start(transactionType, options)
      transaction.adapter = adapter


Set unanswered request handler: if there are no transaction,
return null. Otherwise, queue up in case requester is
inside and hasn't got news yet.

      TransactionRequest.handleUnanswered = (request)->
        if !request.deferred?.promise.isPending()
          console.log("unhandled, not pending:", request.name ? '????')
          return 
        if _.size(Transaction.processing) > 0 || Transaction.implicit.length > 0
          Transaction.unanswered.push request
          if GLOBAL_TIMEOUT?
            setTimeout ->
              if request.deferred?.promise.isPending()
                console.log("UNANSWERED TRANSACTION REQUEST")
                request.reject new Error("Couldn't handle unanswered transaction request")
            , GLOBAL_TIMEOUT            
          else
            check = ->
              setTimeout ->
                if !request.deferred?.promise.isPending()
                  _.remove(Transaction.unanswered, (i)-> i == request)
                else
                  check()
              , 1000
            check()

        else
          console.log("no transactions: fulfill with null")
          request.fulfill(null)

Writes a periodic count of transaction status for debugging.

      deathticks = MAX_REQUEST_IN_TRANSACTION / TICKER_REPEAT
      transactionTicker = (repeat)->
        old = []
        tick = ->
          setTimeout ->
            str = (list)->
              list.map (i)->i.name?.slice(0, 4) ? '????'
              .join ' '
            processing = str(_.values(Transaction.processing))
            implicit = str(Transaction.implicit)
            requests = str(Transaction.unanswered)
            console.log("Transactions: PRC: #{processing} " + 
              "IMP: #{implicit} REQ: #{requests}")
            Transaction.unanswered.slice().map (r, i)->
              if !r.deferred?.promise.isPending()
                Transaction.unanswered.splice(i, 1)
                return
              oi = _.findIndex old, (o)->o.request == r
              if oi != -1
                o = old[oi]
                o.ticks += 1
                if o.ticks > deathticks
                  o.request.reject new Error('Waited too long')
                  old.splice(oi, 1)
              else
                old.push { request: r, ticks: 0 }
            tick()
          , repeat
        tick()
      transactionTicker(TICKER_REPEAT)
        
      return transaction


Check whether adapter supports transactions and subtransactions.

If the adapter declares support, believe it. Otherwise set support
based on presence of interface.

    supportsTransactions = (adapter)->
      adapter.features ?= {}
      support = (adapter.features.transactions ?= {})
      _supports = (fcts)->
        fcts.reduce (a, fct)->
          a and typeof adapter[fct] == 'function'
        , true
      support.basic ?= _supports(BASIC_INTERFACE)
      support.subtransactions ?= _supports(SUBTRANSACTION_INTERFACE)
      return support.basic


    module.exports = (adapter)->
      transaction = makeWithTransaction(adapter)
      transaction.IMPLICIT = IMPLICIT
      transaction.NEW = NEW
      transaction.AUTO = AUTO
      return transaction
