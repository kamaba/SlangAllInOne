# verify-hello-cube.ps1 - end-to-end smoke of the v3 SL class library.
# Plays the role of Unity C#: boot the SLB, drive frames with ONE batched
# call per frame, then read the C++ object table and the native log queue.
# ASCII only (PS 5.1 -File quirk).

param(
    [string]$UnityProject = 'C:\Users\Administrator\My project'
)

$ErrorActionPreference = 'Stop'

# Unity Editor runs with the project root as CWD; mirror that here.
Set-Location -LiteralPath $UnityProject

$dll = Join-Path $UnityProject 'Packages\com.slang.unity\Plugins\x86_64\slang_unity_native3.dll'
$slb = Join-Path $UnityProject 'Assets\StreamingAssets\Slang\HelloCube.module.slb'
foreach ($p in @($dll, $slb))
{
    if (-not (Test-Path -LiteralPath $p)) { throw "missing file: $p" }
}

$dllCs = $dll.Replace('\', '/')
$cs = @"
using System;
using System.Runtime.InteropServices;
public static class SlU
{
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr slu_version();
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern int slu_boot(byte[] pathUtf8);
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "slu_frame_objects")]
    public static extern int FrameObjects(double dt, [Out] double[] outBuffer, int capacity);
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern int slu_diag([Out] int[] out6);
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern int slu_pop_log([Out] byte[] buffer, int capacity);
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern int slu_frame_count();
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern int slu_last_run_code();
    [DllImport("$dllCs", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr slu_obj_name(long handle);
}
"@
Add-Type -TypeDefinition $cs -ErrorAction Stop

$utf8 = New-Object System.Text.UTF8Encoding($false)
Write-Host '== native plugin =='
Write-Host ('    version: ' + [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi([SlU]::slu_version()))

# Do NOT call slu_reset(): the shared section is visible to a running Unity
# Editor loading the same DLL path, and reset would wipe its engine binding.
$rc = [SlU]::slu_boot([System.Text.Encoding]::UTF8.GetBytes($slb + "`0"))
Write-Host ("    slu_boot rc = $rc (last_run_code = " + [SlU]::slu_last_run_code() + ')')

$stride = 20
$maxObjects = 64
$buf = New-Object double[] (1 + $stride * $maxObjects)
$firstFlags = 0
for ($i = 0; $i -lt 60; $i++)
{
    $f = [SlU]::FrameObjects((1.0 / 60.0), $buf, $buf.Length)
    if ($i -eq 0) { $firstFlags = $f }
}
$diag = New-Object int[] 6
[SlU]::slu_diag($diag) | Out-Null

$count = [int]$buf[0]
Write-Host ('    first frame flags = 0x{0:X2}' -f $firstFlags)
Write-Host ('    objects = ' + $count)
$cube = $null
$cam = $null
for ($i = 0; $i -lt $count; $i++)
{
    $b = 1 + $i * $stride
    $handle = [long]$buf[$b]
    $name = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi([SlU]::slu_obj_name($handle))
    Write-Host ('    [' + $i + '] ' + $name + ' pos=(' + $buf[$b+3] + ',' + $buf[$b+4] + ',' + $buf[$b+5] + ') rotY=' + $buf[$b+7] + ' color=(' + $buf[$b+12] + ',' + $buf[$b+13] + ',' + $buf[$b+14] + ') fov=' + $buf[$b+16] + ' volume=' + $buf[$b+17])
    if ($name -eq 'SlangCube') { $cube = $b }
    if ($name -eq 'Main Camera') { $cam = $b }
}
Write-Host ('    diag = IUnityLog:' + $diag[0] + ' renderer:' + $diag[1] + ' device:' + $diag[2] + ' renderEvents:' + $diag[3] + ' frames:' + $diag[4] + ' gfxEvents:' + $diag[5])

Write-Host '== native log queue =='
$logs = New-Object System.Collections.Generic.List[string]
$lbuf = New-Object byte[] 512
while ($true)
{
    $n = [SlU]::slu_pop_log($lbuf, $lbuf.Length)
    if ($n -le 0) { break }
    $line = $utf8.GetString($lbuf, 0, $n)
    $logs.Add($line)
    Write-Host ('    ' + $line)
}
$all = [string]::Join("`n", $logs.ToArray())

$fail = @()
if ($rc -ne 0) { $fail += 'slu_boot rc != 0' }
if ($all -notmatch 'HelloCube v4') { $fail += 'SL never reached C++ (FFI fallback?)' }
if ($all -match 'NOT active') { $fail += 'SL reported C++ binding inactive' }
if ($count -lt 1) { $fail += 'C++ object table is empty' }
if ($null -eq $cube) { $fail += 'SlangCube object missing' }
else
{
    if ([Math]::Abs($buf[$cube+12] - 1.0) -gt 0.001 -or [Math]::Abs($buf[$cube+13] - 0.45) -gt 0.001 -or [Math]::Abs($buf[$cube+14] - 0.1) -gt 0.001) { $fail += 'renderer color not applied by SL' }
    if ($buf[$cube+7] -le 0.0) { $fail += 'C++ frame state did not advance (rotY)' }
    if ([Math]::Abs($buf[$cube+17] - 0.8) -gt 0.001) { $fail += 'audio volume not applied by SL' }
}
if ($null -eq $cam) { $fail += 'Main Camera object missing' }
elseif ([Math]::Abs($buf[$cam+16] - 60.0) -gt 0.001) { $fail += 'camera fov not applied by SL' }
if ($diag[4] -lt 60) { $fail += 'slu_frame_objects did not count 60 frames' }

Write-Host '== result =='
if ($fail.Count -eq 0)
{
    Write-Host 'PASS: SL class library -> C++ FFI direct binding, batched object table, frame loop and state all work.'
    exit 0
}
foreach ($f in $fail) { Write-Host ('FAIL: ' + $f) }
exit 1
