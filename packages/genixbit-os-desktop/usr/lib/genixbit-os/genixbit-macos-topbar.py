#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Pixel-Perfect macOS Top Menu Bar
# Features: [G] System Menu, Global App Menus (App, File, Edit, View, AI, Window, Help),
#           and macOS Status Icons (Cloud, AI, Guard, Night Mode, Battery, Wi-Fi, Spotlight, Control Center, Clock)

import datetime
import os
import subprocess
import sys

def launch_topbar():
    try:
        import gi
        gi.require_version('Gtk', '3.0')
        gi.require_version('Gdk', '3.0')
        from gi.repository import Gtk, Gdk, GLib
    except Exception as e:
        print(f"[TopBar] GTK3 not available: {e}", file=sys.stderr)
        return False

    class MacOSTopBar(Gtk.Window):
        def __init__(self):
            super().__init__(type=Gtk.WindowType.TOPLEVEL)
            self.set_type_hint(Gdk.WindowTypeHint.DOCK)
            self.set_decorated(False)
            self.set_app_paintable(True)
            self.set_keep_above(True)

            screen = Gdk.Screen.get_default()
            width = screen.get_width() if screen else 1920
            self.set_default_size(width, 28)
            self.move(0, 0)

            # Modern macOS Translucent Top Bar CSS
            css = b"""
            window {
                background-color: rgba(12, 18, 34, 0.92);
                color: #f8fafc;
                font-family: -apple-system, BlinkMacSystemFont, "Ubuntu", "Inter", sans-serif;
                font-size: 13px;
                border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            }
            .menu-btn {
                background: transparent;
                color: #f8fafc;
                border: none;
                border-radius: 4px;
                padding: 2px 7px;
                margin: 2px 1px;
                font-weight: 500;
                box-shadow: none;
            }
            .menu-btn:hover {
                background-color: rgba(255, 255, 255, 0.15);
                color: #ffffff;
            }
            .app-title-btn {
                font-weight: 800;
                color: #ffffff;
            }
            .icon-btn {
                background: transparent;
                color: #f8fafc;
                border: none;
                border-radius: 4px;
                padding: 2px 6px;
                margin: 2px 1px;
                font-size: 14px;
                box-shadow: none;
            }
            .icon-btn:hover {
                background-color: rgba(255, 255, 255, 0.15);
                color: #38bdf8;
            }
            .clock-label {
                font-weight: 600;
                color: #ffffff;
                padding: 2px 10px 2px 6px;
                font-size: 13px;
            }
            .logo-btn {
                background: #2563eb;
                color: #ffffff;
                font-weight: 900;
                border-radius: 6px;
                padding: 1px 7px;
                margin: 3px 6px 3px 4px;
                font-size: 11px;
            }
            .logo-btn:hover {
                background: #38bdf8;
            }
            """
            provider = Gtk.CssProvider()
            provider.load_from_data(css)
            Gtk.StyleContext.add_provider_for_screen(
                screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

            # Main Horizontal Bar
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
            self.add(hbox)

            # ==========================================
            # LEFT SIDE: System & Global App Menus
            # ==========================================
            # 1. [G] Logo Menu
            logo_btn = Gtk.Button(label="G")
            logo_btn.get_style_context().add_class("logo-btn")
            logo_btn.connect("clicked", self.on_logo_clicked)
            hbox.pack_start(logo_btn, False, False, 0)

            # 2. Bold Active App Name ("GenixBit AI" / "Xnapper")
            app_btn = Gtk.Button(label="GenixBit AI")
            app_btn.get_style_context().add_class("menu-btn")
            app_btn.get_style_context().add_class("app-title-btn")
            app_btn.connect("clicked", self.on_app_menu_clicked)
            hbox.pack_start(app_btn, False, False, 0)

            # 3. Standard App Menus (App, File, Edit, View, AI, Window, Help)
            menus = [
                ("App", self.create_app_menu),
                ("File", self.create_file_menu),
                ("Edit", self.create_edit_menu),
                ("View", self.create_view_menu),
                ("AI", self.create_ai_menu),
                ("Window", self.create_window_menu),
                ("Help", self.create_help_menu),
            ]
            for label, menu_func in menus:
                btn = Gtk.Button(label=label)
                btn.get_style_context().add_class("menu-btn")
                btn.connect("clicked", lambda b, mf=menu_func: mf().popup_at_widget(b, Gdk.Gravity.SOUTH_WEST, Gdk.Gravity.NORTH_WEST, None))
                hbox.pack_start(btn, False, False, 0)

            # Spacer
            spacer = Gtk.Box()
            hbox.pack_start(spacer, True, True, 0)

            # ==========================================
            # RIGHT SIDE: macOS Status & Control Icons
            # ==========================================
            icons = [
                ("☁️", "GenixBit Cloud Sync: Connected", self.on_cloud_clicked),
                ("✨", "Antigravity AI Assistant", self.on_ai_clicked),
                ("🛡️", "Security Guard: Active", self.on_guard_clicked),
                ("🌙", "Toggle Dark / Light Style", self.on_darkmode_clicked),
                ("🔋", "Battery: 100% (Plugged In)", None),
                ("📶", "Wi-Fi: Connected (High Speed)", None),
                ("🔍", "Spotlight Search (Super+Space)", self.on_spotlight_clicked),
                ("🎛️", "Control Center", self.on_control_clicked),
            ]
            for glyph, tip, cb in icons:
                btn = Gtk.Button(label=glyph)
                btn.get_style_context().add_class("icon-btn")
                btn.set_tooltip_text(tip)
                if cb:
                    btn.connect("clicked", cb)
                hbox.pack_start(btn, False, False, 0)

            # Date & Clock
            self.clock_label = Gtk.Label()
            self.clock_label.get_style_context().add_class("clock-label")
            self.update_clock()
            hbox.pack_start(self.clock_label, False, False, 0)

            # Timer to update clock every second
            GLib.timeout_add_seconds(1, self.update_clock)

        def update_clock(self):
            now = datetime.datetime.now()
            # Format: "Wed 19 Aug  10:25 AM"
            formatted = now.strftime("%a %d %b  %I:%M %p")
            self.clock_label.set_text(formatted)
            return True

        # ==========================================
        # Menus
        # ==========================================
        def on_logo_clicked(self, widget):
            menu = Gtk.Menu()
            items = [
                ("About GenixBit OS", lambda: os.system("genixbit-control-center &")),
                ("System Settings...", lambda: os.system("genixbit-control-center &")),
                ("App Store...", lambda: os.system("genixbit-store &")),
                (None, None),
                ("Force Quit Applications...", lambda: os.system("xkill &")),
                (None, None),
                ("Sleep", lambda: os.system("systemctl suspend &")),
                ("Restart...", lambda: os.system("systemctl reboot &")),
                ("Shut Down...", lambda: os.system("systemctl poweroff &")),
                (None, None),
                ("Lock Screen", lambda: os.system("xflock4 || loginctl lock-session &"))
            ]
            for label, act in items:
                if label is None:
                    menu.append(Gtk.SeparatorMenuItem())
                else:
                    mi = Gtk.MenuItem(label=label)
                    if act: mi.connect("activate", lambda w, a=act: a())
                    menu.append(mi)
            menu.show_all()
            menu.popup_at_widget(widget, Gdk.Gravity.SOUTH_WEST, Gdk.Gravity.NORTH_WEST, None)

        def on_app_menu_clicked(self, widget):
            menu = self.create_app_menu()
            menu.popup_at_widget(widget, Gdk.Gravity.SOUTH_WEST, Gdk.Gravity.NORTH_WEST, None)

        def create_app_menu(self):
            menu = Gtk.Menu()
            for label, act in [
                ("About GenixBit AI", lambda: os.system("genixbit-ai-center-gui &")),
                ("Settings / Preferences...", lambda: os.system("genixbit-control-center &")),
                (None, None),
                ("Hide Active Window", lambda: os.system("xdotool getactivewindow windowminimize &")),
                ("Hide Others", None),
                ("Show All", None),
                (None, None),
                ("Quit GenixBit AI", lambda: os.system("pkill -f genixbit-ai-center-gui &"))
            ]:
                if label is None: menu.append(Gtk.SeparatorMenuItem())
                else:
                    mi = Gtk.MenuItem(label=label)
                    if act: mi.connect("activate", lambda w, a=act: a())
                    menu.append(mi)
            menu.show_all()
            return menu

        def create_file_menu(self):
            menu = Gtk.Menu()
            for label, act in [
                ("New Window", lambda: os.system("xfce4-terminal &")),
                ("New Prompt...", lambda: os.system("genixbit-ai-center-gui &")),
                ("Open File...", lambda: os.system("thunar &")),
                (None, None),
                ("Close Window", lambda: os.system("xdotool getactivewindow windowclose &"))
            ]:
                if label is None: menu.append(Gtk.SeparatorMenuItem())
                else:
                    mi = Gtk.MenuItem(label=label)
                    if act: mi.connect("activate", lambda w, a=act: a())
                    menu.append(mi)
            menu.show_all()
            return menu

        def create_edit_menu(self):
            menu = Gtk.Menu()
            for label in ["Undo", "Redo", "---", "Cut", "Copy", "Paste", "Select All"]:
                if label == "---": menu.append(Gtk.SeparatorMenuItem())
                else: menu.append(Gtk.MenuItem(label=label))
            menu.show_all()
            return menu

        def create_view_menu(self):
            menu = Gtk.Menu()
            for label, act in [
                ("Zoom In", None),
                ("Zoom Out", None),
                ("Actual Size", None),
                (None, None),
                ("Enter Full Screen", lambda: os.system("xdotool key F11 &"))
            ]:
                if label is None: menu.append(Gtk.SeparatorMenuItem())
                else:
                    mi = Gtk.MenuItem(label=label)
                    if act: mi.connect("activate", lambda w, a=act: a())
                    menu.append(mi)
            menu.show_all()
            return menu

        def create_ai_menu(self):
            menu = Gtk.Menu()
            for label, act in [
                ("Model Manager...", lambda: os.system("genixbit-ai-center-gui &")),
                ("Antigravity SDK Bridge...", lambda: os.system("genixbit-agent &")),
                ("Multi-Agent Swarm...", lambda: os.system("genixbit-swarm &")),
                ("Indic Bharat AI...", lambda: os.system("genixbit-bharat &")),
                (None, None),
                ("Pull Gemma 3 2B Model", lambda: os.system("genixbit-ai-center pull gemma-3-2b-it &")),
                ("Check GPU Acceleration", lambda: os.system("genixbit-gpu-diag &"))
            ]:
                if label is None: menu.append(Gtk.SeparatorMenuItem())
                else:
                    mi = Gtk.MenuItem(label=label)
                    if act: mi.connect("activate", lambda w, a=act: a())
                    menu.append(mi)
            menu.show_all()
            return menu

        def create_window_menu(self):
            menu = Gtk.Menu()
            for label, act in [
                ("Minimize", lambda: os.system("xdotool getactivewindow windowminimize &")),
                ("Zoom", lambda: os.system("xdotool key alt+F10 &")),
                (None, None),
                ("Tile Window Left", lambda: os.system("xdotool key super+Left &")),
                ("Tile Window Right", lambda: os.system("xdotool key super+Right &")),
                (None, None),
                ("Bring All to Front", None)
            ]:
                if label is None: menu.append(Gtk.SeparatorMenuItem())
                else:
                    mi = Gtk.MenuItem(label=label)
                    if act: mi.connect("activate", lambda w, a=act: a())
                    menu.append(mi)
            menu.show_all()
            return menu

        def create_help_menu(self):
            menu = Gtk.Menu()
            for label, act in [
                ("GenixBit OS Documentation", lambda: os.system("xdg-open https://docs.os.genixbit.com &")),
                ("Release Notes (1.0.0 LTS)", lambda: os.system("xdg-open https://github.com/GenixBit/genixbit-os/releases &")),
                ("GitHub Repository", lambda: os.system("xdg-open https://github.com/GenixBit/genixbit-os &"))
            ]:
                mi = Gtk.MenuItem(label=label)
                if act: mi.connect("activate", lambda w, a=act: a())
                menu.append(mi)
            menu.show_all()
            return menu

        # ==========================================
        # Right Actions
        # ==========================================
        def on_cloud_clicked(self, widget):
            os.system("genixbit-control-center &")

        def on_ai_clicked(self, widget):
            os.system("genixbit-ai-center-gui &")

        def on_guard_clicked(self, widget):
            os.system("genixbit-guard monitor &")

        def on_darkmode_clicked(self, widget):
            os.system("genixbit-control-center --toggle-theme &")

        def on_spotlight_clicked(self, widget):
            os.system("genixbit-launcher &")

        def on_control_clicked(self, widget):
            os.system("genixbit-control-center &")

    win = MacOSTopBar()
    win.show_all()
    Gtk.main()
    return True

if __name__ == "__main__":
    launch_topbar()
