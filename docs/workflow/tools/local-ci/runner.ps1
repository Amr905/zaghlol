# Zaghlol local CI runner v3 (fast feedback; GitHub Actions stays the merge gate).
# v3: every build/format/analyze/test step runs inside a pinned Linux Docker container (same Flutter and
# .NET versions as GitHub Actions), not on Windows. Git polling and publishing still run on Windows.
# Requires Docker Desktop (Linux containers) to be running.
# Started by START-LOCAL-CI.cmd. Two jobs:
#  1. AUTO: every 30 s, look for new commits on task/* branches. For each new commit run the
#     QUICK pipeline (app: format, analyze, tests; backend: build, format, tests) and publish
#     the result to the 'local-ci' branch as <branch>/<sha>.status and .log.
#  2. QUEUE: *.job files dropped in .\queue (branch=..., pipeline=app|backend|all|quick|probe).
# Builds run in %USERPROFILE%\zaghlol-ci (separate clones), never in this folder.
# Stop it by closing its window.
$ErrorActionPreference = 'Continue'
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Queue   = Join-Path $Here 'queue'
$Results = Join-Path $Here 'results'
$Work    = Join-Path $env:USERPROFILE 'zaghlol-ci'
$Repo    = Join-Path $Work 'repo'
$Pub     = Join-Path $Work 'results-repo'
$Seen    = Join-Path $Work 'seen.txt'
$Origin  = 'https://github.com/Amr905/zaghlol.git'
New-Item -ItemType Directory -Force -Path $Queue,$Results,$Work | Out-Null
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$LogCap  = 1500   # max lines of raw log tail in the published .log (summary and error lines come first)

# Pinned toolchain images. Keep the Flutter version equal to FLUTTER_VERSION in .github/workflows/app-ci.yml
# and the .NET SDK on the 10.0 line used by backend-ci.yml / backend/global.json.
# Override per PC with the environment variables if a tag does not exist.
$FlutterImage = if ($env:ZAGHLOL_FLUTTER_IMAGE) { $env:ZAGHLOL_FLUTTER_IMAGE } else { 'ghcr.io/cirruslabs/flutter:3.47.9' }
$DotnetImage  = if ($env:ZAGHLOL_DOTNET_IMAGE)  { $env:ZAGHLOL_DOTNET_IMAGE }  else { 'mcr.microsoft.com/dotnet/sdk:10.0.402' }
# Named volumes: package caches survive between runs so only the first run downloads everything.
$PubVolume    = 'zaghlol-ci-pub-cache'
$NugetVolume  = 'zaghlol-ci-nuget-cache'

function Log($f,$m){ $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content -Path $f -Value $line -Encoding UTF8; Write-Host $line }

function Strip-Ansi([string]$t) { return ($t -replace ([string][char]27 + '\[[0-9;?]*[A-Za-z]'), '') }

function Docker-Up {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
  docker info *> $null
  return ($LASTEXITCODE -eq 0)
}

function Ensure-Image($log, $image) {
  docker image inspect $image *> $null
  if ($LASTEXITCODE -eq 0) { return $true }
  Log $log "pulling $image (first run only; can take several minutes)"
  $o = & docker pull $image 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } } | Out-String
  $ok = ($LASTEXITCODE -eq 0)
  Add-Content -Path $log -Value $o -Encoding UTF8
  if (-not $ok) { Log $log "docker pull $image FAILED" }
  return $ok
}

