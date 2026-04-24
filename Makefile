# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

export LLVM=1
export CC=clang

# External Makefile for hello-dkms
KDIR ?= /lib/modules/$(shell uname -r)/build

.PHONY: all clean compdb format check-format install uninstall update print-vars load unload reload

# Generate version.h from dkms.conf so MODULE_VERSION is sourced from a single place.
PKG_VER := $(shell sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf)
PKG_NAME := $(shell sed -n 's/^PACKAGE_NAME="\([^"]*\)".*/\1/p' dkms.conf)
BUILT_MODULE_NAME := $(shell sed -n 's/^BUILT_MODULE_NAME\[0\]="\([^"]*\)".*/\1/p' dkms.conf)

VERSION_H := $(PWD)/version.h

all: $(VERSION_H)
	$(MAKE) -C $(KDIR) M=$(PWD) modules

$(VERSION_H):
	printf '#define MODULE_VERSION_STRING "%s"\n' "$(PKG_VER)" > $(VERSION_H)

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	-rm -f $(VERSION_H)

compdb:
	bear -- make

format:
	find . -name '*.c' -o -name '*.h' | xargs clang-format -i

check-format:
	@echo "check format..."
	@find . -name '*.c' -o -name '*.h' -exec clang-format -output-replacements-xml {} \; | \
		grep -q "<replacement " && \
		(echo "format error, please run make format"; exit 1) || \
		echo "format OK"

print-vars:
	@echo "BUILT_MODULE_NAME = $(BUILT_MODULE_NAME)"
	@echo "PKG_NAME        = $(PKG_NAME)"
	@echo "PKG_VER         = $(PKG_VER)"

install:
	. scripts/dkms-helper.bash; \
	dki

uninstall:
	. scripts/dkms-helper.bash; \
	dkrm

update:
	. scripts/dkms-helper.bash; \
	dku

load:
	sudo modprobe $(BUILT_MODULE_NAME) || $(MAKE) install
	journalctl -k -f
unload:
	sudo modprobe -r $(BUILT_MODULE_NAME) || echo "loaded?"
	journalctl -k -f
reload:
	$(MAKE) unload; \
	$(MAKE) load;
	journalctl -k -f
