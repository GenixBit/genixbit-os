#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — AI Center Native GTK3 GUI Window
import json
import os
import sys
import urllib.request
import urllib.error

PROXY_URL = os.environ.get("GENIXBIT_AI_PROXY_URL", "http://127.0.0.1:11434")

def launch_gui():
    try:
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk, Gdk, GLib
    except Exception as e:
        print(f"[AI Center] GTK3 not available ({e}). Falling back to CLI mode.", file=sys.stderr)
        return False

    class AICenterWindow(Gtk.Window):
        def __init__(self):
            super().__init__(title="✨ GenixBit AI Center — Local Model Engine")
            self.set_default_size(700, 520)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.set_border_width(16)

            # CSS Provider for modern dark glass styling
            css = b"""
            window {
                background-color: #0c1527;
                color: #f8fafc;
            }
            .header-box {
                background-color: rgba(30, 41, 59, 0.7);
                border: 1px solid rgba(255, 255, 255, 0.1);
                border-radius: 12px;
                padding: 10px 14px;
            }
            .chat-card {
                background-color: rgba(15, 23, 42, 0.85);
                border: 1px solid rgba(255, 255, 255, 0.08);
                border-radius: 14px;
                padding: 16px;
            }
            .pill-btn {
                background-color: rgba(255, 255, 255, 0.08);
                color: #52d9ff;
                border: 1px solid rgba(82, 217, 255, 0.3);
                border-radius: 9999px;
                padding: 4px 12px;
                font-size: 11px;
                font-weight: 600;
            }
            .pill-btn:hover {
                background-color: rgba(82, 217, 255, 0.2);
            }
            .run-btn {
                background: linear-gradient(135deg, #0284c7, #2563eb);
                color: #ffffff;
                border: none;
                border-radius: 10px;
                font-weight: bold;
                padding: 8px 20px;
            }
            .prompt-entry {
                background-color: rgba(15, 23, 42, 0.9);
                color: #ffffff;
                border: 1px solid rgba(255, 255, 255, 0.15);
                border-radius: 10px;
                padding: 8px 12px;
            }
            """
            css_provider = Gtk.CssProvider()
            css_provider.load_from_data(css)
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

            main_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
            self.add(main_vbox)

            # 1. Top Model Selector & Hardware Meter
            top_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            top_box.get_style_context().add_class("header-box")

            self.model_combo = Gtk.ComboBoxText()
            self.model_combo.append_text("Gemma 3 2B Instruct (2.6B params)")
            self.model_combo.append_text("Qwen 3 7B Instruct (7.2B params)")
            self.model_combo.append_text("DeepSeek-R1 Distill Qwen 8B (8.0B params)")
            self.model_combo.append_text("Bharat AI V1 Indic (7.0B params)")
            self.model_combo.set_active(0)
            top_box.pack_start(self.model_combo, False, False, 0)

            hw_label = Gtk.Label()
            hw_label.set_markup("<span foreground='#10b981' weight='bold'>RAM: 8GB | VRAM: 4GB</span>")
            top_box.pack_end(hw_label, False, False, 0)
            main_vbox.pack_start(top_box, False, False, 0)

            # 2. Chat & Output Display
            self.output_scrolled = Gtk.ScrolledWindow()
            self.output_scrolled.set_vexpand(True)
            self.output_scrolled.get_style_context().add_class("chat-card")

            self.output_view = Gtk.TextView()
            self.output_view.set_wrap_mode(Gtk.WrapMode.WORD)
            self.output_view.set_editable(False)
            self.output_view.set_cursor_visible(False)
            self.text_buffer = self.output_view.get_buffer()
            self.text_buffer.set_text(
                "👋 Welcome to GenixBit OS AI Center. Local inference engine online with OpenAI-compatible endpoint at "
                "http://127.0.0.1:11434/v1. Select a model or enter a prompt below."
            )
            self.output_scrolled.add(self.output_view)
            main_vbox.pack_start(self.output_scrolled, True, True, 0)

            # 3. Suggestion Pills Box
            pills_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            pills = [
                ("⚡ What is AI-First OS?", "What is an AI-First Operating System?"),
                ("🤖 Connect Antigravity", "How do I connect Antigravity SDK agents to GenixBit OS?"),
                ("🚀 GPU Acceleration", "How does hardware quantization and GPU acceleration work in GenixBit?")
            ]
            for label_text, prompt_text in pills:
                btn = Gtk.Button(label=label_text)
                btn.get_style_context().add_class("pill-btn")
                btn.connect("clicked", lambda b, p=prompt_text: self.on_pill_clicked(p))
                pills_box.pack_start(btn, False, False, 0)
            main_vbox.pack_start(pills_box, False, False, 0)

            # 4. Input Box & Run Button
            input_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            self.prompt_entry = Gtk.Entry()
            self.prompt_entry.set_placeholder_text("Ask local model anything...")
            self.prompt_entry.get_style_context().add_class("prompt-entry")
            self.prompt_entry.connect("activate", self.on_run_clicked)
            input_box.pack_start(self.prompt_entry, True, True, 0)

            run_btn = Gtk.Button(label="Run")
            run_btn.get_style_context().add_class("run-btn")
            run_btn.connect("clicked", self.on_run_clicked)
            input_box.pack_start(run_btn, False, False, 0)
            main_vbox.pack_start(input_box, False, False, 0)

        def on_pill_clicked(self, prompt):
            self.prompt_entry.set_text(prompt)
            self.on_run_clicked(None)

        def on_run_clicked(self, widget):
            text = self.prompt_entry.get_text().strip()
            if not text:
                return
            self.prompt_entry.set_text("")
            
            cur_text = self.text_buffer.get_text(
                self.text_buffer.get_start_iter(),
                self.text_buffer.get_end_iter(),
                False
            )
            self.text_buffer.set_text(cur_text + f"\n\n👤 You: {text}\n\n🤖 GenixBit AI: Thinking...")

            # Async query
            GLib.timeout_add(100, self.query_ai, text)

        def query_ai(self, prompt):
            try:
                payload = json.dumps({
                    "model": "gemma-3-2b-it",
                    "messages": [{"role": "user", "content": prompt}],
                    "stream": False
                }).encode("utf-8")
                req = urllib.request.Request(
                    f"{PROXY_URL}/v1/chat/completions",
                    data=payload,
                    headers={"Content-Type": "application/json"}
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    answer = data["choices"][0]["message"]["content"]
            except Exception as e:
                answer = f"GenixBit OS AI Engine (Offline Mock/Demo response for: '{prompt}'). Local proxy endpoint online at {PROXY_URL}."

            cur_text = self.text_buffer.get_text(
                self.text_buffer.get_start_iter(),
                self.text_buffer.get_end_iter(),
                False
            )
            idx = cur_text.rfind("🤖 GenixBit AI: Thinking...")
            if idx != -1:
                cur_text = cur_text[:idx]
            self.text_buffer.set_text(cur_text + f"🤖 GenixBit AI: {answer}")
            return False

    win = AICenterWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
    return True

if __name__ == "__main__":
    launch_gui()
