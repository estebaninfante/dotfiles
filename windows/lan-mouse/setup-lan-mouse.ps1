<#
.SYNOPSIS
    Instala la configuracion de LAN Mouse en Windows (laptop o desktop).

.DESCRIPTION
    Deja LAN Mouse funcionando en cualquiera de los 4 escenarios
    (laptop/desktop en Windows u Omarchy). Hace:

      1. Detecta la maquina por hardware (bateria => laptop) salvo que le
         pases -Machine.
      2. Copia config.<maquina>.toml a %LOCALAPPDATA%\lan-mouse\config.toml
         (con backup del anterior) y lan-mouse.pem (identidad compartida con
         las instalaciones Linux; su fingerprint ya esta autorizada en el peer).
      3. Busca lan-mouse.exe y deja un autostart en la carpeta Inicio para
         que el daemon arranque al iniciar sesion.
      4. Con -SetStaticIP (requiere PowerShell como Administrador) agrega la
         IP KVM (laptop 192.168.1.240 / desktop 192.168.1.241) como direccion
         secundaria de la placa Ethernet, para que el otro equipo la alcance
         por el cable.

.PARAMETER Machine
    laptop | desktop. Si se omite, se detecta por hardware.

.PARAMETER SetStaticIP
    Agrega la IP KVM estatica a la placa Ethernet (necesita Administrador).

.PARAMETER NoAutostart
    No crear el autostart al iniciar sesion.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup-lan-mouse.ps1

.EXAMPLE
    # Como Administrador, ademas fija la IP KVM en el cable:
    powershell -ExecutionPolicy Bypass -File .\setup-lan-mouse.ps1 -SetStaticIP
#>
[CmdletBinding()]
param(
    [ValidateSet('laptop', 'desktop')]
    [string]$Machine,
    [string]$SourceDir = $PSScriptRoot,
    [switch]$SetStaticIP,
    [switch]$NoAutostart
)

$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "[lan-mouse] $m" }
function Warn2($m) { Write-Warning "[lan-mouse] $m" }

# ── 1) Detectar maquina ─────────────────────────────────────────────
if (-not $Machine) {
    $hasBattery = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0
    $Machine = if ($hasBattery) { 'laptop' } else { 'desktop' }
}
Info "Maquina: $Machine"

# ── 2) IPs KVM ──────────────────────────────────────────────────────
if ($Machine -eq 'laptop') {
    $KvmIp = '192.168.1.240'; $PeerIp = '192.168.1.241'; $PeerPos = 'top'
} else {
    $KvmIp = '192.168.1.241'; $PeerIp = '192.168.1.240'; $PeerPos = 'bottom'
}
Info "IP KVM local: $KvmIp   peer: $PeerIp ($PeerPos)"

# ── 3) Config de lan-mouse ──────────────────────────────────────────
$cfgDir = Join-Path $env:LOCALAPPDATA 'lan-mouse'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

$srcCfg = Join-Path $SourceDir "config.$Machine.toml"
if (-not (Test-Path $srcCfg)) { throw "No encuentro $srcCfg" }
$dstCfg = Join-Path $cfgDir 'config.toml'
if (Test-Path $dstCfg) {
    $bak = "$dstCfg.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $dstCfg $bak -Force
    Info "Backup del config anterior: $bak"
}
Copy-Item $srcCfg $dstCfg -Force
Info "config.toml -> $dstCfg"

$srcPem = Join-Path $SourceDir 'lan-mouse.pem'
if (Test-Path $srcPem) {
    Copy-Item $srcPem (Join-Path $cfgDir 'lan-mouse.pem') -Force
    Info 'lan-mouse.pem (identidad compartida) instalado'
} else {
    Warn2 'No encuentro lan-mouse.pem junto al script'
}

# ── 4) Buscar lan-mouse.exe ─────────────────────────────────────────
$exe = (Get-Command lan-mouse.exe -ErrorAction SilentlyContinue).Source
if (-not $exe) {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\lan-mouse\lan-mouse.exe'),
        (Join-Path $env:LOCALAPPDATA 'lan-mouse\lan-mouse.exe'),
        (Join-Path $env:ProgramFiles 'lan-mouse\lan-mouse.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'lan-mouse\lan-mouse.exe')
    )
    $exe = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if ($exe) {
    Info "lan-mouse.exe: $exe"
} else {
    Warn2 'No encontre lan-mouse.exe. Descargalo de https://github.com/feschber/lan-mouse/releases y volve a correr este script.'
}

# ── 5) Autostart al iniciar sesion ──────────────────────────────────
if (-not $NoAutostart -and $exe) {
    $startup = [Environment]::GetFolderPath('Startup')
    $cmd = Join-Path $startup 'lan-mouse.cmd'
    @(
        '@echo off',
        ('start "" "{0}" daemon' -f $exe)
    ) | Set-Content -Path $cmd -Encoding ASCII -Force
    Info "Autostart creado: $cmd"
}

# ── 6) IP KVM estatica (opcional) ───────────────────────────────────
if ($SetStaticIP) {
    $admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        Warn2 '-SetStaticIP necesita PowerShell como Administrador. Se omite.'
    } else {
        $eth = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.MediaType -eq '802.3' } | Select-Object -First 1
        if (-not $eth) {
            Warn2 'No encontre una placa Ethernet fisica. Se omite la IP estatica.'
        } elseif (Get-NetIPAddress -IPAddress $KvmIp -ErrorAction SilentlyContinue) {
            Info "$KvmIp ya esta configurada; no toco nada."
        } else {
            New-NetIPAddress -InterfaceIndex $eth.ifIndex -IPAddress $KvmIp `
                -PrefixLength 24 -SkipAsSource $true | Out-Null
            Info "IP KVM $KvmIp agregada a '$($eth.Name)' (secundaria)"
        }
    }
}

Info 'Listo. Cerra y volve a abrir LAN Mouse (o reinicia la PC) para aplicar.'
