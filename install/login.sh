sudo pacman -S uwsm libnewt

cat <<EOF | sudo tee /etc/systemd/system/auto-login.service
[Unit]
Description=Auto-Login
Conflicts=getty@tty1.service
After=systemd-user-sessions.service getty@tty1.service plymouth-quit.service systemd-logind.service
PartOf=graphical.target

[Service]
Type=simple
ExecStart=uwsm start -- hyprland.desktop
Restart=always
RestartSec=2
User=$USER
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal+console
PAMName=login

[Install]
WantedBy=graphical.target
EOF

# Make plymouth remain until graphical.target
sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d
sudo tee /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf <<'EOF'
[Unit]
After=multi-user.target
EOF

# Prevent plymouth-quit-wait.service
systemctl mask plymouth-quit-wait.service

sudo systemctl daemon-reload
sudo systemctl enable auto-login.service

# Disable getty@tty1 to prevent conflicts
sudo systemctl disable getty@tty1.service
