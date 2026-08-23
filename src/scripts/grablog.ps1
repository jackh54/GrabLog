# GrabLog client for Windows PowerShell
# Placeholders are replaced by the worker at request time.
$ErrorActionPreference = 'Stop'

$GrabLogApi = '__GRABLOG_API__'
$GrabLogLauncher = '__GRABLOG_LAUNCHER__'
$GrabLogInstance = '__GRABLOG_INSTANCE__'
$GrabLogName = '__GRABLOG_NAME__'
$GrabLogType = '__GRABLOG_TYPE__'
$GrabLogServer = '__GRABLOG_SERVER__'
$GrabLogYes = '__GRABLOG_YES__'

function Write-Banner {
  Write-Host ''
  Write-Host '  GrabLog  ' -NoNewline -ForegroundColor Green
  Write-Host 'minecraft log share' -ForegroundColor DarkGray
  Write-Host '  ────────────────────────────' -ForegroundColor DarkGray
  Write-Host ''
}

function Test-LauncherMatch {
  param([string]$Path, [string]$Want)
  if ([string]::IsNullOrWhiteSpace($Want)) { return $true }
  $p = $Path.ToLowerInvariant()
  $w = $Want.ToLowerInvariant()
  switch -Regex ($w) {
    '^(vanilla|minecraft|official)$' {
      return ($p -match '\\.minecraft\\' -or $p -match '\\minecraft\\logs\\')
    }
    '^(prism|prismlauncher)$' { return $p -match 'prism' }
    '^polymc$' { return $p -match 'polymc' }
    '^multimc$' { return $p -match 'multimc' }
    '^(modrinth|theseus)$' { return ($p -match 'modrinth' -or $p -match 'theseus') }
    '^(curse|curseforge)$' { return $p -match 'curse' }
    '^(atlauncher|at)$' { return $p -match 'atlauncher' }
    '^lunar$' { return $p -match 'lunar' }
    '^(gdlauncher|gd)$' { return $p -match 'gdlauncher' }
    default { return $p.Contains($w) }
  }
}

function Test-InstanceMatch {
  param([string]$Path, [string]$Want)
  if ([string]::IsNullOrWhiteSpace($Want)) { return $true }
  return $Path.ToLowerInvariant().Contains($Want.ToLowerInvariant())
}

function Test-NameMatch {
  param([string]$Path, [string]$Want)
  if ([string]::IsNullOrWhiteSpace($Want)) { return $true }
  $base = [IO.Path]::GetFileName($Path).ToLowerInvariant()
  return $base.Contains($Want.ToLowerInvariant())
}

function Test-TypeMatch {
  param([string]$Path, [string]$Want)
  if ([string]::IsNullOrWhiteSpace($Want) -or $Want -eq 'any') { return $true }
  $base = [IO.Path]::GetFileName($Path).ToLowerInvariant()
  switch ($Want.ToLowerInvariant()) {
    'crash' { return $base -like 'crash-*.txt' -or $base -like '*-crash*.txt' }
    'log' { return $base -like '*.log' -or $base -like '*.log.gz' }
    'latest' { return $base -like '*.log' -or $base -like '*.log.gz' }
    default { return $true }
  }
}

