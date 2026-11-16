import Core;
import Std;
import Math;

# ============================================================================
# Batcher — 引擎侧合批器（P2，doc/05 §3）
# ----------------------------------------------------------------------------
# 流程：collect(scene, cullMask) 收集可见候选并**一次性读全键数据** →
# sortCandidates() 稳定排序（renderQueue 升序）→ build() 按键聚组。
# 架构约束（doc/10 §6 跨模块缺陷家族，SimBatchTest 实证）：
#   - 所有跨模块对象字段读（MeshRef/MaterialRef/MaterialData）只在
#     collectFrom 的收集上下文做一次（该上下文实测可靠），键值写入
#     Batcher 自己的平行 Int32/bool/Float32 数组；
#   - sort/build 阶段只消费平行数组标量，不再触碰跨模块对象图——
#     同一读取代码在后续方法上下文会返回 -1 类坏值；
#   - List 表达式下标 `list[i - 1]` 解析不支持（下标先落局部变量）；
#     List 下标写（_setItem_ override）跨模块静默失效——排序用
#     「新列表 + insert」稳定插入法；`>=` 循环条件不生效（用 `> 0 - 1`）；
#   - 组访问用 groupAt(i)（跨模块返回 List 容器不可靠）。
# Submit 段由调用方按组描述驱动 SLangRender（doc/05 §4 映射表）；
# 本类不引用 SLangRender（双模块根级同名类冲突）。
# ============================================================================

public class Batcher
{
    public Int32 maxObjectsPerBatch = 256

    List<BatchGroup> _groups = List<BatchGroup>( 8 )
    List<GameObject> _candGo = List<GameObject>( 32 )
    List<MeshRef> _candMesh = List<MeshRef>( 32 )
    List<MaterialRef> _candMat = List<MaterialRef>( 32 )
    # 平行键数组（collect 一次读全，sort/build 只消费标量）
    List<Int32> _candQueue = List<Int32>( 32 )
    List<MaterialData> _candMatData = List<MaterialData>( 32 )
    List<Int32> _candProgram = List<Int32>( 32 )
    List<Int32> _candTexture = List<Int32>( 32 )
    List<Int32> _candKind = List<Int32>( 32 )
    List<Int32> _candSlot = List<Int32>( 32 )
    List<Int32> _candLayer = List<Int32>( 32 )
    List<Int32> _candAnimMode = List<Int32>( 32 )
    List<Float32> _candSpecular = List<Float32>( 32 )
    List<Float32> _candAnimSpeed = List<Float32>( 32 )
    List<bool> _candShadow = List<bool>( 32 )
    List<bool> _candColorOv = List<bool>( 32 )
    List<Float32_3> _candColor = List<Float32_3>( 32 )
    List<Float32_3> _candVert0 = List<Float32_3>( 32 )

    public Int32 groupCount()
    {
        ret this._groups.length
    }

    # 按下标取组（单对象返回；跨模块返回 List 容器不可靠）
    public BatchGroup groupAt( Int32 idx )
    {
        ret this._groups[idx]
    }

    public Int32 candidateCount()
    {
        ret this._candGo.length
    }

    public void clear()
    {
        this._candGo.clear()
        this._candMesh.clear()
        this._candMat.clear()
        this._candQueue.clear()
        this._candMatData.clear()
        this._candProgram.clear()
        this._candTexture.clear()
        this._candKind.clear()
        this._candSlot.clear()
        this._candLayer.clear()
        this._candAnimMode.clear()
        this._candSpecular.clear()
        this._candAnimSpeed.clear()
        this._candShadow.clear()
        this._candColorOv.clear()
        this._candColor.clear()
        this._candVert0.clear()
        this._groups.clear()
    }

