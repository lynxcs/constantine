import
  # STD lib
  std/[os, strutils, cpuinfo, strformat, math],
  # Library
  ../../constantine/threadpool

when not defined(windows):
  # bench
  import ../wtime, ../resources

var tp: Threadpool

proc fib(n: int): int =
  # int64 on x86-64
  if n < 2:
    return n

  let x = tp.spawn fib(n-1)
  let y = fib(n-2)

  result = sync(x) + y

proc main() =
  var n = 40
  var nthreads: int

  if paramCount() == 0:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <n-th fibonacci number requested:{n}> "
    echo &"Running with default n = {n}"
  elif paramCount() == 1:
    n = paramStr(1).parseInt
  else:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <n-th fibonacci number requested:{n}>"
    quit 1

  if existsEnv"CTT_NUM_THREADS":
    nthreads = getEnv"CTT_NUM_THREADS".parseInt()
  else:
    nthreads = countProcessors()

  tp = Threadpool.new()

  # measure overhead during tasking
  when not defined(windows):
    var ru: Rusage
    getrusage(RusageSelf, ru)
    var
      rss = ru.ru_maxrss
      flt = ru.ru_minflt

    let start = wtime_msec()
  let f = fib(n)

  when not defined(windows):
    let stop = wtime_msec()

  tp.shutdown()

  when not defined(windows):
    getrusage(RusageSelf, ru)
    rss = ru.ru_maxrss - rss
    flt = ru.ru_minflt - flt

  echo "--------------------------------------------------------------------------"
  echo "Scheduler:                                    Constantine's Threadpool"
  echo "Benchmark:                                    Fibonacci"
  echo "Threads:                                      ", nthreads
  when not defined(windows):
    echo "Time(ms)                                      ", round(stop - start, 3)
    echo "Max RSS (KB):                                 ", ru.ru_maxrss
    echo "Runtime RSS (KB):                             ", rss
    echo "# of page faults:                             ", flt
  echo "--------------------------------------------------------------------------"
  echo "n requested:                                  ", n
  echo "result:                                       ", f

main()
