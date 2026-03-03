# =============================================================================
#  Makefile — devsetup build & packaging helpers
# =============================================================================
NAME        := devsetup
VERSION     := 1.1.0
ARCH        := all
MAINTAINER  := akashpurjalkar66@gmail.com <[EMAIL_ADDRESS]>
DESCRIPTION := DevOps bootstrapper — interactive installer for Docker, kubectl, Terraform, AWS CLI, Helm, Node.js, Python, Git and more.

PREFIX      ?= /usr/local
BINDIR      := $(PREFIX)/bin
SHAREDIR    := $(PREFIX)/share/$(NAME)

DEB_DIR     := packaging/debian
BUILD_DIR   := /tmp/$(NAME)-build
DEB_FILE    := $(NAME)_$(VERSION)_$(ARCH).deb

# ── Local install (no packaging) ─────────────────────────────────────────────
.PHONY: install
install:
	@echo "→ Installing $(NAME) to $(BINDIR) ..."
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(SHAREDIR)/lib
	install -d $(DESTDIR)$(SHAREDIR)/config
	sed \
		-e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"$(SHAREDIR)\"|" \
		-e "s|^LIB_DIR=.*|LIB_DIR=\"\$${DEVSETUP_DIR}/lib\"|" \
		-e "s|^CONF_DIR=.*|CONF_DIR=\"\$${DEVSETUP_DIR}/config\"|" \
		devsetup | install -m 755 /dev/stdin $(DESTDIR)$(BINDIR)/$(NAME)
	install -m 644 lib/*.sh   $(DESTDIR)$(SHAREDIR)/lib/
	chmod +x $(DESTDIR)$(SHAREDIR)/lib/*.sh
	install -m 644 config/*   $(DESTDIR)$(SHAREDIR)/config/
	@echo "✔  Installed: $(BINDIR)/$(NAME)"

# ── Uninstall ─────────────────────────────────────────────────────────────────
.PHONY: uninstall
uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/$(NAME)
	rm -rf $(DESTDIR)$(SHAREDIR)
	@echo "✔  Uninstalled $(NAME)"

# ── Build .deb package ────────────────────────────────────────────────────────
.PHONY: deb
deb: clean-build
	@echo "→ Building .deb package: $(DEB_FILE)"

	# Stage directory tree (mirroring what dpkg-deb expects)
	install -d $(BUILD_DIR)/DEBIAN
	install -d $(BUILD_DIR)/usr/bin
	install -d $(BUILD_DIR)/usr/share/$(NAME)/lib
	install -d $(BUILD_DIR)/usr/share/$(NAME)/config
	install -d $(BUILD_DIR)/usr/share/doc/$(NAME)

	# Binary (with DEVSETUP_DIR patched to installed location)
	sed \
		-e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"/usr/share/$(NAME)\"|" \
		-e "s|^LIB_DIR=.*|LIB_DIR=\"\$${DEVSETUP_DIR}/lib\"|" \
		-e "s|^CONF_DIR=.*|CONF_DIR=\"\$${DEVSETUP_DIR}/config\"|" \
		devsetup | install -m 755 /dev/stdin $(BUILD_DIR)/usr/bin/$(NAME)

	# Lib & config
	install -m 644 lib/*.sh   $(BUILD_DIR)/usr/share/$(NAME)/lib/
	chmod +x $(BUILD_DIR)/usr/share/$(NAME)/lib/*.sh
	install -m 644 config/*   $(BUILD_DIR)/usr/share/$(NAME)/config/

	# Docs
	install -m 644 README.md  $(BUILD_DIR)/usr/share/doc/$(NAME)/

	# DEBIAN control files
	sed \
		-e "s|@@VERSION@@|$(VERSION)|g" \
		-e "s|@@ARCH@@|$(ARCH)|g" \
		-e "s|@@MAINTAINER@@|$(MAINTAINER)|g" \
		-e "s|@@DESCRIPTION@@|$(DESCRIPTION)|g" \
		$(DEB_DIR)/control.template > $(BUILD_DIR)/DEBIAN/control

	install -m 755 $(DEB_DIR)/postinst $(BUILD_DIR)/DEBIAN/postinst 2>/dev/null || true
	install -m 755 $(DEB_DIR)/prerm    $(BUILD_DIR)/DEBIAN/prerm    2>/dev/null || true

	# Build the .deb
	dpkg-deb --build --root-owner-group $(BUILD_DIR) $(DEB_FILE)
	@echo ""
	@echo "✔  Package ready: $(DEB_FILE)"
	@echo "   Install with:  sudo apt install ./$(DEB_FILE)"

# ── Quick local install of the .deb ──────────────────────────────────────────
.PHONY: deb-install
deb-install: deb
	sudo apt install ./$(DEB_FILE)

# ── Clean ─────────────────────────────────────────────────────────────────────
.PHONY: clean-build
clean-build:
	rm -rf $(BUILD_DIR)

.PHONY: clean
clean: clean-build
	rm -f $(DEB_FILE)

# ── Lint / syntax check ───────────────────────────────────────────────────────
.PHONY: lint
lint:
	@echo "→ bash -n checks..."
	@bash -n devsetup && echo "  devsetup: OK"
	@for f in lib/*.sh; do bash -n "$$f" && echo "  $$f: OK"; done
	@echo "✔  All syntax checks passed"

# ── Smoke test (dry-run mode) ─────────────────────────────────────────────────
.PHONY: test
test: lint
	@echo ""
	@echo "→ Running smoke tests..."
	@bash devsetup --version | grep -q "devsetup" && echo "  --version: OK"     || echo "  --version: FAIL"
	@bash devsetup --help > /dev/null 2>&1        && echo "  --help: OK"        || echo "  --help: FAIL"
	@bash devsetup --list > /dev/null 2>&1        && echo "  --list: OK"        || echo "  --list: FAIL"
	@bash devsetup --doctor > /dev/null 2>&1;                                      echo "  --doctor: OK (ran)"
	@DRY_RUN=true bash devsetup --install git > /dev/null 2>&1 && echo "  --dry-run --install: OK" || echo "  --dry-run --install: FAIL"
	@bash devsetup --preview-aliases > /dev/null 2>&1  && echo "  --preview-aliases: OK"  || echo "  --preview-aliases: FAIL"
	@bash devsetup --preview-scaffold > /dev/null 2>&1 && echo "  --preview-scaffold: OK" || echo "  --preview-scaffold: FAIL"
	@echo "✔  Smoke tests done"

# ── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo ""
	@echo "  devsetup Makefile targets:"
	@echo ""
	@echo "    make install      Install to $(PREFIX)/bin  (default PREFIX)"
	@echo "    make uninstall    Remove installed files"
	@echo "    make deb          Build a .deb package ($(DEB_FILE))"
	@echo "    make deb-install  Build + install the .deb via apt"
	@echo "    make lint         Run bash -n syntax checks"
	@echo "    make clean        Remove build artifacts"
	@echo ""
	@echo "  Override install prefix:"
	@echo "    make install PREFIX=/usr"
	@echo ""
