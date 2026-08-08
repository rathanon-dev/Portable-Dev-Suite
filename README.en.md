# 🚀 Portable Dev Suite

> **Zero System Footprint, Fully Portable Development Environment for Windows**
> A modern, isolated development environment with automated dependency management for Python, Git, CUDA, and cuDNN. No installation required.

---

## 📌 Overview

**Portable Dev Suite** is designed to solve the complexities of environment setups on Windows. It provides a robust, portable ecosystem that prevents global namespace pollution, registry modifications, and dependency conflicts on the host machine.

Perfect for running AI models, complex Python workloads, and applications that require precise CUDA/cuDNN acceleration without breaking your main OS.

## ✨ Key Features

- **Zero System Footprint:** Operates 100% in a portable mode. Does not modify Windows Registry or global Environment Variables.
- **Automated GPU Acceleration:** Smart extraction and PATH injection for CUDA and cuDNN runtime DLLs.
- **Triple-Tier Download Engine:** Built-in fallback mechanisms using Aria2 $\rightarrow$ cURL $\rightarrow$ Native PowerShell.
- **Local CDN Proxy Support:** Automatically detects TCP proxies on the local network to cache large binary files and bypass rate limits.
- **Isolated Python & Git:** Runs dedicated instances of Python and Git to prevent conflicts with host installations.

## 🛠️ Technical Specifications

- **OS Compatibility:** Windows 10 / Windows 11 (64-bit)
- **Core Engine:** Windows PowerShell 5.1 (Native compatibility)
- **Architecture:** 100% Portable (Relative pathing via `$PSScriptRoot`)

## 🚀 Quick Start

1. **Clone or Download** the repository to your preferred location.
2. **Double-click `start.bat`** to initialize the environment and launch the Live Shell.
3. Once inside the Live Shell, use the `setup` alias to manage your environment:

```powershell
# Run System & Hardware Diagnostics
.\setup.ps1 -c

# Show Command Reference
.\setup.ps1 -h

# Install the complete AI Stack (Python, Git, CUDA, cuDNN) silently
.\setup.ps1 -i all -y

# Install a specific CUDA version
.\setup.ps1 -i cuda -v 12.8
```

## 📦 Project Structure

```text
Portable-Dev-Suite/
├── tools/                # Downloaded toolchains (Python, Git, CUDA, cuDNN)
├── workspace/            # Your project files and working directory
├── auto-install.bat      # One-click bootstrapper and shortcut creator
├── setup.ps1             # Core dependency resolution engine
└── start.bat             # Environment initializer and Live Shell entry point
```

## 📄 License & Author

- **Developer:** [rathanon-dev](https://github.com/rathanon-dev)
- **License:** MIT License
