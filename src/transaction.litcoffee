Transaction
============

A transaction, which wraps database usage in transaction start and
either commit or rollback signals.


Represents a transaction, which can exist in several states:

  * implicit: may or may not be included in another enclosing transaction.

  * prepared: is outer transaction; doesn't have client allocated.

  * merged: inner transaction, waiting with outer to give it client

  * executing: is executing with client

  * complete: is finished execution.

When an implicit transaction is created, it is unknown whether its
inside another transaction. 

    Promise = require 'bluebird'
    _ = require 'lodash'
    Request = require './request'
    psbytes = Promise.promisify(require('crypto').pseudoRandomBytes)
    { NEW, SUB, AUTO, IMPLICIT, 
      GLOBAL_TIMEOUT, MAX_REQUEST_IN_TRANSACTION
      TICKER_REPEAT
    } = require './constants'
    AsyncProxyPool = require 'async-proxy-pool'

    class Transaction

List of explicit transactions currently processing.

      @processing = {}

List of implicit transactions waiting to see if enclosed.

      @implicit = []

List of unanswered transaction requests waiting to see if enclosed.

      @unanswered = []

      constructor: ({@callback, name, @adapter, @id})->
        @name = name
        @state = 'initial'
        @subtransactions = []
        @_client = null
        @isSubtransaction = false

Start the transaction up -- depending on the type.

      start: (transactionType)->
        self = this
        Promise.resolve(@name).then (name)->
          return name if name
          psbytes(12).then (buf)->buf.toString('base64')
        .then (name)->
          Transaction.logger.debug("START", name.slice(0, 4))
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
          @promise = Request.ask({@adapter}, self.name)
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
        return Promise.using @adapter.getClient(), (client)->
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

Start subordinate transaction. Note that we use `takeClient` so that
enclosing transaction cannot interleave other queries.

      merge: (enclosingTransaction)->
        @state = 'merged'
        Transaction.logger.debug("#{@name.slice(0,4)} MERGE WITH #{enclosingTransaction.name.slice(0.4)}")
        self = this
        @isSubtransaction = true
        Promise.using enclosingTransaction.takeClient(@name), (client)->
          self.execute(client)

Execute the transaction.             

      execute: (client)->
        @state = 'executing'
        self = this
        {clientMethods, clientDataAttributes} = @adapter.features.xwrap
        @_client = new AsyncProxyPool(
          [client], clientMethods, clientDataAttributes)
        self.openTransaction().then ->
          Request.handle(
            self, self.callback(self), self.adapter.id)
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
        @_client = null          
        if _.size(Transaction.processing) > 0
          return

        implicit = Transaction.implicit.shift()
        if implicit?
          Request.handleRequest null, implicit.promise,
            adapter: @adapter
        else
          while Transaction.unanswered.length > 0
            request = Transaction.unanswered.pop()
            request.fulfill(null)
        
Open transaction or subtransaction on adapter. 

If this is a subtransaction and the adapter does not support subtransactions,
this is a noop.

      openTransaction: ()->
        Transaction.logger.debug("OPEN TR", @name.slice(0,4))
        Promise.using @takeClient(@name), (client)=>
          Transaction.logger.trace("OPEN: Got client", client.name)
          if @isSubtransaction
            if @adapter.features.xwrap.subtransactions
              @adapter.openSubTransaction(client, @name)
          else
            @adapter.openTransaction(client)

Commit transaction or sub-transaction on adapter.

If this is a subtransaction and the adapter does not support subtransactions,
this is a noop.

      commit: ()->
        Promise.using( @takeClient(@name), (client)=>
          if @isSubtransaction
            if @adapter.features.xwrap.subtransactions
              @adapter.commitSubTransaction(client, @name)
          else
            @adapter.commitTransaction(client)
        ).finally =>
          @complete()

Commit transaction or sub-transaction on adapter.

If this is a subtransaction and the adapter does not support subtransactions,
this is a noop.

      rollback: ()->
        Promise.using( @takeClient(@name), (client)=>
          if @isSubtransaction
            if @adapter.features.xwrap.subtransactions
              @adapter.rollbackSubTransaction(client, @name)
          else
            @adapter.rollbackTransaction(client)
        ).finally =>
          @complete()

Get the transaction client. Wrap in `Promise.using` to ensure that
transaction gets client back when you are through!

      takeClient: (name)->
        if @state != 'executing'
          return Promise.reject new Error(
            'Cannot get client from non-executing transaction.')
        Transaction.logger.debug('taking client:', name)
        return @_client.use()

Get a shared proxy for the transaction client.

      client: (name)->
        if @state != 'executing'
          return Promise.reject new Error(
            'Cannot get client from non-executing transaction.')
        Transaction.logger.debug('sharing client:', name)
        return @_client.share()

---------------------------------------------------------------------

Set unanswered request handler: if there are no transaction,
return null. Otherwise, queue up in case requester is
inside and hasn't got news yet.

      Request.handleUnanswered = (request)->
        if !request.deferred?.promise.isPending()
          Request.logger.debug("unhandled, not pending:", request.name ? '????')
          return 
        if _.size(Transaction.processing) > 0 || Transaction.implicit.length > 0
          Transaction.unanswered.push request
          if GLOBAL_TIMEOUT?
            setTimeout ->
              if request.deferred?.promise.isPending()
                Request.logger.error("UNANSWERED TRANSACTION REQUEST")
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
          Request.logger.info("no transactions: fulfill with null")
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
            Request.logger.info("Transactions: PRC: #{processing} " + 
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


    module.exports = Transaction

[**Home**](./index.html)
    