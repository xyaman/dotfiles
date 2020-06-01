#! /bin/bash

picom -b &
nitrogen --restore &
redshift-gtk &
light-locker &

# Status bar (requires xorg-xsetroot)
~/.config/dwm/statusbar.sh &
