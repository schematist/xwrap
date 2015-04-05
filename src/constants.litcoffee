XWrap Constants
===============

`NEW`, `SUB` and `AUTO` define types of transaction. Use `NEW` to force a top- level transaction (or
trigger an error if no wrapper exists), and `SUB` to force a sub-transaction
(or trigger and error if no wrapper exists). `AUTO` represents an "autocommit"
transaction, which simply doesn't wrap client calls. `IMPLICIT` marks
a transaction that could either be top-level or wrapped.


    module.exports = {
      NEW: 'new'
      SUB: 'sub'
      AUTO: 'auto'
      IMPLICIT: 'implicit'
      GLOBAL_TIMEOUT: null #10000
      MAX_REQUEST_IN_TRANSACTION: 1000 * 10
      TICKER_REPEAT: 1000 * 5

    }