import Core;
import Std;
import Math;

# AnimSystem — 动画采样系统（P5，doc/07 §3.2 帧序）
# 用法：app.animSystem = AnimSystem()；Application 每帧在 start/update 段
# 之前调 update(activeScene, deltaTime)——「先采样再收集批次」（doc/07
# §3.2 关键顺序：采样后的变换才进合批顶点烘焙）。
# 只推进 playing 的 Animation；非 loop 到尾自动停住（Animation.advance）。
public class AnimSystem
{
    public Int32 animCount = 0

    public void update( Scene scene, Float32 dt )
    {
        if scene == null
        {
            ret
        }
        List<Animation> anims = List<Animation>( 8 )
        List<GameObject> stack = List<GameObject>( 16 )
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
            if cur.getActiveInHierarchy() && cur.pendingDestroy == false
            {
                Animation a = cur.getComponent<Animation>()
                if a != null
                {
                    anims.add( a )
                }
            }
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
        this.animCount = anims.length
        Int32 i = 0
        Int32 n = anims.length
        while i < n
        {
            Animation a = anims[i]
            if a.playing
            {
                a.advance( dt )
                a.evaluate( a.time )
            }
            i = i + 1
        }
    }
}
