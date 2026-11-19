import Core;
import Std;
import Math;
import SimGameEngine;
import SLangRender;

# SceneInspector minimal (bisect)
public class SceneInspector
{
    static bool visible = false
    static Scene targetScene = null
    static string lastSelPath = ""

    public static void toggle( Scene scene )
    {
        if scene == null
        {
            ret
        }
        targetScene = scene
        visible = !visible
        if visible
        {
            QTHost.inspectorShow()
            refreshTree()
            lastSelPath = "@reset@"
        }
        else
        {
            QTHost.inspectorHide()
        }
    }

    public static void poll()
    {
        if !visible
        {
            ret
        }
        string sel = QTHost.insTreeSelectedPath()
        if sel != lastSelPath
        {
            lastSelPath = sel
            if sel.length > 0
            {
                GameObject go = targetScene.find( sel )
                showInfo( go, sel )
            }
        }
    }

    static void refreshTree()
    {
        QTHost.insTreeClear()
        Int32 i = 0
        Int32 n = targetScene.rootCount
        while i < n
        {
            GameObject r = targetScene.getRoot( i )
            if r != null
            {
                addNode( r, "" )
            }
            i = i + 1
        }
        QTHost.insTreeExpandAll()
    }

    static void addNode( GameObject go, string parentPath )
    {
        string path = go.name
        if parentPath.length > 0
        {
            path = parentPath + "/" + go.name
        }
        QTHost.insTreeAddPath( path )
        Int32 j = 0
        Int32 m = go.childCount
        while j < m
        {
            GameObject ch = go.getChild( j )
            if ch != null
            {
                addNode( ch, path )
            }
            j = j + 1
        }
    }

    static string b2s( bool v )
    {
        if v
        {
            ret "true"
        }
        ret "false"
    }

    static void showInfo( GameObject go, string path )
    {
        if go == null
        {
            QTHost.insTextSetText( "node not found: " + path )
            ret
        }
        string nl = "\n"
        string t = "=== Node ===" + nl
        t = t + "name: " + go.name + nl
        t = t + "tag: " + go.tag + nl
        t = t + "layer: " + go.layer.toString() + nl
        bool aself = go.activeSelf
        t = t + "activeSelf: " + b2s( aself ) + nl
        bool aih = go.getActiveInHierarchy()
        t = t + "activeInHierarchy: " + b2s( aih ) + nl
        bool pd = go.pendingDestroy
        t = t + "pendingDestroy: " + b2s( pd ) + nl
        Int64 nid = go.nodeId
        t = t + "nodeId: " + nid.toString() + nl
        Int32 cc = go.childCount
        t = t + "childCount: " + cc.toString() + nl
        GameObject pa = go.getParent()
        if pa != null
        {
            string pn = pa.name
            t = t + "parent: " + pn + nl
        }
        else
        {
            t = t + "parent: (root)" + nl
        }
        Transform tf = go.transform
        if tf != null
        {
            t = t + nl + "=== Transform ===" + nl
            Float32_3 lp = tf.position
            t = t + "localPosition: " + v3s( lp ) + nl
            Float32 lrz = tf.localRotationZ
            t = t + "localRotationZ: " + lrz.toString() + nl
            Float32_3 ls = tf.localScale
            t = t + "localScale: " + v3s( ls ) + nl
            Float32_3 wp = tf.worldPosition()
            t = t + "worldPosition: " + v3s( wp ) + nl
        }
        Int32 cn = go.componentCount()
        t = t + nl + "=== Components (" + cn.toString() + ") ===" + nl
        Int32 i = 0
        while i < cn
        {
            Component c = go.componentAt( i )
            if c != null
            {
                bool cen = c.getEnabled()
                string cs = c.toString()
                t = t + "[" + i.toString() + "] " + cs + "  enabled=" + b2s( cen ) + nl
            }
            i = i + 1
        }
        QTHost.insTextSetText( t )
    }

    static string v3s( Float32_3 v )
    {
        Float32 vx = v.x
        Float32 vy = v.y
        Float32 vz = v.z
        ret "(" + vx.toString() + ", " + vy.toString() + ", " + vz.toString() + ")"
    }
}
