module attributes {gpu.container_module} {
  gpu.module @kernels [#nvvm.target<chip = "sm_75">] {
    gpu.func @vecadd(%a: !llvm.ptr, %b: !llvm.ptr, %c: !llvm.ptr, %n: i64) kernel {
      %tix = gpu.thread_id x
      %bdx = gpu.block_dim x
      %bix = gpu.block_id x
      %off = arith.muli %bix, %bdx : index
      %idx = arith.addi %off, %tix : index
      %i = arith.index_cast %idx : index to i64
      %cnd = arith.cmpi slt, %i, %n : i64
      cf.cond_br %cnd, ^bb1, ^bb2
    ^bb1:
      %pa = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, f64
      %va = llvm.load %pa : !llvm.ptr -> f64
      %pb = llvm.getelementptr %b[%i] : (!llvm.ptr, i64) -> !llvm.ptr, f64
      %vb = llvm.load %pb : !llvm.ptr -> f64
      %s = arith.addf %va, %vb : f64
      %pc = llvm.getelementptr %c[%i] : (!llvm.ptr, i64) -> !llvm.ptr, f64
      llvm.store %s, %pc : f64, !llvm.ptr
      cf.br ^bb2
    ^bb2:
      gpu.return
    }
  }
  func.func @host_add(%a: !llvm.ptr, %b: !llvm.ptr, %c: !llvm.ptr, %n: i64) -> i64 {
    %c255 = arith.constant 255 : i64
    %c256 = arith.constant 256 : i64
    %c1 = arith.constant 1 : i64
    %c0 = arith.constant 0 : i64
    %nb = arith.addi %n, %c255 : i64
    %gx64 = arith.divsi %nb, %c256 : i64
    %one = arith.constant 1 : i64
    %blk = arith.constant 256 : i64
    gpu.launch_func @kernels::@vecadd blocks in (%gx64, %one, %one) threads in (%blk, %one, %one) : i64
        args(%a: !llvm.ptr, %b: !llvm.ptr, %c: !llvm.ptr, %n: i64)
    return %c0 : i64
  }
}
