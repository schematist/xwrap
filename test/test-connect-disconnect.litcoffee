# Test XWrap connect & disconnect

    {should} = require './base'
    initializer = require '../src/xwrap'

    describe 'connect & disconnect', ->
      xtransaction = null
      afterEach ->
        if xtransaction?
          xtransaction.disconnect()

      it 'new transaction factory without identity should have assigned id', ->
        xtransaction = initializer({adapter: 'memory'})
        should.exist(xtransaction.id, 'xtransaction identity should exist')

      it 'new transaction factory should assume passed in identity', ->
        xtransaction = initializer({adapter: 'memory', id: 'foo'})
        xtransaction.id.should.equal 'foo'


      it '2nd new transaction factory created with same id share adapter', ->
        xtransaction = initializer({adapter: 'memory', id: 'foo'})
        xtransaction2 = initializer({adapter: 'memory', id: 'foo'})
        xtransaction.adapter.should.equal xtransaction2.adapter