    # ── CollectVisible（键数据一次读全）──────────────────
    # 显式栈先序遍历（父先子后）——**不用递归**：递归方法体内的跨模块
    # 字段读失效（mat.renderQueue 读出 -1），非递归上下文同代码可靠
    # （doc/10 §6）。未激活节点不入栈（子树整体剪枝）。
    public void collect( Scene scene, Int32 cullMask )
    {
        this.clear()
        if scene == null
        {
            ret
        }
        List<GameObject> stack = List<GameObject>( 16 )
        # 根逆序入栈 → 弹出顺序 = 原序；根遍历用 rootCount/getRoot
        # （跨模块返回 List 容器不可靠）
        Int32 ri = scene.rootCount() - 1
        while ri > 0 - 1
        {
            GameObject r = scene.getRoot( ri )
            if r != null
            {
                stack.add( r )
            }
            ri = ri - 1
        }
        while stack.length > 0
        {
            Int32 lastIdx = stack.length - 1
            GameObject cur = stack[lastIdx]
            stack.removeAt( lastIdx )
            bool active = cur.getActiveInHierarchy()
            if active
            {
                Int32 layer = cur.layer
                Int32 layerBit = 1 << layer
                Int32 masked = layerBit & cullMask
                if masked != 0
                {
                    MeshRef mr = cur.getComponent<MeshRef>()
                    if mr != null
                    {
                        if mr.visible
                        {
                            MaterialRef mref = cur.getComponent<MaterialRef>()
                            if mref != null
                            {
                                MaterialData mat = mref.material
                                if mat != null
                                {
                                    # 键数据一次读全。
                                    # 坑：`mref.renderQueue` 跨模块 Int32 字段读
                                    # 返回垃圾且 `== 0 - 1` 比较失效——改用
                                    # 「< 1 = 跟随材质」判断（垃圾/0 都正确回退）
                                    Int32 q = mref.renderQueue
                                    if q < 1
                                    {
                                        q = mat.renderQueue
                                    }
                                    this._candGo.add( cur )
                                    this._candMesh.add( mr )
                                    this._candMat.add( mref )
                                    this._candQueue.add( q )
                                    this._candMatData.add( mat )
                                    this._candProgram.add( mat.programId )
                                    this._candTexture.add( mat.textureId )
                                    this._candKind.add( mr.meshKind )
                                    this._candSlot.add( mr.meshSlot )
                                    this._candLayer.add( layer )
                                    this._candAnimMode.add( mref.animatedMode )
                                    this._candSpecular.add( mat.specular )
                                    this._candAnimSpeed.add( mref.animatedSpeed )
                                    this._candShadow.add( mat.castShadow )
                                    this._candColorOv.add( mref.instanceColorOverride )
                                    if mref.instanceColorOverride
                                    {
                                        this._candColor.add( mref.instanceColor )
                                    }
                                    else
                                    {
                                        this._candColor.add( mat.color )
                                    }
                                }
                            }
                        }
                    }
                }
                # 子节点逆序入栈（弹出即原序）
                Int32 cn = cur.childCount
                Int32 ci = cn - 1
                while ci > 0 - 1
                {
                    GameObject ch = cur.getChild( ci )
                    if ch != null
                    {
                        stack.add( ch )
                    }
                    ci = ci - 1
                }
            }
        }
        this.sortCandidates()
    }

    # 按有效 renderQueue 升序稳定排序（新列表 + insert 稳定插入法；
    # 排序全程只消费平行数组标量）
    void sortCandidates()
    {
        List<GameObject> sGo = List<GameObject>( 0 )
        List<MeshRef> sMesh = List<MeshRef>( 0 )
        List<MaterialRef> sMat = List<MaterialRef>( 0 )
        List<Int32> sQueue = List<Int32>( 0 )
        List<MaterialData> sMatData = List<MaterialData>( 0 )
        List<Int32> sProgram = List<Int32>( 0 )
        List<Int32> sTexture = List<Int32>( 0 )
        List<Int32> sKind = List<Int32>( 0 )
        List<Int32> sSlot = List<Int32>( 0 )
        List<Int32> sLayer = List<Int32>( 0 )
        List<Int32> sAnimMode = List<Int32>( 0 )
        List<Float32> sSpecular = List<Float32>( 0 )
        List<Float32> sAnimSpeed = List<Float32>( 0 )
        List<bool> sShadow = List<bool>( 0 )
        List<bool> sColorOv = List<bool>( 0 )
        List<Float32_3> sColor = List<Float32_3>( 0 )
        List<Float32_3> sVert0 = List<Float32_3>( 0 )
        Int32 i = 0
        Int32 n = this._candGo.length
        while i < n
        {
            Int32 iq = this._candQueue[i]
            MaterialData imd = this._candMatData[i]
            GameObject go = this._candGo[i]
            MeshRef mr = this._candMesh[i]
            MaterialRef mref = this._candMat[i]
            Int32 prog = this._candProgram[i]
            Int32 tex = this._candTexture[i]
            Int32 kind = this._candKind[i]
            Int32 slot = this._candSlot[i]
            Int32 lay = this._candLayer[i]
            Int32 am = this._candAnimMode[i]
            Float32 sp = this._candSpecular[i]
            Float32 aspd = this._candAnimSpeed[i]
            bool sh = this._candShadow[i]
            bool cov = this._candColorOv[i]
            Float32_3 col = this._candColor[i]
            Float32_3 v0 = this._candVert0[i]
            # 从尾向头找第一个 queue <= iq 的位置（稳定：相等插其后）
            Int32 pos = sGo.length
            Int32 k = sGo.length - 1
            while k > 0 - 1
            {
                Int32 oq = sQueue[k]
                if oq > iq
                {
                    pos = k
                    k = k - 1
                }
                else
                {
                    k = 0 - 1
                }
            }
            sGo.insert( pos, go )
            sMesh.insert( pos, mr )
            sMat.insert( pos, mref )
            sQueue.insert( pos, iq )
            sMatData.insert( pos, imd )
            sProgram.insert( pos, prog )
            sTexture.insert( pos, tex )
            sKind.insert( pos, kind )
            sSlot.insert( pos, slot )
            sLayer.insert( pos, lay )
            sAnimMode.insert( pos, am )
            sSpecular.insert( pos, sp )
            sAnimSpeed.insert( pos, aspd )
            sShadow.insert( pos, sh )
            sColorOv.insert( pos, cov )
            sColor.insert( pos, col )
            sVert0.insert( pos, v0 )
            i = i + 1
        }
        this._candGo = sGo
        this._candMesh = sMesh
        this._candMat = sMat
        this._candQueue = sQueue
        this._candMatData = sMatData
        this._candProgram = sProgram
        this._candTexture = sTexture
        this._candKind = sKind
        this._candSlot = sSlot
        this._candLayer = sLayer
        this._candAnimMode = sAnimMode
        this._candSpecular = sSpecular
        this._candAnimSpeed = sAnimSpeed
        this._candShadow = sShadow
        this._candColorOv = sColorOv
        this._candColor = sColor
        this._candVert0 = sVert0
    }

