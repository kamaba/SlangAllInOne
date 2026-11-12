import Math;
# UI 矩形变换：在 Transform 之上提供锚点 / 轴心 / 尺寸等 2D 布局能力。
# 2D 量统一使用 Math 库的 Float32_2。
public class RectTransform extends Transform
{
    # 相对锚点的位置
    public Float32_2 anchoredPosition = Float32_2.zero()
    # 相对锚点区域的尺寸偏移
    public Float32_2 sizeDelta = Float32_2.zero()
    # 锚点范围（归一化 [0,1]）
    public Float32_2 anchorMin = Float32_2.zero()
    public Float32_2 anchorMax = Float32_2.one()
    # 轴心（归一化 [0,1]，自身坐标系）
    public Float32_2 pivot = Float32_2( 0.5f, 0.5f )

    # ── 尺寸 ─────────────────────────────────────────────
    public get Float32 width()
    {
        ret this.sizeDelta.x
    }

    public get Float32 height()
    {
        ret this.sizeDelta.y
    }

    public get Float32_2 size()
    {
        ret this.sizeDelta.clone()
    }

    # 左上角位置（以 pivot 为参考反推）
    public get Float32_2 topLeft()
    {
        Float32 x = this.anchoredPosition.x - this.sizeDelta.x * this.pivot.x
        Float32 y = this.anchoredPosition.y - this.sizeDelta.y * this.pivot.y
        ret Float32_2( x, y )
    }

    # ── 设置 ─────────────────────────────────────────────
    public void setSize( Float32_2 size )
    {
        this.sizeDelta.x = size.x
        this.sizeDelta.y = size.y
    }

    public void setSize( Float32 w, Float32 h )
    {
        this.sizeDelta.x = w
        this.sizeDelta.y = h
    }

    public void setAnchoredPosition( Float32_2 pos )
    {
        this.anchoredPosition.x = pos.x
        this.anchoredPosition.y = pos.y
    }

    public void setPivot( Float32_2 p )
    {
        this.pivot.x = Mathf.clamp( p.x, 0.0f, 1.0f )
        this.pivot.y = Mathf.clamp( p.y, 0.0f, 1.0f )
    }

    # 设置锚点（四个角同时设为同一点，常见于固定位置布局）
    public void setAnchor( Float32_2 anchor )
    {
        Float32 x = Mathf.clamp( anchor.x, 0.0f, 1.0f )
        Float32 y = Mathf.clamp( anchor.y, 0.0f, 1.0f )
        this.anchorMin.x = x
        this.anchorMax.x = x
        this.anchorMin.y = y
        this.anchorMax.y = y
    }

    # 拉伸到父级边缘（anchorMin=0, anchorMax=1, 偏移为 0）
    public void stretch()
    {
        this.anchorMin.x = 0.0f
        this.anchorMin.y = 0.0f
        this.anchorMax.x = 1.0f
        this.anchorMax.y = 1.0f
        this.sizeDelta.x = 0.0f
        this.sizeDelta.y = 0.0f
    }

    # ── 命中检测 ─────────────────────────────────────────
    # 点是否落在矩形范围内（point 与 anchoredPosition 同一坐标系）
    public bool containsPoint( Float32_2 point )
    {
        Float32_2 tl = this.topLeft()
        # && 链最多 2 个运算符，拆成 X/Y 两段再合并
        bool inX = point.x >= tl.x && point.x <= tl.x + this.sizeDelta.x
        bool inY = point.y >= tl.y && point.y <= tl.y + this.sizeDelta.y
        ret inX && inY
    }

    public RectTransform cloneRect()
    {
        RectTransform r = RectTransform()
        r.anchoredPosition = this.anchoredPosition.clone()
        r.sizeDelta = this.sizeDelta.clone()
        r.anchorMin = this.anchorMin.clone()
        r.anchorMax = this.anchorMax.clone()
        r.pivot = this.pivot.clone()
        ret r
    }

    override string toString()
    {
        ret String.toFormat( "RectTransform(pos={0}, size={1}, pivot={2})",
            this.anchoredPosition.toString(), this.sizeDelta.toString(), this.pivot.toString() )
    }
}
