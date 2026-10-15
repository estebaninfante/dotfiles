# Playbook: Discord (Developer Portal + instalacion de bot por OAuth2)

## Estado
- verified: 2026-10-13
- perfil: BRAVE REAL del usuario (browser-control). Discord logueado.
- sesiones: una sesion nombrada hay que crearla antes (`browser-control session new <n>`);
  usar una inexistente da `Session not found: <n>`.

## Rutas utiles
- Lista de apps: https://discord.com/developers/applications
- Bot de una app: https://discord.com/developers/applications/<appId>/bot
- Autorizacion OAuth2: https://discord.com/oauth2/authorize?client_id=<appId>&permissions=<bits>&scope=bot

## Caso Astradeux (app id 1549817464697786368)
- App y bot ya existian; bot id == app id.
- Intents ya activos: Presence Update, GUILD_MEMBERS, MESSAGE CONTENT.
- Bits de permisos usados: Ver canales 1024 + Enviar mensajes 2048 + Leer historial 65536 = 68608.
- Server destino: "Isa y yo".

## Token
- Solo se obtiene con "Restablecer token"; no hay boton copiar si el token no se esta viendo.
- El reset invalida el token anterior y exige contrasena/2FA de la cuenta: dialogo
  "Autenticacion de varios factores" (input name=mfaCode). PASO HUMANO.
- Captura sin que el secreto pase por el chat: el usuario pulsa "Copiar" y el agente lee el
  portapapeles con `wl-paste -n`. Validar con
  `^[A-Za-z0-9_-]{24,28}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,45}$`;
  guardar con `umask 077` + `chmod 600`; reportar solo len/last4/sha256 corto; limpiar con
  `wl-copy --clear`.

## Invitacion (flujo de la pagina de autorizacion)
- Paso 1: el combobox de servidor (`input[role="combobox"]`) ya viene con el server
  preseleccionado; el input es `hiddenVisually`, clickearlo falla porque el option intercepta
  el pointer (no hace falta abrirlo). Boton "Continuar".
- Paso 2: lista de permisos con los checkboxes ya tildados; botones "Atras" y "Autorizar".

## Gotchas (hCaptcha)
- Al pulsar "Autorizar" puede aparecer "Espera! Eres un ser humano?".
- hCaptcha monta dos iframes: uno con `#frame=checkbox` y otro con `#frame=challenge`.
- La automatizacion sube la puntuacion de riesgo: clickear el checkbox desde el agente NO pasa;
  hCaptcha responde con un puzzle interactivo ("Arrastra el tubo correcto para completar el
  recorrido", "Intentalo de nuevo"). Es handoff obligatorio al usuario; insistir desde el agente
  empeora el puntaje.
- El 2FA del Developer Portal (modal mfaCode) tambien es handoff.

## Verificacion sin navegador (con el token)
- `GET https://discord.com/api/v10/users/@me` con header `Authorization: Bot <token>` -> {id, username, bot}.
- `GET /users/@me/guilds` -> servidores donde esta el bot (vacio si aun no fue invitado).
- `GET /guilds/<guildId>/channels` -> canales (requiere el bot ya dentro).

## Seguridad
- NUNCA imprimir el token en chat/log. Guardar en archivo 600 fuera de repo
  (~/.config/opencode/secrets/), reportar solo len/last4/sha256 corto.
