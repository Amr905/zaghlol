# Zaghlol local CI runner v2 (fast feedback; GitHub Actions stays the merge gate).
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

function Log($f,$m){ $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content -Path $f -Value $line -Encoding UTF8; Write-Host $line }

function Step($log, $name, $dir, [scriptblock]$cmd) {
  Log $log "=== STEP $name (in $dir)"
  Push-Location $dir
  $out = & $cmd 2>&1 | Out-String
  $code = $LASTEXITCODE
  Pop-Location
  Add-Content -Path $log -Value $out -Encoding UTF8
  if ($null -eq $code) { $code = 0 }
  Log $log "=== RESULT $name exit=$code"
  return [pscustomobject]@{ Name=$name; Exit=$code }
}

function Probe {
  $p = Join-Path $Results 'probe.log'
  Set-Content -Path $p -Value "probe $(Get-Date -Format o)" -Encoding UTF8
  foreach ($t in 'git','flutter','dart','dotnet','java','docker') {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    Add-Content $p ("where {0}: {1}" -f $t, $(if ($c) { $c.Source } else { 'NOT FOUND' }))
  }
  Add-Content $p ("flutter: " + (flutter --version 2>&1 | Out-String))
  Add-Content $p ("dotnet sdks: " + (dotnet --list-sdks 2>&1 | Out-String))
  Add-Content $p ("docker: " + (docker version --format '{{.Server.Version}}' 2>&1 | Out-String))
  Add-Content $p "probe done"
}

function Checkout($log, $branch) {
  if (-not (Test-Path (Join-Path $Repo '.git'))) {
    Log $log "cloning..."; git clone --quiet -c core.autocrlf=false -c core.eol=lf $Origin $Repo 2>&1 | Out-String | Add-Content $log
  }
  Push-Location $Repo
  # Keep LF line endings like CI (dotnet format / dart format reject CRLF). One-time renormalize of an old clone.
  git config core.autocrlf false
  git config core.eol lf
  if (-not (Test-Path (Join-Path $Repo '.git\zaghlol-lf-ok'))) {
    git rm -rq --cached . 2>&1 | Out-Null; git reset --quiet --hard 2>&1 | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $Repo '.git\zaghlol-lf-ok') | Out-Null
  }
  git fetch --quiet --force origin "+refs/heads/main:refs/remotes/origin/main" "+refs/heads/${branch}:refs/remotes/origin/${branch}" 2>&1 | Out-String | Add-Content $log
  git checkout --quiet --force --detach "origin/$branch" 2>&1 | Out-String | Add-Content $log
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
  if ($doApp -and (Test-Path (Join-Path $Repo 'app'))) {
    $r += Step $log 'pub-get' $Repo { flutter pub get --enforce-lockfile }
    $r += Step $log 'format'  $Repo { dart format --output=none --set-exit-if-changed . }
    $r += Step $log 'analyze' $Repo { flutter analyze }
    $r += Step $log 'app-test' (Join-Path $Repo 'app') { flutter test }
    foreach ($pkg in Get-ChildItem (Join-Path $Repo 'packages') -Directory -ErrorAction SilentlyContinue) {
      $r += Step $log "dart-test-$($pkg.Name)" $pkg.FullName { dart test }
    }
    if (-not $quick) {
      foreach ($fl in 'prodNoSms','prodSms') {
        $r += Step $log "apk-$fl" (Join-Path $Repo 'app') { flutter build apk --release --flavor $fl }
      }
    }
  }
  if ($doBe -and (Test-Path (Join-Path $Repo 'backend'))) {
    $b = Join-Path $Repo 'backend'
    $r += Step $log 'dotnet-build'  $b { dotnet build -warnaserror -c Release }
    $r += Step $log 'dotnet-format' $b { dotnet format --verify-no-changes }
    $r += Step $log 'dotnet-test'   $b { dotnet test -c Release --no-build }
  }
  return $r
}

function Publish($branch, $sha, $statusLine, $log) {
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
    Get-Content $log -Tail 400 | Set-Content -Path (Join-Path $dir "$sha.log") -Encoding UTF8
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
  $co = Checkout $log $branch
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
    $co = Checkout $log $branch
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
    Publish $branch $sha $status $log
  }
}

Write-Host "Zaghlol local CI runner v2. Watching task/* branches and $Queue  (close this window to stop)"
Probe
while ($true) {
  Get-ChildItem $Queue -Filter *.job -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object {
    try { Run-Job $_.FullName } catch { Add-Content (Join-Path $Results 'runner-errors.log') "$(Get-Date -Format o) $($_ | Out-String)" }
  }
  try { Auto-Check } catch { Add-Content (Join-Path $Results 'runner-errors.log') "$(Get-Date -Format o) auto: $($_ | Out-String)" }
  Start-Sleep -Seconds 30
}
