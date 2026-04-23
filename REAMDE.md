<!--
  ~ Copyright (c) 2026 lightjunction
  ~
  ~ This program is free software: you can redistribute it and/or modify
  ~ it under the terms of the GNU General Public License as published by
  ~ the Free Software Foundation, either version 3 of the License, or
  ~ (at your option) any later version.
-->

# hello-dkms

A minimal DKMS "Hello World" module .

## 1. Setup Source Directory
DKMS requires the source to be in `/usr/src/<name>-<version>`.
```bash
# paru -S direnv 
# Clone the repo and move to the standard location
git clone https://github.com/lightjunction/hello-dkms.git

```

## 2. Install Dependencies
```bash
# Install DKMS and headers 
sudo pacman -S base-devel dkms linux-headers
```

## 3. Build and Install
```bash
# Add, build and install the module
sudo dkms add -m hello-dkms -v 1.0
sudo dkms build -m hello-dkms -v 1.0
sudo dkms install -m hello-dkms -v 1.0
```

## 4. Verify
```bash
# Load module and check logs
sudo modprobe hello_dkms
sudo dmesg | tail -n 1
# or
journalctl -k | tail -n 1

```

## 5. Remove
```bash
sudo dkms remove -m hello-dkms -v 1.0 --all
```
