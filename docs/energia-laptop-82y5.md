# Consumo de energía — Lenovo Legion Slim 5 14APH8 (82Y5)

Investigación y plan para bajar el consumo en reposo. Objetivo fijado por el
usuario: **< 20 W en reposo, recién arrancada y sin procesos de usuario**.

Este documento es la referencia; los ajustes aplicados viven en
`linux/bin/battery-power-guard.sh` (runtime, por fuente de energía) y en los
params de arranque de Limine (necesitan reinicio, ver §4).

## 1. La máquina

| Dato | Valor |
|---|---|
| Modelo | Legion Slim 5 14APH8 — Type **82Y5** |
| CPU | AMD Ryzen 7 7840HS (Phoenix, Zen4) — 16 hilos |
| iGPU | Radeon 780M (`0000:05:00.0`, amdgpu, eDP-2 = panel interno) |
| dGPU | NVIDIA RTX 4060 Max-Q (`0000:01:00.0`, AD107M, 50 W cap) |
| Panel | 2880x1800 @ 60 Hz (el panel acepta 120 Hz) |
| Wi-Fi | MediaTek **MT7922** (`mt7921e`, `0000:03:00.0`) |
| Almacenamiento | SK hynix P41/PC801 NVMe |
| BIOS | **MACN24WW 1.24 del 2023-09-21** (viejo, ver §5.11) |
| Kernel | 7.2.5-3-omarchy |

Fuente: `/sys/class/dmi/id`, `lspci`, `hyprctl monitors`.

## 2. Cómo medimos

- **Batería real**: `/sys/class/power_supply/BAT0/power_now` (µW). Es la única
  medida que incluye *todo* (paquete APU, dGPU, panel, NVMe, RAM, USB y las
  pérdidas del VRM).
- **Paquete APU**: `/sys/class/hwmon/hwmon4/power1_input` (label `PPT`).
  Ojo: en APUs AMD este sensor informa **el paquete completo (CPU+iGPU+SoC)**,
  no solo la iGPU.
- **Regresión potencia vs. carga**: muestreamos potencia y %CPU busy cada 2 s y
  ajustamos `P = a + b·busy`. El intercepto `a` es la potencia a carga ~0, o sea
  el piso de reposo. Es lo que permite estimar el reposo sin tener que apagar
  todo.
- `nvidia-smi` da solo la potencia del *die* de la dGPU, no del riel completo.
- **Ojo**: leer `/sys/kernel/debug/dri/*/amdgpu_gfxoff` **bloquea** (espera el
  próximo evento de GFXOFF) y el `cat` se queda girando a 80 % de CPU. No usarlo
  en bucles de diagnóstico.

Script de muestreo usado: `/tmp/idle_reg.py` (efímero). Para verificación
permanente ver §6.

## 3. Estado actual medido (arranque del 2026-10-17, en batería)

| Cosa | Estado | Implicancia |
|---|---|---|
| Perfil de energía | `power-saver` (`platform_profile=low-power`) | Ya óptimo |
| Governor / EPP | `powersave` / `power` (amd_pstate **active**) | Ya óptimo |
| Frecuencias | max 3.80 GHz, min 419 MHz | Ya óptimo |
| C-states | llega a C2/C3 (CC6) | Ya óptimo |
| **PSR del panel** | **deshabilitado por `amdgpu.dcdebugmask=0x10`** | ~1 W perdidos |
| **ASPM PCIe** | política `default`; links de iGPU y dGPU **Disabled** | ~0.3–1 W perdidos |
| **dGPU** | **`active` el 99 % del uptime** (suspendida 13.5 s al arrancar) | ≈8–10 W |
| Wi-Fi power save | **off** (Omarchy lo fuerza off) | ~0.3–1 W |
| USB `3-1` ITE Device(8910) (teclado) | `control=on`, nunca suspende | ~1 W |
| USB `1-2` Wireless Present (dongle 2.4 G) | `control=on`, nunca suspende | ~0.2 W |
| Cámara / huella / BT | `auto` + suspendidos | Ya óptimo |
| SD card reader (`02:00.0`) | `control=on`, `active` | ~0.3 W |
| Brillo | 50 % (200 000/400 000) | Ya capado por el guard |
| `hwmon` térmica | Tctl 62 °C, PPT ~20–31 W con carga | — |
| Potencia con carga (5 agentes `pi` + spotify) | batería **~41 W** | No es reposo |

