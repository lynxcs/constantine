# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.
#
# Original code licenses
# ------------------------------------------------------------------------------------------------
#
# /**********************************************************************************************/
# /*  This program is part of the Barcelona OpenMP Tasks Suite                                  */
# /*  Copyright (C) 2009 Barcelona Supercomputing Center - Centro Nacional de Supercomputacion  */
# /*  Copyright (C) 2009 Universitat Politecnica de Catalunya                                   */
# /*                                                                                            */
# /*  This program is free software; you can redistribute it and/or modify                      */
# /*  it under the terms of the GNU General Public License as published by                      */
# /*  the Free Software Foundation; either version 2 of the License, or                         */
# /*  (at your option) any later version.                                                       */
# /*                                                                                            */
# /*  This program is distributed in the hope that it will be useful,                           */
# /*  but WITHOUT ANY WARRANTY; without even the implied warranty of                            */
# /*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                             */
# /*  GNU General Public License for more details.                                              */
# /*                                                                                            */
# /*  You should have received a copy of the GNU General Public License                         */
# /*  along with this program; if not, write to the Free Software                               */
# /*  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA            */
# /**********************************************************************************************/
#
# /*
#  * Original code from the Cilk project (by Keith Randall)
#  *
#  * Copyright (c) 2000 Massachusetts Institute of Technology
#  * Copyright (c) 2000 Matteo Frigo
#  */

import
  # Stdlib
  system/ansi_c, std/[strformat, os, strutils, cpuinfo],
  # library
  ../../constantine/threadpool

when not defined(windows):
  # bench
  import ../wtime, ../resources

# Nim helpers
# -------------------------------------------------

when defined(windows):
  proc alloca(size: int): pointer {.header: "<malloc.h>".}
else:
  proc alloca(size: int): pointer {.header: "<alloca.h>".}

template alloca*(T: typedesc): ptr T =
  cast[ptr T](alloca(sizeof(T)))

template alloca*(T: typedesc, len: Natural): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](alloca(sizeof(T) * len))

proc tp_alloc*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T] {.inline.} =
  when defined(TP_useNimAlloc):
    cast[type result](createSharedU(T, len))
  else:
    cast[type result](c_malloc(csize_t len*sizeof(T)))

proc tp_free*[T: ptr](p: T) {.inline.} =
  when defined(TP_useNimAlloc):
    freeShared(p)
  else:
    c_free(p)

# We assume that Nim zeroMem vs C memset
# and Nim copyMem vs C memcpy have no difference
# Nim does have extra checks to handle GC-ed types
# but they should be eliminated by the Nim compiler.

# -------------------------------------------------

type CharArray = ptr UncheckedArray[char]

var tp: Threadpool
var example_solution: ptr UncheckedArray[char]

func isValid(n: int32, a: CharArray): bool =
  ## `a` contains an array of `n` queen positions.
  ## Returns true if none of the queens conflict and 0 otherwise.

  for i in 0'i32 ..< n:
    let p = cast[int32](a[i])

    for j in i+1 ..< n:
      let q = cast[int32](a[j])
      if q == p or q == p - (j-i) or q == p + (j-i):
        return false
  return true

proc nqueens_ser(n, j: int32, a: CharArray): int32 =
  # Serial nqueens
  if n == j:
    # Good solution count it
    if example_solution.isNil:
      example_solution = tp_alloc(char, n)
      copyMem(example_solution, a, n * sizeof(char))
    return 1

  # Try each possible position for queen `j`
  for i in 0 ..< n:
    a[j] = cast[char](i)
    if isValid(j+1, a):
      result += nqueens_ser(n, j+1, a)

proc nqueens_par(n, j: int32, a: CharArray): int32 {.gcsafe.} =

  if n == j:
    # Good solution, count it
    return 1

  var localCounts = alloca(Flowvar[int32], n)
  zeroMem(localCounts, n * sizeof(Flowvar[int32]))

  # Try each position for queen `j`
  for i in 0 ..< n:
    var b = alloca(char, j+1)
    copyMem(b, a, j * sizeof(char))
    b[j] = cast[char](i)
    if isValid(j+1, b):
      localCounts[i] = tp.spawn nqueens_par(n, j+1, b)

  for i in 0 ..< n:
    if localCounts[i].isSpawned():
      result += sync(localCounts[i])

const solutions = [
  1,
  0,
  0,
  2,
  10, # 5x5
  4,
  10,
  92, # 8x8
  352,
  724, # 10x10
  2680,
  14200,
  73712,
  365596,
  2279184, # 15x15
  14772512
]

proc verifyQueens(n, res: int32) =
  if n > solutions.len:
    echo &"Cannot verify result: {n} is out of range [1,{solutions.len}]"
    return

  if res != solutions[n-1]:
    echo &"N-Queens failure: {res} is different from expected {solutions[n-1]}"

proc main() =
  var
    n = 11'i32
    nthreads: int

  if existsEnv"CTT_NUM_THREADS":
    nthreads = getEnv"CTT_NUM_THREADS".parseInt()
  else:
    nthreads = countProcessors()

  if paramCount() == 0:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <N:{n}>"
    echo &"Running with default config N = {n}\n"

  if paramCount() >= 1:
    n = paramStr(1).parseInt.int32

  if n notin 1 .. solutions.len:
    echo &"The number of queens N (on a NxN board) must be in the range [1, {solutions.len}]"
    quit 1

  when not defined(windows):
    var ru: Rusage
    getrusage(RusageSelf, ru)
    var
      rss = ru.ru_maxrss
      flt = ru.ru_minflt

  tp = Threadpool.new(numThreads = nthreads)

  when not defined(windows):
    let start = wtime_msec()

  let count = nqueens_par(n, 0, alloca(char, n))

  when not defined(windows):
    let stop = wtime_msec()

  when not defined(windows):
    getrusage(RusageSelf, ru)
    rss = ru.ru_maxrss - rss
    flt = ru.ru_minflt - flt

  tp.shutdown()

  verifyQueens(n, count)

  if not example_solution.isNil:
    stdout.write("Example solution: ")
    for i in 0 ..< n:
      c_printf("%2d ", example_solution[i])
    stdout.write('\n')

  echo "--------------------------------------------------------------------------"
  echo "Scheduler:            Constantine's Threadpool"
  echo "Benchmark:            N-queens"
  echo "Threads:              ", nthreads
  when not defined(windows):
    echo "Time(ms)              ", stop - start
    echo "Max RSS (KB):         ", ru.ru_maxrss
    echo "Runtime RSS (KB):     ", rss
    echo "# of page faults:     ", flt
  echo "Problem size:         ", n,"x",n, " board with ",n, " queens"
  echo "Solutions found:      ", count
  echo "--------------------------------------------------------------------------"

  quit 0

main()
