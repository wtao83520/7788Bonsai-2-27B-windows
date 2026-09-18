# Ternary-Bonsai-2-27B-PQ2_0 - interactive chat (llama-cli, PrismML fork)
# Usage: .\run-chat.ps1 [-Prompt "your question"]
param(
    [string]$Prompt = "",
    [int]$Context = 32768,
    [switch]$NoThink   # use instruct-mode sampling instead of thinking mode
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$model = ".\models\Ternary-Bonsai-2-27B-PQ2_0.gguf"
if (-not (Test-Path $model)) { throw "Model not found: $model  (run download first)" }

# Recommended sampling from the model card:
#   thinking mode : temp=1.0 top_p=0.95 top_k=20 min_p=0.0 pres_pen=0.0 rep_pen=1.0
#   instruct mode : temp=0.7 top_p=0.80 top_k=20 min_p=0.0 pres_pen=1.5 rep_pen=1.0
if ($NoThink) { $args = @("--temp","0.7","--top-p","0.80","--top-k","20","--min-p","0.0","--presence-penalty","1.5") }
else          { $args = @("--temp","1.0","--top-p","0.95","--top-k","20","--min-p","0.0","--presence-penalty","0.0") }

$cmd = @( ".\bin\llama-cli.exe" ) +
    @("-m", $model, "-ngl", "99", "-fa", "on", "-c", "$Context") +
    $args +
    @("--system", "You are a helpful assistant.")

if ($Prompt -ne "") { $cmd += @("-p", $Prompt) } else { $cmd += @("-repl") }

Write-Host "`n=== Ternary-Bonsai-2-27B-PQ2_0 | context=$Context | mode=$(if($NoThink){'instruct'}else{'thinking'}) ===`n" -ForegroundColor Cyan
& .\bin\llama-cli.exe @cmd
