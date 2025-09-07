PREFIX ?=
BINDIR = $(PREFIX)/sbin
INITRAMFS_TOOLS = $(PREFIX)/etc/initramfs-tools

.PHONY: help install uninstall

help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  install     Show this help message"
	@echo "  uninstall   Show this help message"
	@echo "  help        Show this help message"

install:
	@install -m 755 multipass $(BINDIR)
	@install -m 755 hook.sh $(INITRAMFS_TOOLS)/hooks/multipass
	@install -m 755 script.sh $(INITRAMFS_TOOLS)/scripts/local-premount/multipass

uninstall:
	@rm -f $(BINDIR)/multipipass
	@rm -f $(INITRAMFS_TOOLS)/hooks/multipass
	@rm -f $(INITRAMFS_TOOLS)/scripts/local-premount/multipass
