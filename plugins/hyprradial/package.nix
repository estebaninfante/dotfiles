{ lib, mkHyprlandPlugin, cmake }:

mkHyprlandPlugin {
  pluginName = "hyprradial";
  version = "0.0.1";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ cmake ];
  buildInputs = [ ];
  dontStrip = true;
  meta = {
    description = "hyprradial spike: log grid delta de cambio de workspace";
    homepage = "https://github.com/eztvn/dotfiles";
    license = lib.licenses.mit;
  };
}