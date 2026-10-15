# Omarchy por voz — chuleta del cerebro

Para cualquier cosa del sistema usá el CLI `omarchy` (interfaz estable).
El índice completo y exacto de los 371 comandos está en `omarchy-commands.txt`.
Si algo no figura acá: `omarchy commands | grep -i PALABRA` o `omarchy <grupo> --help`.

## Consultar (seguro, no cambia nada)
- tema actual: `omarchy theme current`
- temas disponibles: `omarchy theme list`
- fuente actual: `omarchy font current`
- estado de red: `omarchy network status`
- batería: `omarchy battery status`
- CPU/RAM: `omarchy system stats`
- versión: `omarchy version`
- comandos: `omarchy commands`

## Temas y aspecto
- cambiar tema: `omarchy theme set <nombre>`
- siguiente fondo: `omarchy theme bg next`
- fondo puntual: `omarchy theme bg set <ruta>`
- tamaño de texto: `omarchy display text size <tamaño>` / `omarchy display text size reset`
- fuente monoespaciada: `omarchy font set <nombre>`
- barra: `omarchy toggle bar`

## Pantalla, luz y energía
- luz nocturna: `omarchy toggle nightlight`
- brillo: `omarchy brightness display +10%` / `omarchy brightness display -10%`
- brillo del teclado: `omarchy brightness keyboard up|down|off`
- bloqueo: `omarchy system lock`
- suspender: `systemctl suspend`
- ahorro de energía: `omarchy powerprofiles <perfil>` (mirar args con --help)

## Audio y Bluetooth
- silenciar micrófono: `omarchy audio input mute`
- cambiar salida de audio: `omarchy audio output switch`
- volumen: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%+` (o `10%-`, `toggle` para mute)
- bluetooth on/off: `omarchy bluetooth power toggle`
- conectar dispositivo bluetooth: `omarchy bluetooth device connect <mac>`

## Capturas y grabación
- captura de pantalla: `omarchy screenshot`
- captura por región: `omarchy capture screenshot region`
- grabar pantalla: `omarchy screenrecord`
- detener grabación: `omarchy capture screenrecording --stop-recording`
- texto de la pantalla (OCR): `omarchy capture text`

## Recordatorios y avisos
- recordatorio: `omarchy reminder <minutos> "texto"`
- ver recordatorios: `omarchy reminder show`
- borrar recordatorios: `omarchy reminder clear`
- no molestar: `omarchy toggle notification silencing`

## Apps
- navegador: `omarchy launch browser [url]`
- terminal: `omarchy launch terminal`
- terminal con un programa adentro: `omarchy launch terminal <comando>` (ej. `omarchy launch terminal pi`)
- agente de código por defecto: `omarchy agent`
- abrir o enfocar app: `omarchy launch or focus <app>`
- enfocar ventana Hyprland: `omarchy hyprland focus app <nombre>`

## Sistema (PELIGROSO — preguntar y esperar "sí")
- apagar: `omarchy shutdown`
- reiniciar: `omarchy reboot`
- cerrar sesión: `omarchy logout`
- cerrar todas las ventanas: `omarchy hyprland window close all`
- instalar paquetes: `omarchy pkg add <packages>`
- desinstalar: `omarchy pkg drop <packages>`
- actualizar todo: `omarchy update`

## Regla de seguridad
Nunca ejecutes sin un "sí" explícito del usuario: apagar, reiniciar, cerrar
sesión, cerrar todas las ventanas, desinstalar, borrar datos, cambiar
contraseñas de disco. Para el resto, preferí comandos reversibles.