    # ── BuildBatches（只消费平行数组标量）────────────────
    public void build()
    {
        Int32 i = 0
        Int32 n = this._candGo.length
        while i < n
        {
            GameObject go = this._candGo[i]
            MeshRef mr = this._candMesh[i]
            if mr.hasVertexData
            {
                this.addToBakedGroup( i, go, mr )
            }
            else
            {
                this.addSingleGroup( i, go, mr )
            }
            i = i + 1
        }
    }

    BatchGroup newGroup( Int32 i, GameObject go, MeshRef mr )
    {
        BatchGroup g = BatchGroup()
        g.material = this._candMatData[i]
        g.programId = this._candProgram[i]
        g.textureId = this._candTexture[i]
        g.meshKind = this._candKind[i]
        g.meshSlot = this._candSlot[i]
        g.layer = this._candLayer[i]
        g.renderQueue = this._candQueue[i]
        g.specular = this._candSpecular[i]
        g.castShadow = this._candShadow[i]
        g.animatedMode = this._candAnimMode[i]
        g.animatedSpeed = this._candAnimSpeed[i]
        g.color = this._candColor[i]
        this._groups.add( g )
        ret g
    }

    void addSingleGroup( Int32 i, GameObject go, MeshRef mr )
    {
        BatchGroup g = this.newGroup( i, go, mr )
        g.singleObject = true
        g.soleMember = go
        g.members.add( go )
    }

    void addToBakedGroup( Int32 i, GameObject go, MeshRef mr )
    {
        Int32 idx = this.findOpenGroup( i )
        BatchGroup g = null
        if idx >= 0
        {
            g = this._groups[idx]
        }
        if g == null
        {
            g = this.newGroup( i, go, mr )
        }
        g.members.add( go )
    }

    # 找同键且未满的烘焙组（键比较只用平行数组标量）
    Int32 findOpenGroup( Int32 i )
    {
        Int32 j = 0
        Int32 n = this._groups.length
        while j < n
        {
            BatchGroup g = this._groups[j]
            if !g.singleObject
            {
                Int32 mc = g.memberCount()
                if mc < this.maxObjectsPerBatch
                {
                    bool same = this.keyEquals( g, i )
                    if same
                    {
                        ret j
                    }
                }
            }
            j = j + 1
        }
        ret 0 - 1
    }

    bool keyEquals( BatchGroup g, Int32 i )
    {
        # 材质实例身份（键分量 2）：引用比较（跨模块引用 != 可靠，
        # 同 List.indexOf 先例）。比较右侧一律先落局部变量
        # （`g.x != this._candY[i]` 形态解析报「不能进行加减运算」）
        MaterialData mo = this._candMatData[i]
        if g.material != mo
        {
            ret false
        }
        Int32 rp = this._candProgram[i]
        if g.programId != rp
        {
            ret false
        }
        Int32 rt = this._candTexture[i]
        if g.textureId != rt
        {
            ret false
        }
        Int32 rk = this._candKind[i]
        if g.meshKind != rk
        {
            ret false
        }
        Int32 rsl = this._candSlot[i]
        if g.meshSlot != rsl
        {
            ret false
        }
        Int32 rl = this._candLayer[i]
        if g.layer != rl
        {
            ret false
        }
        Int32 rq = this._candQueue[i]
        if g.renderQueue != rq
        {
            ret false
        }
        Int32 ram = this._candAnimMode[i]
        if g.animatedMode != ram
        {
            ret false
        }
        Float32 rs = this._candSpecular[i]
        if g.specular != rs
        {
            ret false
        }
        bool rsh = this._candShadow[i]
        if g.castShadow != rsh
        {
            ret false
        }
        Float32_3 gc = g.color
        Float32_3 cc = this._candColor[i]
        bool sameColor = Batcher.colorEq( gc, cc )
        if !sameColor
        {
            ret false
        }
        ret true
    }

    static bool colorEq( Float32_3 a, Float32_3 b )
    {
        if a.x != b.x
        {
            ret false
        }
        if a.y != b.y
        {
            ret false
        }
        if a.z != b.z
        {
            ret false
        }
        ret true
    }
}
