// gpu_spike2.mlir — end-to-end staging spike (mirrors the planned C# emitter output).
//
// Kernel side:  grid-stride loop over [0, n) with locals spilled to an
//               llvm.alloca stack (kernel-mode equivalent of the host
//               memref spill machinery).
// Host side:    malloc device buffers, HtoD inputs, gpu.launch_func with
//               device pointers, DtoH outputs, free.
module attributes {gpu.container_module} {
  gpu.module @kernels [#nvvm.target<chip = "sm_75">] {
    gpu.func @vecadd(%a: !llvm.ptr, %b: !llvm.ptr, %c: !llvm.ptr, %n: i64) kernel {
      // ---- prologue: thread id / stride ----
      %c8 = llvm.mlir.constant(8 : i64) : i64
      %c1s = llvm.mlir.constant(1 : i64) : i64
      %tix = gpu.thread_id x
      %bdx = gpu.block_dim x
      %bix = gpu.block_id x
      %gdx = gpu.grid_dim x
      %off = arith.muli %bix, %bdx : index
      %idx = arith.addi %off, %tix : index
      %i0 = arith.index_cast %idx : index to i64
      %gstride = arith.muli %gdx, %bdx : index
      %stride = arith.index_cast %gstride : index to i64
      // ---- locals stack (slot 1 = loop var i) ----
      %stack = llvm.alloca %c8 x i64 : (i64) -> !llvm.ptr
      %pi = llvm.getelementptr %stack[%c1s] : (!llvm.ptr, i64) -> !llvm.ptr, i64
      llvm.store %i0, %pi : i64, !llvm.ptr
      cf.br ^head
    ^head:
      %i1 = llvm.load %pi : !llvm.ptr -> i64
      %cnd = arith.cmpi slt, %i1, %n : i64
      cf.cond_br %cnd, ^body, ^exit
    ^body:
      %pa = llvm.getelementptr %a[%i1] : (!llvm.ptr, i64) -> !llvm.ptr, f64
      %va = llvm.load %pa : !llvm.ptr -> f64
      %pb = llvm.getelementptr %b[%i1] : (!llvm.ptr, i64) -> !llvm.ptr, f64
      %vb = llvm.load %pb : !llvm.ptr -> f64
      %s = arith.addf %va, %vb : f64
      %pc = llvm.getelementptr %c[%i1] : (!llvm.ptr, i64) -> !llvm.ptr, f64
      llvm.store %s, %pc : f64, !llvm.ptr
      cf.br ^incr
    ^incr:
      %i2 = llvm.load %pi : !llvm.ptr -> i64
      %i3 = arith.addi %i2, %stride : i64
      llvm.store %i3, %pi : i64, !llvm.ptr
      cf.br ^head
    ^exit:
      gpu.return
    }
  }

  func.func @host_vecadd_staged(%a: !llvm.ptr, %b: !llvm.ptr, %c: !llvm.ptr, %n: i64) -> i64 {
    %c8 = arith.constant 8 : i64
    %c255 = arith.constant 255 : i64
    %c256 = arith.constant 256 : i64
    %c1 = arith.constant 1 : i64
    %c0 = arith.constant 0 : i64
    // staging: device buffers
    %bytes = arith.muli %n, %c8 : i64
    %da = llvm.call @slgpuMalloc(%bytes) : (i64) -> !llvm.ptr
    %db = llvm.call @slgpuMalloc(%bytes) : (i64) -> !llvm.ptr
    %dc = llvm.call @slgpuMalloc(%bytes) : (i64) -> !llvm.ptr
    llvm.call @slgpuMemcpyHtoD(%da, %a, %bytes) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.call @slgpuMemcpyHtoD(%db, %b, %bytes) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    // grid = ceil(n / 256)
    %nb = arith.addi %n, %c255 : i64
    %gx = arith.divsi %nb, %c256 : i64
    gpu.launch_func @kernels::@vecadd blocks in (%gx, %c1, %c1) threads in (%c256, %c1, %c1) : i64
        args(%da: !llvm.ptr, %db: !llvm.ptr, %dc: !llvm.ptr, %n: i64)
    // copy back results
    llvm.call @slgpuMemcpyDtoH(%c, %dc, %bytes) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.call @slgpuFree(%da) : (!llvm.ptr) -> ()
    llvm.call @slgpuFree(%db) : (!llvm.ptr) -> ()
    llvm.call @slgpuFree(%dc) : (!llvm.ptr) -> ()
    return %c0 : i64
  }

  llvm.func @slgpuMalloc(i64) -> !llvm.ptr
  llvm.func @slgpuMemcpyHtoD(!llvm.ptr, !llvm.ptr, i64)
  llvm.func @slgpuMemcpyDtoH(!llvm.ptr, !llvm.ptr, i64)
  llvm.func @slgpuFree(!llvm.ptr)
}
