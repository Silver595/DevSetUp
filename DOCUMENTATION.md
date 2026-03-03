# devsetup — Complete Project Documentation

> **Version:** 1.1.0 · **Repo:** [github.com/Silver595/DevSetUp](https://github.com/Silver595/DevSetUp)

---

## Table of Contents

1. [What is devsetup?](#1-what-is-devsetup)
2. [Project File Structure](#2-project-file-structure)
3. [Installation Methods](#3-installation-methods)
4. [CLI Reference — Every Command](#4-cli-reference)
5. [Architecture — How the Code Works](#5-architecture)
6. [Source File Details](#6-source-file-details)
7. [All 36 Tools — Installers & Categories](#7-all-36-tools)
8. [Config Files](#8-config-files)
9. [Packaging — .deb Build](#9-packaging)
10. [Version History — Every Change](#10-version-history)
11. [Bugs Found & Fixed](#11-bugs-found-and-fixed)

---

## 1. What is devsetup?

**devsetup** is a production-grade, interactive DevOps bootstrapper for Linux. It installs 36 development tools on Debian/Ubuntu, Fedora/RHEL, Arch, and openSUSE systems with a single command.

**Key goals:**
- One command sets up a fresh machine for development work
- Interactive TUI so you pick exactly what you need
- Idempotent — safe to re-run, skips already-installed tools
- Works as root or with sudo (e.g. fresh VPS setup)
- Distributable via `curl | bash` or `.deb` package

---

## 2. Project File Structure

```
DevSetUp/
├── devsetup                    ← Main entry-point script
├── install.sh                  ← curl-based one-line installer
├── Makefile                    ← Build shortcuts (build, install, clean)
├── README.md                   ← Public documentation with badges
│
├── lib/                        ← Library modules (sourced by devsetup)
│   ├── logger.sh               ← Colors, spinner, progress counter, summary box
│   ├── detect.sh               ← OS detection, doctor pre-flight checks
│   ├── install.sh              ← All 36 tool installer functions
│   ├── tui.sh                  ← Interactive TUI (4 backends)
│   ├── aliases.sh              ← Shell alias injection / removal
│   └── scaffold.sh             ← Project folder scaffolding
│
├── config/                     ← Data files
│   ├── tools.conf              ← Tool list (CATEGORY:TOOL_NAME format)
│   ├── aliases.conf            ← DevOps shell aliases to inject
│   └── folders.conf            ← Project folder structure template
│
└── packaging/
    └── debian/
        ├── control.template    ← .deb control file template (@@VERSION@@ etc.)
        ├── postinst            ← Runs after dpkg install/upgrade
        └── prerm               ← Runs before dpkg remove/upgrade
```

---

## 3. Installation Methods

### Method 1: curl (recommended for fresh machines)

```bash
curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | sudo bash
```

**What install.sh does, step by step:**
1. Detects if running as root or with sudo
2. Checks internet connectivity (fails fast if offline)
3. Detects OS and package manager
4. Downloads via `git clone --depth=1` (fast, single commit) — falls back to individual [curl](file:///home/d3fa4lt/Desktop/auto_pkg_downloader/lib/install.sh#29-42) downloads if [git](file:///home/d3fa4lt/Desktop/auto_pkg_downloader/lib/install.sh#117-125) is missing
5. Sanity-checks the download (verifies [devsetup](file:///home/d3fa4lt/Desktop/auto_pkg_downloader/devsetup), `lib/`, [config/](file:///home/d3fa4lt/Desktop/auto_pkg_downloader/devsetup#166-205) exist)
6. Rewrites three path vars in the script with `sed`:
   - `DEVSETUP_DIR="/usr/share/devsetup"`
   - `LIB_DIR="${DEVSETUP_DIR}/lib"`
   - `CONF_DIR="${DEVSETUP_DIR}/config"`
7. Installs binary to `/usr/local/bin/devsetup` (mode 755)
8. Copies `lib/*.sh` to `/usr/share/devsetup/lib/` and `config/*` to `/usr/share/devsetup/config/`
9. Fixes `PATH` if `/usr/local/bin` is not in it
10. Runs `--version` to verify the install worked

### Method 2: .deb package

```bash
sudo dpkg -i devsetup_1.1.0_all.deb
```

Binary lands at `/usr/bin/devsetup` (managed by dpkg).
The `.deb` includes `Replaces: devsetup (<< 1.1.0)` so it cleanly upgrades older versions.

### Method 3: Run from source

```bash
git clone https://github.com/Silver595/DevSetUp.git
cd DevSetUp
bash devsetup
```

When run from source, `DEVSETUP_DIR` is auto-detected via `readlink -f "${BASH_SOURCE[0]}"`.

---

## 4. CLI Reference

| Command | What it does |
|---|---|
| `devsetup` | Launch interactive TUI tool selector |
| `devsetup --install TOOL [...]` | Install one or more tools directly |
| `devsetup --update TOOL [...]` | Re-install/update to latest version |
| `devsetup --uninstall TOOL [...]` | Remove tools using the system package manager |
| `devsetup --status` | Show a version table of every installed tool |
| `devsetup --doctor` | Pre-flight: internet ✔, sudo ✔, disk ✔, apt lock ✔ |
| `devsetup --list` | List all 36 tools with installed/not-installed status |
| `devsetup --git-config` | Interactive Git global config wizard |
| `devsetup --aliases` | Inject 40+ DevOps shell aliases into .bashrc/.zshrc |
| `devsetup --remove-aliases` | Remove injected aliases from RC files |
| `devsetup --preview-aliases` | Preview aliases without injecting |
| `devsetup --scaffold [NAME]` | Create a DevOps project folder structure |
| `devsetup --preview-scaffold` | Show what scaffold would create |
| `devsetup --export FILE` | Export currently installed tools to a file |
| `devsetup --import FILE` | Read tool list from a file and install them |
| `devsetup --log [N]` | List and optionally view the last `N` log files |
| `devsetup --self-update` | Update devsetup from the GitHub repository |
| `devsetup --dry-run [CMD...]` | Preview any action without changing anything |
| `devsetup --version` | Print version string |
| `devsetup --help` | Show full help |

**Examples:**
```bash
devsetup --install docker nginx postgresql   # install 3 tools at once
devsetup --dry-run --install terraform       # preview: what would be done
devsetup --uninstall nginx                   # remove nginx
devsetup --doctor                            # check if system is ready
DEVSETUP_TUI=whiptail devsetup              # force whiptail TUI
```

---

## 5. Architecture

### Startup flow

```
devsetup called
  ├── Source lib/logger.sh    (colors, spinner, logging functions)
  ├── Source lib/detect.sh    (detect_os → sets OS_ID, PKG_MANAGER, SUDO)
  ├── Source lib/install.sh   (all install_* functions)
  ├── Source lib/aliases.sh   (inject_aliases, remove_aliases)
  ├── Source lib/scaffold.sh  (scaffold_project, scaffold_interactive)
  └── Source lib/tui.sh       (tui_select_tools, tui_confirm, tui_read)

  → _acquire_lock()           (flock on /tmp/devsetup.lock)
  → detect_os()               (sets PKG_MANAGER, OS_FAMILY, SUDO, ARCH)
  → parse $1 → case statement → run appropriate function
  → _on_exit trap  (releases lock, kills spinner, prints summary if interrupted)
  → _on_abort trap (Ctrl+C: restores terminal stty, prints partial summary)
```

### Library loading

Each `lib/*.sh` file is sourced (not executed) by `devsetup`. They share a common namespace. The load order matters:

```
logger.sh → detect.sh → install.sh → aliases.sh → scaffold.sh → tui.sh
```

`tui.sh` depends on color vars from `logger.sh`. `install.sh` depends on `PKG_MANAGER` from `detect.sh`.

### Lock file

`/tmp/devsetup.lock` is held with `flock -n 9` while devsetup runs. Prevents two concurrent installs from corrupting the package database.

### Dry-run mode

When `--dry-run` is passed, `DRY_RUN=true` is exported. All `_do_install`, `run_cmd`, and `_pkg_install` calls check `_dry_run` and print `[dry-run] Would install: X` instead of running.

---

## 6. Source File Details

### `devsetup` (main script)

**Path:** `/usr/bin/devsetup` (installed) or repo root (source)

**Key functions:**

| Function | Purpose |
|---|---|
| `_acquire_lock` | `flock -n 9` on lock file; exits with error if already locked |
| `_on_exit` | EXIT trap: kills spinner, releases lock |
| `_on_abort` | INT/TERM trap: restores `stty`, prints summary, exits 130 |
| `_print_banner` | 6-line ASCII art banner in ANSI color |
| `_print_help` | Full usage help using `printf` (not heredoc — avoids literal `\033`) |
| `_load_tools_conf` | Reads `config/tools.conf` → populates `TOOL_GROUPS` associative array |
| `run_git_config_wizard` | Interactive `tui_read` prompts → `git config --global` |
| `install_tool_list` | Loops over tools, calls `log_progress` counter, then `install_tool` |
| `_print_list` | Shows all tools by category with ✔ installed / ◦ not installed |
| `run_interactive` | Pre-flight → TUI → installs → alias prompt → scaffold prompt |
| `main` | Parses `$1`, dispatches to the right function |

**Path rewriting (for installed binary):**

When building the `.deb` or installing via curl, three `sed` substitutions patch the path vars:
```bash
sed \
  -e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"/usr/share/devsetup\"|" \
  -e "s|^LIB_DIR=.*|LIB_DIR=\"\${DEVSETUP_DIR}/lib\"|" \
  -e "s|^CONF_DIR=.*|CONF_DIR=\"\${DEVSETUP_DIR}/config\"|"
```

---

### `lib/logger.sh`

**Purpose:** All terminal output — colors, spinner, progress, summary box.

**Color variable syntax (critical detail):**
```bash
# WRONG (literal 7-char string — shown as garbage in heredocs/cat):
RESET="\033[0m"

# CORRECT (real ESC byte — works everywhere):
RESET=$'\033[0m'
```
All 25+ color vars use `$'\033'` syntax.

**Key functions:**

| Function | Output |
|---|---|
| `log_info` | `HH:MM:SS  ●  INFO  message` |
| `log_ok` | `HH:MM:SS  ✔  OK    message` |
| `log_warn` | `HH:MM:SS  ⚠  WARN  message` |
| `log_error` | `HH:MM:SS  ✘  ERROR message` |
| `log_skip` | `HH:MM:SS  ⊘  SKIP  message` |
| `log_section` | Box-drawing section header with title |
| `log_progress N TOTAL NAME` | `[N/TOTAL]  name` step counter |
| `spinner_start MSG` | Background braille spinner process |
| `spinner_stop ok\|fail\|skip` | Kills spinner, prints ✔/✘/⊘ |
| `summary_ok/fail/skip TEXT` | Append to summary arrays (strips `\n`) |
| `log_summary` | Box-drawing summary: lists ok/fail/skip items + count |
| `run_cmd ARGS...` | In dry-run: prints `[dry-run]`. Otherwise runs and logs to `$LOG_FILE` |

**Log file:** Auto-created at `/tmp/devsetup_YYYYMMDD_HHMMSS.log`.

---

### `lib/detect.sh`

**Purpose:** OS/arch detection and doctor pre-flight checks.

**`detect_os()`** sets these globals:

| Variable | Example value |
|---|---|
| `OS_ID` | `ubuntu`, `fedora`, `arch`, `debian` |
| `OS_FAMILY` | `debian`, `rhel`, `arch`, `suse`, `macos` |
| `OS_VERSION` | `22.04`, `38`, `rolling` |
| `PKG_MANAGER` | `apt`, `dnf`, `yum`, `pacman`, `zypper`, `brew` |
| `ARCH` | `x86_64`, `aarch64` |
| `SUDO` | `sudo` (non-root) or `` (root) |

**Supported OS families:**

| Family | Distros |
|---|---|
| Debian | Ubuntu, Debian, Mint, Pop!_OS, Kali, elementary, Zorin, Raspbian |
| RHEL | Fedora, RHEL, CentOS, AlmaLinux, Rocky, Oracle Linux |
| Arch | Arch, Manjaro, EndeavourOS, Garuda, Artix |
| SUSE | openSUSE, SLES |
| macOS | macOS (Homebrew) |

**Doctor checks (`run_doctor`):**
1. `check_internet` — `curl https://1.1.1.1` with 4s timeout
2. `check_sudo` — `sudo -n true` (passwordless) or EUID==0
3. `check_disk_space /` — warn <1024MB, fail <500MB
4. `check_pkg_manager` — verifies PKG_MANAGER is known
5. `check_required_tools` — curl and bash must exist
6. `check_pkg_lock` — `fuser /var/lib/dpkg/lock-frontend` (apt only)

---

### `lib/install.sh`

**Purpose:** Every tool installer function.

**Install patterns (3 types):**

**Type 1 — Simple `_pkg_install` wrapper:**
```bash
install_git() {
    _already_installed git && { summary_skip "git"; return 0; }
    log_step "Installing Git..."
    spinner_start "Installing git"
    _do_install git _pkg_install git || { summary_fail "git"; return 1; }
    _installed_ok "Git → $(git --version)"
    summary_ok "git → $(git --version | awk '{print $3}')"
}
```

**Type 2 — Custom `_install_TOOL_body` function (complex tools):**
```bash
_install_docker_body() {
    # Removes old versions, adds Docker GPG key, adds repo, installs
}
install_docker() {
    _already_installed docker && { summary_skip "docker"; return 0; }
    spinner_start "Installing Docker"
    _do_install docker _install_docker_body || { summary_fail "docker"; return 1; }
    ...
}
```

**Type 3 — Uninstall functions:**
```bash
uninstall_docker() {
    _do_install docker _pkg_remove docker-ce docker-ce-cli containerd.io ...
}
```

**Core helpers:**

| Helper | Purpose |
|---|---|
| `_already_installed CMD` | `command -v CMD` — skips if found |
| `_do_install TOOL BODY_FN` | Runs body; in dry-run prints `[dry-run]`; catches failures |
| `_pkg_install PKGS...` | `apt-get install -y` / `dnf install -y` / etc. |
| `_pkg_remove PKGS...` | Remove + autoremove |
| `_pkg_update` | `apt-get update` / `dnf check-update` etc. |
| `_pkg_enable_service NAME` | `systemctl enable --now NAME` |
| `_wait_pkg_lock` | Waits up to 60s for dpkg lock to release |
| `_curl_retry ARGS...` | curl with 3 retries + exponential backoff |

**`install_tool TOOLNAME` dispatcher:**
```bash
install_tool() {
    local fn="install_${1,,}"
    declare -f "$fn" >/dev/null || { log_error "No installer for: $1"; return 1; }
    "$fn"
}
```

---

### `lib/tui.sh`

**Purpose:** Interactive tool selector — 4 backends.

**Backend detection:**
```bash
_tui_detect_backend() {
    local pref="${DEVSETUP_TUI:-}"    # respect env override
    [[ -n "$pref" ]] && command -v "$pref" &>/dev/null && { echo "$pref"; return; }
    echo "bash"   # default: always works
}
```

**Override:** `DEVSETUP_TUI=whiptail devsetup`

**How all backends work:**

All 4 backends write the selected tool list to `$_tui_out_file` (a temp file set by `run_interactive`). This avoids all subshell/fd-swap problems. `tui_select_tools()` is called directly (no subshell).

```bash
# In run_interactive:
_tui_out_file="$(mktemp)"
export _tui_out_file
tui_select_tools TOOL_GROUPS    # writes to $_tui_out_file directly
selected_raw="$(cat "$_tui_out_file")"
```

**Pure-bash TUI features (default backend):**

| Key | Action |
|---|---|
| `↑` / `k` | Move cursor up |
| `↓` / `j` | Move cursor down |
| `Space` | Toggle selection |
| `Enter` | Confirm and install |
| `a` | Select all |
| `n` | Clear all |
| `q` / `Esc` | Quit |
| `PgUp/PgDn` | Scroll half-page |

**Category colours:**

| Category | Colour |
|---|---|
| DevOps | Teal |
| IaC | Orange |
| Cloud | Indigo |
| WebServer | Lime |
| PHP | Lavender |
| Database | Coral |
| Languages | Yellow |
| VCS | Bright Cyan |
| Utils | Pink |

**Critical bug fix (`mapfile -t`):**
```bash
# BROKEN — only reads the FIRST line (first category = Cloud = 3 tools):
IFS=$'\n' read -ra sorted_cats <<< "$(printf '%s\n' "${!_grps[@]}" | sort)"

# FIXED — reads ALL lines into the array:
mapfile -t sorted_cats < <(printf '%s\n' "${!_grps[@]}" | sort)
```

---

### `lib/aliases.sh`

**Purpose:** Inject/remove DevOps shell aliases.

**Block marker used in RC files:**
```bash
# >>> devsetup aliases >>>
alias dk='docker'
...
# <<< devsetup aliases <<<
```

**Supported shells:** bash (`~/.bashrc`), zsh (`~/.zshrc`), fish (`~/.config/fish/config.fish`)

**Key functions:**
- `inject_aliases CONF_FILE` — injects block into detected RC file
- `remove_aliases` — removes the marker block from all RC files
- `preview_aliases CONF_FILE` — shows what would be injected (dry-run)

---

### `lib/scaffold.sh`

**Purpose:** Create a standardised DevOps project folder structure.

**Key functions:**
- `scaffold_project CONF_FILE DEST_DIR` — creates all folders from `folders.conf`
- `scaffold_interactive CONF_FILE` — prompts for project name, then scaffolds
- `preview_scaffold CONF_FILE` — shows tree without creating

---

## 7. All 36 Tools

### DevOps & Containers

| Tool | Installer method | Notes |
|---|---|---|
| `docker` | Official GPG key + Docker repo | Adds user to `docker` group; enables service |
| `kubectl` | Binary from `dl.k8s.io/release/stable.txt` | Detects CPU arch (amd64/arm64) |
| `helm` | Official `get-helm-3` script | |
| `k9s` | GitHub releases binary | Detects arch |
| `minikube` | Binary from GitHub | |

### Infrastructure as Code

| Tool | Installer method |
|---|---|
| `terraform` | HashiCorp GPG key + apt/dnf/pacman repo |
| `ansible` | `apt-add-repository ppa:ansible/ansible` or dnf install |
| `vagrant` | HashiCorp repo |

### Cloud CLIs

| Tool | Installer method |
|---|---|
| `awscli` | Official AWS bundle (`awscli-exe-linux-x86_64.zip`) |
| `gcloud` | Google Cloud apt/rpm repo |
| `azure` | Official install script from Microsoft |

### Web Servers

| Tool | Installer method |
|---|---|
| `nginx` | `_pkg_install nginx` + enable service |
| `apache` | `_pkg_install apache2` / `httpd` + enable service |

### PHP Ecosystem

| Tool | Installer method |
|---|---|
| `php` | `_pkg_install php` |
| `phpfpm` | `_pkg_install php-fpm` + enable service |
| `composer` | Official PHP Composer installer script |

### Databases

| Tool | Installer method |
|---|---|
| `mysql` | `_pkg_install mysql-server` + enable service |
| `postgresql` | `_pkg_install postgresql` + enable service |
| `redis` | `_pkg_install redis-server` + enable service |
| `mongodb` | MongoDB official GPG key + repo |

### Version Control

| Tool | Installer method |
|---|---|
| `git` | `_pkg_install git` |
| `gh` | GitHub CLI official repo (apt/dnf/pacman) |

### Languages & Runtimes

| Tool | Installer method |
|---|---|
| `nvm` | Official nvm install script (user install, not sudo) |
| `python` | `_pkg_install python3 python3-pip python3-venv` |
| `golang` | Binary tarball from `go.dev/dl` |
| `rust` | `rustup.rs` official installer |

### CLI Utilities

| Tool | Installer method |
|---|---|
| `fzf` | `_pkg_install fzf` or GitHub binary |
| `bat` | GitHub binary release (detects arch) |
| `eza` | GitHub binary release |
| `ripgrep` | `_pkg_install ripgrep` |
| `jq` | `_pkg_install jq` |
| `yq` | GitHub binary release |
| `httpie` | `_pkg_install httpie` |
| `tmux` | `_pkg_install tmux` |
| `neovim` | `_pkg_install neovim` (or AppImage for old distros) |
| `btop` | `_pkg_install btop` or binary |

---

## 8. Config Files

### `config/tools.conf`

Format: `CATEGORY:TOOL_NAME` (one per line, `#` for comments)

```
DevOps:docker
DevOps:kubectl
...
Database:mysql
```

Each `TOOL_NAME` **must** have a corresponding `install_TOOL_NAME()` function in `lib/install.sh`.

### `config/aliases.conf`

Format: `alias name='command'` (standard bash alias syntax)

Injected as a block between markers into the user's RC file.

Includes 40+ aliases for: docker, kubectl, git, terraform, ansible, SSH, and general navigation.

### `config/folders.conf`

Format: one directory path per line (relative to project root)

Used by `scaffold_project` to `mkdir -p` each entry.

---

## 9. Packaging

### Building the .deb

```bash
# Full build command (used in CI / manual build):
rm -rf /tmp/devsetup-build
mkdir -p /tmp/devsetup-build/DEBIAN \
         /tmp/devsetup-build/usr/bin \
         /tmp/devsetup-build/usr/share/devsetup/lib \
         /tmp/devsetup-build/usr/share/devsetup/config

# Patch paths and install main binary
sed -e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"/usr/share/devsetup\"|" \
    -e "s|^LIB_DIR=.*|LIB_DIR=\"\${DEVSETUP_DIR}/lib\"|" \
    -e "s|^CONF_DIR=.*|CONF_DIR=\"\${DEVSETUP_DIR}/config\"|" \
    devsetup | install -m 755 /dev/stdin /tmp/devsetup-build/usr/bin/devsetup

# Copy libs and config
install -m 644 lib/*.sh  /tmp/devsetup-build/usr/share/devsetup/lib/
install -m 644 config/*  /tmp/devsetup-build/usr/share/devsetup/config/

# Generate control file from template
sed -e "s|@@VERSION@@|1.1.0|g" ... packaging/debian/control.template \
    > /tmp/devsetup-build/DEBIAN/control

dpkg-deb --build --root-owner-group /tmp/devsetup-build devsetup_1.1.0_all.deb
```

### control.template fields

| Field | Value |
|---|---|
| `Package` | `devsetup` |
| `Version` | `@@VERSION@@` |
| `Architecture` | `all` (pure bash, no compiled code) |
| `Depends` | `bash (>= 4.0), curl, git` |
| `Recommends` | `whiptail | dialog, fzf` |
| `Replaces` | `devsetup (<< @@VERSION@@)` |
| `Conflicts` | `devsetup (<< 1.0.0)` |

### prerm

Runs on `remove`, `purge`, and `upgrade`. On remove/purge: strips alias blocks from `.bashrc`/`.zshrc`. On upgrade: removes legacy `/usr/local/bin/devsetup` if present.

### postinst

Runs on `configure` and `upgrade`. Makes all `lib/*.sh` executable. Removes legacy binary if both paths coexist.

---

## 10. Version History

### v1.0.0 — Initial release
- Basic tool installation (Docker, kubectl, Terraform, Git, Node.js, Python)
- Simple menu using `whiptail`
- Basic logging

### v1.0.1 — Expanded tools + curl installer
- Added nginx, apache, PHP stack, databases (mysql, postgresql, redis, mongodb)
- Added cloud CLIs (awscli, gcloud, azure)
- Added `install.sh` one-liner curl installer
- First `.deb` package

### v1.0.2 — TUI improvements + auto-detection
- Added OS auto-detection for Fedora/Arch
- Better error messages during install
- `--git-config` wizard
- `--aliases` shell alias injection (40+ aliases)
- `--scaffold` project folder creator

### v1.0.3 — Production polish (major overhaul)
- Added lock file (`flock`) — prevents concurrent runs
- Added Ctrl+C handler (`_on_abort` trap) — restores terminal, prints partial summary
- Added `--doctor` pre-flight command
- Added `--status` version table
- Added `--dry-run` mode across all commands
- Added step counter `[1/4] Installing…`
- Added summary box at end of install
- Added retry + exponential backoff for curl downloads
- Added apt lock wait (up to 60s)
- Pure-bash arrow-key TUI written (initial version)
- Added `--update` and `--uninstall` commands
- `.deb` packaging with `packaging/debian/` directory
- All 36 tools verified

### v1.0.4 — TUI backend fix
- **Bug:** whiptail was auto-detected but category separator args (`--- [Cloud] ---`) broke whiptail's checklist (wrong arg count → silent crash)
- **Fix:** Removed separator entries from whiptail backend args
- **Fix:** Changed default backend from "auto-detect whiptail first" to **pure-bash always** (works in sudo, SSH, tmux, any terminal)
- whiptail/dialog/fzf available via `DEVSETUP_TUI=whiptail devsetup`

### v1.0.5 — TUI all-categories fix + full audit
- **Bug (critical):** `IFS=$'\n' read -ra arr <<< "multiline"` only reads the **first line** — so TUI showed only the first category (`Cloud` = 3 tools: awscli, gcloud, azure)
- **Fix:** Replaced all 3 occurrences with `mapfile -t arr < <(...)` which correctly reads all lines
- **Fix:** Pre-computed install status cache in `_tui_bash` — `command -v` now runs once at startup instead of on every keypress × every visible tool (major memory/CPU reduction)
- **Fix:** `_print_help` changed from `cat <<EOF` heredoc to `printf` — heredoc with `"\033"` color vars prints literal backslash text; `printf` handles it correctly
- **Fix:** `install.sh` completely rewritten — OS detection, internet check, PATH fix, sanity checks, correct version
- **Fix:** `check_internet` was being called with `2>/dev/null` in pre-flight, hiding its ✔/✘ output from the user
- `README.md` updated with v1.0.5 badge and new TUI backends table

### v1.1.0 — New commands & polish
- Added `--export` / `--import` to save and restore selected tools
- Added `--log` viewer for recent install logs
- Added `--self-update` to pull the latest script from GitHub
- Improved doctor checks (bash version, low-memory warning)
- Improved TUI performance and key bindings; better status display
- Curl installer and Makefile updated for version 1.1.0 `.deb` builds

---

## 11. Bugs Found & Fixed

### Bug 1: Garbage text in `--help` (v1.0.3 → v1.0.3 fix)

**Symptom:** `devsetup --help` showed `\033[1m` as literal text instead of bold.

**Root cause:** Color variables defined as `"\033[0m"` (double-quotes). In bash, `"\033"` is NOT an escape sequence — it's a literal backslash-0-3-3. When substituted into a `cat <<EOF` heredoc, the terminal sees the literal 7 characters, not the ESC byte.

**Fix:** Changed all definitions to `$'\033[0m'`. With `$'...'` syntax, bash processes the octal at assignment time, storing the actual ESC byte (0x1B).

---

### Bug 2: TUI not appearing (v1.0.3 → v1.0.4)

**Symptom:** Running `devsetup` showed pre-flight then immediately exited with "No tools selected."

**Root cause:** whiptail was auto-detected as backend. The checklist args included category separators:
```bash
args+=("--- [Cloud] ---" "" "OFF")  # 3 args for separator
args+=("awscli" "Cloud" "OFF")      # 3 args for tool
```
Whiptail checklist requires exactly `tag description state` per item. The separator used `""` as description which corrupted the arg count, causing whiptail to crash/exit silently (rc=1 → empty output → "No tools selected").

**Also:** When running as root with `sudo devsetup`, the pure-bash TUI couldn't overwrite the whiptail-detected backend.

**Fix:** Default backend changed to pure-bash. Whiptail separator rows removed.

---

### Bug 3: TUI shows only 3 packages (v1.0.4 → v1.0.5)

**Symptom:** After v1.0.4, TUI appeared but only showed 3 tools (awscli, gcloud, azure).

**Root cause:** `IFS=$'\n' read -ra sorted_cats <<< "multiline_string"` in bash processes the herestring as a single-line read. The `read` command reads until the first `\n` (record separator), then uses `IFS` to split fields. With `IFS=$'\n'`, the read stops at the first newline, so `sorted_cats` = `("Cloud")` — only ONE category (alphabetically first: Cloud). Cloud has exactly 3 tools.

```bash
# This was the broken line (read only captures "Cloud"):
IFS=$'\n' read -ra sorted_cats <<< "$(printf '%s\n' "${!_grps[@]}" | sort)"
```

**Fix:**
```bash
# mapfile reads ALL lines:
mapfile -t sorted_cats < <(printf '%s\n' "${!_grps[@]}" | sort)
```

This bug existed in 3 places in `tui.sh`.

---

### Bug 4: install.sh path rewrite incomplete (v1.0.2 → v1.0.3)

**Symptom:** After curl install, `devsetup` couldn't find its lib files.

**Root cause:** `install.sh` only patched `DEVSETUP_DIR=` with sed, but the new script has `LIB_DIR=` and `CONF_DIR=` as separate lines after it. Those lines weren't being rewritten, so they remained as relative paths (`"$DEVSETUP_DIR/lib"` evaluated in the wrong location).

**Fix:** sed now patches all three lines:
```bash
sed \
  -e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"/usr/share/devsetup\"|" \
  -e "s|^LIB_DIR=.*|LIB_DIR=\"\${DEVSETUP_DIR}/lib\"|" \
  -e "s|^CONF_DIR=.*|CONF_DIR=\"\${DEVSETUP_DIR}/config\"|"
```

---

### Bug 5: Old .deb not replaced on upgrade (v1.0.1 → v1.0.3)

**Symptom:** `dpkg -i devsetup_1.0.3_all.deb` while v1.0.1 was installed showed a conflict.

**Root cause:** `control.template` had no `Replaces:` or `Conflicts:` fields. dpkg had no information that this package replaces older versions.

**Fix:** Added to `control.template`:
```
Replaces: devsetup (<< @@VERSION@@)
Conflicts: devsetup (<< 1.0.0)
```

Also, curl installs placed binary in `/usr/local/bin/devsetup` while deb placed it in `/usr/bin/devsetup` — both coexisted. Fixed in `prerm` (removes legacy binary on upgrade) and `postinst` (removes it after install if both exist).

---

*Documentation generated for devsetup v1.1.0 — 2026-03-03*
