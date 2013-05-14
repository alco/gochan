A "proof of concept" implementation of [Go channels][1] in Elixir.

  [1]: http://golang.org/doc/effective_go.html#channels

## The "what"

The API is simple: you get the `Chan` module with five methods:

* `new()` -- creates an unbuffered channel.
* `new(size)` -- creates a channel with buffer of size `size`.
* `read(chan)` -- reads from `chan` or blocks until data is available.
* `write(chan, term)` -- writes `term` to `chan` or blocks if no one is reading from the channel or its buffer is full.
* `close(chan)` -- closes `chan`. Subsequent reads from `chan` return `nil` immediately. Subsequent writes raise. Closing a channel for the second time will raise too.

## The "why"

This is merely a proof of concept. They are not the same channels as in Go for the following reasons:

* Go channels are typed, in Elixir they are not.
* Go channels are built into the language, so they are efficient.
* Go channels are used to synchronize access to mutable data. Elixir does not have mutable data.

There aren't any practical advantages to channels over processes in Elixir. They provide a slightly different concurrency model with additional runtime overhead.

## The "how"

Each channel is backed by a process running a receive loop. Synchronous writes are achieved using `receive` after send. To catch reads to and writes from closed channels, monitors are set up for the channel process before each `receive` from it.
