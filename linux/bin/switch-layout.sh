#!/bin/bash
# switch-layout.sh <layout_index>
# 0 = dvk_prog, 1 = es, 2 = us
LAYOUT="${1:-2}"
hyprctl switchxkblayout usb-usb-keyboard "$LAYOUT" 2>/dev/null
hyprctl switchxkblayout keyd-virtual-keyboard "$LAYOUT" 2>/dev/null
