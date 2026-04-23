# MG Activities - Instalador Completo Windows v2
# ActivityWatch + mg-sync como servico Windows via NSSM
#
# USO (PowerShell como Administrador):
#   iex (irm https://lumiatech.com.br/static/install-activities.ps1)
#
# Pre-requisito: PowerShell Admin (Botao direito -> Executar como administrador)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# TLS 1.2+ pra HTTPS moderno (PS 5.1 default e TLS 1.0)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

$MG_HOST = "lumiatech.com.br"
$MG_URL  = "https://$MG_HOST"

# 0. Verificar admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "ERRO: precisa rodar em PowerShell como Administrador." -ForegroundColor Red
    Write-Host ""
    Write-Host "1. Feche essa janela." -ForegroundColor Yellow
    Write-Host "2. Menu Iniciar -> digite 'powershell' -> BOTAO DIREITO -> 'Executar como administrador'"
    Write-Host "3. Aceite o UAC (janela azul que pergunta 'deseja permitir...')"
    Write-Host "4. Cole de novo:"
    Write-Host "   iex (irm $MG_URL/static/install-activities.ps1)" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "+-------------------------------------------------+" -ForegroundColor Cyan
Write-Host "|     MG Activities - Instalador v2              |" -ForegroundColor Cyan
Write-Host "|     ActivityWatch + Sync (servico Windows)     |" -ForegroundColor Cyan
Write-Host "+-------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""

# 1. Detectar maquina/usuario
$HOSTNAME_DETECTED = $env:COMPUTERNAME
$USER_DETECTED     = $env:USERNAME
$FULL_NAME = try { ([adsi]"WinNT://./$USER_DETECTED,user").FullName } catch { $USER_DETECTED }
if (-not $FULL_NAME) { $FULL_NAME = $USER_DETECTED }
$DISPLAY_NAME = $FULL_NAME

Write-Host "> Maquina:  $HOSTNAME_DETECTED" -ForegroundColor Green
Write-Host "> Usuario:  $USER_DETECTED ($DISPLAY_NAME)" -ForegroundColor Green
Write-Host ""

$INSTALL_DIR = "$env:LOCALAPPDATA\MgActivities"
if (-not (Test-Path $INSTALL_DIR)) { New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null }

# 2. Baixar ActivityWatch
if (-not (Test-Path "$INSTALL_DIR\activitywatch\aw-qt.exe")) {
    Write-Host "> Baixando ActivityWatch v0.12.2 (~80MB, pode levar 1-2min)..." -ForegroundColor Cyan
    $AW_URL = "https://github.com/ActivityWatch/activitywatch/releases/download/v0.12.2/activitywatch-v0.12.2-windows-x86_64.zip"
    $zip = "$env:TEMP\aw.zip"
    Invoke-WebRequest -Uri $AW_URL -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $INSTALL_DIR -Force
    Remove-Item $zip -Force
    Write-Host "  OK" -ForegroundColor Green
} else {
    Write-Host "> ActivityWatch ja instalado" -ForegroundColor Yellow
}

# 3. aw-client.toml (aponta pra plataforma)
Write-Host "> Configurando aw-client -> $MG_URL..." -ForegroundColor Cyan
$CONFIG_DIR = "$env:APPDATA\activitywatch\aw-client"
if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
@"
[server]
hostname = "$MG_HOST"
port     = "443"
protocol = "https"
path     = "/aw"

[server-testing]
hostname = "$MG_HOST"
port     = "443"
"@ | Set-Content -Path "$CONFIG_DIR\aw-client.toml" -Encoding UTF8

# AFK timeout 60min (evita pausa em video/jogos)
$afkCfgDir = "$env:APPDATA\activitywatch\aw-watcher-afk"
if (-not (Test-Path $afkCfgDir)) { New-Item -ItemType Directory -Path $afkCfgDir -Force | Out-Null }
@"
[aw-watcher-afk]
timeout = 3600
poll_time = 5

[aw-watcher-afk-testing]
timeout = 3600
poll_time = 5
"@ | Set-Content -Path "$afkCfgDir\aw-watcher-afk.toml" -Encoding UTF8
Write-Host "  OK" -ForegroundColor Green

