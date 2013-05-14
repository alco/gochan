Code.require_file "../test_helper.exs", __FILE__

defmodule GochanTest do
  use ExUnit.Case

  test "read block" do
    # Make sure nothing is leftover from previous test
    refute_receive _

    c = Chan.new
    mypid = self()

    pid = spawn(fn -> mypid <- { :ok_read, self(), Chan.read(c) } end)
    refute_receive _

    Chan.write(c, "hello")
    assert_receive { :ok_read, ^pid, "hello" }

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

    Chan.write(c, 16)
    assert Chan.read(c) == 256
    assert_receive {:finished, ^pid}

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
    pids = t

    [pid|t] = pids
    Chan.write(c, "2")
    assert_receive {2, ^pid, "2"}
    pids = t

    [pid|_] = pids
    Chan.write(c, "3")
    assert_receive {3, ^pid, "3"}

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
    pids = t

    [pid|t] = pids
    assert Chan.read(c) == 2
    assert_receive {2, ^pid, :finished}
    pids = t

    [pid|_] = pids
    assert Chan.read(c) == 3
    assert_receive {3, ^pid, :finished}

    Chan.close(c)
    assert Chan.read(c) == nil

    # Make sure nothing is leftover after out test
    refute_receive _
  end
end

defmodule GochanBufTest do
  use ExUnit.Case
end

