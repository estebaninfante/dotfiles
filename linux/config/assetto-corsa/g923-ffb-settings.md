# Assetto Corsa — Logitech G923 FFB Settings (Linux/Proton)

## Content Manager (CM) — Settings > Controls

### Wheel
- **Degrees of rotation:** 900
- **Gamma:** 1.00 (lineal 1:1)
- **Filter:** 0.00 (sin smoothing, máximo detalle)
- **Speed Sensitivity:** 0.00

### Force Feedback
- **Gain:** 100% (ajustar en oversteer, no en CM)
- **Minimum Force:** 0% (el G923 tiene buen torque base)
- **Kerb Effect:** 70%
- **Road Effect:** 25%
- **Slip Effect:** 0%
- **ABS Effect:** 25%
- **Enhanced Understeer Effect:** OFF
- **Half FFB Update Rate:** OFF

## Oversteer (GUI) — configuración recomendada

```bash
oversteer --device /dev/input/eventXX --range 900 --autocenter 0 --ff-gain 100
```

O usar la GUI: `oversteer`

### Settings en oversteer:
- **Rotation range:** 900°
- **Center spring:** OFF (desactivar autocenter en el volante)
- **FF Gain:** 100%
- **Combined pedals:** OFF (si usas pedalera separada)
- **Autocenter strength:** 0 (el juego controla el centro)

## Notas

- **new-lg4ff** (kernel module) provee FFB mejorado vs el driver in-tree.
  Habilitado vía `hardware.new-lg4ff.enable = true` en NixOS.
- **Oversteer** se instala vía NixOS (`services.udev.packages`).
  Necesario para configurar range, gain y monitoring de FFB.
- **TrueForce** no soportado en AC original (solo ACC/AC EVO).
- Si el volante no se detecta: verificar que esté en modo PC (no PS).
  El G923 PS/PC (046d:c266) necesita `new-lg4ff`.
  El G923 Xbox/PC (046d:c26d) necesita `usb_modeswitch`.
- Si FFB se siente débil: aumentar Minimum Force a 5-10% en CM.
- Si el volante vibra en rectas: reducir Gain o subir Dynamic Damping.