# 4. Registrar na plataforma
Write-Host "> Registrando na plataforma..." -ForegroundColor Cyan
try {
    $body = @{
        hostname   = $HOSTNAME_DETECTED
        user_label = $DISPLAY_NAME
        os         = "windows"
        arch       = $env:PROCESSOR_ARCHITECTURE
    } | ConvertTo-Json
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    Invoke-RestMethod -Uri "$MG_URL/api/activities/enroll" -Method Post -Body $bodyBytes `
        -ContentType 'application/json; charset=utf-8' -UserAgent 'MG-Activities-Agent/2.0' | Out-Null
    Write-Host "  OK" -ForegroundColor Green
} catch {
    Write-Host "  (falhou, mas agent funciona: $_)" -ForegroundColor Yellow
}

# 5. aw-qt via Task Scheduler (precisa de sessao do usuario pra watcher-window)
Write-Host "> Configurando aw-qt (Scheduled Task AtLogOn)..." -ForegroundColor Cyan
$awqt = "$INSTALL_DIR\activitywatch\aw-qt.exe"
$taskName = "MGActivitiesAgent"
try { schtasks /Delete /TN $taskName /F 2>&1 | Out-Null } catch {}
$LASTEXITCODE = 0
$action   = New-ScheduledTaskAction -Execute $awqt
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

# Parar instancias antigas e iniciar a nova agora
Get-Process aw-qt, aw-watcher-window, aw-watcher-afk -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process -FilePath $awqt -WindowStyle Hidden
Write-Host "  OK" -ForegroundColor Green

# 6. NSSM + mg-sync como servico Windows (auto-restart, sobe no boot)
# IMPORTANTE: binarios+script em C:\ProgramData\MgActivities (path ASCII limpo,
# sem acento/espaco). NSSM corrompe non-ASCII ao passar argv pro powershell.exe.
$SYS_DIR = "C:\ProgramData\MgActivities"
if (-not (Test-Path $SYS_DIR)) { New-Item -ItemType Directory -Path $SYS_DIR -Force | Out-Null }

Write-Host "> Baixando NSSM..." -ForegroundColor Cyan
$nssm = "$SYS_DIR\nssm.exe"
if (-not (Test-Path $nssm)) {
    Invoke-WebRequest -Uri "$MG_URL/static/nssm.exe" -OutFile $nssm -UseBasicParsing
}
Write-Host "  OK" -ForegroundColor Green

Write-Host "> Baixando mg-sync.ps1..." -ForegroundColor Cyan
$syncScript = "$SYS_DIR\mg-sync.ps1"
Invoke-WebRequest -Uri "$MG_URL/static/mg-sync.ps1" -OutFile $syncScript -UseBasicParsing
Write-Host "  OK" -ForegroundColor Green

Write-Host "> Instalando servico MGActivitiesSync..." -ForegroundColor Cyan
$svc = "MGActivitiesSync"

# NSSM/schtasks escrevem em stderr quando objeto nao existe (1a instalacao).
# Desligar ErrorActionPreference=Stop durante o bloco pra nao abortar script.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

# Limpar instalacoes anteriores (idempotente - erros esperados na 1a vez)
& $nssm stop   $svc 2>&1 | Out-Null
& $nssm remove $svc confirm 2>&1 | Out-Null
schtasks /End    /TN $svc 2>&1 | Out-Null
schtasks /Delete /TN $svc /F 2>&1 | Out-Null
Get-WmiObject Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'mg-sync' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item "$INSTALL_DIR\sync.log","$INSTALL_DIR\sync.log.tmp","$INSTALL_DIR\sync-service.log" `
    -Force -ErrorAction SilentlyContinue

& $nssm install $svc "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$syncScript`"" 2>&1 | Out-Null
& $nssm set $svc Start           SERVICE_AUTO_START                      2>&1 | Out-Null
& $nssm set $svc AppDirectory    "$INSTALL_DIR"                          2>&1 | Out-Null
& $nssm set $svc AppStdout       "$INSTALL_DIR\sync-service.log"         2>&1 | Out-Null
& $nssm set $svc AppStderr       "$INSTALL_DIR\sync-service.log"         2>&1 | Out-Null
& $nssm set $svc AppRotateFiles  1                                       2>&1 | Out-Null
& $nssm set $svc AppRotateBytes  1048576                                 2>&1 | Out-Null
& $nssm set $svc AppThrottle     10000                                   2>&1 | Out-Null
& $nssm set $svc AppExit Default Restart                                 2>&1 | Out-Null
& $nssm set $svc AppRestartDelay 5000                                    2>&1 | Out-Null

# LocalSystem + env vars do usuario (nao precisa senha, acha AppData certinho)
& $nssm set $svc ObjectName LocalSystem 2>&1 | Out-Null
& $nssm set $svc AppEnvironmentExtra `
    "LOCALAPPDATA=$env:USERPROFILE\AppData\Local" `
    "APPDATA=$env:USERPROFILE\AppData\Roaming" `
    "USERPROFILE=$env:USERPROFILE" `
    "COMPUTERNAME=$env:COMPUTERNAME" 2>&1 | Out-Null

& $nssm start $svc 2>&1 | Out-Null

$ErrorActionPreference = $prevEAP
Start-Sleep -Seconds 12
$svcStatus = (Get-Service $svc -ErrorAction SilentlyContinue).Status
if ($svcStatus -eq 'Running') {
    Write-Host "  Servico Running" -ForegroundColor Green
} else {
    Write-Host "  Status: $svcStatus (esperado: Running)" -ForegroundColor Yellow
}

# 7. Resultado final
Write-Host ""
Write-Host "+-------------------------------------------------+" -ForegroundColor Green
Write-Host "|   Instalacao concluida!                         |" -ForegroundColor Green
Write-Host "+-------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "Dashboard:  $MG_URL/activities/team/"
Write-Host "Voce e:     $DISPLAY_NAME ($HOSTNAME_DETECTED)"
Write-Host ""
Write-Host "Componentes instalados:"
Write-Host "  aw-qt    (coletor)   -> Scheduled Task 'MGActivitiesAgent'"
Write-Host "  mg-sync  (backgnd)   -> Windows Service 'MGActivitiesSync'"
Write-Host ""
Write-Host "Tudo sobe sozinho no boot (antes ate de voce logar)."
Write-Host ""
Write-Host "Validar apos reiniciar o PC:"
Write-Host "  Get-Service MGActivitiesSync" -ForegroundColor Cyan
Write-Host "  Get-Content `"$INSTALL_DIR\sync.log`" -Tail 5" -ForegroundColor Cyan
Write-Host ""
Write-Host "Opcional - captura URLs do navegador (aw-watcher-web):" -ForegroundColor Yellow
Write-Host "  Chrome:  https://chrome.google.com/webstore/detail/nglaklhklhcoonedhgnpgddginnjdadi"
Write-Host "  Firefox: https://addons.mozilla.org/firefox/addon/activitywatch-web-watcher/"
Write-Host ""
