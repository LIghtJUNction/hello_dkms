# hello-dkms

A minimal DKMS "Hello World" module .

## 1. Setup Source Directory
DKMS requires the source to be in `/usr/src/<name>-<version>`.
```bash
# Clone the repo and move to the standard location
git clone https://github.com/.../...
sudo cp -r hello-dkms /usr/src/hello-dkms-1.0
cd /usr/src/hello-dkms-1.0
```

## 2. Install Dependencies
```bash
# Install DKMS and headers (CachyOS example)
sudo pacman -S base-devel dkms linux-cachyos-bore-lto-headers
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
