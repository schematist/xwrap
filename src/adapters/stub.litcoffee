Stub Adapter
=============

An adapter that stubs the adapter API for testing.

    Promise = require 'bluebird'
    AsyncPool = require 'async-pool'
    logger = (require 'logger-facade-nodejs').getLogger('xwrap')

    exports.initialize = (settings)->
      return new StubAdapter(settings)

    class StubAdapter

      constructor: (settings)->
        @settings = settings
        @pool = new AsyncPool([new StubClient('A'), new StubClient('B')])

      query: (text)->
        Promise.using @xtransaction.client(), (client)->
            client.query(text)

Get a client. Use with `Promise.using` in order to ensure client is
put back properly.

      getRawClient: ()->
        @pool.use()

      enableTransactions: ()->
        @transactionsEnabled = true

      disableTransactions: ()->
        @transactionsEnabled = false

      openTransaction: (client)->
        client.query('begin')

      openSubTransaction: (client, name)->
        client.query("savepoint \"#{name}\"")

      commitTransaction: (client)->
        client.query("commit")

      commitSubTransaction: (client, name)->
        client.query("release \"#{name}\"")

      rollbackTransaction: (client)->
        client.query("rollback")

      rollbackSubTransaction: (client, name)->
        client.query("rollback to \"#{name}\"")

    class StubClient

      constructor: (name)->
        @name = name

      query: (text)->
        logger.trace("query client #{@name}: #{text}")
        new Promise (res)->
          setTimeout ->
            res()
          , 1


[**Home**](./index.html)
