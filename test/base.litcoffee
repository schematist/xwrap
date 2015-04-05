Test base
=========

    mocha = require 'mocha'
    chai = require 'chai'
    sinon = require 'sinon'
    should = chai.should()
    chai.use(require 'sinon-chai')
    chai.use(require 'chai-string')
    Logger = require 'logger-facade-nodejs'
    if Logger.plugins().length == 0
      Logger.use new (require 'logger-facade-console-plugin-nodejs') {
        level: 'info'
        timeFormat: 'MM:ss.SSS'
        messageFormat: "%time: %logger: %msg"
      }
    logger = Logger.getLogger("test")


    initializer = require('../src/xwrap')
    if !global.getXWrap?
      global.getXWrap = ->
        return initializer({adapter:'memory', id: 'memory'})

    module.exports = {mocha, chai, should, sinon, getXWrap, logger}
