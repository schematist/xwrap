# Transactions and Promises

## Problem

There are a number of different tools that can interact with
a database: a basic driver, ORMs, reporting & analytics tools,
maintenance tools, REST interfaces, perhaps connectors to other
databases, etc. 

Ideally, all of these modules should be composable. In part, a well designed
database driver makes this possible. For instance, [node-postgres][1] creates
a pool of clients to the database; any other utility connecting to a
given database with the same settings will use the same pool.

[1] https://github.com/brianc/node-postgres

But what if you need to use transactions? A REST package may want
to wrap interactions in transactions, but a reporting package many
not use transactions, and a maintenance package may use its own 
transactions.

In some environments, when tools share a common database driver
or ORM, composing packages that use transactions is fairly straightforward.
For instance, in python, using [django][2], a view that generates
a web page can be wrapped in a decorator which causes everything
that the view does to be wrapped in a transaction:

[2] https://www.djangoproject.com/

    from django.db import transaction

    @transaction.commit_on_success()
    def view_foo(request):
      ...

Any utility called by `view_foo` -- even a plugin written by a third
party which has no notion of transactions -- can get a database cursor:

    from django.db import connection
    cursor = connection.cursor()

Database queries executed using this query will automatically be wrapped in
`begin` and `commit` or (if an exception is thrown to `view_foo`) `rollback`.

Unfortunately, in `node`'s asynchronous environment, it would seem this isn't
possible. As (the equivalent of) `view_foo` processes, other views might 
start processing while `view_foo` waits on i/o. There may well be several  
different database clients in use -- but only one with the transaction
initiated by `view_foo`. How could a utility plugin know which client
to use, unless it was written in advance to accept a transaction?

Its worth noting that the problem isn't asynchronicity per se. If we are 
using django together with [gunicorn][3] running with [gevent][4], 

[3] http://docs.gunicorn.org/en/19.3/
[4] http://www.gevent.org/

The python runtime will switch contexts while waiting for i/o in a fashion
similiar to node, and yet it is still possible to get code that is oblivious
to the transaction state to work! This is possible because the "greenlets"
used by gevent have identity accross context switches. It is possible to associate database clients with greenlets, so that, when called while
running inside a greenlet, django can get the right client.

In node this technique seems impossible to utilize: each asynchronous event
starts an anonymous call-stack. Though the C++ code might know how to 
identify these events, there is nothing for a javascript program to refer
to, unless it passes information from one call to another, including
threading it through 3rd party libraries.

## Promises to the Rescue!

The Promise specification is a brilliant framework that allows you to write
ansynchronous code in a style much more closely paralleling synchonous code.
The synchronous bits of asynchronous code are wrapped in promise objects,
which are chained together using the "then" method (or other methods for
parallel execution and error handling). The chain of promises is constructed
synchronously, and flattens out complex pyramids of callbacks.

The salient point here is that promises convert an asyncrhonous chain of
callbacks into a stack of promises that exists all at once. If any leaf node
does execute asynchronously there will be a chain of promises from that 
leaf to the root that made the call.

In fact, if we can "refer" to this chain in a request for a client for which 
a transaction was started at the root, its all we need to solve are dilemma.
In yet another way, promises allow asynchronous code in node to be written
in the same fashion that synchronous code would be written.

The mechanism by which we "refer" to the chain is to pass a message
up the chain using the "progress" interface, and wait for an answer. 
At the root, where the transaction was started, a listener for this 
message is registered. Whenever a message in the correct form is received,
it passes back the client which executes.

Of course, the chain of calls is really a tree, and only exists ephemerally. But if leaves explicitly wait, then the chain between root and leaf will exist, and the client can pass.

In `xwrap`, the `Request` class encapsulates this exchange. When
it needs a client, the leaf node creates a `Request` object
and calls `getTransction` (this is wrapped in a single global function
call in the interface):

      getTransaction: ->
        self = this
        @deferred = d = Promise.defer()
        process.nextTick ->
          d.progress self
        return d.promise

Here, the leaf node creates a promise but doesn't resolve it. Instead
the resolution callback is stored in the request object and sent up 
the chain (as "self") to the wrapping transaction.

The transaction calls the class method handle, with the transaction
and its own promise, which will be attached to the leaf:

      @handle: (transaction, promise)->
        promise.progressed (request)->
          # unwrap -- annoying oddity
          while request.value?
            request = request.value
          if !(request instanceof Request)
            return
          request.fulfill(transaction)
        return promise

The transaction registers a handler (the "progressed" call), that
fulfills instances of the request with the transaction (which
contains the client).

      fulfill: (transaction)->
        if @deferred?.promise.isPending()
          @deferred.resolve(transaction)
          delete @deferred

With the transaction in hand, the leaf can take the client and execute (when
it is free -- it might have to wait for the call to write "begin" or for any
subtransactions).

Problem solved! (See [the package][5] and [the source documentation][6]
for more details.)

[5] https://github.com/schematist/xwrap
[6] http://schematist.github.io/xwrap/xwrap.html

## Oh No!

Unfortunately, the good folks who maintain the promise specification
and write libraries to support it don't know how genial they really are.
The progress inteface works fine, and plays an irreplacable role
in coordinating activity that would otherwise need the equivalent
of "thread-local storage" to effect. However, some users had too
high expectations of progress: rather than have the root and leaf 
explicitly coordinate their interaction, as is encapsultated in the 
`Request` class, they wanted the promise library itself to mediate
interactions. For instance, if the "progressed" handler throws an 
exception, perhaps the leaf should be automatically cancelled?

This sort of functionality is at odds with the purpose of the Promise
interface, which is to simulate a synchronous flow of events accross
asyncrhonous calls. In a "flow of events", surely a given thing should 
happen only once. Yet what if the progressed handler throws an exception
but the leaf does something else? "What happens" at the leaf should be
immutable, and the responsibility shouldn't be spread around, or
have to be mediated by complex conventions.

If the progressed handler can't affect the chain, though, then
can't the progress event simply be handled by a global event handler?
Currently, "progress" is decrecated, with the recommendation that
"progress" calls should be replaced by global events.

What was overlooked, however, was:

1) **Progress calls are _scoped_ events**, and the scope encodes
the identity of the call stack, **which is otherwise unidentifiable.**

2) It is completely unnecessary to involve the promise library in
mediating the interaction between handler and leaf. If necessary, 
**leaf and root can transfer ownership of the result explicitly**, 
while always maintaining one clear source of authority for the result.

I hope that the maintainers of promises, reading this, will recognize
what a hidden gem the "progress" interface really is. In another important
respect it allows asynchronous code to be written like synchronous code,
but avoids the overhead of "fibers" (or what have you).


