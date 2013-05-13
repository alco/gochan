defmodule Chan do
  @moduledoc """
  An implementation of channels from the Go programming language.
  """

  @doc """
  Returns a new channel. If `buffer_size` is 0, the channel is unbuffered and
  writing to it will block the writing process until someone reads from the
  channel on the other end.
  """
  def new() do
    { spawn(ChanProcess, :init, []), 0 }
  end

  def new(buffer_size) do
    { spawn(ChanBufProcess, :init, [buffer_size]), buffer_size }
  end

  @doc """
  Writes data to the channel. Blocks 1) if the channel is non-buffered and
  nobody is reading from it or 2) if the buffer is full.

  Writing to a closed channel raises RuntimeError.

  Writing to a nil channel blocks forever.
  """
  def write(nil, _) do
    #receive do
    #end
  end

  def write({chan, _}, data) do
    ref = make_ref()
    chan <- { :write, {self(), ref, data} }
    # Check that the channel exists
    mref = Process.monitor(chan)
    result = receive do
      { :DOWN, ^mref, _, _, _ } ->
        raise "Channel is closed"

      { :ok, ^ref } ->
        :ok
    end
    Process.demonitor(mref)
    result
  end

  @doc """
  Reads from the channel. Blocks until data is available.

  Reading from a nil channel blocks forever.

  Reading from a closed channel returns nil.
  """
  def read(nil) do
    #receive do
    #end
  end

  def read({chan, _}) do
    ref = make_ref()
    chan <- { :read, {self(), ref} }
    # Check that the channel exists
    mref = Process.monitor(chan)
    result = receive do
      { :DOWN, ^mref, _, _, _ } ->
        nil

      { :ok, ^ref, data } ->
        data
    end
    Process.demonitor(mref)
    result
  end

  @doc """
  Closes the channel making all currently waiting receivers receive nil.
  Closing a nil channel raises.

  Reading from a closed channel returns nil immediately.

  Writing to a closed channel raises.
  """
  def close(nil) do
    raise "Cannot close a nil channel"
  end

  def close({chan, _}) do
    # Check that the channel exists
    mref = Process.monitor(chan)
    receive do
      { :DOWN, ^mref, _, _, _ } ->
        raise "Trying to close an already closed channel"

      after 0 ->
        chan <- :close
    end
  end

  @doc """
  Returns channel's buffer size.
  """
  def cap({_, size}) do
    size
  end

  @doc """
  Returns number of elements enqueued in the buffer
  """
  def len({chan, size}) do
    if size == 0 do
      0
    else
      ref = make_ref()
      chan <- { :len, self(), ref }
      receive do
        { :ok, ^ref, length } ->
          length
      end
    end
  end
end

defmodule ChanBufProcess do
  defrecord ChanBufState, cap: 0, buffer: [], readers: [], writers: []

  def init(buffer_size) do
    loop(ChanBufState.new(cap: buffer_size))
  end

  def loop(state=ChanBufState[]) do
    receive do
      { :write, msg={from, ref, data} } ->
        if length(state.buffer) < state.cap do
          from <- { :ok, ref }
          loop(update_readers(state.update_buffer(&1 ++ [data])))
        else
          # The buffer if full
          loop(state.update_writers(&1 ++ [msg]))
        end

      { :read, msg={from, ref} } ->
        if match?([data|t], state.buffer) do
          from <- { :ok, ref, data }
          loop(update_writers(state.buffer(t)))
        else
          # The buffer is empty
          loop(state.update_readers(&1 ++ [msg]))
        end

      { :len, from, ref } ->
        from <- { :ok, ref, length(state.buffer) }
        loop(state)

      :close ->
        # do nothing to quit the process
        :ok
    end
  end

  defp update_readers(state=ChanBufState[buffer: []]), do: state
  defp update_readers(state=ChanBufState[readers: []]), do: state
  defp update_readers(state=ChanBufState[buffer: [data|bt], readers: [{from, ref}|rt]]) do
    from <- { :ok, ref, data }
    update_readers(state.buffer(bt).readers(rt))
  end

  defp update_writers(state=ChanBufState[writers: []]), do: state
  defp update_writers(state=ChanBufState[writers: [{from, ref, data}|wt]]) do
    # We assume that length(state.buffer) == state.cap - 1
    from <- { :ok, ref }
    state.update_buffer(&1 ++ [data]).writers(wt)

    #if length(state.buffer) < state.cap do
      #from <- { :ok, ref }
      #update_writers(state.update_buffer(&1 ++ [data]).writers(wt))
    #else
      #state
    #end
  end
end

defmodule ChanProcess do
  defrecord ChanState, readers: [], writers: []

  def init() do
    loop(ChanState.new())
  end

  def loop(state=ChanState[]) do
    receive do
      { :write, msg={from, ref, data} } ->
        if match?([{reader, rref}|t], state.readers) do
          # Someone is already waiting on the channel, so we can unblock the sender
          reader <- { :ok, rref, data }
          from <- { :ok, ref }
          loop(state.readers(t))
        else
          # Add the sender to the writers list
          loop(state.update_writers(&1 ++ [msg]))
        end

      { :read, msg={from, ref} } ->
        if match?([{writer, wref, data}|t], state.writers) do
          # Someone is waiting in the writing state. Get their value and send them a confirmation.
          writer <- { :ok, wref }
          from <- { :ok, ref, data }
          loop(state.writers(t))
        else
          # Add sender to the readers list
          loop(state.update_readers(&1 ++ [msg]))
        end

      :close ->
        # quit the process
        :ok
    end
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