# Runs one pipeline step inside a container. $cmd is a bash command line WITHOUT double quotes
# (Windows PowerShell 5.1 mangles them when calling native programs).
function Docker-Step($log, $name, $image, $kind, $subdir, $cmd) {
  Log $log "=== STEP $name (docker $image, /work/$subdir)"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $code = 1; $out = ''
  if (Ensure-Image $log $image) {
    $a = @('run','--rm',
      '-v', "${Repo}:/work", '-w', "/work/$subdir",
      '-e', 'GIT_CONFIG_COUNT=1', '-e', 'GIT_CONFIG_KEY_0=safe.directory', '-e', 'GIT_CONFIG_VALUE_0=*',
      '-e', 'CI=true')
    if ($kind -eq 'flutter') {
      $a += @('-v', "${PubVolume}:/pubcache", '-e', 'PUB_CACHE=/pubcache', '-e', 'FLUTTER_SUPPRESS_ANALYTICS=true')
    } else {
      $a += @('-v', "${NugetVolume}:/nuget", '-e', 'NUGET_PACKAGES=/nuget',
              '-e', 'DOTNET_NOLOGO=1', '-e', 'DOTNET_CLI_TELEMETRY_OPTOUT=1', '-e', 'DOTNET_CLI_HOME=/tmp',
              # Backend tests start sibling PostgreSQL containers through the host Docker daemon (Testcontainers).
              '-v', '/var/run/docker.sock:/var/run/docker.sock',
              '-e', 'TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal',
              '--add-host=host.docker.internal:host-gateway')
    }
    $a += @($image, 'bash', '-c', $cmd)
    $out = & docker @a 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } } | Out-String
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 1 }
  } else {
    $out = "could not pull docker image $image (offline, wrong tag, or Docker not logged in?). Set ZAGHLOL_FLUTTER_IMAGE / ZAGHLOL_DOTNET_IMAGE to override.`n"
  }
  $out = Strip-Ansi $out
  Add-Content -Path $log -Value $out -Encoding UTF8
  Log $log "=== RESULT $name exit=$code ($([int]$sw.Elapsed.TotalSeconds)s)"
  return [pscustomobject]@{ Name=$name; Exit=$code; Out=$out; Secs=[int]$sw.Elapsed.TotalSeconds }
}

# Error lines of a failing step: what a developer needs before looking at the raw tail.
function Get-ErrorLines($name, $out) {
  $lines = @($out -split "`r?`n")
  $hits = New-Object System.Collections.Generic.List[string]
  function Ctx($rx, $after) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match $rx) {
        $hi = [Math]::Min($lines.Count - 1, $i + $after)
        for ($j = $i; $j -le $hi; $j++) { $hits.Add($lines[$j]) }
        $hits.Add('')
      }
    }
  }
  switch -Regex ($name) {
    '^format$'        { foreach ($l in $lines) { if ($l -match '^Changed |^Could not format|^Formatted ') { $hits.Add($l) } } ; break }
    '^analyze$'       { foreach ($l in $lines) { if ($l -match '^\s*(info|warning|error)\s' -or $l -match '^\d+ issues? found') { $hits.Add($l) } } ; break }
    '^dotnet-format$' { foreach ($l in $lines) { if ($l -match ': (error|warning) [A-Za-z0-9_]+:|Unhandled exception|Formatted code file') { $hits.Add($l) } } ; break }
    '^dotnet-build$'  { foreach ($l in ($lines | Select-Object -Unique)) { if ($l -match ': (error|warning) [A-Z]+[0-9]+') { $hits.Add($l) } } ; break }
    '^dotnet-test$'   { Ctx '^\s*Failed \S' 12 ; break }
    'test'            { Ctx '\[E\]\s*$' 10 ; break }
    default           { foreach ($l in $lines) { if ($l -match '(?i)\berror\b|exception|failed|could not') { $hits.Add($l) } } ; break }
  }
  if ($hits.Count -eq 0) { $hits.AddRange([string[]]@($lines | Select-Object -Last 25)) }
  return @($hits | Select-Object -First 200)
}

# Published log: per-step summary, then error lines of failing steps, then the raw tail.
function Write-PublishLog($log, $statusLine, $steps, $dest) {
  $o = New-Object System.Collections.Generic.List[string]
  $o.Add('== SUMMARY ==')
  $o.Add($statusLine)
  foreach ($s in $steps) { $o.Add(("{0,-28} {1}  exit={2}  {3}s" -f $s.Name, $(if ($s.Exit -eq 0) {'PASS'} else {'FAIL'}), $s.Exit, $s.Secs)) }
  foreach ($s in ($steps | Where-Object { $_.Exit -ne 0 })) {
    $o.Add('')
    $o.Add("== ERRORS: $($s.Name) ==")
    foreach ($l in (Get-ErrorLines $s.Name $s.Out)) { $o.Add($l) }
  }
  $o.Add('')
  $o.Add("== FULL LOG (last $LogCap lines) ==")
  if (Test-Path $log) { foreach ($l in (Get-Content $log -Tail $LogCap)) { $o.Add($l) } }
  Set-Content -Path $dest -Value $o -Encoding UTF8
}

