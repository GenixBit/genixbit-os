# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS — GenixKit Application Lifecycle Manager

import os
import signal
import sys
import time

class AppState:
    INITIALIZING = "initializing"
    RUNNING = "running"
    SUSPENDED = "suspended"
    TERMINATING = "terminating"

class GenixApp:
    """
    Base class for GenixBit OS native applications.
    Manages lifecycle events: on_launch, on_suspend, on_resume, on_terminate.
    """
    def __init__(self, app_id, app_name, version="1.0.0"):
        self.app_id = app_id
        self.app_name = app_name
        self.version = version
        self.state = AppState.INITIALIZING
        self._setup_signals()

    def _setup_signals(self):
        signal.signal(signal.SIGINT, self._handle_termination)
        signal.signal(signal.SIGTERM, self._handle_termination)
        if hasattr(signal, "SIGUSR1"):
            signal.signal(signal.SIGUSR1, self._handle_suspend)
        if hasattr(signal, "SIGUSR2"):
            signal.signal(signal.SIGUSR2, self._handle_resume)

    def _handle_termination(self, signum, frame):
        self.state = AppState.TERMINATING
        self.on_terminate()
        sys.exit(0)

    def _handle_suspend(self, signum, frame):
        self.state = AppState.SUSPENDED
        self.on_suspend()

    def _handle_resume(self, signum, frame):
        self.state = AppState.RUNNING
        self.on_resume()

    def on_launch(self):
        """Called when application finishes initialization."""
        pass

    def on_suspend(self):
        """Called when system requests power/memory saving suspension."""
        pass

    def on_resume(self):
        """Called when application resumes from suspension."""
        pass

    def on_terminate(self):
        """Called prior to application shutdown to persist state."""
        pass

    def run(self):
        """Main execution loop."""
        self.state = AppState.RUNNING
        self.on_launch()
        print(f"[GenixKit] Application {self.app_name} ({self.app_id}) v{self.version} started.")
        return 0
