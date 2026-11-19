# SnakeGame sfx generator - synthesizes small 16-bit mono WAV files into sfx\.
# Deterministic (no external assets). Re-run any time to regenerate.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File make-sfx.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sfxDir = Join-Path $root 'sfx'
New-Item -ItemType Directory -Force -Path $sfxDir | Out-Null
$sr = 22050

function Write-Wav {
    param([string]$path, [int[]]$samples)
    $n = $samples.Count
    $dataBytes = $n * 2
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
    $bw.Write([Int32](36 + $dataBytes))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
    $bw.Write([Int32]16)
    $bw.Write([Int16]1)              # PCM
    $bw.Write([Int16]1)              # mono
    $bw.Write([Int32]$sr)
    $bw.Write([Int32]($sr * 2))      # byte rate
    $bw.Write([Int16]2)              # block align
    $bw.Write([Int16]16)             # bits
    $bw.Write([Text.Encoding]::ASCII.GetBytes("data"))
    $bw.Write([Int32]$dataBytes)
    foreach ($s in $samples) { $bw.Write([Int16]$s) }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($path, $ms.ToArray())
    $bw.Close()
    Write-Host ("wrote " + $path + " (" + $n + " frames)")
}

function Tone {
    # shape: 0 = square (crisp arcade), 1 = saw (falling)
    param([double]$f0, [double]$f1, [double]$ms, [int]$shape, [double]$amp)
    $frames = [int]($sr * $ms / 1000.0)
    $out = New-Object 'System.Collections.Generic.List[int]'
    $phase = 0.0
    for ($i = 0; $i -lt $frames; $i++) {
        $t = $i / [double]$frames
        $f = $f0 + ($f1 - $f0) * $t
        $phase = $phase + $f / $sr
        if ($phase -ge 1.0) { $phase = $phase - 1.0 }
        $env = (1.0 - $t) * (1.0 - $t)
        $v = 0.0
        if ($shape -eq 0) {
            if ($phase -lt 0.5) { $v = 1.0 } else { $v = -1.0 }
        } else {
            $v = $phase * 2.0 - 1.0
        }
        $out.Add([int][math]::Round($v * $env * $amp))
    }
    return $out.ToArray()
}

function Concat {
    param([int[]]$a, [int[]]$b)
    $out = New-Object 'System.Collections.Generic.List[int]'
    foreach ($s in $a) { $out.Add($s) }
    foreach ($s in $b) { $out.Add($s) }
    return $out.ToArray()
}

# eat: quick rising square blip
$eat = Tone -f0 520 -f1 1040 -ms 90 -shape 0 -amp 9000
Write-Wav -path (Join-Path $sfxDir 'eat.wav') -samples $eat

# die: long falling saw sweep
$die = Tone -f0 420 -f1 70 -ms 480 -shape 1 -amp 10000
Write-Wav -path (Join-Path $sfxDir 'die.wav') -samples $die

# start: two rising square notes (C5 -> G5)
$j1 = Tone -f0 523 -f1 523 -ms 110 -shape 0 -amp 8500
$j2 = Tone -f0 784 -f1 784 -ms 150 -shape 0 -amp 8500
$start = Concat -a $j1 -b $j2
Write-Wav -path (Join-Path $sfxDir 'start.wav') -samples $start

# move: clear short beep per step ("di"), loud enough to be heard over bgm
$move = Tone -f0 880 -f1 880 -ms 50 -shape 0 -amp 9500
Write-Wav -path (Join-Path $sfxDir 'move.wav') -samples $move

# bgm: short chiptune loop (~6s, square arpeggio, soft amplitude)
function Notes([double[]]$freqs, [int]$noteMs, [int]$gapMs, [double]$amp) {
    $out = New-Object 'System.Collections.Generic.List[int]'
    foreach ($f in $freqs) {
        $frames = [int]($sr * $noteMs / 1000.0)
        $phase = 0.0
        for ($i = 0; $i -lt $frames; $i++) {
            $t = $i / [double]$frames
            $phase = $phase + $f / $sr
            if ($phase -ge 1.0) { $phase = $phase - 1.0 }
            $env = 1.0 - 0.35 * $t
            $v = 1.0
            if ($phase -ge 0.5) { $v = -1.0 }
            $out.Add([int][math]::Round($v * $env * $amp))
        }
        $gap = [int]($sr * $gapMs / 1000.0)
        for ($i = 0; $i -lt $gap; $i++) { $out.Add(0) }
    }
    return $out.ToArray()
}
$bgmFreqs = @(523.25, 659.25, 783.99, 1046.50, 783.99, 659.25,
              587.33, 698.46, 880.00, 1174.66, 880.00, 698.46,
              523.25, 659.25, 783.99, 1046.50, 987.77, 783.99, 659.25, 523.25)
$bgm = Notes -freqs $bgmFreqs -noteMs 270 -gapMs 30 -amp 6500
Write-Wav -path (Join-Path $sfxDir 'bgm.wav') -samples $bgm

Write-Host "sfx generation done -> " $sfxDir