function Probe {
  $p = Join-Path $Results 'probe.log'
  Set-Content -Path $p -Value "probe $(Get-Date -Format o)" -Encoding UTF8
  foreach ($t in 'git','docker') {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    Add-Content $p ("where {0}: {1}" -f $t, $(if ($c) { $c.Source } else { 'NOT FOUND' }))
  }
  Add-Content $p ("docker running: " + (Docker-Up))
  Add-Content $p ("docker server: " + (docker version --format '{{.Server.Version}} {{.Server.Os}}' 2>&1 | Out-String))
  foreach ($img in $FlutterImage,$DotnetImage) {
    docker image inspect $img *> $null
    Add-Content $p ("image {0}: {1}" -f $img, $(if ($LASTEXITCODE -eq 0) { 'present' } else { 'not pulled yet (pulled on first use)' }))
  }
  Add-Content $p "probe done"
}

function Checkout($log, $branch) {
  if (-not (Test-Path (Join-Path $Repo '.git'))) {
    Log $log "cloning..."; git clone --quiet -c core.autocrlf=false -c core.eol=lf $Origin $Repo 2>&1 | Out-String | Add-Content $log
  }
  # Guard (review major): never run reset/clean outside the CI clone.
  if (-not (Test-Path (Join-Path $Repo '.git'))) { throw "checkout: clone of $Origin into $Repo failed" }
  $top = (git -C $Repo rev-parse --show-toplevel 2>$null | Out-String).Trim()
  $want = ((Resolve-Path $Repo).Path -replace '\\','/').TrimEnd('/')
  if (-not $top -or (($top -replace '\\','/').TrimEnd('/') -ne $want)) { throw "checkout: $Repo is not the root of the CI clone (git top-level: '$top')" }
  Push-Location $Repo -ErrorAction Stop
  # Keep LF line endings like CI (dotnet format / dart format reject CRLF). One-time renormalize of an old clone.
  git config core.autocrlf false
  git config core.eol lf
  if (-not (Test-Path (Join-Path $Repo '.git\zaghlol-lf-ok'))) {
    git rm -rq --cached . 2>&1 | Out-Null; git reset --quiet --hard 2>&1 | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $Repo '.git\zaghlol-lf-ok') | Out-Null
  }
  git fetch --quiet --force origin "+refs/heads/main:refs/remotes/origin/main" "+refs/heads/${branch}:refs/remotes/origin/${branch}" 2>&1 | Out-String | Add-Content $log
  git checkout --quiet --force --detach "origin/$branch" 2>&1 | Out-String | Add-Content $log
  if (-not (Test-Path (Join-Path $Repo '.git\zaghlol-docker-ok'))) {
    git clean -fdxq 2>&1 | Out-Null   # drop artifacts built natively on Windows before the Docker switch
    New-Item -ItemType File -Force -Path (Join-Path $Repo '.git\zaghlol-docker-ok') | Out-Null
  }
  git clean -fdxq -e 'app/build' -e '.dart_tool' -e 'bin' -e 'obj' 2>&1 | Out-String | Add-Content $log
  $sha = (git rev-parse HEAD).Trim()
  $changed = (git diff --name-only "origin/main...HEAD" 2>$null | Out-String)
  Pop-Location
  return [pscustomobject]@{ Sha=$sha; Changed=$changed }
}

