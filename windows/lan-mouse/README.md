# LAN Mouse en Windows (laptop y desktop)

Deja el KVM compartido funcionando en los **4 escenarios**:

| Maquina | Sistema | Config | IP KVM |
|---|---|---|---|
| laptop  | Omarchy | `linux/config/lan-mouse/config.laptop.toml`  | `192.168.1.240` |
| laptop  | Windows | `windows/lan-mouse/config.laptop.toml`       | `192.168.1.240` |
| desktop | Omarchy | `linux/config/lan-mouse/config.desktop.toml` | `192.168.1.241` |
| desktop | Windows | `windows/lan-mouse/config.desktop.toml`      | `192.168.1.241` |

En todos los casos el peer es el **otro** equipo y la `position` es consistente:
la laptop ve al desktop arriba (`top`) y el desktop ve a la laptop abajo
(`bottom`). En Windows la config vive en:

```
%LOCALAPPDATA%\lan-mouse\config.toml
%LOCALAPPDATA%\lan-mouse\lan-mouse.pem
```

`lan-mouse.pem` es la **identidad compartida** (mismo certificado que las
instalaciones Linux; su fingerprint ya esta autorizada en el otro equipo), asi
que Windows no necesita pedir autorizacion de nuevo.

## Instalacion

1. Instala LAN Mouse en Windows desde
   <https://github.com/feschber/lan-mouse/releases> (zip con
   `lan-mouse.exe`; descomprimilo, p.ej. en `%LOCALAPPDATA%\Programs\lan-mouse`).
2. Copia esta carpeta (`setup-lan-mouse.ps1`, `config.*.toml`,
   `lan-mouse.pem`) a la PC Windows.
3. En PowerShell, dentro de la carpeta:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-lan-mouse.ps1
   ```

   Detecta si es laptop o desktop (por bateria), instala la config y deja
   LAN Mouse arrancando al iniciar sesion.
4. **Recomendado** (una sola vez, PowerShell como Administrador): fija la IP
   KVM en la placa de cable para que el otro equipo la alcance por Ethernet.

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-lan-mouse.ps1 -SetStaticIP
   ```

   Sin esto, Windows usa la IP que le asigne el router y el peer (que apunta a
   `.240`/`.241`) no lo va a encontrar por IP fija.

## Notas

- LAN Mouse conecta el peer **al pasar el mouse al borde** (o al arrancar si el
  peer ya responde); no hace falta hacer nada mas.
- El firewall de Windows debe permitir **TCP/UDP 4242** entrante en la red
  privada. La primera vez Windows pregunta; elegi "Redes privadas".
- Para forzar la maquina: `-Machine laptop` o `-Machine desktop`.
- Los `config.*.toml` de esta carpeta son equivalentes a los de
  `linux/config/lan-mouse/`; si cambia una IP o posicion, actualiza ambos.
