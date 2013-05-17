defmodule SelectTest do
  def timer(seconds) do
    c = Chan.new
    {chan_pid, _} = c
    IO.puts "chan pid = #{inspect chan_pid}"
    spawn(fn ->
      IO.puts "timer pid = #{inspect self()}"
      :timer.sleep(seconds * 1000)
      Chan.write(c, :ok)
    end)
    c
  end

  def test_select() do
    require Chan

    #c = Chan.new
    c = timer(1)

    result = Chan.select do
      #c <- :value ->
        #:ok
      _ <= c ->
        :timeout
      #:default ->
        #:default
    end
    IO.puts result
  end
end
