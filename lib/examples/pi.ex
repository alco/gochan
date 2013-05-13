"""
Execution time comparison.

Go:

    λ ./pi
    3.1416426510898874
    0.065972
    # 0.065972 seconds

Elixir:

    λ ERL_COMPILER_OPTIONS="native" mix compile
    Compiled lib/examples/pi.ex
    Compiled lib/gochan.ex
    Generated gochan.app

[raw processes]:

    λ erl -pa /Users/alco/Documents/git/elixir/lib/*/ebin -pa ebin -noshell -s Elixir-PiNative run -s init stop
    3.14174275369505640043e+00
    {192138,:ok}
    # 0.192138 seconds

[gochan]:

    λ erl -pa /Users/alco/Documents/git/elixir/lib/*/ebin -pa ebin -noshell -s Elixir-Pi run -s init stop
    3.14164265108988693953e+00
    {2357628,:ok}
    # 2.357628 seconds

"""

"""
// Concurrent computation of pi.
// See http://goo.gl/ZuTZM.
//
// This demonstrates Go's ability to handle
// large numbers of concurrent processes.
// It is an unreasonable way to calculate pi.
package main

import (
	"fmt"
	"math"
	"time"
)

func main() {
	ts := time.Now()
	fmt.Println(pi(20000))
	fmt.Println(time.Now().Sub(ts).Seconds())
)

// pi launches n goroutines to compute an
// approximation of pi.
func pi(n int) float64 {
	ch := make(chan float64)
	for k := 0; k <= n; k++ {
		go term(ch, float64(k))
	}
	f := 0.0
	for k := 0; k <= n; k++ {
		f += <-ch
	}
	return f
}

func term(ch chan float64, k float64) {
	ch <- 4 * math.Pow(-1, k) / (2*k + 1)
}
"""

defmodule PiNative do
  def run() do
    IO.inspect :timer.tc fn -> IO.puts approx(20000) end
  end

  def reduce(0, acc) do
    acc
  end

  def reduce(n, acc) do
    acc = acc + receive do
      term -> term
    end
    reduce(n-1, acc)
  end

  def approx(n) do
    mypid = self()
    Enum.each 0..n, fn(k) ->
      spawn(__MODULE__, :term, [mypid, k])
    end
    reduce(n, 0)
  end

  def term(pid, k) do
    pid <- 4 * :math.pow(-1, k) / (2*k + 1)
  end
end

defmodule Pi do
  def run() do
    IO.inspect :timer.tc fn -> IO.puts approx(20000) end
  end

  @doc """
  Launches n concurrent processes to compute an approximation of pi.
  """
  def approx(n) do
    ch = Chan.new
    Enum.each 0..n, fn(k) ->
      spawn(__MODULE__, :term, [ch, k])
    end
    result = Enum.reduce 0..n, 0, fn(_, acc) ->
      acc + Chan.read(ch)
    end
    Chan.close(ch)
    result
  end

  def term(ch, k) do
    Chan.write(ch, 4 * :math.pow(-1, k) / (2*k + 1))
  end
end
