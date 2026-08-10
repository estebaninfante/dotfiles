# ── Teclado: layout custom dvk_prog (Dvorak Programador Español V5) ──
# Fuente de verdad: linux/xkb/dvk_prog (mismo archivo que Fedora enlaza
# a /usr/share/X11/xkb/symbols/).
#
# Cubre las TRES superficies donde Fedora tenia el layout:
#   1. X11/GDM (login): services.xserver.xkb.layout
#   2. Wayland/Hyprland: hyprland.lua ya pide kb_layout = "dvk_prog"
#      (el extraLayouts lo hace resolvible; aqui se activa para GDM)
#   3. TTY (consola): la consola usa keymaps de kbd, NO XKB → se genera
#      un keymap de consola exacto con ckbcomp desde el mismo symbols
#      file y se activa con console.keyMap.
{ config, lib, pkgs, ... }:

let
  dvkSymbols = ../../linux/xkb/dvk_prog;

  # xkeyboard-config parcheado con el layout custom (mismo mecanismo
  # que usa el modulo extra-layouts.nix de NixOS para XKB).
  xkb_patched = pkgs.xkeyboard-config_custom {
    layouts.dvk_prog = {
      description = "Dvorak Programmer";
      languages = [ "eng" ];
      compatFile = null;
      geometryFile = null;
      keycodesFile = null;
      typesFile = null;
      symbolsFile = dvkSymbols;
    };
  };

  # Keymap de consola generado desde el mismo symbols file (ckbcomp).
  # Sin esto el TTY queda en QWERTY (la consola no entiende XKB).
  dvkConsoleMap = pkgs.runCommand "dvk_prog-kmap" {
    nativeBuildInputs = [ pkgs.ckbcomp ];
  } ''
    mkdir -p $out
    XKB_DIR=${xkb_patched}/etc/X11/xkb
    ckbcomp -I$XKB_DIR -model pc105 -layout dvk_prog > $out/dvk_prog.map
    # sanity: debe contener ~108 keycodes
    test "$(grep -c keycode $out/dvk_prog.map)" -ge 100
  '';
in
{
  # TTY/consola → layout dvk_prog
  console.keyMap = "${dvkConsoleMap}/dvk_prog.map";

  # X11 + GDM (login) → layout dvk_prog
  services.xserver.xkb = {
    layout = "dvk_prog";
    extraLayouts.dvk_prog = {
      description = "Dvorak Programmer";
      languages = [ "eng" ];
      symbolsFile = dvkSymbols;
    };
  };
}
