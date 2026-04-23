# MG Activities - Desinstalador Completo Windows
# Remove: servico MGActivitiesSync, Scheduled Task MGActivitiesAgent,
#         ActivityWatch bundle, configs aw-client/aw-watcher-afk, NSSM,
#         dados locais (logs, state, checkpoints).
#
# USO (PowerShell como Administrador):
#   iex (irm https://lumiatech.com.br/static/uninstall-activities.ps1)

$ErrorActionPreference = 'Continue'   # tolerante: tudo aqui e idempotente
$ProgressPreference    = 'SilentlyContinue'

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# 0. Verificar admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "ERRO: precisa rodar em PowerShell como Administrador." -ForegroundColor Red
    Write-Host ""
    Write-Host "1. Menu Iniciar -> 'powershell' -> BOTAO DIREITO -> 'Executar como administrador'"
    Write-Host "2. Cole:"
    Write-Host "   iex (irm https://lumiatech.com.br/static/uninstall-activities.ps1)" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "+-------------------------------------------------+" -ForegroundColor Yellow
Write-Host "|     MG Activities - Desinstalador              |" -ForegroundColor Yellow
Write-Host "+-------------------------------------------------+" -ForegroundColor Yellow
Write-Host ""

$svc      = "MGActivitiesSync"
$taskName = "MGActivitiesAgent"
$USER_DIR = "$env:LOCALAPPDATA\MgActivities"
$SYS_DIR  = "C:\ProgramData\MgActivities"
$AW_CFG_1 = "$env:APPDATA\activitywatch\aw-client"
$AW_CFG_2 = "$env:APPDATA\activitywatch\aw-watcher-afk"

# 1. Parar + remover servico (via nssm.exe se ainda existir, senao via sc.exe)
Write-Host "> Parando/removendo servico $svc..." -ForegroundColor Cyan
$nssmCandidates = @(
    "$SYS_DIR\nssm.exe",
    "$USER_DIR\nssm\nssm.exe"       # layout antigo pre-C:\ProgramData
)
$nssm = $nssmCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($nssm) {
    & $nssm stop   $svc         2>&1 | Out-Null
    & $nssm remove $svc confirm 2>&1 | Out-Null
} else {
    # fallback: sc.exe ainda da conta de parar/deletar um servico legado
    sc.exe stop   $svc 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    sc.exe delete $svc 2>&1 | Out-Null
}

if (Get-Service $svc -ErrorAction SilentlyContinue) {
    Write-Host "  AVISO: servico ainda existe, Windows pode estar com lock pendente" -ForegroundColor Yellow
} else {
    Write-Host "  OK" -ForegroundColor Green
}

# 2. Remover Scheduled Task do aw-qt
Write-Host "> Removendo Scheduled Task $taskName..." -ForegroundColor Cyan
schtasks /End    /TN $taskName    2>&1 | Out-Null
schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
Write-Host "  OK" -ForegroundColor Green

# 3. Matar processos residuais (aw-qt, watchers, mg-sync)
Write-Host "> Matando processos residuais..." -ForegroundColor Cyan
$killed = 0
Get-Process aw-qt, aw-watcher-window, aw-watcher-afk, aw-server, aw-server-rust `
    -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killed++
    }
Get-WmiObject Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -match 'mg-sync' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $killed++
    }
Write-Host "  $killed processo(s) encerrado(s)" -ForegroundColor Green

# 4. Remover arquivos de sistema (C:\ProgramData\MgActivities)
Write-Host "> Removendo $SYS_DIR..." -ForegroundColor Cyan
if (Test-Path $SYS_DIR) {
    Remove-Item $SYS_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path $SYS_DIR) {
    Write-Host "  AVISO: restou algum arquivo em uso em $SYS_DIR" -ForegroundColor Yellow
} else {
    Write-Host "  OK" -ForegroundColor Green
}

# 5. Remover dados do usuario (ActivityWatch + logs + state)
Write-Host "> Removendo $USER_DIR..." -ForegroundColor Cyan
if (Test-Path $USER_DIR) {
    Remove-Item $USER_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path $USER_DIR) {
    Write-Host "  AVISO: restou algum arquivo em uso em $USER_DIR" -ForegroundColor Yellow
} else {
    Write-Host "  OK" -ForegroundColor Green
}

# 6. Remover configs aw-client / aw-watcher-afk
Write-Host "> Removendo configs do ActivityWatch..." -ForegroundColor Cyan
foreach ($cfg in @($AW_CFG_1, $AW_CFG_2)) {
    if (Test-Path $cfg) {
        Remove-Item $cfg -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# Se a pasta pai $env:APPDATA\activitywatch ficou vazia, remove tambem
$awBase = "$env:APPDATA\activitywatch"
if ((Test-Path $awBase) -and -not (Get-ChildItem $awBase -Force -ErrorAction SilentlyContinue)) {
    Remove-Item $awBase -Force -ErrorAction SilentlyContinue
}
Write-Host "  OK" -ForegroundColor Green

# 7. Resultado final
Write-Host ""
Write-Host "+-------------------------------------------------+" -ForegroundColor Green
Write-Host "|   Desinstalacao concluida                       |" -ForegroundColor Green
Write-Host "+-------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "Removido:"
Write-Host "  Servico Windows     $svc"
Write-Host "  Scheduled Task      $taskName"
Write-Host "  $SYS_DIR (NSSM + mg-sync.ps1)"
Write-Host "  $USER_DIR (ActivityWatch + logs)"
Write-Host "  Configs aw-client/aw-watcher-afk em $env:APPDATA\activitywatch"
Write-Host ""
Write-Host "Observacoes:" -ForegroundColor Yellow
Write-Host "  - Maquina continua listada no dashboard ate admin (Bruno) remover."
Write-Host "    O 'last_seen' vai parar de atualizar, ela cai pra 'offline' sozinha."
Write-Host "  - Extensoes aw-watcher-web (Chrome/Firefox) precisam ser removidas"
Write-Host "    manualmente nos navegadores se voce instalou."
Write-Host ""
Write-Host "Reinstalar depois:"
Write-Host "  iex (irm https://lumiatech.com.br/static/install-activities.ps1)" -ForegroundColor Cyan
Write-Host ""
