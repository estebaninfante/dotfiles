# MAIN-BRIDGE — hablar con el agente `main` desde Discord

Puente para que el dueno hable con su agente primario `main` (opencode, `deepseek-v4.1-flash`)
desde el celular/escritorio por Discord, sin exponer puertos y sin PWA. El agente vive en un
**canal dedicado** del servidor; ahi se le escribe y ahi responde.

## Arquitectura (fase 1: Discord)

```
 Discord (canal dedicado)  <--Gateway WS-->  rig-discord-bot  --rig send-->  silla tmux "main-seat" (agente main)
      ^                                          |                                  |
      |                                          +-- lee events.jsonl (kind=reply, actor=main)
      +------------------------------------------<--------------------------------- rig say "respuesta"
```

- **Entrada**: el bot recibe el `MESSAGE_CREATE` del canal dedicado, valida que el autor este en
  la allowlist de user ids y lo inyecta en la silla con `rig send main-seat "[dc] <texto>"`.
- **Salida**: `main` responde con `rig say "<respuesta>"` (emite `kind=reply`, `actor=main`).
  El bot sigue `~/.local/state/rig/events.jsonl` por offset (inodo+cursor) y reenvia cada reply
  al canal dedicado.
- **Sin puertos abiertos**: el bot abre una conexion **saliente** al Gateway de Discord
  (`wss://gateway.discord.gg`), como cualquier cliente. Nada escucha en la LAN ni en internet.
- **Sin dependencias**: el bot es Python3 stdlib (incluye su propio cliente WebSocket sobre
  `ssl`+`socket`); no usa `discord.js`, `discord.py` ni `websockets`.
- **Regla para `main`**: cuando el mensaje empieza con `[dc]`, su respuesta al usuario se manda
  con `rig say "<respuesta>"`.

`main` corre como **silla tmux** (`rig spawn main-seat --agent main`); el pane de herdr le hace
`tmux attach` para seguir viendolo en el escritorio. `rig seats` debe listar `main-seat`.

## Setup