## 4. Palancas ordenadas por impacto

### 4.1 dGPU encendida siempre — el mayor consumo (≈8–10 W estimados)

Es el hallazgo más grande. `runtime_active_time` es igual al uptime: la RTX 4060
**nunca se suspende**. Motivos:

1. `omnivoz-whisper` (faster-whisper/CUDA) y `kokoro-tts` mantienen **2.2 GB de
   VRAM** reservados constantemente (`nvidia-smi`).
2. Hyprland, hyprpaper, swaync, swayosd, `ohm-bin` y spotify tienen
   `/dev/dri/card1` abierto (clientes DRM de la dGPU), lo que mantiene
   referencias de runtime-PM.

Evidencia del driver nvidia (610.57.04) con `sudo cat
/proc/driver/nvidia/gpus/0000:01:00.0/power`:

```
Runtime D3 status:          Enabled (fine-grained)
Video Memory:               Active
```

y de `/proc/driver/nvidia/params`:

```
DynamicPowerManagement: 3
DynamicPowerManagementVideoMemoryThreshold: 200      <- 200 MB
```

El punto clave: **`DynamicPowerManagementVideoMemoryThreshold=200` MB significa
que cualquier proceso con más de 200 MB de VRAM asignada impide que la dGPU se
apague**. Whisper (1086 MB) y Kokoro (1158 MB) están muy por encima, así que son
*exactamente* lo que bloquea el ahorro. La opción 'de sacar el runtime-PM' no
alcanza mientras esos dos servicios estén cargados.

El foro de Arch documenta el mismo síntoma en una Legion Slim 5 gen 9
(8845HS + 4060): **pasa de ~14 W a ~25 W** cuando la dGPU queda encendida, y la
solución es apagarla por ACPI con `acpi_call`:

```
echo '\_SB.PCI0.GPP0.PG00._OFF' > /proc/acpi/call
```

Ya está en `~/.local/bin/gpu-mode.sh`, que prueba exactamente ese método
(`_SB.PCI0.GPP0.PG00._OFF`, ver SSDT4, PowerResource PEGP→PG00).

Opciones, de menos a más agresiva:

| Opción | Ahorro | Costo |
|---|---|---|
| Que whisper/kokoro/ollama corran en **CPU/iGPU cuando hay batería** (los tres son los que abren CUDA) | 8–10 W | Hay que tocar los servicios (mayor latencia en STT/TTS) |
| Subir `NVreg_DynamicPowerManagementVideoMemoryThreshold` por encima de 2 GB | 8–10 W | El propio driver usa ese umbral porque guardar/restaurar esa VRAM es caro; riesgo de artifacts/cuelgues |
| No exponer `card1` al compositor (`AQ_DRM_DEVICES=/dev/dri/card2`) | ayuda parcial | No alcanza solo: spotify/ohm/swaync lo abren por su cuenta |
| `acpi_call _OFF` al pasar a batería | 8–10 W | **Irreversible hasta reiniciar** (esta BIOS no expone `_ON`); rompe whisper/kokoro |
| `udev` que hace `remove` del dispositivo NVIDIA | 8–10 W | Igual de irreversible; molesta para jugar |

Con `echo '_SB.PCI0.GPP0.PG00._ON'` se puede comprobar si la BIOS expone el
encendido; si no, `_OFF` es un viaje de ida.

**Estado**: `battery-power-guard.sh` hoy solo pone `power/control=auto`. Por eso
es insuficiente mientras los servicios de IA tengan la GPU tomada.

### 4.2 PSR del panel deshabilitado (≈0.5–2 W) — **NO tocar sin evidencia nueva**

`amdgpu.dcdebugmask=0x10` = `DC_DISABLE_PSR`. Se agregó a `/etc/default/limine`
el **2026-10-09** (hay `.bak` de ese día).

**El motivo está documentado** en el vault:
`~/alicia/Inbox/2026-1009-fix-freeze-amdgpu-psr-dcdebugmask-resuelto.md`.
No es estético: la laptop se **congelaba (freeze de pantalla) en 2 de cada 4
boots** por una regresión del driver amdgpu en el módulo de power / PSR:

```
WARNING: drivers/gpu/drm/amd/amdgpu/display/modules/power/power_psr.c:236
         mod_power_set_psr_event+0x4cd
workqueue: amdgpu_dm_crtc_vblank_control_worker   (ruta ISM idle-optimization)
```

