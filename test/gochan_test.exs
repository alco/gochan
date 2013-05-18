Code.require_file "../test_helper.exs", __FILE__

defmodule GochanTest do
  use ExUnit.Case

  test "close" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    assert Chan.close(c) == :close
    refute_receive _

    assert_raise RuntimeError, "Trying to close an already closed channel", fn ->
      Chan.close(c)
    end

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "close read" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    Chan.close(c)

    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "close write" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    Chan.close(c)

    assert_raise RuntimeError, "Channel is closed", fn ->
      Chan.write(c, :anything)
    end

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "read block" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    mypid = self()

    pid = spawn(fn -> mypid <- { :ok_read, self(), Chan.read(c) } end)
    refute_receive _

    Chan.write(c, "hello")
    assert_receive { :ok_read, ^pid, "hello" }
    refute_receive _

    Chan.close(c)
    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "write block" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    mypid = self()

    pid = spawn(fn -> Chan.write(c, "who's there?"); mypid <- {:finished, self()} end)
    refute_receive _

    msg = Chan.read(c)
    assert msg == "who's there?"
    assert_receive {:finished, ^pid}
    refute_receive _

    Chan.close(c)
    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "back and forth" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    mypid = self()

    pid = spawn(fn ->
      x = Chan.read(c)
      Chan.write(c, x * 2)
      y = Chan.read(c)
      Chan.write(c, y * y)
      mypid <- {:finished, self()}
    end)
    refute_receive _

    Chan.write(c, 4)
    assert Chan.read(c) == 8
    refute_receive _

    Chan.write(c, 16)
    assert Chan.read(c) == 256
    assert_receive {:finished, ^pid}
    refute_receive _

    Chan.close(c)
    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "multiple readers" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    mypid = self()

    pids = Enum.map 1..3, fn n ->
      spawn fn -> mypid <- {n, self(), Chan.read(c)} end
    end
    refute_receive _

    [pid|t] = pids
    Chan.write(c, "1")
    assert_receive {1, ^pid, "1"}
    refute_receive _
    pids = t

    [pid|t] = pids
    Chan.write(c, "2")
    assert_receive {2, ^pid, "2"}
    refute_receive _
    pids = t

    [pid|_] = pids
    Chan.write(c, "3")
    assert_receive {3, ^pid, "3"}
    refute_receive _

    Chan.close(c)
    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  test "multiple writers" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    mypid = self()

    pids = Enum.map 1..3, fn n ->
      spawn fn -> Chan.write(c, n); mypid <- {n, self(), :finished} end
    end
    refute_receive _

    [pid|t] = pids
    assert Chan.read(c) == 1
    assert_receive {1, ^pid, :finished}
    refute_receive _
    pids = t

    [pid|t] = pids
    assert Chan.read(c) == 2
    assert_receive {2, ^pid, :finished}
    refute_receive _
    pids = t

    [pid|_] = pids
    assert Chan.read(c) == 3
    assert_receive {3, ^pid, :finished}
    refute_receive _

    Chan.close(c)
    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end

  defp timer(seconds) do
    c = Chan.new
    spawn(fn ->
      :timer.sleep(seconds * 1000)
      Chan.write(c, :ok)
    end)
    c
  end

  test "select" do
    require Chan

    refute_receive _

    c1 = Chan.new
    c2 = Chan.new

    spawn(fn -> :timer.sleep(500); Chan.write(c1, :hello) end)

    result = Chan.select do
      x <= c1 -> x
      :default -> :default
    end
    assert result == :default

    result = Chan.select do
      x <= c1 -> x
      c2 <- "ping" -> :okwrite
      _ <= timer(1) -> :timeout
    end
    assert result == :hello

    result = Chan.select do
      x <= c1 ->
        x
      c2 <- "ping" ->
        :okwrite
      _ <= timer(1) ->
        :timeout
    end
    assert result == :timeout

    pid = self()
    spawn(fn -> :timer.sleep(500); pid <- Chan.read(c2) end)

    result = Chan.select do
      x <= c1 ->
        x
      c2 <- "ping" ->
        :okwrite
      _ <= timer(1) ->
        :timout
    end
    assert result == :okwrite
    assert_receive "ping"

    result = Chan.select do
      x <= c1 ->
        x
      c2 <- "ping" ->
        :okwrite
      _ <= timer(1) ->
        :timout
      :default ->
        :default
    end
    assert result == :default

    Chan.close(c1)
    Chan.close(c2)

    assert Chan.read(c1) == nil
    assert Chan.read(c2) == nil

    refute_receive _
  end
end

defmodule GochanBufTest do
  use ExUnit.Case
end