1. **Crear la aplicacion y el bot** (portal de Discord: https://discord.com/developers/applications):

   - Si ya tenes una aplicacion creada por vos para esto, **reusala** (entra a ella y salta al
     paso 2). Si no, `New Application` -> ponele nombre (p.ej. `Astradeux`).
   - En el menu lateral: **Bot**. Si el bot ya existe, listo; si no, se crea con la aplicacion.
   - En **Bot -> Privileged Gateway Intents**, activa **MESSAGE CONTENT INTENT** (sin esto el bot
     recibe los mensajes con el contenido vacio). Guarda.
   - En **Bot -> Token**, `Reset Token` (el viejo Astradeux lo borraste del canal; el token no se
     recupera, hay que regenerarlo) y copia el token nuevo.

2. **Invitar el bot al servidor** con permisos de leer y escribir mensajes. En el portal, arma la
   URL de invitacion (reemplaza `TU_APP_ID` con el *Application ID* de la pestana General
   Information):

   ```
   https://discord.com/oauth2/authorize?client_id=TU_APP_ID&scope=bot&permissions=76800
   ```

   - `76800` = **View Channel** (1024) + **Send Messages** (2048) + **Read Message History**
     (65536). Abri la URL, elegi tu servidor, autoriza.
   - En el servidor, asegurate de que el bot tenga acceso al **canal dedicado** y permiso de
     enviar mensajes ahi (si el canal es privado, agregalo con `Edit Channel -> Permissions`).

3. **Datos y IDs** (activa **User Settings -> Advanced -> Developer Mode** en tu cliente Discord):

   - **Tu user id**: click derecho sobre tu usuario -> `Copy User ID`.
   - **Channel id**: click derecho sobre el canal dedicado -> `Copy Channel ID`.

4. **Armar el entorno** (fuera del repo, permisos 600):

   ```bash
   mkdir -p ~/.config/rig
   cat > ~/.config/rig/discord.env <<'EOF'
   DISCORD_BOT_TOKEN=TU_TOKEN_ACA
   DISCORD_ALLOWED_USER_IDS=TU_USER_ID
   DISCORD_CHANNEL_ID=TU_CHANNEL_ID
   RIG_SEAT=main-seat
   EOF
   chmod 600 ~/.config/rig/discord.env
   ```

5. **Levantar la silla de `main`** (una sola vez por sesion de escritorio):

   ```bash
   rig spawn main-seat --agent main
   rig spawn main-seat --agent main --herdr --focus   # variante con pane herdr
   ```

6. **Instalar y arrancar el servicio**:

   ```bash
   ~/dotfiles/scripts/link-dotfiles.sh
   mkdir -p ~/.config/systemd/user
   ln -sf ~/dotfiles/linux/system/systemd-user/rig-discord-bot.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now rig-discord-bot.service
   ```

Sin `~/.config/rig/discord.env` el servicio queda en estado `condition failed` (no arranca, no
ensucia el journal): es intencional.

## Uso

- Escribis en el canal dedicado -> main responde en el canal.
- El bot ignora sus propios mensajes, mensajes de otros bots, de otros canales y de user ids
  fuera de la allowlist.
- Voz: nota de voz -> STT local -> texto (ver abajo).

## Variables de entorno (discord.env)

| Variable | Default | Uso |
|----------|---------|-----|
| `DISCORD_BOT_TOKEN` | — | requerido; token del bot (portal Discord) |
| `DISCORD_ALLOWED_USER_IDS` | — | requerido; user ids separados por coma (solo el dueno) |
| `DISCORD_CHANNEL_ID` | — | requerido; canal dedicado donde vive el agente |
| `RIG_SEAT` | `main-seat` | silla destino |
| `RIG_EVENTS_FILE` | `~/.local/state/rig/events.jsonl` | store de eventos |
| `RIG_BIN` | `rig` en PATH o `~/.local/bin/rig` | binario rig |
| `RIG_DISCORD_GATEWAY` | `wss://gateway.discord.gg/?v=10&encoding=json` | Gateway (no cambiar salvo test) |
| `RIG_DISCORD_API` | `https://discord.com/api/v10` | REST base |
| `RIG_DISCORD_PREFIX` | `[dc]` | prefijo del mensaje inyectado |
| `RIG_DISCORD_STATE_DIR` | `~/.local/state/rig/discord` | cursor de eventos + sesion de gateway |
| `RIG_STT_CMD` | vacio | comando de transcripcion (fase 2), recibe la ruta del audio |

## Verificacion

```bash
verify run bridge          # py_compile + selftest + token-leak + unit + symlink (discord y telegram)
verify auto ~/dotfiles/linux/bin/rig-discord-bot
systemctl --user status rig-discord-bot.service
journalctl --user -u rig-discord-bot -n 30 --no-pager
```

## Seguridad

- Allowlist estricta por **user id**: el mensaje de un user no listado se rechaza y se registra
  (`discord-reject`). El canal dedicado y los bots se ignoran.
- Token y allowlist en `~/.config/rig/discord.env` (600, FUERA del repo); el script se niega a
  arrancar sin ellos y nunca los loguea.
- Solo trafico **saliente** (Gateway WebSocket + REST); nada escucha en la LAN/internet.
- Cada mensaje entrante/saliente queda como evento (`discord-in`, `discord-out`, `discord-voice`,
  `discord-error`, `discord-reject`), actor `discord-bridge`.

## Alternativa documentada — Telegram (no implementada como transporte)

Existe `linux/bin/rig-telegram-bot` + `rig-telegram-bot.service` con el mismo diseno (Bot API
oficial, long-polling `getUpdates`, allowlist por `chat_id`, prefijo `[tg]`, env en
`~/.config/rig/telegram.env`). Queda como **alternativa** lista para usar si algun dia se quiere
cambiar de transporte: misma inyeccion (`rig send`), misma salida (`rig say` -> events.jsonl).

**No correr ambos a la vez**: los dos reenvian los mismos eventos `kind=reply` al chat/canal, y
el default de `rig say --to` es `telegram` (el bot de Discord acepta `to` en
`discord|telegram|hub|all|vacio`). Dejar habilitado **solo uno**.

## Fase 2 — WhatsApp (no implementado; opciones y riesgo)

| Opcion | Tipo | Costo | Riesgo | Notas |
|--------|------|-------|--------|-------|
| WhatsApp Cloud API | oficial (Meta) | gratis hasta el tramo de conversaciones de servicio; luego por conversacion | requiere numero dedicado + verificacion de negocio en Meta; aprobacion | la via estable; mismo modelo de webhook |
| Baileys / whatsapp-web.js | no oficial (WhatsApp Web) | gratis | riesgo real de **bloqueo del numero**; hay que mantener la sesion viva | nunca con el numero personal |

Recomendacion: si se pide WhatsApp, usar **Cloud API** con un numero dedicado. La no-oficial solo
si se acepta el riesgo de bloqueo.

## Fase 2 — Voz

- **Nota de voz entrante** (mensaje de voz de Discord = attachment con `content_type audio/*`):
  el bot descarga el audio y lo pasa a `RIG_STT_CMD` (STT local). En esta maquina NO hay STT
  listo (falta binario `whisper` o `faster-whisper`); hay modelos GGUF de whisper cacheados por
  `handy` y un server `faster-whisper` de `omnivoz` sin montar. Hasta montarlo, la voz responde
  "escribi texto".
- **Respuesta en audio**: TTS local ya existe (comando `voice` + chatterbox); se puede enviar la
  respuesta como nota de voz subiendo el audio al canal.
- **Llamada telefonica real (SIP)**: **no viable** sin un proveedor externo (Twilio, etc.: costo
  por minuto + numero). No se promete. La via realista de "hablar" es nota de voz + TTS. Discord
  si tiene canales de voz nativos, pero el bot (via Gateway de texto) no participa de ellos sin
  un cliente de voz (Voz de Discord usa WebRTC/opus, fuera del alcance de este puente).

## Hermes (pregunta abierta)

En la maquina hay un harness de agente Python **`hermes`** instalado (`~/.local/bin/hermes`,
`~/dotfiles/linux/bin/hermes`, `hermes-acp`, dashboard WebUI en `127.0.0.1:9119`), con plugin
`herdr-agent-state` y skills propias. Es independiente de opencode. Hoy `main` corre bajo
**opencode**; migrarlo a hermes es una decision aparte (no la toma este ticket). Este puente solo
depende de que `main` viva en una silla tmux accesible por `rig send` / `rig say`, independiente
del harness.
