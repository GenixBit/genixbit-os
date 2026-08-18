#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS Live Server Desktop & noVNC Startup Manager
set -e

echo '>>> Stopping existing VNC and XFCE processes...'
pkill -f 'websockify.*6080' || true
pkill -f 'x11vnc.*5900' || true
pkill -f 'xfce4-session' || true
pkill -f 'xfdesktop' || true
pkill -f 'xfwm4' || true
pkill -f 'plank' || true
pkill -f 'Xvfb.*:99' || true
sleep 2

export DISPLAY=:99

echo '>>> Configuring clean macOS-style XFCE desktop layout without overlaps...'
mkdir -p /home/ubuntu/.config/xfce4/xfconf/xfce-perchannel-xml/
mkdir -p /home/ubuntu/.config/plank/dock1/launchers/
mkdir -p /home/ubuntu/.config/autostart/

# Ensure panel 2 (bottom panel) is removed so only Plank is at bottom
cat << 'XML' > /home/ubuntu/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
  </property>
  <property name="panel-1" type="empty">
    <property name="position" type="string" value="p=6;x=0;y=0"/>
    <property name="length" type="uint" value="100"/>
    <property name="position-locked" type="bool" value="true"/>
    <property name="size" type="uint" value="30"/>
    <property name="plugin-ids" type="array">
      <value type="int" value="1"/>
      <value type="int" value="2"/>
      <value type="int" value="3"/>
      <value type="int" value="4"/>
      <value type="int" value="5"/>
      <value type="int" value="6"/>
    </property>
    <property name="background-style" type="uint" value="0"/>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray"/>
    <property name="plugin-5" type="string" value="statusnotifier"/>
    <property name="plugin-6" type="string" value="clock">
      <property name="digital-format" type="string" value="%a %b %d  %H:%M"/>
    </property>
  </property>
</channel>
XML

# Configure Plank Dock centered at bottom
cat << 'PLANK' > /home/ubuntu/.config/plank/dock1/settings
[DockItem]
ItemType=Dock
Theme=Transparent
Position=Bottom
Alignment=Center
Offset=0
IconSize=48
HideMode=0
UnhideDelay=0
HideDelay=0
LockItems=false
AutoPin=true
ShowDockItem=false
ZoomEnabled=true
ZoomPercent=130
PLANK

# Populate Plank Dock launchers
cat << 'DK' > /home/ubuntu/.config/plank/dock1/launchers/terminal.dockitem
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/xfce4-terminal.desktop
DK

cat << 'DK' > /home/ubuntu/.config/plank/dock1/launchers/studio.dockitem
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/genixbit-agent-studio.desktop
DK

cat << 'DK' > /home/ubuntu/.config/plank/dock1/launchers/store.dockitem
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/genixbit-store.desktop
DK

cat << 'DK' > /home/ubuntu/.config/plank/dock1/launchers/files.dockitem
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/thunar.desktop
DK

# Autostart Plank
cat << 'AS' > /home/ubuntu/.config/autostart/plank.desktop
[Desktop Entry]
Type=Application
Exec=plank
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Plank Dock
AS

echo '>>> Starting Xvfb at 1920x1080x24 on display :99...'
nohup Xvfb :99 -screen 0 1920x1080x24 > /home/ubuntu/xvfb.log 2>&1 &
sleep 2

echo '>>> Starting XFCE Desktop session...'
nohup dbus-launch --exit-with-session xfce4-session > /home/ubuntu/xfce4.log 2>&1 &
sleep 3

if [ -f /home/ubuntu/genixbit-os-wallpaper.png ]; then
  DISPLAY=:99 feh --bg-fill /home/ubuntu/genixbit-os-wallpaper.png || true
fi

echo '>>> Starting Plank Dock...'
nohup plank > /home/ubuntu/plank.log 2>&1 &
sleep 1

echo '>>> Starting x11vnc on 127.0.0.1:5900...'
nohup x11vnc -display :99 -rfbport 5900 -forever -shared -nopw -noxrecord -noxfixes -noxdamage -repeat > /home/ubuntu/x11vnc.log 2>&1 &
sleep 2

echo '>>> Starting websockify noVNC bridge on 0.0.0.0:6080...'
nohup websockify --web /usr/share/novnc 6080 127.0.0.1:5900 > /home/ubuntu/websockify.log 2>&1 &
sleep 2

echo '>>> Desktop VNC Stack is fully active!'
ps aux | grep -E 'Xvfb|xfce4|x11vnc|websockify|plank' | grep -v grep
