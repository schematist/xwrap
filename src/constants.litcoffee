XWrap Constants
===============

`NEW`, `SUB` and `AUTO` define types of transaction. Use `NEW` to force a top- level transaction (or
trigger an error if no wrapper exists), and `SUB` to force a sub-transaction
(or trigger and error if no wrapper exists). `AUTO` represents an "autocommit"
transaction, which simply doesn't wrap client calls. `IMPLICIT` marks
a transaction that could either be top-level or wrapped.

    env = process.env

    module.exports = {
      NEW: 'new'
      SUB: 'sub'
      AUTO: 'auto'
      IMPLICIT: 'implicit'
      LOGLEVEL: env.XW_LOGLEVEL ? 'info'
      GLOBAL_TIMEOUT: env.XW_GLOBAL_TIMEOUT ? null #10000
      MAX_REQUEST_IN_TRANSACTION: env.XW_MAX_REQUEST_IN_TRANSACTION ? 2000 * 60
      TICKER_REPEAT: env.XW_TICKER_REPEAT ? 1000 * 30

    }

[**Home**](./index.html)
    