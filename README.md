A "proof of concepts" implementation of [Go channels][1] in Elixir.

## The "what"

The API is simple: you get the `Chan` module with five methods:

* `new()` -- creates an unbuffered channel
* `new(size)` -- creates a channel with buffer of size `size`
* `read(chan)` -- reads from `chan` or blocks until data is available
* `write(chan, term)` -- writes `term` to `chan` or blocks if no one is reading from the channel or its buffer is full
* `close(chan)` -- closes `chan`. Subsequent reads from `chan` return `nil` immediately. Subsequent write raise. Closing a channel for the second time will raise too.

## The "why"

This is merely a proof of concepts. There aren't any practical advantages to channels over processes. They provide a slightly different concurrency model with additional runtime overhead.

## The "how"

Each channel is backed by a process running a receive loop. Synchronous writes are achieved using `receive` after send. To catch reads to and writes from closed channels, monitors are set up for the channel process before each `receive` from it.
