Test transactions
=================

    Promise = require 'bluebird'
    _ = require 'lodash'
    {mocha, should, sinon, logger} = require './base'
    xwrap = require '../src/xwrap'


    describe 'transactions on stub', ->
      adapter = xtransaction = clients = null
      IMPLICIT = NEW = AUTO = null
      beforeEach ->
        xtransaction = xwrap({adapter: 'stub'})
        {IMPLICIT, NEW, AUTO, adapter} = xtransaction
        clients = adapter.pool.resources.slice()
        spyClients(clients)

      afterEach ->
        xwrap.disconnect()

      it 'single query', ->
        xtransaction NEW, ()->
          xtransaction.adapter.query('Q1')
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'Q1', 'commit']

      it 'multiple queries', ->
        xtransaction NEW, ()->
          Promise.map ("Q#{i}" for i in [1..5]), (q)->
            xtransaction.adapter.query(q)
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands)
          commands.sort()
          commands.should.eql ['Q1', 'Q2', 'Q3', 'Q4', 'Q5']

      it 'nested transaction', ->
        name = null
        xtransaction NEW, ()->
          xtransaction (transaction)->
            name = transaction.name
            xtransaction.adapter.query('Q1')
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands)
          commands = checkSavepoint(commands, name)
          commands.should.eql ['Q1']

      it 'explicit rollback', ->
        xtransaction NEW, (transaction)->
          xtransaction.adapter.query('Q1')
          .then ->
            transaction.rollback()
          .then ->
            xtransaction.adapter.query('Q2')
        .then ->
          commands = querySeq(clients[1].query)
          commands = checkCommit(commands, 'rollback')
          commands.should.eql ['Q1']
          other = querySeq(clients[0].query)
          other.should.eql ['Q2']


Transactions in any order, will execute, interleaved, on both adapter clients.
However, the streams in the clients will have the transactions using that client
serialized, so that when we put the command streams together we have all the
transactions serialized.

      it 'multiple transactions', ->
        Promise.map [1..5], (i)->
          if i == 2
            debugger
          xtransaction NEW, "X#{i}", ()->
            xtransaction.adapter.query("Q#{i}")
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
        xtransaction NEW, ()->
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
        xtransaction NEW, 'O', ()->
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
          xtransaction NEW, xprefix, ()->
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
        nfound = 0
        popLoose = (q)->
          idx = looseQueries.indexOf(q)
          return false if idx == -1
          looseQueries.splice(idx, 1)
          nfound += 1
          return true
        checkEnds = (sub)->
          for i in [1..5]
            sub.splice(0, 1) if popLoose(sub[0])
            sub.pop() if popLoose(sub.slice(-1)[0])
        relexp = new RegExp("release \"#{prefix}T\\d\"$")
        commands = splitArray(commands, relexp)
        commands = _.sortBy commands, (s)->s.slice(-1)[0]
        commands.forEach (sub, i)->
          checkEnds(sub)
          sub = checkSavepoint(sub, "#{prefix}T#{i + 1}")
          srelexp = new RegExp("release \"#{prefix}T\d\d\"$")
          sub = splitArray(sub, srelexp)
          sub = _.sortBy(sub, 0)
          sub.forEach (ssub, j)->
            prefix = "#{prefix}T#{i + 1}#{j + 1}"
            ssub = checkSavepoint(ssub, prefix)
            checkQueries(ssub, prefix, 5)
        nfound.should.equal 5

      it 'single query with exception', ->
        xtransaction NEW, ()->
          xtransaction.adapter.query('Q1').then ->
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
        xtransaction NEW, ()->
          xtransaction.adapter.query('Q1')
        .catch (foo)->
          foo.message.should.equal 'foo'
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'rollback']

      it 'single query with exception on commit', ->
        clients[1].query.restore()
        stub = sinon.stub(clients[1], 'query')
        stub.onCall(2).throws(new Error('foo'))
        xtransaction NEW, ()->
          xtransaction.adapter.query('Q1')
        .catch (foo)->
          foo.message.should.equal 'foo'
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'Q1', 'commit']

      it 'subtransaction with exception caught', ->
        xtransaction NEW, 'X', ()->
          xtransaction.adapter.query('X1').then ->
            xtransaction IMPLICIT, 'sub', ()->
              xtransaction.adapter.query('Q1').then ->
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
          logger.error('Outer: error', err)
          throw err
        .then (res)->
          res.should.equal 'OK'
          commands = querySeq(clients[1].query)
          commands.should.eql ['begin', 'X1', 'savepoint "sub"', 'Q1', 'rollback to "sub"', 'commit']

      it.skip 'execute single autocommit', ->
        xtransaction AUTO, ->
          xtransaction.adapter.query('Q1')
        .then ->
          commands = querySeq(clients[1].query)
          commands.should.eql ['Q1']

Implicit transactions wait if any top-level are executing, in
case they are wrapped. Here we insure that they restart if
they aren't wrapped.

      it 'delay implicit for open top-level', ()->
        resolver = null
        p2 = p3 = null
        p1 = xtransaction NEW, ->
          xtransaction.adapter.query('Q1').delay(1).then ->
            p2 = new Promise (res)->
              resolver = res
            # transaction not wrapped because promise p3 doesn't
            # chain back to outer
            p3 = xtransaction IMPLICIT, ->
              xtransaction.adapter.query('Q2').then ->
                return 'bar'

            commands = querySeq(clients[1].query)
            commands.should.eql ['begin', 'Q1']
            setTimeout( ->
              resolver('foo')
              Promise.join(p1, p3).spread (r1, r3)->
                r1.should.equal 'foo'
                r3.should.equal 'bar'
                commands = querySeq(clients[1].query)
                commands.should.eql [
                  'begin', 'Q1', 'commit', 'begin', 'Q2', 'commit']

            , 10)
            return p2

Execute set of queries.

      doQueries = (prefix = 'Q')->
        Promise.map ("#{prefix}#{i}" for i in [1..5]), (q)->
          xtransaction.adapter.query(q)

Execute set of transactions.

      doTransactions = (prefix = 'T', callback = doQueries)->
        Promise.map [1..5], (i)->
          name = "#{prefix}#{i}"
          xtransaction IMPLICIT, name, ()->callback(name)

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

[**Home**](./index.html)
