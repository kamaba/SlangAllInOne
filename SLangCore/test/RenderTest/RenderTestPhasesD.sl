import SLangRender;
import SLangAudio;
import Math;
import Std;

# RT 句柄池 phase 分组（2026-11-18：FEATURE/ASSET/FS 相位随 SRP 草稿链
# 移除，仅保留独立于草稿的 RT 池验证）：
#   runRtPool          Phase RTPOOL   RT 句柄池（同尺寸复用 / releaseAll）
public class RenderTestPhasesD
{
    # ── Phase RTPOOL：RT 句柄池（AIPrompt P4：RTHandleSystem 等价物）──
    # 同尺寸请求复用（C 侧纹理计数不变）+ 异尺寸新建 + releaseAll 归零。
    public static bool runRtPool()
    {
        Console.println( "-- Phase RTPOOL: RTHandlePool request/reuse/release (cap 64) --" )
        SLang.RTHandlePool pool = SLang.RTHandlePool()
        if pool == null
        {
            Console.println( "[pool] FAIL: pool alloc" )
            ret false
        }
        if pool.count() != 0
        {
            Console.println( "[pool] FAIL: fresh pool expect 0" )
            ret false
        }
        Int64 texPtr = RenderTestHelpers.makeGradientTexture()
        if texPtr == 0
        {
            Console.println( "[pool] FAIL: texture pixels alloc" )
            ret false
        }
        Int32 baseline = RenderFFI.ffiTextureCount()

        # ① 同尺寸两次请求 -> 同一句柄，C 侧纹理计数只 +1
        SLang.RenderTexture t1 = pool.request( 64, 64, texPtr )
        if t1 == null
        {
            Console.println( "[pool] FAIL: request 64x64 - " + SLang.Render.errorString() )
            Memory.free( texPtr )
            ret false
        }
        SLang.RenderTexture t2 = pool.request( 64, 64, texPtr )
        if t2 == null
        {
            Console.println( "[pool] FAIL: request 64x64 again" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        if t2.handle != t1.handle
        {
            Console.println( "[pool] FAIL: same-size request should reuse handle" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Int32 afterReuse = RenderFFI.ffiTextureCount()
        if afterReuse != baseline + 1
        {
            Console.println( "[pool] FAIL: texture count expect +1 after reuse, got +" + ( afterReuse - baseline ).toString() )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }

        # ② 异尺寸请求 -> 新建句柄（池计数 2）
        SLang.RenderTexture t3 = pool.request( 32, 32, texPtr )
        if t3 == null
        {
            Console.println( "[pool] FAIL: request 32x32" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        if t3.handle == t1.handle
        {
            Console.println( "[pool] FAIL: different-size request must not reuse" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Int32 afterNew = RenderFFI.ffiTextureCount()
        if afterNew != baseline + 2 || pool.count() != 2 || pool.reuseCount() != 1 || pool.requestCount() != 3
        {
            Console.println( "[pool] FAIL: pool stats (count/reuse/request)" )
            pool.releaseAll()
            Memory.free( texPtr )
            ret false
        }
        Console.println( "[pool] " + pool.toString() + ", texture count " + baseline.toString() + " -> " + afterNew.toString() )

        # ③ releaseAll -> 计数归零、C 侧纹理数回基线
        pool.releaseAll()
        if pool.count() != 0
        {
            Console.println( "[pool] FAIL: releaseAll count expect 0" )
            Memory.free( texPtr )
            ret false
        }
        Int32 afterRelease = RenderFFI.ffiTextureCount()
        if afterRelease != baseline
        {
            Console.println( "[pool] FAIL: texture count should return to baseline" )
            Memory.free( texPtr )
            ret false
        }
        Memory.free( texPtr )
        Console.println( "[pool] Phase RTPOOL: PASS (size-keyed reuse + releaseAll: counts all ok)" )
        ret true
    }
}
