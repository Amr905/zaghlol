# Wrapper: .\sms_scenario.ps1 --list | --live | --historical | --sender CIB --text "..."
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { Write-Error "Python 3 not found"; exit 2 }
& $py.Source (Join-Path $PSScriptRoot "sms_scenario.py") @args
exit $LASTEXITCODE
