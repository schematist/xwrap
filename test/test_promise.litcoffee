Test Promise
============

Tests properties of promises related to progress.

    Promise = require 'bluebird'
    {should, logger} = require './base'

    describe 'promises', ->

      it 'capture stack trace through Promise.using', ->

      foo = ()->
        Promise.using Promise.resolve(), ->
          throw new Error()
        .catch (err)->
          debugger

      `function zzz() { return foo()};`
      zzz()