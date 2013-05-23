defmodule Chan do
  @moduledoc """
  An implementation of channels from the Go programming language.
  """

  @doc """
  Returns a new channel. If `buffer_size` is 0, the channel is unbuffered and
  writing to it will block the writing process until someone reads from the
  channel on the other end.
  """
  def new(buffer_size // 0) when buffer_size >= 0 do
    { spawn(ChanProcess, :init, [buffer_size]), buffer_size }
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

  def write(chan, data) do
    write(chan, data, true)
  end

  defp fast_write(chan, data) do
    quote do
      Chan.write(unquote(chan), unquote(data), false)
    end
  end

  @doc false
  def write({chan, _}, data, should_block) do
    ref = make_ref()
    chan <- { :write, {self(), ref, data}, should_block }
    # Check that the channel exists
    mref = Process.monitor(chan)
    result = receive do
      { :DOWN, ^mref, _, _, _ } ->
        raise "Channel is closed"

      { :closed, ^ref } ->
        raise "Channel is closed"

      { :ok, ^ref } ->
        :ok

      { :empty, ^ref } ->
        :empty
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

  def read(chan) do
    read(chan, true)
  end

  defp fast_read(chan) do
    quote do
      Chan.read(unquote(chan), false)
    end
  end

  @doc false
  def read({chan, _}, should_block) do
    ref = make_ref()
    chan <- { :read, {self(), ref}, should_block }
    # Check that the channel exists
    mref = Process.monitor(chan)
    result = receive do
      { :DOWN, ^mref, _, _, _ } ->
        nil

      { :closed, ^ref } ->
        nil

      { :ok, ^ref, data } ->
        if should_block do
          data
        else
          { :ok, data }
        end

      { :empty, ^ref } ->
        :empty
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

  ###

  defp new_var(i) do
    binary_to_atom("chan_var_#{i}")
  end

  defp evaluate_clauses(clauses) do
    # For each clause, replace the second argument with a variable
    {clauses, vars, _} = Enum.reduce clauses, {[], [], 0}, fn(clause, {clauses, vars, counter}) ->
      case clause do
        { [{:<-, info, [left, right]}], body } ->
          varname = new_var(counter)
          v = quote do
            var!(unquote(varname)) = unquote(right)
          end
          { [{ [{:<-, info, [left, quote do: var!(unquote(varname))]}], body } | clauses], [v | vars], counter+1 }

        { [{:<=, info, [left, right]}], body } ->
          varname = new_var(counter)
          v = quote do
            var!(unquote(varname)) = unquote(right)
          end
          { [{ [{:<=, info, [left, quote do: var!(unquote(varname))]}], body } | clauses], [v | vars], counter+1 }

        other -> { [other | clauses], vars, counter }
      end
    end
    {clauses, vars}
  end

  defp transform_clauses(clauses) do
    # Transforms each select clause into a normal Elixir clause
    Enum.reduce clauses, [], fn(clause, acc) ->
      q = case clause do
        { [{:<-, _, [left, right]}], body } ->
          # Convert chan <- value to fast_write(chan, value)
          quote do
            case unquote(fast_write(left, right)) do
              :ok -> throw {:return, unquote(body)}
              _ -> nil
            end
          end

        { [{:<=, _, [left, right]}], body } ->
          # Convert var <= chan to var = fast_read(chan)
          quote do
            case unquote(fast_read(right)) do
              { :ok, unquote(left) } -> throw {:return, unquote(body)}
              _ -> nil
            end
          end

        { [:default], body } ->
          quote do
            throw {:return, unquote(body)}
          end
      end
      [q | acc]
    end
  end

  defp build_select(vars, clauses) do
    # Initialize vars, then run a recursive loop that goes through each clause
    # until one returns
    quote do
      unquote(vars)
      f = fn(f) ->
        try do
          unquote_splicing(clauses)
          :timer.sleep(10)
          f.(f)
        catch
          { :return, result } ->
            result
        end
      end
      f.(f)
    end
  end

  defmacro select([do: {:->, _, clauses}]) when is_list(clauses) do
    {clauses, vars} = evaluate_clauses(clauses)
    new_clauses = transform_clauses(clauses)
    build_select(vars, new_clauses)
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

  def len(q) do
    :queue.len(q)
  end
end

defmodule ChanProcess do
  @moduledoc """
  Channel process for unbuffered channels.
  """

  defrecord ChanState, closed: false, cap: 0, buffer: Queue.new(), readers: Queue.new(), writers: Queue.new()

  def init(buffer_size) do
    loop(ChanState.new(cap: buffer_size))
  end

  def loop(state=ChanState[]) do
    receive do
      { :write, {from, ref, data}, _should_block } ->
        if state.closed do
          from <- { :closed, ref }
          loop(state)
        else
          state = state.update_buffer(Queue.put(&1, {ref, data}))
          if Queue.len(state.buffer) <= state.cap do
            from <- { :ok, ref }
          else
            state = state.update_writers(Queue.put(&1, {from, ref}))
          end
          loop(update_state(state))
        end
        #case { Queue.get(state.readers), should_block } do
          #{ { {reader, rref}, t }, _ } ->
            ## Someone is already waiting on the channel, so we can unblock the sender
            #reader <- { :ok, rref, data }
            #from <- { :ok, ref }
            #loop(state.readers(t))

          #{ _, true } ->
            ## Add the sender to the writers list
            #loop(state.update_writers(Queue.put(&1, msg)))

          #{ _, false } ->
            #from <- { :empty, ref }
            #loop(state)
        #end

      { :read, msg={_, _}, _should_block } ->
        state = state.update_readers(Queue.put(&1, msg))
        loop(update_state(state))
        #case { Queue.get(state.writers), should_block } do
          #{ { {writer, wref, data}, t }, _ } ->
            ## Someone is waiting in the writing state. Get their value and send them a confirmation.
            #writer <- { :ok, wref }
            #from <- { :ok, ref, data }
            #loop(state.writers(t))

          #{ _, true } ->
            ## Add sender to the readers list
            #loop(state.update_readers(Queue.put(&1, msg)))

          #{ _, false } ->
            #from <- { :empty, ref }
            #loop(state)
        #end

      { :len, from, ref } ->
        len = min(Queue.len(state.buffer), state.cap)
        from <- { :ok, ref, len }
        loop(state)

      :close ->
        Enum.each :queue.to_list(state.writers), fn {w, ref} ->
          w <- { :closed, ref }
        end
        Enum.each :queue.to_list(state.readers), fn {r, ref} ->
          r <- { :closed, ref }
        end
        if Queue.len(state.buffer) === 0 do
          # quit the process
          :ok
        else
          loop(state.readers(Queue.new()).writers(Queue.new()).closed(true))
        end
    end
  end

  # Both state.readers and state.writers can be empty, but all three of
  # { state.buffer, state.readers, state.writers } cannot be empty at the
  # same time.
  #
  # Possible patterns include:
  #
  #  { nil, ..., nil }  # nothing changes
  #  { ..., nil, nil }  # nothing changes
  #  { ..., nil, ... }  # nothing changes
  #  { ..., ..., nil }  # unblock reader and reduce buffer
  #  { ..., ..., ... }  # unblock reader, unblock writer, and reduce buffer
  #
  def update_state(state) do
    case { Queue.get(state.buffer), Queue.get(state.readers) } do
      { nil, { {reader, ref}, rt } } ->
        if state.closed do
          reader <- { :closed, ref }
          state.readers(rt)
        else
          state
        end

      { _, nil } -> state

      { { {wref, data}, bt }, { {reader, ref}, rt } } ->
        reader <- { :ok, ref, data }
        state = state.readers(rt).buffer(bt)

        # See if we should unblock any writers
        cap = state.cap
        case { Queue.get(state.writers), Queue.len(state.buffer) - Queue.len(state.writers) } do
          { { {from, ^wref}, wt }, _ } ->
            from <- { :ok, wref }
            state.writers(wt)

          { { {from, wref}, wt }, diff } when diff < cap ->
            from <- { :ok, wref }
            state.writers(wt)

          _ ->
            state
        end
    end
  end
end
