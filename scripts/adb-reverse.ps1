# Ativa o portal USB `celular:8080 → PC:80` (Sprint M1+).
#
# Sem isto, o app rodando no celular físico (Moto G62 5G / etc.) não
# alcança o Docker do PC quando `APP_ENV=localhost`. Basicamente:
#
#   1. Cabo USB do celular ligado no PC.
#   2. Depuração USB autorizada.
#   3. Este script (rode uma vez por conexão USB — se o cabo cair, refaça).
#
# Uso:
#   .\scripts\adb-reverse.ps1              # auto-detecta o único device
#   .\scripts\adb-reverse.ps1 -Serial 0081282819   # força um serial
#
# Também é chamado automaticamente pelo perfil VSCode
# "Dev — localhost (USB, adb reverse)" via `preLaunchTask` (ver
# .vscode/tasks.json e .vscode/launch.json).

[CmdletBinding()]
param(
    [string]$Serial
)

$ErrorActionPreference = 'Stop'

# Localiza o adb.exe do SDK instalado por este projeto (dev/android-sdk).
# Se algum dia o SDK sair de lá, ajuste este bloco.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    # Fallback: instalação alternativa que o projeto documenta.
    $adb = "C:\Users\Diogo\dev\android-sdk\platform-tools\adb.exe"
}
if (-not (Test-Path $adb)) {
    # Último recurso: procurar no PATH.
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { $adb = $cmd.Source }
}
if (-not (Test-Path $adb)) {
    Write-Error "adb.exe não encontrado. Verifique se o Android SDK platform-tools está instalado."
    exit 1
}

# Auto-detecta o serial se não veio como argumento.
if (-not $Serial) {
    $devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "^\S+\s+device$" }
    $count = ($devices | Measure-Object).Count

    if ($count -eq 0) {
        Write-Error "Nenhum device conectado. Ligue o cabo USB e autorize a depuração no celular."
        exit 1
    }
    if ($count -gt 1) {
        Write-Host "Múltiplos devices conectados:" -ForegroundColor Yellow
        $devices | ForEach-Object { Write-Host "  $_" }
        Write-Error "Especifique qual usar com: .\scripts\adb-reverse.ps1 -Serial <SERIAL>"
        exit 1
    }
    $Serial = ($devices | Select-Object -First 1).Split()[0]
}

Write-Host "Configurando adb reverse tcp:8080 → tcp:80 no device $Serial..." -ForegroundColor Cyan

& $adb -s $Serial reverse tcp:8080 tcp:80 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha no adb reverse. Verifique se o device está autorizado."
    exit $LASTEXITCODE
}

Write-Host "OK. Reverses ativos:" -ForegroundColor Green
& $adb -s $Serial reverse --list
