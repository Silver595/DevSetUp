<div align="center">

```
  ██████╗ ███████╗██╗   ██╗███████╗███████╗████████╗██╗   ██╗██████╗
  ██╔══██╗██╔════╝██║   ██║██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
  ██║  ██║█████╗  ██║   ██║███████╗█████╗     ██║   ██║   ██║██████╔╝
  ██║  ██║██╔══╝  ╚██╗ ██╔╝╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
  ██║  ██║██╔══╝  ╚██╗ ██╔╝╚════██║██╔══╝     ██║   ██║   ██║██╔═╝
  ██████╔╝███████╗ ╚████╔╝ ███████║███████╗   ██║   ╚██████╔╝██║
  ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝
```

**One-command setup for your entire DevOps environment.**

[![Version](https://img.shields.io/badge/version-1.0.5-indigo?style=flat-square)](https://github.com/Silver595/DevSetUp/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash%204%2B-blue?style=flat-square)](https://www.gnu.org/software/bash/)
[![OS](https://img.shields.io/badge/OS-Debian%20·%20Ubuntu%20·%20Fedora%20·%20Arch-orange?style=flat-square)](#-supported-operating-systems)

</div>

---

## ⚡ Quick Install

### Option 1 — `curl | bash` (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | bash
```

Then run from anywhere:

```bash
devsetup
```

### Option 2 — `.deb` package (Debian / Ubuntu)

```bash
curl -fsSLO https://github.com/Silver595/DevSetUp/releases/latest/download/devsetup_1.1.0_all.deb
sudo dpkg -i devsetup_1.1.0_all.deb
```

### Option 3 — Clone & run

```bash
git clone https://github.com/Silver595/DevSetUp.git
cd DevSetUp
bash devsetup
```

---

## 🎯 What It Does

`devsetup` is a DevOps bootstrapper that sets up a fresh Linux machine for development in minutes. Pick the tools you want in an interactive menu — it handles OS detection, the right package manager, repo keys, and service setup automatically.

```
  ╔══════════════════════════════════════════════════════════╗
  ║        devsetup — Tool Selector                        ║
  ╚══════════════════════════════════════════════════════════╝
  ↑↓ navigate   Space toggle   Enter confirm   a all   q quit

  ▸ ⎈ DevOps
    [✔] docker            ✔ installed
    [ ] kubectl
    [ ] helm
  ▸ ▣ Database
    [ ] mysql
    [ ] postgresql
    [ ] redis
  ...
  9 tool(s) selected
```

---

## 📖 Commands

```bash
# Interactive TUI (arrow keys, space to select, enter to confirm)
devsetup

# Install specific tools directly
devsetup --install docker nginx mysql python

# Pre-flight system check (internet, sudo, disk, locks)
devsetup --doctor

# Show versions of all installed tools
devsetup --status

# Update a tool to latest version
devsetup --update terraform

# Remove a tool
devsetup --uninstall nginx

# Preview what would be installed without changing anything
devsetup --dry-run --install docker nginx golang

# List all available tools with install status
devsetup --list

# Configure Git globally (interactive wizard)
devsetup --git-config

# Inject 40+ curated DevOps shell aliases into .bashrc / .zshrc
devsetup --aliases

# Create a DevOps project folder structure
devsetup --scaffold my-api

# Show help
devsetup --help
```

---

## 📦 Available Tools (36 total)

### ⎈ DevOps & Containers
| Tool | Description |
|---|---|
| `docker` | Container runtime + Compose plugin |
| `kubectl` | Kubernetes CLI |
| `helm` | Kubernetes package manager |
| `k9s` | Terminal UI for Kubernetes clusters |
| `minikube` | Local Kubernetes cluster |

### ⛌ Infrastructure as Code
| Tool | Description |
|---|---|
| `terraform` | HashiCorp infrastructure provisioning |
| `ansible` | Agentless configuration management |
| `vagrant` | VM environment management |

### ☁ Cloud CLIs
| Tool | Description |
|---|---|
| `awscli` | AWS CLI v2 |
| `gcloud` | Google Cloud CLI |
| `azure` | Azure CLI (`az`) |
| `gh` | GitHub CLI |

### 🌐 Web Servers
| Tool | Description |
|---|---|
| `nginx` | High-performance web / reverse-proxy server |
| `apache` | Apache HTTP Server (`apache2` / `httpd`) |

### λ PHP Ecosystem
| Tool | Description |
|---|---|
| `php` | PHP 8 + common extensions (curl, mbstring, xml, zip, mysql, pgsql) |
| `phpfpm` | PHP-FPM process manager (auto-detects version) |
| `composer` | PHP dependency manager |

### ▣ Databases
| Tool | Description |
|---|---|
| `mysql` | MySQL Server |
| `postgresql` | PostgreSQL Server |
| `redis` | Redis in-memory data store |
| `mongodb` | MongoDB 7.0 |

### ⟨/⟩ Languages & Runtimes
| Tool | Description |
|---|---|
| `nvm` | Node Version Manager + Node.js LTS |
| `python` | Python 3 + pip + venv |
| `golang` | Go (latest stable, installed to `/usr/local/go`) |
| `rust` | Rust via `rustup` |

### ⑂ Version Control
| Tool | Description |
|---|---|
| `git` | Git VCS |
| `gh` | GitHub CLI |

### ⚒ CLI Utilities
| Tool | Description |
|---|---|
| `fzf` | Fuzzy finder |
| `bat` | `cat` with syntax highlighting |
| `eza` | Modern `ls` replacement |
| `ripgrep` | Fast regex search (`rg`) |
| `jq` | JSON processor |
| `yq` | YAML / JSON processor |
| `httpie` | User-friendly HTTP client (`http`) |
| `tmux` | Terminal multiplexer |
| `neovim` | Modern Vim (`nvim`) |
| `btop` | Resource monitor |

---

## 🩺 Pre-flight Doctor

Before installing, run:

```bash
devsetup --doctor
```

```
  devsetup --doctor  Pre-flight system check

  ✔  Internet connectivity          reachable
  ✔  Sudo access                    passwordless sudo available
  ✔  Disk space (/)                 98432MB free
  ✔  Package manager                apt (OS: ubuntu 24.04)
  ✔  Required tools                 curl, bash present
  ✔  Package lock                   no lock detected

  ✔  All checks passed — ready to install!
```

---

## 📊 Status Check

See what's installed and at what version:

```bash
devsetup --status
```

```
  ╭────────────────────────────────────────────╮
  │          Installed Tool Versions           │
  ├────────────────────────────────────────────┤
  │  ✔  docker           26.1.4                │
  │  ✔  kubectl          v1.29.3               │
  │  ✔  git              2.43.0                │
  │  ✔  python3          3.12.2                │
  │  ✔  jq               jq-1.7               │
  ╰────────────────────────────────────────────╯
```

---

## 🔁 Dry Run

Preview exactly what will happen — nothing is installed:

```bash
devsetup --dry-run --install docker nginx postgresql golang
```

```
  [dry-run]  sudo apt-get update -qq
   1/4   docker      → [dry-run] Would install: docker
   2/4   nginx       → [dry-run] Would install: nginx
   3/4   postgresql  → SKIP (already installed)
   4/4   golang      → [dry-run] Would install: golang

  ╭─ Installation Summary ─────────────────────╮
  │  ✔  docker (would install)                 │
  │  ✔  nginx (would install)                  │
  │  ✔  golang (would install)                 │
  │  ⊘  postgresql                             │
  │  3 ok  0 failed  1 skipped                 │
  ╰────────────────────────────────────────────╯
```

---

## 🔒 Reliability Features (v1.1.0)

| Feature | Details |
|---|---|
| **Lock file** | `flock` prevents two `devsetup` processes from colliding |
| **Ctrl+C protection** | Clean abort message, spinner killed, partial summary printed, terminal restored |
| **Network retry** | curl downloads retry 3× with exponential backoff (1s → 2s → 4s) |
| **dpkg lock detection** | Waits up to 60s if apt is locked by another process |
| **Silent installs** | All package manager output goes to a log file — terminal stays clean |
| **Progress counter** | `[2/5] Installing nginx...` during batch installs |
| **Summary box** | Success / failed / skipped summary after every install run |

---

## ⚙️ Configuration

All config lives in `config/`. Edit these to customise without touching code.

### `config/tools.conf`
Defines which tools appear in the TUI and are available to `--install`:
```ini
# Format: CATEGORY:tool_name
DevOps:docker
DevOps:kubectl
Database:postgresql
Languages:golang
```
Each `tool_name` maps to an `install_<tool_name>()` function in `lib/install.sh`.

### `config/aliases.conf`
Shell aliases that `--aliases` injects into `.bashrc` / `.zshrc`:
```ini
[Docker]
dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
dex='docker exec -it'

[Kubernetes]
k='kubectl'
kgp='kubectl get pods'
```

### `config/folders.conf`
Project folder template for `--scaffold`:
```
src/api
src/frontend
infra/terraform/modules
infra/ansible/roles
tests/unit
tests/e2e
docs
```

---

## 🔧 Adding a Custom Tool

1. Add an install function to `lib/install.sh`:

```bash
install_mytool() {
    _already_installed mytool && { summary_skip "mytool"; return 0; }
    log_step "Installing mytool..."
    spinner_start "Installing mytool"
    _do_install mytool _pkg_install mytool || { summary_fail "mytool"; return 1; }
    _installed_ok "mytool → $(mytool --version 2>/dev/null)"
    summary_ok "mytool"
}
```

2. Register it in `config/tools.conf`:

```ini
MyCategory:mytool
```

That's it — it will appear in the TUI, be available via `--install mytool`, and show in `--list` and `--status`.

---

## 📁 Project Structure

```
devsetup/
├── devsetup                # Main entry-point (chmod +x)
├── lib/
│   ├── logger.sh           # Colours, spinner, progress, summary box
│   ├── detect.sh           # OS / arch / PKG_MANAGER + doctor checks
│   ├── install.sh          # Idempotent installers (36 tools)
│   ├── aliases.sh          # Shell alias injection / removal
│   ├── scaffold.sh         # Project folder creation
│   └── tui.sh              # Multi-backend TUI (whiptail/dialog/fzf/bash)
├── config/
│   ├── tools.conf          # Tool registry (CATEGORY:tool)
│   ├── aliases.conf        # Shell aliases ([Section] key='value')
│   └── folders.conf        # Folder template (one path per line)
└── packaging/
    └── debian/
        ├── control.template
        ├── postinst
        └── prerm
```

---

## 🌍 Supported Operating Systems

| Distribution | Package Manager | Status |
|---|---|---|
| Ubuntu 20.04+ / Debian 11+ | `apt` | ✔ Full support |
| Fedora 38+ / RHEL 9+ / AlmaLinux | `dnf` | ✔ Full support |
| CentOS 7 / older RHEL | `yum` | ✔ Basic support |
| Arch Linux / Manjaro / EndeavourOS | `pacman` | ✔ Full support |
| openSUSE Leap / Tumbleweed | `zypper` | ✔ Basic support |
| macOS (via Homebrew) | `brew` | ⚠ Partial support |

---

## 🌐 TUI Backends

The pure-bash arrow-key TUI is the **default** — it works everywhere: sudo, SSH, tmux, any terminal.

| Backend | Experience | How to use |
|---|---|---|
| **Pure bash** | ✔ Arrow keys, built-in | Default — always works |
| `whiptail` | ✔ Dialog boxes | `DEVSETUP_TUI=whiptail devsetup` |
| `dialog` | ✔ Dialog boxes | `DEVSETUP_TUI=dialog devsetup` |
| `fzf` | ✔ Fuzzy search | `DEVSETUP_TUI=fzf devsetup` |

**Pure-bash controls:** `↑↓` / `j k` navigate · `Space` toggle · `Enter` confirm · `a` select all · `n` clear · `q` quit

---

## 🔒 Security Notes

- `sudo` is called **only** when required (system package installs, `/usr/local/bin` writes).
- Running as root skips `sudo` entirely.
- All downloads use HTTPS with official GPG keys.
- No data is collected or sent anywhere.
- Lock file (`/tmp/devsetup.lock`) prevents concurrent runs from corrupting your system.

---

## 📚 Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DRY_RUN` | `false` | Set to `true` to preview all actions |
| `LOG_FILE` | `/tmp/devsetup_DATE.log` | Override the log file path |
| `NVM_DIR` | `~/.nvm` | nvm installation directory |

```bash
DRY_RUN=true devsetup --install docker nginx
LOG_FILE=~/devsetup.log devsetup --install terraform
```

---

## 🤝 Contributing

1. Fork the repo
2. Add your tool to `lib/install.sh` following the pattern above
3. Register it in `config/tools.conf`
4. Test with `bash devsetup --dry-run --install <yourtool>`
5. Open a PR

---

## 📜 License

MIT — use freely, modify freely.

---

<div align="center">

Made with ❤️ by [Silver595](https://github.com/Silver595)

**[⭐ Star on GitHub](https://github.com/Silver595/DevSetUp)** · **[🐛 Report a Bug](https://github.com/Silver595/DevSetUp/issues)** · **[💡 Request a Feature](https://github.com/Silver595/DevSetUp/issues)**

</div>
