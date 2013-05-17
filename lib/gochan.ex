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
        Process.demonitor(mref)
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


  def fast_read({chan, _}) do
    ref = make_ref()
    chan <- { :fast_read, {self(), ref} }
    # Check that the channel exists
    mref = Process.monitor(chan)
    result = receive do
      { :DOWN, ^mref, _, _, _ } ->
        nil

      { :ok, ^ref, data } ->
        { :ok, data }

      { :nodata, ^ref } ->
        :nodata
    end
    Process.demonitor(mref)
    result
  end

  def fast_write({chan, _}, data) do
    ref = make_ref()
    chan <- { :fast_write, {self(), ref, data} }
    # Check that the channel exists
    mref = Process.monitor(chan)
    result = receive do
      { :DOWN, ^mref, _, _, _ } ->
        raise "Channel is closed"

      { :ok, ^ref } ->
        :ok

      { :noreaders, ^ref } ->
        :noreaders
    end
    Process.demonitor(mref)
    result
  end

  defp new_var() do
    num = if x = Process.get(:chan_var) do
      Process.put(:chan_var, x+1)
      x
    else
      Process.put(:chan_var, 1)
      0
    end
    binary_to_atom("chan_var_#{num}")
  end

  defmacro select([do: {:->, _, clauses}]) when is_list(clauses) do
    {clauses, vars} = Enum.reduce clauses, {[], []}, fn(clause, {clauses, vars}) ->
      case clause do
        { [{:<-, info, [left, right]}], body } ->
          varname = new_var()
          v = quote do
            var!(unquote(varname)) = unquote(right)
          end
          { [{ [{:<-, info, [left, quote do: var!(unquote(varname))]}], body } | clauses], [v | vars] }

        { [{:<=, info, [left, right]}], body } ->
          varname = new_var()
          v = quote do
            var!(unquote(varname)) = unquote(right)
          end
          { [{ [{:<=, info, [left, quote do: var!(unquote(varname))]}], body } | clauses], [v | vars] }

        other -> { [other | clauses], vars }
      end
    end
    new_clauses = Enum.reduce clauses, [], fn(clause, acc) ->
      q = case clause do
        { [{:<-, _, [left, right]}], body } ->
          # Convert chan <- value to Chan.fast_write(chan, value)
          quote do
            case Chan.fast_write(unquote(left), unquote(right)) do
              :ok ->
                throw {:return, unquote(body)}
              :noreaders ->
                nil
            end
          end

        { [{:<=, _, [left, right]}], body } ->
          # Convert var <= chan to var = Chan.fast_read(chan)
          quote do
            case Chan.fast_read(unquote(right)) do
              { :ok, unquote(left) } ->
                throw {:return, unquote(body)}
              :nodata ->
                nil
            end
          end

        { [:default], body } ->
          quote do
            throw {:return, unquote(body)}
          end
      end
      [q | acc]
    end
    quote do
      unquote(vars)
      f = fn(f) ->
        try do
          unquote_splicing(new_clauses)
          :timer.sleep(1)
          f.(f)
        catch
          { :return, result } ->
            result
        end
      end
      f.(f)
    end
  end
end

defmodule Queue do
  def new do
    :queue.new
  end

  def put(q, val) do
    :queue.in(val, q)
  end

  def get(q) do
    case :queue.out(q) do
      { :empty, _ } ->
        nil

      { {:value, val}, queue } ->
        { val, queue }
    end
  end
end

defmodule ChanProcess do
  @moduledoc """
  Channel process for unbuffered channels.
  """

  defrecord ChanState, readers: Queue.new(), writers: Queue.new()

  def init() do
    loop(ChanState.new())
  end

  def loop(state=ChanState[]) do
    receive do
      { :write, msg={from, ref, data} } ->
        if match?({ {reader, rref}, t }, Queue.get(state.readers)) do
          # Someone is already waiting on the channel, so we can unblock the sender
          reader <- { :ok, rref, data }
          from <- { :ok, ref }
          loop(state.readers(t))
        else
          # Add the sender to the writers list
          loop(state.update_writers(Queue.put(&1, msg)))
        end

      { :read, msg={from, ref} } ->
        if match?({ {writer, wref, data}, t }, Queue.get(state.writers)) do
          # Someone is waiting in the writing state. Get their value and send them a confirmation.
          writer <- { :ok, wref }
          from <- { :ok, ref, data }
          loop(state.writers(t))
        else
          # Add sender to the readers list
          loop(state.update_readers(Queue.put(&1, msg)))
        end

      { :fast_read, {from, ref} } ->
        if match?({ {writer, wref, data}, t }, Queue.get(state.writers)) do
          writer <- { :ok, wref }
          from <- { :ok, ref, data }
          loop(state.writers(t))
        else
          from <- { :nodata, ref }
          loop(state)
        end

      { :fast_write, {from, ref, data} } ->
        if match?({ {reader, rref}, t }, Queue.get(state.readers)) do
          reader <- { :ok, rref, data }
          from <- { :ok, ref }
          loop(state.readers(t))
        else
          from <- { :noreaders, ref }
          loop(state)
        end

      :close ->
        # quit the process
        :ok
    end
  end
end


defmodule ChanBufProcess do
  @moduledoc """
  Channel process for buffered channels.
  """

  defrecord ChanState, cap: 0, buffer: [], readers: [], writers: []

  def init(buffer_size) do
    loop(ChanState.new(cap: buffer_size))
  end

  def loop(state=ChanState[]) do
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

  defp update_readers(state=ChanState[buffer: []]), do: state
  defp update_readers(state=ChanState[readers: []]), do: state
  defp update_readers(state=ChanState[buffer: [data|bt], readers: [{from, ref}|rt]]) do
    from <- { :ok, ref, data }
    update_readers(state.buffer(bt).readers(rt))
  end

  defp update_writers(state=ChanState[writers: []]), do: state
  defp update_writers(state=ChanState[writers: [{from, ref, data}|wt]]) do
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


