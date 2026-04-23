# Copyright (c) 2026 lightjunction
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# External Makefile for hello-dkms
KDIR ?= /lib/modules/$(shell uname -r)/build

# Generate version.h from dkms.conf so MODULE_VERSION is sourced from a single place.
PKG_VER := $(shell sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' dkms.conf)
VERSION_H := $(PWD)/version.h

all: $(VERSION_H)
	$(MAKE) -C $(KDIR) M=$(PWD) modules

$(VERSION_H):
	printf '#define MODULE_VERSION_STRING "%s"\n' "$(PKG_VER)" > $(VERSION_H)

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	-rm -f $(VERSION_H)
