"""
Execution time comparison.

Go:

    λ time ./pi
    3.1417926135957908
    ./pi  0.01s user 0.01s system 87% cpu 0.027 total

Elixir[raw processes]:

    λ time mix run 'IO.puts PiNative.approx(20000)'
    3.14154091392784406978e+00
    mix run 'IO.puts PiNative.approx(20000)'  0.57s user 0.24s system 162% cpu 0.497 total

Elixir[gochan]:

    λ time mix run 'IO.puts Pi.approx(20000)'
    3.14164265108988693953e+00
    mix run 'IO.puts Pi.approx(20000)'  3.86s user 0.90s system 215% cpu 2.212 total

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
)

func main() {
	fmt.Println(pi(20000))
}

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