Verificado en vivo: el sink sí soporta PSR pero el driver lo tiene apagado por
el debugmask.

```
$ sudo cat /sys/kernel/debug/dri/0000:05:00.0/eDP-2/psr_capability
Sink support: yes [0x01]
Driver support: no [0xffffffff]     <-- bloqueado por el debugmask
```

Entonces **PSR queda como está**: es un workaround de estabilidad, no un
interruptor de ahorro. Reevaluar solo si un kernel más nuevo arregla
`power_psr.c` (la regresión se vio en la serie 7.2.x). Si se prueba: sacar la
línea, `limine-update`, y volver a ponerla si reaparece el freeze. Escalada
sugerida en la propia nota: `dcdebugmask=0x410` (PSR + Panel Replay; acá
`replay_capability` dice que el sink **no** soporta Panel Replay, así que no
aplica).

### 4.3 ASPM PCIe (≈0.3–1 W)

`/sys/module/pcie_aspm/parameters/policy` = `default`. Resultado en los links:

| Device | LnkCap | LnkCtl actual |
|---|---|---|
| `05:00.0` iGPU | L0s L1 | **ASPM Disabled** |
| `01:00.0` dGPU | L1 | **ASPM Disabled** (link ya bajado a 2.5 GT/s) |
| `03:00.0` Wi-Fi | L0s L1 | L1 Enabled |
| `04:00.0` NVMe | L1 | L1 Enabled |

Los dos links importantes quedan sin ASPM. Se puede cambiar **en caliente**
(`echo powersave > /sys/module/pcie_aspm/parameters/policy`) o desde el arranque
con `pcie_aspm.policy=powersave`.

**Verificado tras aplicar `powersave`**: el link de la **iGPU pasa a
`ASPM L0s L1 Enabled`** (antes Disabled). El de la dGPU sigue en `Disabled`
porque lo maneja el driver nvidia mientras la GPU está activa; cuando la dGPU
se suspenda debería caer. Wi-Fi y NVMe ya tenían L1.

### 4.4 Wi-Fi power save apagado (≈0.3–1 W)

`/etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf` lo fuerza:
`wifi.powersave = 2` (**2 = DISABLE**; `3 = ENABLE`). El comentario de Omarchy
dice que se hace por los picos de latencia (20–300 ms) en links ociosos — con
KVM/lan-mouse y agentes de voz eso se nota. Es un intercambio consciente, no un
bug. Si se quiere, se puede habilitar **solo en batería** (ver §6).

### 4.5 Controladores USB que nunca suspenden (≈1–1.5 W)

- `3-1` **ITE Device(8910)**: es el controlador del teclado/LEDs. En el foro de
  Arch, el equivalente ITE Device(8176) figura con **1.23 W**. Ponerlo en
  `auto` puede dejar el teclado interno inutilizable hasta la próxima tecla
  (o directamente roto si no tiene wakeup). **Riesgoso: probar y revertir.**
- `1-2` **Wireless Present** (dongle 2.4 G del presentador): `auto` es seguro,
  el ahorro es chico pero gratis.

Nota del foro: **el display/backlight a brillo alto pesa 14.6 W**. En esta
máquina el brillo ya está capado al 50 % en batería, así que no hay mucho más
que rascar ahí salvo bajarlo más.

### 4.6 Cargador ↔ dGPU (bug conocido, ~11 W)

En la Legion Slim 5 gen 9 del foro: **arrancar en batería ≈14 W; después de
conectar y desconectar el cargador ≈25 W**, porque el cargador despierta la dGPU
y al desenchufar ya no se apaga. Vale la pena medir en esta máquina
(comparar `power_now` antes/después de un ciclo AC).

### 4.7 Lector de SD encendido (≈0.3 W potenciales, **no aplicable**)

`02:00.0` O2 Micro SD/MMC: `control=on`, `status=active`. Se probó ponerlo en
`auto` y **el kernel lo ignora**: `sdhci-pci` no expone `autosuspend_delay_ms` y
`runtime_suspended_time` se queda en 0 — o sea que no soporta runtime-PM.
Solo se apagaría con `unbind`/`remove` del controlador, lo que rompe el lector
de SD. Descartado.

### 4.8 NMI watchdog (≈0.1–0.3 W)