function Run-Pipeline($log, $pipeline) {
  $r = @()
  $quick = $pipeline -like 'quick*'
  $doApp = $pipeline -in 'app','all','quick','quick-app'
  $doBe  = $pipeline -in 'backend','all','quick','quick-backend'
  if (-not (Docker-Up)) {
    $msg = "Docker is not running. Start Docker Desktop (Linux containers) and re-push or queue a job."
    Log $log $msg
    return @([pscustomobject]@{ Name='docker-not-running'; Exit=1; Out=$msg; Secs=0 })
  }
  if ($doApp -and (Test-Path (Join-Path $Repo 'app'))) {
    $r += Docker-Step $log 'pub-get' $FlutterImage 'flutter' '' 'flutter pub get --enforce-lockfile'
    $r += Docker-Step $log 'format'  $FlutterImage 'flutter' '' 'dart format --output=none --set-exit-if-changed .'
    $r += Docker-Step $log 'analyze' $FlutterImage 'flutter' '' 'flutter analyze'
    $r += Docker-Step $log 'app-test' $FlutterImage 'flutter' 'app' 'flutter test'
    foreach ($pkg in Get-ChildItem (Join-Path $Repo 'packages') -Directory -ErrorAction SilentlyContinue) {
      $r += Docker-Step $log "dart-test-$($pkg.Name)" $FlutterImage 'flutter' "packages/$($pkg.Name)" 'dart test'
    }
    if (-not $quick) {
      foreach ($fl in 'prodNoSms','prodSms') {
        $r += Docker-Step $log "apk-$fl" $FlutterImage 'flutter' 'app' "flutter build apk --release --flavor $fl"
      }
    }
  }
  if ($doBe -and (Test-Path (Join-Path $Repo 'backend'))) {
    $r += Docker-Step $log 'dotnet-build'  $DotnetImage 'dotnet' 'backend' 'dotnet build Zaghlol.sln -warnaserror -c Release'
    $r += Docker-Step $log 'dotnet-format' $DotnetImage 'dotnet' 'backend' 'dotnet format Zaghlol.sln --no-restore --verify-no-changes --verbosity normal'
    $r += Docker-Step $log 'dotnet-test'   $DotnetImage 'dotnet' 'backend' 'dotnet test Zaghlol.sln -c Release --no-build'
  }
  return $r
}

function Publish($branch, $sha, $statusLine, $log, $steps = @()) {
  try {
    if (-not (Test-Path (Join-Path $Pub '.git'))) { git clone --quiet $Origin $Pub 2>&1 | Out-Null }
    Push-Location $Pub
    git fetch --quiet origin 2>&1 | Out-Null
    $has = git ls-remote --heads origin local-ci
    if ($has) { git checkout --quiet --force -B local-ci origin/local-ci 2>&1 | Out-Null }
    else { git checkout --quiet --orphan local-ci 2>&1 | Out-Null; git rm -rfq . 2>&1 | Out-Null }
    $dir = Join-Path $Pub ($branch -replace '/','__')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path (Join-Path $dir "$sha.status") -Value $statusLine -Encoding UTF8
    Write-PublishLog $log $statusLine $steps (Join-Path $dir "$sha.log")
    git add -A 2>&1 | Out-Null
    git -c user.name='zaghlol-local-ci' -c user.email='local-ci@invalid' commit --quiet -m "local-ci: $branch $($sha.Substring(0,7))" 2>&1 | Out-Null
    $push = git push --quiet origin local-ci 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Add-Content (Join-Path $Results 'runner-errors.log') "$(Get-Date -Format o) publish failed: $push" }
    Pop-Location
  } catch { Add-Content (Join-Path $Results 'runner-errors.log') "$(Get-Date -Format o) publish: $($_ | Out-String)"; Pop-Location }
}

