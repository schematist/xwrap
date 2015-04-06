// Generated by CoffeeScript 1.9.0
(function() {
  var Promise, Request, __requestNumber;

  Promise = require('bluebird');

  __requestNumber = 0;

  Request = (function() {
    Request.ask = function(id, name) {
      return (new Request(id, name)).getTransaction();
    };

    Request.client = function(id, name) {
      return Request.ask(id, name).then(function(transaction) {
        return transaction.client();
      });
    };

    Request.takeClient = function(id, name) {
      return Request.ask(id, name.then)(function(transaction) {
        return transaction.takeClient();
      });
    };

    function Request(_at_id, _at_name) {
      this.id = _at_id;
      this.name = _at_name;
      __requestNumber += 1;
      if (this.name == null) {
        this.name = "?" + __requestNumber;
      }
    }

    Request.prototype.getTransaction = function() {
      var d, err, self;
      self = this;
      this.deferred = d = Promise.defer();
      Request.logger.debug("ASK " + this.name);
      process.nextTick(function() {
        Request.logger.debug("(ASK UP)");
        d.progress(self);
        return process.nextTick(function() {
          Request.logger.debug("(ASK UNA)");
          if (d.promise.isPending()) {
            return Request.handleUnanswered(self);
          }
        });
      });
      err = new Error("cancelled");
      return d.promise["catch"](function(cerr) {
        err.cancel = cerr;
        throw err;
      });
    };

    Request.prototype.fulfill = function(transaction) {
      var _ref;
      if ((_ref = this.deferred) != null ? _ref.promise.isPending() : void 0) {
        Request.logger.debug("FULFILL " + this.name + " by:", transaction != null ? transaction.name.slice(0, 4) : void 0);
        this.deferred.resolve(transaction);
        return delete this.deferred;
      }
    };

    Request.prototype.reject = function(reason) {
      var _ref;
      if ((_ref = this.deferred) != null ? _ref.promise.isPending() : void 0) {
        this.deferred.reject(reason);
        return delete this.deferred;
      }
    };

    Request.handle = function(transaction, promise, id) {
      Request.logger.debug("HANDLE BY", transaction.name.slice(0, 4));
      if ((promise == null) || (promise.progressed == null)) {
        throw new Error("Cannot pass transaction: no promise; got " + promise);
      }
      promise.progressed(function(request) {
        while (request.value != null) {
          request = request.value;
        }
        if (!(request instanceof Request)) {
          return;
        }
        if ((id == null) || request.id === id) {
          request.fulfill(transaction);
          throw {
            name: 'StopProgressPropagation'
          };
        }
        Request.logger.debug("REQ-" + request.name + " doesn't match", transaction.name.slice(0, 4));
      });
      return promise;
    };

    Request.handleUnanswered = function(request) {
      debugger;
      return request.fulfill(null);
    };

    return Request;

  })();

  module.exports = Request;

}).call(this);