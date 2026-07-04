$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$PluginDir = Join-Path $Root "executas\notes-summarizer"
$Fixture = Join-Path $Root "fixtures\sampling-mock.jsonl"

Set-Location $PluginDir

Write-Host "== describe ==" -ForegroundColor Cyan
anna-app executa dev --describe

Write-Host "`n== invoke with mock sampling ==" -ForegroundColor Cyan
anna-app executa dev `
  --mock-sampling $Fixture `
  --invoke summarize_notes `
  --args '{"notes":[{"order":1,"content":"明天跟客户 follow up"},{"order":2,"content":"修复登录 bug"}]}'

Write-Host "`nDone." -ForegroundColor Green
