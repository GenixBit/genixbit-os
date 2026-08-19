# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit Developer SDK
"""
GenixKit is the official developer framework for building native, secure,
AI-first applications for GenixBit OS.
"""

from .app import GenixApp
from .ai import GenixAI
from .security import GenixSecurity, Permission
from .storage import AppStorage
from .system import GenixSystem
from .ipc import GenixIPC

__version__ = "1.0.0-lts"
__all__ = ["GenixApp", "GenixAI", "GenixSecurity", "Permission", "AppStorage", "GenixSystem", "GenixIPC"]
