# CRASH-AUTODIAGNOSE — el crash se investiga solo y queda como ticket del rig

Cuando un proceso crashea en esta máquina, la investigación **arranca sola** y
queda registrada como un ticket del rig. El dueño no tiene que clickear nada;
después entra al tablero y ve el diagnóstico con su evidencia.

## El problema

Omarchy trae un watcher (`omarchy-crash-watch`) que, al detectar un core dump,
manda una notificación *"Process crashed: X — Click to diagnose with AI"*. El
diagnóstico solo corría si el usuario hacía click, y no quedaba rastro en ningún
lado: ni ticket, ni traza, ni evidencia. Si el aviso se perdía, el crash se
perdía con él.

## Lo que hace ahora

```
systemd-coredump (journal MESSAGE_ID)
        │
        ▼
omarchy-crash-watch.service  ──drop-in──▶  omarchy-crash-autodiagnose
        │                                        │  (dedupe por programa, solo este usuario,
        │                                        │   respeta el toggle crash-capture-off)
        │                                        ▼
        │                              systemd-run --user (unit transitorio, sobrevive al watcher)
        │                                        │
        │                                        ▼
        │                              omarchy-crash-diagnose <pid> <comm> <exe> <signal>
        │                                        │
        │                          ┌─────────────┴──────────────┐
        │                          ▼                            ▼
        │                 rig ticket add (infra)       opencode run headless
        │                 ticket CRASH-<pid>-<epoch>   SOLO modelos free, con fallback
        │                          │                            │
        │                          └─────────────┬──────────────┘
        │                                        ▼
        │                              rig ticket set --status done|blocked
        │                              + evidencia + sesión + evento (crash-ok/crash-fail)
        │                              + aviso de escritorio
        ▼
  rig board / rig queue / rig events / rig ticket show
```

- **Sin click.** El watcher ya no ofrece diagnóstico: lo lanza.
- **Con rastro.** Cada crash abre un ticket `CRASH-<pid>-<epoch>` en el proyecto
  `infra`, con el nombre del proceso y la señal en el título. `rig board` y
  `rig queue` lo muestran; `rig ticket show` trae la ficha con la sesión de
  opencode y sus métricas.
- **Solo modelos free.** El diagnóstico prueba, en orden, modelos free de
  OpenCode Zen (`longcat-2.5-preview-free`, `beam-free`, `nemotron-3-ultra-free`,
  `nemotron-3.5-lightning-free`, `space-bunny-free`, `mimo-v2.6-flash-free`).
  Si uno responde 429 / `FreeUsageLimitError`, pasa al siguiente. Ningún modelo
  pago entra en la lista.
- **El método en un solo lugar.** El prompt manda a la skill `diagnose-crash`
  (`/usr/share/omarchy/default/agents/skills/diagnose-crash/SKILL.md`), así que
  el cómo se investiga se edita ahí y no en el script.

## Por qué drop-in y no editar Omarchy

`/usr/share/omarchy` es del paquete: se pisa en cada `omarchy update`. El cambio
va como **drop-in de systemd** (`linux/system/systemd-user/omarchy-crash-watch.service.d/override.conf`)
que solo reemplaza `ExecStart` y conserva el resto del unit (el toggle, `PartOf`,
`Restart`). `scripts/install-user-units.sh` enlaza los drop-ins versionados,
igual que los units.

## Criterios de aceptación (verificados por `scripts/verify/crash.sh`)

1. El unit `omarchy-crash-watch` arranca `omarchy-crash-autodiagnose` (drop-in).
2. El watcher escucha el `MESSAGE_ID` de systemd-coredump, deduplica por
   programa y filtra por usuario, y lanza el diagnóstico desprendido
   (`systemd-run` o `setsid`).
3. `omarchy-crash-diagnose` abre un ticket del rig, usa solo modelos `-free` y
   cierra el ticket (done o blocked) con evidencia.
4. `install-user-units.sh` enlaza drop-ins `*.d/`.

## Uso

- Ver el tablero: `rig board` · la cola: `rig queue` · el feed: `rig events`.
- Ficha de un crash: `rig ticket show CRASH-<pid>-<epoch>`.
- Log completo: `~/.local/state/crash-autodiagnose/diagnose-<proc>-<pid>.log`.
- Apagar/prender el watcher (y el autodiagnóstico): `omarchy toggle crash-capture`
  o el menú de Omarchy.
