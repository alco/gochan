defmodule Chan do
  @moduledoc """
  An implementation of channels from the Go programming language.
  """

  @doc """
  Returns a new channel. If `buffer_size` is 0, the channel is unbuffered and
  writing to it will block the writing process until someone will read from the
  channel on the other end.
  """
  def new(buffer_size // 0) do
    spawn(ChanProcess, :init, [buffer_size])
  end

  @doc """
  Writes data to the channel. Blocks 1) if the channel is non-buffered and
  nobody is receiving from it or 2) if the buffer is full.
  """
  def write(chan, data) do
    ref = make_ref()
    chan <- { :write, self(), ref, data }
    receive do
      { :ok, ^ref } -> :ok
    end
  end

  @doc """
  Reads from the channel. Blocks until data is available.
  """
  def read(chan) do
    ref = make_ref()
    chan <- { :read, self(), ref }
    receive do
      { :ok, ^ref, data } ->
        data
    end
  end

  @doc """
  Closes the channel making all currently waiting receivers receive nil.
  Writing to a closed channel will block forever (unlike Go, which would produce a runtime panic).
  """
  def close(chan) do
    chan <- :close
  end
end

defmodule ChanProcess do
  defrecord ChanState, buffer_size: 0, buffer: [], waiting: [], blocking: []

  def init(buffer_size) do
    loop(ChanState.new(buffer_size: buffer_size))
  end

  def loop(state=ChanState[]) do
    receive do
      { :write, from, ref, data } ->
        if match?([{reader, rref}|t], state.waiting) do
          # Someone is already waiting on the channel, so we can unblock the sender
          reader <- { :ok, rref, data }
          from <- { :ok, ref }
          loop(state.waiting(t))
        else
          # Add the sender on the blocking list
          loop(enqueue_write(state, from, ref, data))
        end

      { :read, from, ref } ->
        cond do
          match?([h|t], state.buffer) ->
            # Got a value in the buffer. Send it over and check if we need to unblock any writers.
            from <- { :ok, ref, h }
            loop(update_writers(state.buffer(t)))

          match?([{writer, wref, data}|t], state.blocking) ->
            # Someone is waiting in the writing state. Get their value and send them a confirmation.
            writer <- { :ok, wref }
            from <- { :ok, ref, data }
            loop(state.blocking(t))

          true ->
            # Add sender to the waiting list
            loop(state.update_waiting(&1 ++ [{from, ref}]))
        end

      :close ->
        # do nothing to quit the process
        :ok
    end
  end

  def enqueue_write(state=ChanState[], from, ref, data) do
    state.update_blocking(&1 ++ [{from, ref, data}])
  end

  def update_writers(state) do
    state
  end
end

defmodule ChanTest do
  def test_read_block() do
    c = Chan.new
    mypid = self()

    IO.puts "My pid = #{inspect mypid}; chan pid = #{inspect c}"

    pid = spawn(fn -> mypid <- { :ok_read, Chan.read(c) } end)

    IO.puts "Spawned a reader at #{inspect pid}"

    receive do
      x ->
        raise "Error: received #{inspect x}"
      after 500 ->
        :ok
    end

    IO.puts "writing to chan"
    Chan.write(c, "hello")
    receive do
      { :ok_read, msg } ->
        IO.puts "Received #{msg}"
    end
  end

  def test_write_block() do
    c = Chan.new
    mypid = self()

    IO.puts "My pid = #{inspect mypid}; chan pid = #{inspect c}"

    pid = spawn(fn -> Chan.write(c, "who's there?"); IO.puts "writer finished" end)

    IO.puts "Spawned a writer at #{inspect pid}"

    msg = Chan.read(c)
    IO.puts msg
  end

  def test_multiple_readers() do
    c = Chan.new

    Enum.each 1..3, fn _ ->
      spawn fn -> IO.puts Chan.read(c) end
    end

    Chan.write(c, "1")
    Chan.write(c, "2")
    Chan.write(c, "3")
  end

  def test_multiple_writers() do
    c = Chan.new

    Enum.each 1..3, fn x ->
      spawn fn -> IO.puts Chan.write(c, x) end
    end

    IO.puts Chan.read(c)
    IO.puts Chan.read(c)
    IO.puts Chan.read(c)
  end
end
