Test transactions
=================

    Promise = require 'bluebird'
    _ = require 'lodash'
    {mocha, should, sinon} = require './base'
    Schema = require( '../src/schema' ).Schema


    describe 'transactions on stub', ->
      schema = adapter = transaction = clients = null
      IMPLICIT = NEW = AUTO = null
      beforeEach ->
        schema = new Schema('stub', {})
        schema.connect().then ->
          {adapter, transaction} = schema
          {IMPLICIT, NEW, AUTO} = transaction
          clients = adapter.pool.resources
          spyClients(clients)

      afterEach ->
        schema.disconnect()

      it 'single query', ->
        schema.transaction NEW, ()->
          schema.adapter.query('Q1')
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'Q1', 'commit']

      it 'multiple queries', ->
        schema.transaction NEW, ()->
          Promise.map ("Q#{i}" for i in [1..5]), (q)->
            schema.adapter.query(q)
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands)
          commands.sort()
          commands.should.eql ['Q1', 'Q2', 'Q3', 'Q4', 'Q5']

      it 'nested transaction', ->
        name = null
        schema.transaction NEW, ()->
          schema.transaction (transaction)->
            name = transaction.name
            schema.adapter.query('Q1')
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands)
          commands = checkSavepoint(commands, name)
          commands.should.eql ['Q1']

Transactions in any order, will execute, interleaved, on both adapter clients.
However, the streams in the clients will have the transactions using that client
serialized, so that when we put the command streams together we have all the
transactions serialized.

      it 'multiple transactions', ->
        Promise.map [1..5], (i)->
          schema.transaction NEW, ()->
            schema.adapter.query("Q#{i}")
        .then ->
          commands0 = querySeq(clients[0].query)
          commands1 = querySeq(clients[1].query)
          # check that all weren't serialized on one client
          commands0.length.should.be.greaterThan 0
          commands1.length.should.be.greaterThan 0
          commands = commands1.concat(commands0)
          commits = splitArray(commands, 'commit')
          _.sortBy(commits, 1).map (commit, i)->
            checkCommit(commit).should.eql ["Q#{i+1}"]

Queries executed by "map" can be in any order, but "then" forces order.

      it 'sequential batches', ->
        schema.transaction NEW, ()->
          doQueries('P').then ->doQueries('Q')
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands)
          checkQueries(commands.slice(0,5), 'P', 5)
          checkQueries(commands.slice(5), 'Q', 5)

Create an overall transactions with a bunch of subtransactions which themselves
have subtransactions with multiple queries. Just for kicks, we throw in some
extra queries in the outer transaction. None of the groups is ordered, but the
heirarchy must be preserved in the executed queries.

Note that the extra queries can come on either side of the savepoint groups.

      it 'nested subtransactions', ->
        schema.transaction NEW, ()->
          Promise.join(
            doQueries('X'),
            doTransactions("XT", doTransactions))
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands)
          checkNestedSubtransactions(commands, 'X')

