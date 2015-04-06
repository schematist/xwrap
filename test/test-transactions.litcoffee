Test transactions
=================

These tests are indended to test an adapter, passing if the wrapped 
transactions are ACID. It needs much work.

    Promise = require 'bluebird'
    _ = require 'lodash'
    {should, sinon, logger} = require './base'
    xwrap = require '../src/xwrap'

    spies = {}
    db = null
    Post = null
    describe 'transactions', ->
      adapter = xtransaction = clients = query = null
      IMPLICIT = NEW = AUTO = null

Start adapter and create a model. Skip suite if tranactions aren't  supported by
the adapter. Otherwise instrument adapter transaction interface.

      before ->
        {xtransaction, query} = global.getXWrap()      
        {IMPLICIT, NEW, AUTO, adapter} = xtransaction

        if !adapter.features.xwrap.basic
          return @skip()
        instrumentAdapter(adapter)

Remove spies from adapter after all tests complete.

      after: ()->
        _.mapValues spies, (spy)->
          spy.restore()

      describe 'basic', ->
        beforeEach ->
          if !adapter.features.transactions.basic
            @skip()
          logger.trace("RESET")
          resetSpies()

        it.skip 'wraps database use in transaction open/close', ->
          getSpyTransaction (client)->
            logger.trace('create')
            query(client, 'create')
          .then (client)->
            checkTransactionWrapped(client)

        it.skip 'reveals created objects inside before commit', ->

        it.skip 'hide created object from outside before commit', ->

        it.skip 'removes created object on rollback', ->

        it.skip 'allows separate transactions to proceed in parallel', ->

      describe 'sub-transactions', ->
        beforeEach ->
          if !db.features.transactions.subtransactions
            @skip()

        it.skip 'wraps database use in subtransaction open/close', ->

        it.skip 'removes create object on rollback', ->

        it.skip 'leaves object in transaction but not subtransaction on rollback', ->

        it.skip 'serializes subtransaction of single transaction', ->

    getSpyClient = (callback)->
      client = null
      db.transaction NEW, (transaction)=>
        spies.trClient = sinon.spy transaction, 'getClient'
        Promise.using transaction.getClient(), (c)->
          client = c
        .then ->
          callback(c)
        .then ->
          return client 

    instrumentAdapter = (adapter)->
      _.flatten([BASIC_INTERFACE, SUBTRANSACTION_INTERFACE]).map (method)->
        spies[method] = sinon.spy(adapter, method)
      spies.query = sinon.spy(adapter, 'query')

    resetSpies = ()->
      if spies.trClient?
        spies.trClient.restore()
        delete spies.trClient
      _.mapValues spies, (spy)->
        spy.reset()

Check that client calls are wrapped by open/close transaction.

We check that the adapter has only been asked once for a cilent, that
this was the same client that the transaction has, that that open and 
close have been called, and that the transaction itself has only
been asked for a client between open and close of transaction.

**TODO** this seems to check more and less than it should. I have
not yet found a suitably abstract way to make sure that transaction
protocol is followed.

    checkTransactionWrapped = (client, committed = true)->
      spyPromiseValue = (spy, n)->
        spies[spy].returnValues[n]._promise.value()

      spies.getClient.should.have.been.calledOnce
      spyPromiseValue('getClient', 0).should.equal client
      spies.openTransaction.should.have.been.calledOnce
      spies.openTransaction.should.have.been.calledWith(client)
      if committed
        closeSpy = spies.commitTransaction
      else
        closeSpy = spies.rollbackTransaction
      closeSpy.should.have.been.calledOnce
      closeSpy.should.have.been.calledWith(client)

      trClient = spies.trClient
      [0...trClient.callCount].map (i)->
        spyPromiseValue('trClient', i).should.equal client

[**Home**](./index.html)
