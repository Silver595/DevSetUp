# DevOps Bootstrapper (`devsetup`)

> One-command setup for your entire DevOps environment — Docker, Kubernetes, Terraform, AWS CLI, Helm, Node.js, Python, Git, and more.

---

## ✨ Features

| Feature | Details |
|---|---|
| **Interactive TUI** | Grouped, multi-select tool menu (whiptail / dialog / fzf / plain fallback) |
| **Smart OS Detection** | Debian/Ubuntu · Fedora/RHEL · Arch Linux · openSUSE |
| **Idempotent Installs** | Skips already-installed tools automatically |
| **Git Wizard** | Interactive `git config --global` setup with sensible defaults |
| **Shell Aliases** | Injects 40+ curated DevOps aliases into `.bashrc` / `.zshrc` |
| **Project Scaffolding** | Creates a full DevOps project folder tree in one command |
| **Dry-Run Mode** | Preview all actions without changing your system |
| **Declarative Config** | Customise tools, aliases, and folders through plain-text config files |

---

## 🚀 Quick Start

```bash
git clone https://github.com/silver595/DevSetUp.git
cd DevSetUp
./devsetup
```

---

## 📖 Usage

```
./devsetup                         # Interactive TUI (recommended)
./devsetup --install docker kubectl helm
./devsetup --dry-run --install terraform
./devsetup --list                  # Show all installable tools & status
./devsetup --git-config            # Run Git configuration wizard
./devsetup --aliases               # Inject shell aliases only
./devsetup --scaffold my-service   # Create project folder structure
./devsetup --remove-aliases        # Remove injected aliases
./devsetup --preview-scaffold      # Preview folder tree without creating
./devsetup --help
```

---

## 📦 Installable Tools

| Category | Tools |
|---|---|
| **DevOps** | Docker, kubectl, Helm |
| **IaC** | Terraform |
| **Cloud** | AWS CLI v2 |
| **VCS** | Git (+ wizard) |
| **Languages** | Node.js (via nvm), Python 3 + pip |

---

## 📁 Project Structure

```
devsetup/
├── devsetup            # Main entry-point (chmod +x)
├── lib/
│   ├── logger.sh       # Colored logging, timestamps, spinners
│   ├── detect.sh       # OS / arch / package-manager detection
│   ├── install.sh      # Idempotent install functions per tool
│   ├── aliases.sh      # Shell alias injection / removal
│   ├── scaffold.sh     # Project folder structure creation
│   └── tui.sh          # Interactive menu (whiptail/dialog/fzf/plain)
└── config/
    ├── tools.conf      # Declarative tool list (CATEGORY:tool)
    ├── aliases.conf    # Shell aliases ([Section] key='value')
    └── folders.conf    # Folder template (one path per line)
```

---

## ⚙️ Configuration

### `config/tools.conf`
Add or remove tools from the TUI menu:
```ini
DevOps:docker
DevOps:kubectl
IaC:terraform
```
Each `CATEGORY:tool_name` pair maps to an `install_<tool_name>()` function in `lib/install.sh`.

### `config/aliases.conf`
Add your own shell aliases:
```ini
[MyTools]
myalias='my command here'
```

### `config/folders.conf`
Add paths for your preferred project layout:
```
src/api
infra/terraform/modules
tests/e2e
```

---

## 🔧 Adding a New Tool

1. Add an install function to `lib/install.sh`:
   ```bash
   install_mytool() {
       _already_installed mytool && return 0
       log_step "Installing mytool..."
       spinner_start "Installing mytool"
       _pkg_install mytool        # or custom curl install
       spinner_stop ok
       log_ok "mytool installed: $(mytool --version)"
   }
   ```
2. Register it in `config/tools.conf`:
   ```ini
   MyCategory:mytool
   ```
That's it — it will appear in the TUI and be available via `--install mytool`.

---

## 🌍 Supported Operating Systems

| OS | Package Manager |
|---|---|
| Ubuntu / Debian | `apt` |
| Fedora / RHEL / AlmaLinux | `dnf` / `yum` |
| Arch / Manjaro | `pacman` |
| openSUSE | `zypper` |

---

## 🔒 Security Notes

- The script only calls `sudo` when required (package installs, system-level writes).
- Running as root skips sudo entirely.
- No data is collected or sent anywhere.

---

## 📜 License

MIT — use freely, modify freely.
