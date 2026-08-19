# GenixBit OS — GenixKit Developer SDK Platform (GenixKit)

## 1. Overview
GenixKit is the native application framework for building secure, high-performance, AI-first applications for GenixBit OS.

---

## 2. Core Modules
- **`genixkit.app`**: Standardized application lifecycle manager (`on_launch`, `on_suspend`, `on_resume`, `on_terminate`).
- **`genixkit.ai`**: Local AI inference client supporting OpenAI/Ollama-compatible REST/SSE streaming on `http://127.0.0.1:11434`.
- **`genixkit.security`**: Capability-based permission negotiation and security auditing.
- **`genixkit.storage`**: Sandboxed key-value and local data persistence (`AppStorage`).

---

## 3. Quickstart Example
```python
from genixkit import GenixApp, GenixAI, GenixSecurity, Permission

class MyApp(GenixApp):
    def on_launch(self):
        sec = GenixSecurity(self.app_id)
        if sec.request_permission(Permission.READ_FILE):
            ai = GenixAI()
            print(ai.chat("Hello from GenixKit!"))

if __name__ == "__main__":
    app = MyApp("com.genixbit.hello", "Hello World")
    app.run()
```
