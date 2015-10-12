XWrap Transaction Manager
=========================

Implements transaction management using two classes: [`Transaction`][1]
which represents transactions themselves, and [`Request`][2] which represent
requests for transactions, and wrap requests for database clients.

[1]: ./transaction.html
[2]: ./request.html

It exports a facade defined in this file.

    Promise = require 'bluebird'
    _ = require 'lodash'
    {NEW, SUB, AUTO, IMPLICIT} = require './constants'
    Transaction = require './transaction'
    Request = require './request'
    Logger = require 'logger-facade-nodejs'
    fs = require 'fs'

Logger output: if not otherwise configured, output to console, level "WARN"

    if Logger.plugins().length == 0
      Logger.use new (require 'logger-facade-console-plugin-nodejs') {
        level: 'info'
        timeFormat: 'MM:ss.SSS'
        messageFormat: "%time: %logger: %msg"
      }

By default, we use logger named "xwrap". Override using "setLogger"
function.

    logger = Logger.getLogger('xwrap')
    Request.logger = logger
    Transaction.logger = logger

    adapters = {}

All aruments can be passed in a hash. If the first argument is not a hash,
then, arguments are interpreted based on which argument is callable: the
first callable argument is taken to be the callback, and some or
all of `type`, `id` and `name` may be undefined depending on the 
order of the callback.

* `type`: Type of transaction requested: 

  * `NEW` a new top-level transaction
  * `SUB` a sub-transaction
  * `AUTO` an "autocommit" (dummy) transaction, which doesn't wrap
    sub-calls.
  * `IMPLICIT` (default) either new or sub transaction, depending on
    whether we are wrapped by another open transaction.

* `name`: name associated with the caller who opened the transaction.
  Specify for logging and debugging.

* `callback`: callback in which to wrap database calls in transaction.

--

    module.exports = initializer = ({adapter, settings, id, wrap})->
      adapterName = adapter
      adapter = undefined
      wrap ?= true
      xtransaction = ()->
        if typeof arguments[0] == 'object'
          {type, callback, name} = type
        for arg, i in arguments
          if typeof arg == 'function'
            callback = arg
            [type, name] = Array::slice.call(arguments, 0, i)
            break
        if !callback?
          new Error('callback must be specified')

        Transaction.create({callback, type, name, adapter, id})

      adapter = resolveAdapter(adapterName, settings, id)
      adapter.xtransaction = xtransaction
      adapters[id] = adapter
      findAdapterFeatures(adapter)
      # NEED TO FIX & TEST WRAPPING
      #if wrap? and adapter.features.xwrap.wrap
      #  adapter.wrap 

      # add a full xwrap interface to transaction, but specialized
      # to the id of the adapter.
      xtransaction.client = (callerName)->
        return initializer.client(id, callerName)

      xtransaction.takeClient = (callerName)->
        return initializer.takeClient(id, callerName)

      xtransaction.getTransaction = (callerName)->
        return initializer.getTransaction(id, callerName)

      xtransaction.disconnect = ()->
        return initializer.disconnect(id)

      xtransaction.NEW = NEW
      xtransaction.SUB = SUB
      xtransaction.AUTO = AUTO
      xtransaction.Transaction = Transaction
      xtransaction.Request = Request
      xtransaction.adapter = adapter
      xtransaction.id = adapter.id
      return xtransaction

Load and initialize an adapter, given name, settings and ID.

    __adapterID = 0;
  
    resolveAdapter = (name, settings, id)->
      adapter = adapters[id]
      return adapter if adapter?
      try
        switch
          when typeof name == 'object'
            @name = name.name
            return name
          when name.match(/^\//)
            adapterClass = require(name)
          when fs.existsSync(__dirname + '/adapters/' + name + '.js') ||
              fs.existsSync(__dirname + '/adapters/' + name + '.coffee') ||
              fs.existsSync(__dirname + '/adapters/' + name + '.litcoffee')
            adapterMod = require './adapters/' + name
          else
            adapterMod = require "xwrap-#{name}"
        adapter = adapterMod.initialize(settings)
        if !adapter.id?
          adapter.id = id ? name + (++__adapterID);
        return adapter

      catch e
        if e.message.indexOf('Cannot find module') != -1
          throw new Error("XWrap adapter '#{name}' not found.")
        else
          throw e

Check adapter for interfaces, and set features if not set.

    BASIC_INTERFACE = [
      'getRawClient', 'openTransaction', 'commitTransaction', 'rollbackTransaction' ]
    SUBTRANSACTIONS_INTERFACE = [ 
      'openSubTransaction', 'commitSubTransaction', 'rollbackSubTransaction' ]
    WRAP_INTERACE = ['wrap']      

    findAdapterFeatures = (adapter)->
      features = (adapter.features ?= {})
      xwrapFeatures = (features.xwrap ?= {})
      xwrapFeatures.clientMethods ?= ['query']
      xwrapFeatures.clientDataAttributes ?= []

      for api in ['basic', 'subtransactions', 'wrap']
        continue if xwrapFeatures[api]?
        methods = switch api
          when 'basic' then BASIC_INTERFACE
          when 'subtransactions' then SUBTRANSACTIONS_INTERFACE
          when 'wrap' then WRAP_INTERACE
        missing = false
        for method in methods
          if !adapter[method]?
            missing = true
            break
        xwrapFeatures[api] = !missing

Return adapter for id, or "the" adapter if there is only one

    initializer.getAdapter = getAdapter = (id)->
      return adapters[id] if id?
      switch _.size(adapters)
        when 1 then return _.values(adapters)[0]
        when 0 then null
        else
          throw new Error('Must specify adapter id when more than one.')

Add xwrap interface to initializer function.

Get a client -- either a client in a transaction or any client
if no active transaction.

    initializer.client = (id, callerName)->
      return Request.client(id, callerName).then (client)->
        return client ? getAdapter(id).getRawClient()

Take client from transaction -- other users of transaction will wait.
Wrap in "Promise.using" to insure client is returned.

Returns null if no active transaction.

    initializer.takeClient = (id, callerName)->
      return Request.takeClient(id, callerName)

    initializer.xtransaction = (id, callerName)->
      adapter = getAdapter(id)
      adapter.xtransaction

Disconnect from data source; return promise fulfilled when 
disconnection complete.

    initializer.disconnect = (id)->
      adapter = getAdapter(id)
      return Promise.resolve() if !adapter?
      if id?
        delete adapters[id]
      else
        # must be only one or "getAdapter" will raise an error
        delete adapters[Object.keys(adapters)[0]]
      adapter?.disconnect?()

    initializer.NEW = NEW
    initializer.SUB = SUB
    initializer.AUTO = AUTO
    initializer.Transaction = Transaction
    initializer.Request = Request
    initializer.BASIC_INTERFACE = BASIC_INTERFACE
    initializer.SUBTRANSACTIONS_INTERFACE = SUBTRANSACTIONS_INTERFACE
    initializer.WRAP_INTERACE = WRAP_INTERACE

    initializer.useLogger = (logger_)->
      Request.logger = Transaction.logger = logger = logger_

[**Home**](./index.html)

