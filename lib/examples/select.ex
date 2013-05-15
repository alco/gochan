defmodule SelectTest do
  def timer(seconds) do
    c = Chan.new
    spawn(fn ->
      :timer.sleep(seconds * 1000)
      Chan.write(c, :ok)
    end)
    c
  end

  def test_select() do
    require Chan

    c = Chan.new

    Chan.select do
      c <- :value ->
        :ok
      x <= timer(1) ->
        :timeout
      :default ->
        :default
    end
  end
end