function Run-Job($jobFile) {
  $kv = @{}
  foreach ($l in Get-Content $jobFile) { if ($l -match '^\s*([a-z]+)\s*=\s*(.+?)\s*$') { $kv[$Matches[1]] = $Matches[2] } }
  $id = [IO.Path]::GetFileNameWithoutExtension($jobFile)
  Remove-Item $jobFile -Force
  $log = Join-Path $Results "$id.log"; $status = Join-Path $Results "$id.status"
  Set-Content -Path $log -Value "job $id $(Get-Date -Format o)" -Encoding UTF8
  Set-Content -Path $status -Value "RUNNING" -Encoding UTF8
  $branch = $kv['branch']; $pipeline = $kv['pipeline']
  if ($branch -notmatch '^[A-Za-z0-9._/-]{1,100}$' -or $pipeline -notmatch '^(app|backend|all|quick|quick-app|quick-backend|probe)$') {
    Set-Content $status "FAIL invalid job (branch/pipeline)"; return
  }
  if ($pipeline -eq 'probe') { Probe; Set-Content $status "DONE probe"; return }
  try { $co = Checkout $log $branch } catch { Log $log "$_"; Set-Content -Path $status -Value "FAIL checkout=1" -Encoding UTF8; return }
  $r = Run-Pipeline $log $pipeline
  $summary = ($r | ForEach-Object { "{0}={1}" -f $_.Name, $_.Exit }) -join ' '
  $fail = @($r | Where-Object { $_.Exit -ne 0 }).Count
  $line = "{0} sha={1} pipeline={2} {3}" -f $(if ($fail -eq 0) {'PASS'} else {'FAIL'}), $co.Sha, $pipeline, $summary
  Set-Content -Path $status -Value $line -Encoding UTF8
  Log $log "SUMMARY $summary"
}

function Auto-Check {
  $refs = git ls-remote --heads $Origin 'refs/heads/task/*' 2>$null
  if (-not $refs) { return }
  $seenSet = @{}
  $first = -not (Test-Path $Seen)
  if (-not $first) { foreach ($s in Get-Content $Seen) { $seenSet[$s] = 1 } }
  foreach ($line in $refs) {
    $parts = $line -split '\s+'
    if ($parts.Count -lt 2) { continue }
    $sha = $parts[0]; $branch = $parts[1] -replace '^refs/heads/',''
    if ($sha -notmatch '^[0-9a-f]{40}$' -or $branch -notmatch '^[A-Za-z0-9._/-]{1,100}$') { continue }
    if ($seenSet.ContainsKey($sha)) { continue }
    Add-Content $Seen $sha
    if ($first) { continue }   # first start: remember existing commits, don't rebuild them
    $log = Join-Path $Results ("auto-" + ($branch -replace '/','__') + "-" + $sha.Substring(0,7) + ".log")
    Set-Content -Path $log -Value "auto $branch $sha $(Get-Date -Format o)" -Encoding UTF8
    Publish $branch $sha "RUNNING sha=$sha" $log
    try { $co = Checkout $log $branch } catch { Log $log "$_"; Publish $branch $sha "FAIL sha=$sha pipeline=checkout checkout=1" $log; continue }
    $c = $co.Changed
    $pipeline = if (($c -match '(?m)^(app|packages)/') -and ($c -match '(?m)^backend/')) { 'quick' }
                elseif ($c -match '(?m)^backend/') { 'quick-backend' }
                elseif ($c -match '(?m)^(app|packages)/') { 'quick-app' }
                else { '' }
    if (-not $pipeline) { Publish $branch $sha "SKIP sha=$sha no app/packages/backend changes" $log; continue }
    $r = Run-Pipeline $log $pipeline
    $summary = ($r | ForEach-Object { "{0}={1}" -f $_.Name, $_.Exit }) -join ' '
    $fail = @($r | Where-Object { $_.Exit -ne 0 }).Count
    $status = "{0} sha={1} pipeline={2} {3}" -f $(if ($fail -eq 0) {'PASS'} else {'FAIL'}), $sha, $pipeline, $summary
    Log $log "SUMMARY $status"
    Publish $branch $sha $status $log $r
  }
}

Write-Host "Zaghlol local CI runner v3 (Docker). Watching task/* branches and $Queue  (close this window to stop)"
Probe
while ($true) {
  Get-ChildItem $Queue -Filter *.job -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
    try { Run-Job $_.FullName } catch { Add-Content (Join-Path $Results 'runner-errors.log') "$(Get-Date -Format o) $($_ | Out-String)" }
  }
  try { Auto-Check } catch { Add-Content (Join-Path $Results 'runner-errors.log') "$(Get-Date -Format o) auto: $($_ | Out-String)" }
  Start-Sleep -Seconds 30
}