`kernel.nmi_watchdog = 1`. Son NMIs periódicas en cada CPU; apagarlo
(`sysctl kernel.nmi_watchdog=0`, o `nowatchdog` en cmdline) es gratis y no
afecta el uso normal (solo se pierde el detector de hardlocks).

### 4.9 ABM (Adaptive Backlight Management) (≈1 W con contenido oscuro)

`amdgpu.abmlevel=0..4` (hoy `-1` = default de la BIOS). Corre un algoritmo en el
hardware del panel que baja el backlight según el contenido; ~1 W en contenido
oscuro. Requiere cmdline/module param (no hay `panel_power_savings` en este
kernel). Efecto visible: menos contraste/brillo. Empezar por `1` o `2`.

### 4.10 Servicios propios: el verdadero piso del sistema

Aun con todo lo anterior, "sin ningún proceso" no es lo que corre esta laptop.
Al arrancar hay, entre otros: `ollama`, `omnivoz-listen` (wake word escuchando
micrófono 100 % del tiempo), `omnivoz-whisper`, `kokoro-tts`, `voice-daemon`,
`agentes-platform-main`/`developing` (dos Next.js), `ohm`, `speeedy`,
`openclaw-gateway`, `rig-*`, `syncthing` (se apaga en batería), spotify,
`lan-mouse`, `weylus`, docker.

Cada uno suma: microfonía constante, dos servidores Node, un LLM local y dos
modelos ocupando la dGPU. Para el objetivo "<20 W sin procesos" el punto de
partida correcto es un *perfil de batería* que apague o posponga lo que no se
usa. Eso es más grande que "tunear el kernel" y hay que decidirlo aparte.

### 4.11 BIOS vieja

BIOS **MACN24WW 1.24 (2023-09-21)**. Lenovo publica actualizaciones para el
82Y5 (ej. `ds564694`, solo `.exe` para Windows; fwupd **no** está instalado y
este modelo no aparece en LVFS). Una BIOS más nueva suele traer mejoras de
ASPM/PSR/curva de ventiladores. Actualizar requiere Windows temporal o
`fwupd` + `.cab` convertido. **No verificado cuál es la última versión** (el
sitio de Lenovo devolvió 403 desde acá).

## 5. Qué se aplicó automáticamente

En `linux/bin/battery-power-guard.sh` (corre en cada boot y en cada cambio de
fuente, como root):

- ASPM: `powersave` en batería / `default` en AC (sube el link de la iGPU a
  ASPM L0s+L1; verificado).
- NMI watchdog a 0 en batería.
- Wi-Fi power save **opt-in** (`touch /var/lib/power-guard/wifi-powersave`):
  apagado por defecto por los picos de latencia.
- (lo que ya hacía) perfil `power-saver`, dGPU `power/control=auto`,
  syncthing off, brillo ≤50 %.

Y en los params de arranque de Limine (requieren **reinicio** y quedan fuera del
repo, porque Omarchy administra `/etc/default/limine`):

- agregar `pcie_aspm.policy=powersave` (asegura ASPM desde el arranque, antes de
  que corra el guard),
- opcional `nowatchdog` (equivale al NMI watchdog off en AC también),
- **NO** tocar `amdgpu.dcdebugmask=0x10`: es el workaround de freeze (§4.2).

## 6. Verificación

Dos herramientas, ambas deterministas:

1. `scripts/verify/energia.sh` — lee el estado y falla si una palanca gestionada
   se revirtió (ASPM, NMI watchdog, dGPU, USB, Wi-Fi PS ~ PSR). Sale 1 si hay
   fallas.
2. `~/.local/bin/power-idle-bench.sh` — mide el **consumo real** en reposo
   (batería min/avg/max + PPT del APU) y lo agrega a `/var/log/power-idle.tsv`.
   Corre sola al arrancar en batería (`power-idle-bench.service`), así se puede
   comparar entre boots. `--show` lista el historial.

Estados esperados:

- ASPM: `[powersave]` en batería y link de iGPU con `ASPM L0s L1 Enabled`
- NMI watchdog: `0` en batería
- Wi-Fi: off salvo que exista `/var/lib/power-guard/wifi-powersave`
- dGPU: `auto` (y `suspended` cuando nadie la usa)
- PSR: sigue bloqueado a propósito

## 7. Conclusión: ¿se puede bajar de 20 W?

Estimación del piso en reposo, juntando lo medido y las fuentes.

**Medición del 2026-10-17 04:30** (batería, dGPU despierta, sesión de usuario
arriba con ~8 servicios y agentes corriendo, 150 s de muestreo):

