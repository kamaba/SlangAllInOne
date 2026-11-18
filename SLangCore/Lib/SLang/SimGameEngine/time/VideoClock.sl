import Core;
import Std;
import Math;

# ============================================================================
# VideoClock — 视频域时钟门面（doc/18 v1.1，域 5）
# ----------------------------------------------------------------------------
# 引擎不直连视频解码设备；本类只承接「视频播放头（微秒）」上报，转交
# TimeService 在帧尾统一折算进域偏移。EngineTime.videoNowUs() 读到的即
# 对齐后的视频时间（无后端时退化为 C 单调钟，接口行为不变）。
# 使用：每帧上报一次 headUs；seek 后传 snapNow=true 一步对齐。
# ============================================================================

public class VideoClock
{
    TimeService _service = null
    Int64 _headUs = 0
    bool _hasHead = false
    public Int32 reportCount = 0
    public Int32 lastSnap = 0

    public void _init_()
    {
        this._service = null
        this._headUs = 0
        this._hasHead = false
        this.reportCount = 0
        this.lastSnap = 0
    }

    # 绑定时间服务（Application.init 自动注入；也可手动绑定）
    public bool attach( TimeService svc )
    {
        if svc == null
        {
            ret false
        }
        this._service = svc
        ret true
    }

    # 上报播放头（微秒）。snapNow=true = seek/重置后一步对齐。
    public bool reportHeadUs( Int64 headUs, bool snapNow )
    {
        if this._service == null
        {
            ret false
        }
        this._service.reportVideoHead( headUs, snapNow )
        this._headUs = headUs
        this._hasHead = true
        this.reportCount = this.reportCount + 1
        if snapNow
        {
            this.lastSnap = 1
        }
        else
        {
            this.lastSnap = 0
        }
        ret true
    }

    # 由秒数上报（后端只给 Float32 秒时用；内部换算微秒）
    public bool reportHeadSec( Float32 headSec, bool snapNow )
    {
        Int64 us = SystemConvertInt64( headSec * 1000000.0f )
        ret this.reportHeadUs( us, snapNow )
    }

    public Int64 headUs()
    {
        ret this._headUs
    }

    public bool hasHead()
    {
        ret this._hasHead
    }

    # 对齐后的视频域时刻（微秒）
    public Int64 nowUs()
    {
        ret EngineTime.videoNowUs()
    }

    # 本帧漂移（> 0 = 视频域落后主钟）；未上报时 0
    public Int64 driftUs()
    {
        if this._service == null || !this._hasHead
        {
            ret 0
        }
        ret this._service.domainDriftUs( 5, this._headUs )
    }

    public void clear()
    {
        this._headUs = 0
        this._hasHead = false
        this.reportCount = 0
        this.lastSnap = 0
        if this._service != null
        {
            this._service.clearExternalHeads()
        }
    }
}
