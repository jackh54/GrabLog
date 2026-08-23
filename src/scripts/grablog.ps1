# GrabLog client for Windows PowerShell
# Placeholders are replaced by the worker at request time.
$ErrorActionPreference = 'Stop'

$GrabLogApi = '__GRABLOG_API__'
$GrabLogLauncher = '__GRABLOG_LAUNCHER__'
$GrabLogInstance = '__GRABLOG_INSTANCE__'
$GrabLogName = '__GRABLOG_NAME__'
$GrabLogType = '__GRABLOG_TYPE__'
$GrabLogYes = '__GRABLOG_YES__'

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

function Get-Score {
  param([IO.FileInfo]$File)
  $base = $File.Name.ToLowerInvariant()
  $score = [int64]500000000000
  if ($base -eq 'latest.log') { $score = [int64]1000000000000 }
  elseif ($base -eq 'debug.log') { $score = [int64]900000000000 }
  elseif ($base -like 'crash-*.txt') { $score = [int64]800000000000 }
  elseif ($base -like '*.log') { $score = [int64]700000000000 }
  elseif ($base -like '*.log.gz') { $score = [int64]600000000000 }
  return $score + [int64]([DateTimeOffset]$File.LastWriteTimeUtc).ToUnixTimeSeconds()
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

Write-Host ''
Write-Host '  GrabLog — Minecraft log finder'
Write-Host ''

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
  $matched++
  $info = Get-Item -LiteralPath $path
  $score = Get-Score -File $info
  if ($score -gt $bestScore) {
    $bestScore = $score
    $best = $info
  }
}

if ($null -eq $best) {
  $msg = 'No Minecraft log found'
  if ($GrabLogLauncher) { $msg += " (launcher=$GrabLogLauncher)" }
  if ($GrabLogInstance) { $msg += " (instance=$GrabLogInstance)" }
  if ($GrabLogName) { $msg += " (name=$GrabLogName)" }
  Write-Error "$msg. Tried common vanilla / Prism / Modrinth / CurseForge / MultiMC / Lunar paths."
  exit 1
}

Write-Host ("Found:   {0}" -f $best.FullName)
Write-Host ("Size:    {0:N0} bytes" -f $best.Length)
Write-Host ("Modified:{0:yyyy-MM-dd HH:mm:ss}" -f $best.LastWriteTime)
Write-Host ("Matched  {0} candidate(s); selecting most recent preferred log." -f $matched)
Write-Host ''

if ($best.Extension -ne '.gz') {
  Write-Host '--- last 8 lines ---'
  Get-Content -LiteralPath $best.FullName -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
  Write-Host '--------------------'
  Write-Host ''
} else {
  Write-Host '(compressed log — preview skipped)'
  Write-Host ''
}

$yes = $GrabLogYes -eq '1' -or $GrabLogYes -eq 'true'
if (-not $yes) {
  $ans = Read-Host 'Upload this log to GrabLog for 24 hours? [y/N]'
  if ($ans -notmatch '^(y|yes)$') {
    Write-Host 'Cancelled.'
    exit 0
  }
}

Write-Host 'Uploading...'
$bytes = [IO.File]::ReadAllBytes($best.FullName)
$contentType = if ($best.Extension -eq '.gz') { 'application/gzip' } else { 'text/plain' }

try {
  $resp = Invoke-RestMethod -Method Post -Uri ($GrabLogApi.TrimEnd('/') + '/api/upload') `
    -Headers @{ 'X-GrabLog-Filename' = $best.Name } `
    -ContentType $contentType `
    -Body $bytes
} catch {
  Write-Error ("Upload failed: {0}" -f $_.Exception.Message)
  exit 1
}

if (-not $resp.url) {
  Write-Error ("Upload failed: {0}" -f ($resp | ConvertTo-Json -Compress))
  exit 1
}

Write-Host ''
Write-Host 'Share link (expires in 24h):'
Write-Host $resp.url
Write-Host ''
