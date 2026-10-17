module attributes {gpu.container_module} {
  gpu.module @kernels {
    llvm.func @vecadd(%arg0: !llvm.ptr, %arg1: !llvm.ptr, %arg2: !llvm.ptr, %arg3: i64) attributes {gpu.kernel, nvvm.kernel} {
      %0 = nvvm.read.ptx.sreg.tid.x : i32
      %1 = llvm.sext %0 : i32 to i64
      %2 = nvvm.read.ptx.sreg.ntid.x : i32
      %3 = llvm.sext %2 : i32 to i64
      %4 = nvvm.read.ptx.sreg.ctaid.x : i32
      %5 = llvm.sext %4 : i32 to i64
      %6 = llvm.mul %5, %3 : i64
      %7 = llvm.add %6, %1 : i64
      %8 = llvm.icmp "slt" %7, %arg3 : i64
      scf.if %8 {
        %9 = llvm.getelementptr %arg0[%7] : (!llvm.ptr, i64) -> !llvm.ptr, f64
        %10 = llvm.load %9 : !llvm.ptr -> f64
        %11 = llvm.getelementptr %arg1[%7] : (!llvm.ptr, i64) -> !llvm.ptr, f64
        %12 = llvm.load %11 : !llvm.ptr -> f64
        %13 = llvm.fadd %10, %12 : f64
        %14 = llvm.getelementptr %arg2[%7] : (!llvm.ptr, i64) -> !llvm.ptr, f64
        llvm.store %13, %14 : f64, !llvm.ptr
      }
      llvm.return
    }
  }
  llvm.func @host_add(%arg0: !llvm.ptr, %arg1: !llvm.ptr, %arg2: !llvm.ptr, %arg3: i64) -> i64 {
    %0 = llvm.mlir.constant(255 : i64) : i64
    %1 = llvm.mlir.constant(256 : i64) : i64
    %2 = llvm.mlir.constant(1 : i64) : i64
    %3 = llvm.mlir.constant(0 : i64) : i64
    %4 = llvm.add %arg3, %0 : i64
    %5 = llvm.sdiv %4, %1 : i64
    gpu.launch_func  @kernels::@vecadd blocks in (%5, %2, %2) threads in (%1, %2, %2) : i64 args(%arg0 : !llvm.ptr, %arg1 : !llvm.ptr, %arg2 : !llvm.ptr, %arg3 : i64)
    llvm.return %3 : i64
  }
}

