# Linux setup options

Three ways to get a Linux prompt for your OpenClaw build. Option 1 is recommended.

---

## Option 1: Hostinger VPS (recommended) — $14.99/mo

A dedicated server that runs 24/7. Your agents keep working while you sleep.

1. Go to [hostinger.com](https://hostinger.com) and create an account
2. Choose a VPS plan — the **2 vCPU / 8 GB RAM** tier at $14.99/mo with no commitment works well
3. Select **Ubuntu 24.04** as the operating system
4. Choose a data center close to you
5. Set a root password during setup
6. Once provisioned (2-3 min), SSH in: `ssh root@<your-server-ip>` (the IP is shown in your Hostinger dashboard)
7. Install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
8. After authenticating, note the Tailscale IP: `tailscale ip -4`
9. From now on, connect via the Tailscale IP instead of the public IP

**Pros:** Always on, dedicated resources, agents run 24/7.
**Cons:** $15/mo. Worth it once you have agents doing real work.

---

## Option 2: Windows — WSL (Windows Subsystem for Linux)

If you have a Windows 10 or 11 machine, you already have Linux available.

1. Open PowerShell as Administrator
2. Run: `wsl --install`
3. Restart your computer when prompted
4. After restart, a terminal window opens asking you to create a username and password
5. You now have Ubuntu running. Verify with: `lsb_release -a`
6. Install Tailscale inside WSL:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

**Pros:** Free, no monthly cost, fast to set up.
**Cons:** Only runs when your laptop is open. Agents stop when you close the lid.

---

## Option 3: Mac — dual-boot with Linux

Give Linux its own partition so it runs natively alongside macOS.

### Intel Macs

1. Back up your Mac with Time Machine first
2. Open **Disk Utility** (Applications > Utilities > Disk Utility)
3. Select your main drive (usually "Macintosh HD") and click **Partition**
4. Click **+** to add a partition. Set the size to 25% of your total disk (e.g., 250 GB on a 1 TB drive). Name it "Linux" and format it as **MS-DOS (FAT)** — the Ubuntu installer will reformat it
5. Click Apply and wait for the partition to complete
6. Download Ubuntu 24.04 Desktop from [ubuntu.com/download/desktop](https://ubuntu.com/download/desktop)
7. Create a bootable USB drive:
   ```bash
   # On macOS, find the USB device name
   diskutil list
   # Flash the ISO (replace diskN with your USB device)
   sudo dd if=~/Downloads/ubuntu-24.04-desktop-amd64.iso of=/dev/rdiskN bs=1m
   ```
8. Restart your Mac and hold the **Option (⌥)** key at boot
9. Select the USB drive (shows as "EFI Boot")
10. In the Ubuntu installer, choose **"Something else"** for installation type
11. Select the partition you created, set it to ext4, mount point `/`, and install
12. After install, hold **Option (⌥)** at boot to choose between macOS and Ubuntu

### Apple Silicon Macs (M1/M2/M3/M4)

Apple Silicon doesn't support traditional dual-boot. Your best options:

- **Asahi Linux** ([asahilinux.org](https://asahilinux.org)) — native Linux on Apple Silicon. Run `curl https://alx.sh | sh` from macOS Terminal and it handles the partitioning for you. Set the partition to 25% of your disk when prompted.
- **UTM** ([mac.getutm.app](https://mac.getutm.app)) — free virtual machine app. Create an Ubuntu VM with 25% of your disk allocated. Not a true dual-boot but runs Linux at near-native speed on Apple Silicon.

### After installing Linux (either Mac type)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

**Pros:** Free, native performance, full Linux environment.
**Cons:** Setup takes 30-60 minutes. Agents stop when the machine sleeps. Reboot required to switch OSes (Intel) or log out to free resources (Asahi).

---

## After you have a Linux prompt (all options)

Two commands to bootstrap, then Claude Code handles the rest.

### Step 1: Bootstrap (installs Node.js + Claude Code)

```bash
curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash
```

### Step 2: Authenticate

```bash
claude login
```

Follow the browser link to authenticate with your Anthropic account.

### Step 3: Let Claude Code do the rest

```bash
claude
```

Once Claude Code is running, paste this prompt:

> Install the OpenClaw framework from https://github.com/mikeengleai/openclaw-framework.git — clone it to ~/openclaw-framework, run the install.sh script, then install all system dependencies (python3, python3-pip, python3-venv, sqlite3, tmux, curl, jq, tailscale). After everything is installed, run "cw" to verify the workspace manager works.

Claude Code will install everything, configure your PATH, and verify the setup. You just approve the commands as it goes.
