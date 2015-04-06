Test base
=========

    mocha = require 'mocha'
    chai = require 'chai'
    sinon = require 'sinon'
    should = chai.should()
    chai.use(require 'sinon-chai')
    #chai.use(require 'chai-string')
    Logger = require 'logger-facade-nodejs'

For the moment we use console logging. "Info" is not quiet even
when everything works normally: when the package is more stable, we
may change to "warn".

    if Logger.plugins().length == 0
      Logger.use new (require 'logger-facade-console-plugin-nodejs') {
        level: 'info'
        timeFormat: 'MM:ss.SSS'
        messageFormat: "%time: %logger: %msg"
      }
    logger = Logger.getLogger("test")

To run tests on a specific adapter, inject "getXWrap" into globals
before loading this module. "getXWrap" should provide:

* `xtranaction` -- initialized by specific adapter

* `clientMethods` -- methods on database client we should spy on.

* `query` -- method that wraps a database query

--

    initializer = require('../src/xwrap')
    if !global.getXWrap?
      global.getXWrap = ->
        return {
          xtransaction: initializer({adapter:'memory', id: 'memory'})
          clientMethods: ['get', 'set']
          query: (client, qstring)->
            client.get(qstring)
        }

    module.exports = {mocha, chai, should, sinon, getXWrap, logger}

[**Home**](./index.html)
