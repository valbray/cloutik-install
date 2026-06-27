# Cloutik Deployment Suite

Welcome to the official deployment repository for **Cloutik**, the MikroTik Fleet Management Solution.
This repository contains the automated scripts required to install, configure, and launch the Cloutik On-Premise stack.

Cloutik is deployed as a self-contained Docker stack on a single server or virtual machine.

## 📋 Prerequisites

Before running the installation, ensure your server meets the following requirements:

* **CPU:** 4-6 vCPUs / cores
* **RAM:** 8-12 GB
* **OS:** Ubuntu 20.04 / 22.04 / 24.04 (recommended) or Debian 11 / 12
* **Permissions:** root access or a user with `sudo` privileges
* **Git:** required to clone this repository
* **Domain name:** a domain pointing to your server's public IP (required for automatic SSL)
* **Public IP** with the following ports open:

    | Port | Usage |
    |------|-------|
    | `80` / `443` | Web interface (HTTP / HTTPS) |
    | `1194/tcp` | Device VPN tunnel |
    | `5014/udp` | Device log ingestion |

## 🚀 Installation (first time)

Run the wizard **once** on a fresh server. It checks dependencies, retrieves your
access credentials, configures your instance (`.env`) and, at the end, **offers to
launch the stack for you**.

```bash
# 1. Clone the repository
git clone https://github.com/valbray/cloutik-install.git
cd cloutik-install

# 2. Make the scripts executable
chmod +x install.sh start.sh update.sh

# 3. Run the installation wizard
./install.sh
```

## The three scripts

| Script | When to use | What it does |
|--------|-------------|--------------|
| `install.sh` | **Once**, on first setup | Configures the instance (credentials, domain, `.env`) and offers to launch at the end |
| `start.sh` | To **(re)launch** later | Pulls the images and brings all containers up — use it after a reboot, a stop, or any time you need to start the stack |
| `update.sh` | To **change version** | Moves the instance to a new version, then restarts |

So in practice: you only run `install.sh` **the first time**. Afterwards you use
`start.sh` to bring the stack back up, and `update.sh` to upgrade.

```bash
./start.sh     # (re)launch the stack
./update.sh    # upgrade to a new version
```

> To stop the stack: `docker compose down` (from this directory).
