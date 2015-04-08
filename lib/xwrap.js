// Generated by CoffeeScript 1.9.1
(function() {
  var AUTO, BASIC_INTERFACE, IMPLICIT, Logger, NEW, Promise, Request, SUB, SUBTRANSACTIONS_INTERFACE, Transaction, WRAP_INTERACE, _, adapters, findAdapterFeatures, fs, getAdapter, initializer, logger, ref, resolveAdapter;

  Promise = require('bluebird');

  _ = require('lodash');

  ref = require('./constants'), NEW = ref.NEW, SUB = ref.SUB, AUTO = ref.AUTO, IMPLICIT = ref.IMPLICIT;

  Transaction = require('./transaction');

  Request = require('./request');

  Logger = require('logger-facade-nodejs');

  fs = require('fs');

  if (Logger.plugins().length === 0) {
    Logger.use(new (require('logger-facade-console-plugin-nodejs'))({
      level: 'info',
      timeFormat: 'MM:ss.SSS',
      messageFormat: "%time: %logger: %msg"
    }));
  }

  logger = Logger.getLogger('xwrap');

  Request.logger = logger;

  Transaction.logger = logger;

  adapters = {};

  module.exports = initializer = function(arg1) {
    var adapter, adapterName, id, settings, wrap, xtransaction;
    adapter = arg1.adapter, settings = arg1.settings, id = arg1.id, wrap = arg1.wrap;
    adapterName = adapter;
    adapter = void 0;
    if (wrap == null) {
      wrap = true;
    }
    xtransaction = function() {
      var arg, callback, i, j, len, name, newTransaction, ref1, ref2, type;
      if (typeof arguments[0] === 'object') {
        ref1 = type, type = ref1.type, callback = ref1.callback, name = ref1.name, id = ref1.id;
      }
      for (i = j = 0, len = arguments.length; j < len; i = ++j) {
        arg = arguments[i];
        if (typeof arg === 'function') {
          callback = arg;
          ref2 = Array.prototype.slice.call(arguments, 0, i), type = ref2[0], id = ref2[1], name = ref2[2];
          break;
        }
      }
      if (callback == null) {
        new Error('callback must be specified');
      }
      newTransaction = new Transaction({
        callback: callback,
        name: name,
        adapter: adapter,
        id: id
      });
      if (type == null) {
        type = IMPLICIT;
      }
      return newTransaction.start(type);
    };
    adapter = resolveAdapter(adapterName, settings, id);
    adapter.id = id;
    adapter.xtransaction = xtransaction;
    findAdapterFeatures(adapter);
    if ((wrap != null) && adapter.features.xwrap.wrap) {
      adapter.wrap(function(callerName) {
        return Request.client(id, callerName);
      });
    }
    xtransaction.client = function(callerName) {
      return Request.client(id, callerName);
    };
    xtransaction.takeClient = function(callerName) {
      return Request.takeClient(id, callerName);
    };
    xtransaction.getTransaction = function(callerName) {
      return Request.ask(id, callerName);
    };
    xtransaction.disconnect = function() {
      adapter.disconnect();
      return delete adapters[adapter.id];
    };
    xtransaction.NEW = NEW;
    xtransaction.SUB = SUB;
    xtransaction.AUTO = AUTO;
    xtransaction.Transaction = Transaction;
    xtransaction.Request = Request;
    xtransaction.adapter = adapter;
    xtransaction.id = id;
    return xtransaction;
  };

  resolveAdapter = function(name, settings, id) {
    var adapter, adapterClass, adapterMod, e;
    adapter = adapters[id];
    if (adapter != null) {
      return adapter;
    }
    try {
      switch (false) {
        case typeof name !== 'object':
          this.name = name.name;
          return name;
        case !name.match(/^\//):
          adapterClass = require(name);
          break;
        case !(fs.existsSync(__dirname + '/adapters/' + name + '.js') || fs.existsSync(__dirname + '/adapters/' + name + '.coffee') || fs.existsSync(__dirname + '/adapters/' + name + '.litcoffee')):
          adapterMod = require('./adapters/' + name);
          break;
        default:
          adapterMod = require("xwrap-" + name);
      }
      return adapterMod.initialize(settings);
    } catch (_error) {
      e = _error;
      if (e.message.indexOf('Cannot find module') !== -1) {
        throw new Error("XWrap adapter '" + name + "' not found.");
      } else {
        throw e;
      }
    }
  };

  BASIC_INTERFACE = ['getRawClient', 'openTransaction', 'commitTransaction', 'rollbackTransaction'];

  SUBTRANSACTIONS_INTERFACE = ['openSubTransaction', 'commitSubTransaction', 'rollbackSubTransaction'];

  WRAP_INTERACE = ['wrap'];

  findAdapterFeatures = function(adapter) {
    var api, features, j, k, len, len1, method, methods, missing, ref1, results, xwrapFeatures;
    features = (adapter.features != null ? adapter.features : adapter.features = {});
    xwrapFeatures = (features.xwrap != null ? features.xwrap : features.xwrap = {});
    if (xwrapFeatures.clientMethods == null) {
      xwrapFeatures.clientMethods = ['query'];
    }
    if (xwrapFeatures.clientDataAttributes == null) {
      xwrapFeatures.clientDataAttributes = [];
    }
    ref1 = ['basic', 'subtransactions', 'wrap'];
    results = [];
    for (j = 0, len = ref1.length; j < len; j++) {
      api = ref1[j];
      if (xwrapFeatures[api] != null) {
        continue;
      }
      methods = (function() {
        switch (api) {
          case 'basic':
            return BASIC_INTERFACE;
          case 'subtransactions':
            return SUBTRANSACTIONS_INTERFACE;
          case 'wrap':
            return WRAP_INTERACE;
        }
      })();
      missing = false;
      for (k = 0, len1 = methods.length; k < len1; k++) {
        method = methods[k];
        if (adapter[method] == null) {
          missing = true;
          break;
        }
      }
      results.push(xwrapFeatures[api] = !missing);
    }
    return results;
  };

  getAdapter = function(id) {
    if (id != null) {
      return adapters[id];
    }
    switch (_.size(adapters)) {
      case 1:
        return _.values(adapters)[0];
      case 0:
        return null;
      default:
        throw new Error('Must specify adapter id when more than one.');
    }
  };

  initializer.client = function(id, callerName) {
    return new Request.client(id, callerName);
  };

  initializer.takeClient = function(id, callerName) {
    return new Request.takeClient(id, callerName);
  };

  initializer.xtransaction = function(id, callerName) {
    var adapter;
    adapter = getAdapter(id);
    return adapter.xtransaction;
  };

  initializer.disconnect = function(id) {
    var adapter;
    adapter = getAdapter(id);
    if (adapter == null) {
      return;
    }
    if (adapter != null) {
      adapter.disconnect();
    }
    if (id != null) {
      return delete adapters[id];
    } else {
      return delete adapters[Object.keys(adapters)[0]];
    }
  };

  initializer.NEW = NEW;

  initializer.SUB = SUB;

  initializer.AUTO = AUTO;

  initializer.Transaction = Transaction;

  initializer.Request = Request;

  initializer.BASIC_INTERFACE = BASIC_INTERFACE;

  initializer.SUBTRANSACTIONS_INTERFACE = SUBTRANSACTIONS_INTERFACE;

  initializer.WRAP_INTERACE = WRAP_INTERACE;

  initializer.useLogger = function(logger_) {
    return Request.logger = Transaction.logger = logger = logger_;
  };

}).call(this);