| Métrica | Valor |
|---|---|
| Batería min / max | **29.9 W** / 40.3 W |
| PPT del APU min / max | **7.3 W** / 23.7 W |
| %CPU busy | 18–33 % |
| dGPU | activa el 99 % del uptime (suspendida solo 13.5 s, al arrancar) |

O sea: el paquete del APU baja a ~7 W, pero el sistema sigue en ~30 W. La
diferencia (~22 W) es dGPU + panel + NVMe + RAM + Wi-Fi + USB + pérdidas. Si la
dGPU se lleva ~8–10 W (el `nvidia-smi` de 4 W es **solo el die**; hay que sumar
GDDR, link y VRM), el resto (~12 W) es panel y periféricos.

Desglose estimado del piso:

| Componente | Reposo | Nota |
|---|---|---|
| Paquete APU (PPT) | 5–7 W | medido 7.3 W como mínimo |
| dGPU | **0 W si suspende, 8–10 W si no** | es la variable que decide todo (§4.1) |
| Panel 2880x1800 @60 Hz, brillo 50 % | 3–5 W | el brillo es carísimo (14.6 W a brillo alto en el foro) |
| NVMe + Wi-Fi + RAM + USB | 3–4 W | |
| Pérdidas de VRM/batería | ~10–15 % | |
| **Total** | **≈ 12–16 W sin la dGPU · ≈ 22–26 W con la dGPU** | |

O sea: **sí, <20 W es alcanzable**, pero el resultado depende casi por completo
de la dGPU. Lo del kernel (ASPM, watchdog, etc.) ya está aplicado y es la parte
fácil; lo que falta es dejar que la RTX 4060 se duerma.

En un arranque **antes de la sesión de usuario** la dGPU está ociosa (de hecho
se suspendió 13.5 s al arrancar y la despertó la sesión), así que el número
debería salir cerca de 12–16 W. Con la sesión arriba y los servicios de IA
cargados, la dGPU se queda encendida y el total queda en 22–26 W aunque no se
haga nada. `power-idle-bench.sh` da el número real en cada arranque.

Los tres caminos concretos, en orden de menor a mayor esfuerzo:

1. **No arrancar los servicios CUDA en batería** (`omnivoz-whisper`,
   `kokoro-tts`, `ollama`) y dejarlos a demanda. Libera la dGPU → −8 a −10 W.
   El rango es estimado: lo medido es el sistema *con* la dGPU despierta
   (~30 W de piso), y el foro mide 11 W de salto en el mismo caso.
2. **No usar Spotify/ohm en batería**: spotify se midió a >200 % de CPU en
   reposo y es cliente de la dGPU.
3. **`gpu-mode.sh`/`acpi_call _OFF`** al pasar a batería si se acepta que la
   dGPU queda apagada hasta reiniciar.

## 8. Fuentes

- `amdgpu.dcdebugmask=0x10` = `DC_DISABLE_PSR`:
  https://knowledgebase.frame.work/en_us/psr-display-flicker-workaround-for-linux-SJTKb7VMl
- PSR y consumo del display:
  https://docs.kernel.org/gpu/intel-display/psr.html
- ABM (`abmlevel`, niveles 0–4, ~1 W):
  https://community.frame.work/t/adaptive-backlight-management-abm/41055
  y https://docs.kernel.org/gpu/amdgpu/index.html
- Palancas de kernel en Ryzen mobile (EPP, ASPM, PCI PM, watchdog):
  https://github.com/jenicek001/ryzen-power-optimization
- Experiencia AMD en Linux (amd_pstate active, platform_profile):
  https://lpcvoid.com/blog/0017_linux_amd_power_tuning/index.html
- Legion Slim 5 gen 9 (8845HS + 4060): 14 W → 25 W por la dGPU encendida,
  arreglado con `acpi_call _OFF`; ITE 1.23 W; backlight 14.6 W:
  https://bbs.archlinux.org/viewtopic.php?id=300872
- Power management general: https://wiki.archlinux.org/title/Power_management
- Hybride graphics / acpi_call:
  https://wiki.archlinux.org/title/Hybrid_graphics#Using_acpi_call
- Nota local del workaround de PSR (freeze, 2 de 4 boots):
  `~/alicia/Inbox/2026-1009-fix-freeze-amdgpu-psr-dcdebugmask-resuelto.md`
