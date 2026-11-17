import Core;
import Std;
import Math;
import SLangRender;

# ============================================================================
# MeshCollider - 网格碰撞体（P3 补全 v0.1 + GJK 精化 v1，doc/11 §2）
# ----------------------------------------------------------------------------
# 退化形态（v0.1，保留）：以「网格近似包围盒」参与检测 - 直接继承
# BoxCollider，worldBounds / 宽相全复用，CollisionSystem 无需新 kind。
# GJK 精化（v1，2026-11-17）：setMeshVertices 登记凸点集（Memory 块缓存，
# float3 紧凑），CollisionSystem 盒-盒窄相命中后若双方均为 MeshCollider
# 且有点集 → C 侧 sle_gjk_intersect 精化（GJK=false 撤销该对——
# 消除包围盒误报）。**计算核心全在 C**（sle_points_transform 世界变换 +
# sle_gjk_intersect 相交），SL 侧只做组块与门面（复用专项约定）。
# 法线/穿透量需 EPA（远期）：当前接触仍取盒路径结果（保守近似）。
# 顶点块在碰撞体生命周期内持有（无 dispose 钩子——与场景同生命周期）。
# ============================================================================

public class MeshCollider extends BoxCollider
{
    # 是否凸包（GJK 语义前提；凹网格请自行拆凸块）
    public bool convex = true

    Int64 _localPtr = 0
    Int64 _worldPtr = 0
    Int64 _matPtr = 0
    Int64 _mtvPtr = 0
    Int32 _vertCount = 0

    # 登记凸点集（local 空间；一次性组块；重复调用覆盖）
    public void setMeshVertices( List<Float32_3> localVerts )
    {
        this._freeBlocks()
        if localVerts == null
        {
            ret
        }
        Int32 n = localVerts.length
        if n < 1
        {
            ret
        }
        Int64 lp = Memory.alloc( n * 12 )
        Int64 wp = Memory.alloc( n * 12 )
        Int64 mp = Memory.alloc( 64 )
        Int64 tp = Memory.alloc( 16 )
        if lp == 0 || wp == 0 || mp == 0 || tp == 0
        {
            if lp != 0
            {
                Memory.free( lp )
            }
            if wp != 0
            {
                Memory.free( wp )
            }
            if mp != 0
            {
                Memory.free( mp )
            }
            if tp != 0
            {
                Memory.free( tp )
            }
            ret
        }
        Int32 i = 0
        while i < n
        {
            Float32_3 v = localVerts[i]
            Int32 off = i * 12
            Memory.writeF32( lp, off + 0, v.x )
            Memory.writeF32( lp, off + 4, v.y )
            Memory.writeF32( lp, off + 8, v.z )
            i = i + 1
        }
        this._localPtr = lp
        this._worldPtr = wp
        this._matPtr = mp
        this._mtvPtr = tp
        this._vertCount = n
    }

    void _freeBlocks()
    {
        if this._localPtr != 0
        {
            Memory.free( this._localPtr )
            this._localPtr = 0
        }
        if this._worldPtr != 0
        {
            Memory.free( this._worldPtr )
            this._worldPtr = 0
        }
        if this._matPtr != 0
        {
            Memory.free( this._matPtr )
            this._matPtr = 0
        }
        if this._mtvPtr != 0
        {
            Memory.free( this._mtvPtr )
            this._mtvPtr = 0
        }
        this._vertCount = 0
    }

    public Int32 meshVertCount()
    {
        ret this._vertCount
    }

    # 顶点集世界变换（每次查询刷新——C 侧批量变换，代价 O(verts)）
    void refreshWorldVerts()
    {
        if this._vertCount < 1 || this._localPtr == 0 || this._worldPtr == 0 || this._matPtr == 0
        {
            ret
        }
        GameObject ow = this.owner
        if ow == null
        {
            ret
        }
        Transform t = ow.transform
        Float32_4x4 m = t.worldMatrix()
        Memory.writeF32( this._matPtr, 0, m.m00 )
        Memory.writeF32( this._matPtr, 4, m.m01 )
        Memory.writeF32( this._matPtr, 8, m.m02 )
        Memory.writeF32( this._matPtr, 12, m.m03 )
        Memory.writeF32( this._matPtr, 16, m.m10 )
        Memory.writeF32( this._matPtr, 20, m.m11 )
        Memory.writeF32( this._matPtr, 24, m.m12 )
        Memory.writeF32( this._matPtr, 28, m.m13 )
        Memory.writeF32( this._matPtr, 32, m.m20 )
        Memory.writeF32( this._matPtr, 36, m.m21 )
        Memory.writeF32( this._matPtr, 40, m.m22 )
        Memory.writeF32( this._matPtr, 44, m.m23 )
        Memory.writeF32( this._matPtr, 48, m.m30 )
        Memory.writeF32( this._matPtr, 52, m.m31 )
        Memory.writeF32( this._matPtr, 56, m.m32 )
        Memory.writeF32( this._matPtr, 60, m.m33 )
        EngineFfi.libPointsTransform( this._matPtr, this._localPtr, this._vertCount, this._worldPtr )
    }

    # GJK 相交查询（双方顶点集世界变换后交 C 判定；无点集一方返回 false——
    # 走盒退化路径由 CollisionSystem 分派）
    public bool meshIntersects( MeshCollider other )
    {
        if other == null
        {
            ret false
        }
        Int32 oc = other.meshVertCount()
        if this._vertCount < 1 || oc < 1
        {
            ret false
        }
        this.refreshWorldVerts()
        other.refreshWorldVerts()
        Int32 hit = EngineFfi.libGjkIntersect( this._worldPtr, this._vertCount, other._worldPtr, oc )
        ret hit == 1
    }

    # GJK/MTV 接触：相交时把 info.normal（B→A）/penetration 覆写为
    # C 侧 26 方向采样 MTV 结果（轴对齐精确/旋转保守近似）；point 取
    # 双方包围盒中心中点（近似接触点）；未相交返回 false。
    public bool meshContact( MeshCollider other, ContactInfo info )
    {
        if other == null || info == null
        {
            ret false
        }
        Int32 oc = other.meshVertCount()
        if this._vertCount < 1 || oc < 1 || this._mtvPtr == 0
        {
            ret false
        }
        this.refreshWorldVerts()
        other.refreshWorldVerts()
        Int32 hit = EngineFfi.libGjkMtv( this._worldPtr, this._vertCount, other._worldPtr, oc, this._mtvPtr )
        if hit != 1
        {
            ret false
        }
        Float32 nx = Memory.readFloat32( this._mtvPtr, 0 )
        Float32 ny = Memory.readFloat32( this._mtvPtr, 4 )
        Float32 nz = Memory.readFloat32( this._mtvPtr, 8 )
        Float32 dep = Memory.readFloat32( this._mtvPtr, 12 )
        Float32_3 n3 = Float32_3( nx, ny, nz )
        info.normal = n3
        info.penetration = dep
        Bounds wa = this.worldBounds
        Bounds wb = other.worldBounds
        Float32_3 ca = wa.center
        Float32_3 cb = wb.center
        Float32_3 mid = Float32_3( ( ca.x + cb.x ) * 0.5f, ( ca.y + cb.y ) * 0.5f, ( ca.z + cb.z ) * 0.5f )
        info.point = mid
        ret true
    }
}