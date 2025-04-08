
# ⚙️ t3rn Executor v2 Installer

This is a smooth and automated script to **install, configure, and run** the [t3rn Executor v2](https://github.com/t3rn/executor-release) on your machine — with support for custom ports, dynamic updates, and auto-config!

---

## 🚀 Installation

Simply run this one-liner in your terminal:

```bash
bash <(curl -s https://raw.githubusercontent.com/xcybermanx/t3rnx/refs/heads/main/runit.sh)
```

💡 **What this does:**

- Updates your system
- Downloads the latest Executor release (only if new version is available)
- Prompts for your `PRIVATE_KEY_LOCAL` and `APIKEY_ALCHEMY`
- Sets up a dynamic RPC config
- Automatically creates and runs a systemd service

---

## 🔧 Configuration

You'll be prompted during installation to:

- Paste your **PRIVATE_KEY_LOCAL**
- Paste your **Alchemy API key**
- Choose whether to **store keys securely** in the environment file

All runtime configuration lives in:

```bash
/etc/t3rn-executor-v2.env
```

---

## 📦 File Locations

| Component             | Path                                      |
|----------------------|-------------------------------------------|
| Binary Executable     | `/home/$USER/t3rn-v2/executor/.../executor` |
| Env File              | `/etc/t3rn-executor-v2.env`              |
| Systemd Service File  | `/etc/systemd/system/t3rn-executor-v2.service` |

---

## 🧼 Uninstall

To **fully remove** the service and files:

```bash
sudo systemctl stop t3rn-executor-v2.service && sudo systemctl disable t3rn-executor-v2.service && sudo rm /etc/systemd/system/t3rn-executor-v2.service && sudo rm -rf /home/$USER/t3rn-v2 && sudo systemctl daemon-reload
```

---

## 📄 Logs

To watch the service logs live:

```bash
sudo journalctl -u t3rn-executor-v2.service -f
```

---

## 🧠 Author

- 🔗 [xcybermanx (GitHub)](https://github.com/xcybermanx)

---

## 🛠️ Powered by

- [t3rn Executor](https://github.com/t3rn/executor-release)
- Bash, Systemd, and Good Vibes ✨

---