function Test-ServerMatch {
  param([string]$Path, [string]$Want)
  if ([string]::IsNullOrWhiteSpace($Want)) { return $true }
  try {
    if ($Path.EndsWith('.gz', [StringComparison]::OrdinalIgnoreCase)) {
      $fs = [IO.File]::OpenRead($Path)
      try {
        $gz = New-Object IO.Compression.GzipStream($fs, [IO.Compression.CompressionMode]::Decompress)
        $reader = New-Object IO.StreamReader($gz)
        $chunkSize = 512 * 1024
        $buf = New-Object char[] $chunkSize
        while (($n = $reader.Read($buf, 0, $chunkSize)) -gt 0) {
          $text = New-Object string ($buf, 0, $n)
          if ($text.IndexOf($Want, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
          }
        }
      } finally {
        $fs.Dispose()
      }
      return $false
    }
    # Stream scan plain logs so huge files stay fast.
    $reader = [IO.File]::OpenText($Path)
    try {
      while ($null -ne ($line = $reader.ReadLine())) {
        if ($line.IndexOf($Want, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
          return $true
        }
      }
    } finally {
      $reader.Dispose()
    }
    return $false
  } catch {
    return $false
  }
}

function Get-Score {
  param([IO.FileInfo]$File, [string]$Server)
  $base = $File.Name.ToLowerInvariant()
  $score = [int64]500000000000
  if ($base -eq 'latest.log') { $score = [int64]1000000000000 }
  elseif ($base -eq 'debug.log') { $score = [int64]900000000000 }
  elseif ($base -like 'crash-*.txt') { $score = [int64]800000000000 }
  elseif ($base -like '*.log') { $score = [int64]700000000000 }
  elseif ($base -like '*.log.gz') { $score = [int64]600000000000 }
  $score += [int64]([DateTimeOffset]$File.LastWriteTimeUtc).ToUnixTimeSeconds()
  if (-not [string]::IsNullOrWhiteSpace($Server) -and $File.Extension -ne '.gz') {
    $tail = Get-Content -LiteralPath $File.FullName -Tail 200 -ErrorAction SilentlyContinue
    if ($tail -and (($tail -join "`n").IndexOf($Server, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
      $score += [int64]50000000000
    }
  }
  return $score
}

function Add-IfLog {
  param(
    [System.Collections.Generic.List[string]]$List,
    [string]$Path
  )
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($null -eq $item -or $item.Length -le 0) { return }
  $name = $item.Name.ToLowerInvariant()
  if ($name -notmatch '\.(log|txt|gz)$') { return }
  if (-not $List.Contains($item.FullName)) {
    [void]$List.Add($item.FullName)
  }
}

function Scan-Tree {
  param(
    [string]$Root,
    [System.Collections.Generic.List[string]]$Out,
    [int]$MaxDepth = 8
  )
  $skip = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('cache', 'libraries', 'assets', 'versions', 'natives', '.git', 'node_modules')
  )
  $queue = New-Object System.Collections.Generic.Queue[object]
  $queue.Enqueue(@{ Path = $Root; Depth = 0 })
  while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    if ($cur.Depth -gt $MaxDepth) { continue }
    $entries = Get-ChildItem -LiteralPath $cur.Path -Force -ErrorAction SilentlyContinue
    foreach ($entry in $entries) {
      if ($entry.PSIsContainer) {
        if ($skip.Contains($entry.Name.ToLowerInvariant())) { continue }
        $queue.Enqueue(@{ Path = $entry.FullName; Depth = $cur.Depth + 1 })
        continue
      }
      $name = $entry.Name.ToLowerInvariant()
      if (
        $name -eq 'latest.log' -or
        $name -eq 'debug.log' -or
        $name -like 'crash-*.txt' -or
        $name -like '*.log.gz'
      ) {
        Add-IfLog -List $Out -Path $entry.FullName
      }
    }
  }
}

Write-Banner

$filterBits = @()
if ($GrabLogLauncher) { $filterBits += "launcher=$GrabLogLauncher" }
if ($GrabLogInstance) { $filterBits += "instance=$GrabLogInstance" }
if ($GrabLogName) { $filterBits += "name=$GrabLogName" }
if ($GrabLogType) { $filterBits += "type=$GrabLogType" }
if ($GrabLogServer) { $filterBits += "server=$GrabLogServer" }
if ($filterBits.Count -gt 0) {
  Write-Host ("  filters: {0}" -f ($filterBits -join ' ')) -ForegroundColor DarkGray
} else {
  Write-Host '  auto: newest log across all launchers' -ForegroundColor DarkGray
}

Write-Host '  › Scanning launcher folders…' -ForegroundColor Cyan

$roots = New-Object System.Collections.Generic.List[string]
$envAppData = $env:APPDATA
$userProfile = $env:USERPROFILE

$candidateRoots = @(
  (Join-Path $envAppData '.minecraft'),
  (Join-Path $envAppData 'PrismLauncher'),
  (Join-Path $envAppData 'PolyMC'),
  (Join-Path $envAppData 'MultiMC'),
  (Join-Path $envAppData 'com.modrinth.Theseus'),
  (Join-Path $envAppData 'modrinth-app'),
  (Join-Path $envAppData 'ATLauncher'),
  (Join-Path $envAppData 'gdlauncher_next'),
  (Join-Path $envAppData 'gdlauncher'),
  (Join-Path $userProfile 'curseforge\minecraft'),
  (Join-Path $userProfile '.lunarclient'),
  (Join-Path $userProfile 'AppData\Roaming\.minecraft')
)

foreach ($r in $candidateRoots) {
  if (Test-Path -LiteralPath $r -PathType Container) {
    [void]$roots.Add($r)
  }
}

$files = New-Object System.Collections.Generic.List[string]
foreach ($root in $roots) {
  Add-IfLog -List $files -Path (Join-Path $root 'logs\latest.log')
  Add-IfLog -List $files -Path (Join-Path $root 'minecraft\logs\latest.log')
  Scan-Tree -Root $root -Out $files
}

$best = $null
$bestScore = [int64]-1
$matched = 0

foreach ($path in $files) {
  if (-not (Test-LauncherMatch -Path $path -Want $GrabLogLauncher)) { continue }
  if (-not (Test-InstanceMatch -Path $path -Want $GrabLogInstance)) { continue }
  if (-not (Test-NameMatch -Path $path -Want $GrabLogName)) { continue }
  if (-not (Test-TypeMatch -Path $path -Want $GrabLogType)) { continue }
  if (-not (Test-ServerMatch -Path $path -Want $GrabLogServer)) { continue }
  $matched++
  $info = Get-Item -LiteralPath $path
  $score = Get-Score -File $info -Server $GrabLogServer
  if ($score -gt $bestScore) {
    $bestScore = $score
    $best = $info
  }
}

if ($null -eq $best) {
  $msg = 'No Minecraft log found'
  if ($filterBits.Count -gt 0) { $msg += " ($($filterBits -join ', '))" }
  Write-Host "  ✗ $msg" -ForegroundColor Red
  Write-Host '    Tried vanilla / Prism / Modrinth / CurseForge / MultiMC / Lunar paths.' -ForegroundColor DarkGray
  exit 1
}

Write-Host '  ✓ Found ' -NoNewline -ForegroundColor Green
Write-Host $best.Name -NoNewline -ForegroundColor White
Write-Host ("  ({0:N0} bytes · {1:yyyy-MM-dd HH:mm})" -f $best.Length, $best.LastWriteTime) -ForegroundColor DarkGray
Write-Host ("    {0}" -f $best.FullName) -ForegroundColor DarkGray
Write-Host ("    {0} candidate(s) matched" -f $matched) -ForegroundColor DarkGray
Write-Host ''

if ($best.Extension -ne '.gz') {
  Write-Host '    last lines' -ForegroundColor DarkGray
  Get-Content -LiteralPath $best.FullName -Tail 6 -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host '    │ ' -NoNewline -ForegroundColor DarkGray
    Write-Host $_
  }
} else {
  Write-Host '    (compressed — preview skipped)' -ForegroundColor DarkGray
}
Write-Host ''

$yes = $GrabLogYes -eq '1' -or $GrabLogYes -eq 'true'
if (-not $yes) {
  $ans = Read-Host '  › Upload for 24 hours? [y/N]'
  if ($ans -notmatch '^(y|yes)$') {
    Write-Host '  ! Cancelled.' -ForegroundColor Yellow
    exit 0
  }
}

Write-Host '  › Uploading…' -ForegroundColor Cyan
$bytes = [IO.File]::ReadAllBytes($best.FullName)
$contentType = if ($best.Extension -eq '.gz') { 'application/gzip' } else { 'text/plain; charset=utf-8' }
$uploadUri = ($GrabLogApi.TrimEnd('/') + '/api/upload')

try {
  # HttpClient gives reliable timeouts (Invoke-RestMethod can hang on bad Expect/proxy paths).
  $handler = New-Object System.Net.Http.HttpClientHandler
  $client = New-Object System.Net.Http.HttpClient($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(120)
  $content = New-Object System.Net.Http.ByteArrayContent($bytes)
  $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($contentType)
  $content.Headers.Add('X-GrabLog-Filename', $best.Name)
  $response = $client.PostAsync($uploadUri, $content).GetAwaiter().GetResult()
  $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if (-not $response.IsSuccessStatusCode) {
    Write-Host ("  ✗ Upload failed ({0})." -f [int]$response.StatusCode) -ForegroundColor Red
    if ($raw) { Write-Host ("    {0}" -f $raw) -ForegroundColor DarkGray }
    exit 1
  }
  $resp = $raw | ConvertFrom-Json
} catch {
  Write-Host ("  ✗ Upload failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
  Write-Host ("    endpoint: {0}" -f $uploadUri) -ForegroundColor DarkGray
  exit 1
} finally {
  if ($content) { $content.Dispose() }
  if ($client) { $client.Dispose() }
}

if (-not $resp.url) {
  Write-Host '  ✗ Upload failed: unexpected response.' -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host '  ✓ Share link ' -NoNewline -ForegroundColor Green
Write-Host '(expires in 24h)' -ForegroundColor DarkGray
Write-Host ''
Write-Host ("  {0}" -f $resp.url) -ForegroundColor White
Write-Host ''
