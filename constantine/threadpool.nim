# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./threadpool/[threadpool, partitioners]
import ./zoo_exports

export threadpool, partitioners

proc ctt_threadpool_new*(num_threads: csize_t): Threadpool {.libPrefix: "", raises: [ResourceExhaustedError].} =
  Threadpool.new(cast[int](numThreads))