As above, except that we repeat everything in multiple top-level
transactions, which will themselves be overleaved accross the two clients.

      it 'multiple transactions, nested subtransactions', ->
        Promise.map [1..5], (i)->
          xprefix = "X#{i}"
          schema.transaction NEW, {name: xprefix}, ()->
            Promise.join(
              doQueries(xprefix),
              doTransactions("#{xprefix}T", doTransactions))
        .then ->
          commands = querySeq(clients[1].query)
          commands = commands.concat(querySeq(clients[0].query))
          commits = splitArray(commands, 'commit')
          commits = commits.map (commit)->
            commit = checkCommit(commit)
          commits = _.sortBy(commits, 0)
          commits.forEach (commit, i)->
            checkNestedSubtransactions(commit, "X#{i + 1}")

      checkNestedSubtransactions = (commands, prefix)->
        looseQueries = ("#{prefix}#{i}" for i in [1..5])
        popLoose = (q)->
          idx = looseQueries.indexOf(q)
          return false if idx == -1
          looseQueries.splice(idx, 1)
          return true
        for i in [1..5]
          commands.splice(0, 1) if popLoose(commands[0])
          commands.pop() if popLoose(commands.slice(-1)[0])
        looseQueries.length.should.equal 0
        relexp = new RegExp("release \"#{prefix}T\d\"$")
        commands = splitArray(commands, relexp)
        commands = _.sortBy(commands, 0)
        commands.forEach (sub, i)->
          sub = checkSavepoint(sub, "#{prefix}T#{i + 1}")
          srelexp = new RegExp("release \"#{prefix}T\d\d\"$")
          sub = splitArray(sub, srelexp)
          sub = _.sortBy(sub, 0)
          sub.forEach (ssub, j)->
            prefix = "#{prefix}T#{i + 1}#{j + 1}"
            ssub = checkSavepoint(ssub, prefix)
            checkQueries(ssub, prefix, 5)

      it 'single query with exception', ->
        schema.transaction NEW, ()->
          schema.adapter.query('Q1').then ->
            throw new Error('foo')
        .catch (foo)->
          foo.message.should.equal 'foo'
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'Q1', 'rollback']

      it 'single query with exception on begin', ->
        clients[1].query.restore()
        stub = sinon.stub(clients[1], 'query')
        stub.onCall(0).throws(new Error('foo')) 
        schema.transaction NEW, ()->
          schema.adapter.query('Q1')
        .catch (foo)->
          foo.message.should.equal 'foo'
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'rollback']

      it 'single query with exception on commit', ->
        clients[1].query.restore()
        stub = sinon.stub(clients[1], 'query')
        stub.onCall(2).throws(new Error('foo')) 
        schema.transaction NEW, ()->
          schema.adapter.query('Q1')
        .catch (foo)->
          foo.message.should.equal 'foo'
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'Q1', 'commit']

      it 'subtransaction with exception caught', ->
        schema.transaction NEW, {name: 'X'}, ()->
          schema.adapter.query('X1').then ->
            schema.transaction IMPLICIT, {name: 'sub'}, ()->
              schema.adapter.query('Q1').then ->
                err = new Error('fooInner')
                err.signed = 'unsigned'
                throw err
          .then ->
            throw new Error('Error not passed through')
          .catch (foo)->
            foo.signed.should.equal 'unsigned'
            foo.message.should.equal 'fooInner'
          .then ->
            return 'OK'
        .catch (err)->
          console.log('Outer: error', err)
          throw err
        .then (res)->
          res.should.equal 'OK'
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'X1', 'savepoint "sub"', 'Q1', 'rollback to "sub"', 'commit']        

      it.skip 'execute single autocommit', ->


Execute set of queries. 

      doQueries = (prefix = 'Q')->
        Promise.map ("#{prefix}#{i}" for i in [1..5]), (q)->
          schema.adapter.query(q)

Execute set of transactions.

      doTransactions = (prefix = 'T', callback = doQueries)->
        Promise.map [1..5], (i)->
          name = "#{prefix}#{i}"
          schema.transaction IMPLICIT, {name: name}, ()->callback(name)

Spy on calls to client query.

    spyClients = (clients)->
      clients.forEach (client)->
        sinon.spy(client, 'query')

Collapse sequence of calls to a query spy to an array of queries.

    querySeq = (querySpy)->
      [0...querySpy.callCount].map (i)->
        args = querySpy.getCall(i).args
        args.length.should.equal 1
        return args[0]

Checks that command sequence is wrapped in commit and passes back inner commands.

    checkCommit = (commands, end = 'commit')->
      commands[0].should.equal 'begin'
      commands.slice(-1)[0].should.equal end
      return commands.slice(1,-1)

Checks that command sequence is wrapped in savepoint and passes back inner commands

    checkSavepoint = (commands, savepoint, end = 'release')->
      commands[0].should.equal "savepoint \"#{savepoint}\""
      commands.slice(-1)[0].should.equal "#{end} \"#{savepoint}\""
      return commands.slice(1,-1)

Checks for sequence of queries in some order.

    checkQueries = (commands, prefix, nqueries)->
      commands.length.should.equal nqueries
      commands.sort()
      commands.should.eql ("#{prefix}#{i}" for i in [1..nqueries])

Splits an array on a given fragment of a string (e.g. "commit").

    splitArray = (a, s)->
      res = []
      j = 0
      for ai, i in a
        if ai.search(s) != -1
          res.push a.slice(j, i + 1)
          j = i + 1
      return res

