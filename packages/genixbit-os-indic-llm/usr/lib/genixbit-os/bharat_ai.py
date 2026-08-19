#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — Bharat AI Engine (Translation, Transliteration, Indic NLP)
import json
import os
import sys

LANG_PATH = "/usr/share/genixbit-os/languages.json"
LOCAL_DEV_LANG_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../share/genixbit-os/languages.json"))

def load_languages():
    for p in [LANG_PATH, LOCAL_DEV_LANG_PATH]:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
    return {"languages": []}

def list_languages():
    data = load_languages()
    return data.get("languages", [])

def get_language_info(code_or_name):
    query = code_or_name.strip().lower()
    if query in ["en", "english"]:
        return {"code": "en", "name": "English", "native": "English", "script": "Latin"}
    for lang in list_languages():
        if lang["code"].lower() == query or lang["name"].lower() == query or lang["native"].lower() == query:
            return lang
    return None

def translate_mock(text, src_code, tgt_code):
    src_info = get_language_info(src_code)
    tgt_info = get_language_info(tgt_code)
    if not src_info or not tgt_info:
        raise ValueError(f"Unsupported language pair: {src_code} -> {tgt_code}")
    
    return {
        "status": "success",
        "source": src_info["code"],
        "source_name": src_info["name"],
        "target": tgt_info["code"],
        "target_name": tgt_info["name"],
        "original_text": text,
        "translated_text": f"[{tgt_info['name']}] {text}"
    }

if __name__ == "__main__":
    langs = list_languages()
    print(f"GenixBit Bharat AI — {len(langs)} Official Indian Languages Loaded.")
