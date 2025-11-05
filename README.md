# SSH + Rclone ML Development Environment

A declarative Nix flake for machine learning development on remote servers using SSH and Rclone synchronization.

## Features

- ⚡ **Zero server-side setup** - Requires no installation or configuration on the remote server beyond standard SSH key access.
- 🔄 **One-way sync and download** - Sync your local ML projects to remote servers and selectively download remote files using scp.
- 🚀 **Background script execution** - Run training scripts in the background and monitor logs
- 📦 **Declarative environment** - Reproducible local development environment using Nix
- 🖥️ **Multi-platform** - Supports Linux and macOS (x86_64 and ARM64)
- 🔐 **SSH integration** - Secure shell access with automatic configuration 

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- Remote server with SSH access
- SSH key for authentication

### Installation

1. **Initialize the project:**

   ```bash
   nix flake init -t github:alex-karev/remote-ml-flake
   ```

2. **Configure your project:**
   
   ```bash
   nvim flake.nix
   ```

   Edit the top part of `flake.nix` for your project (local packages, environment variables and etc.)


3. **Enter the development environment:**
   
   ```bash
   nix develop
   ```

4. **Setup connection:**
   
   ```bash
   server setup
   ```

   (Optionaly) you may need to copy your ssh id to the remote server if your provider doesn't do this for you:

   ```bash
   server sshkey
   ```

   You may need to enter the password.

   `server setup` saves environment variables needed for other scripts into gitignored `.server.env` file. 

   You can repeat this step if you change your server.

## Usage

Once inside the development environment, you have access to these commands:

```
server help — Show help message
server setup — Setup connection to the server
server sshkey — Run ssh-copy-id and send your public key to the server
server command <command> — Run command on server and check the output
server logs <filename> — Show logs of a script
server pkill <filename> — Kill process on server
server pull <filename> — Download a file from server
server push — Sync current project → remote
server run <filename> — Run script in background on remote
server ssh — Open SSH shell
server tail <filename> — Follow logs in real time
```

## Example ML Workflow

1. **Develop locally** - Write your ML code on your local machine
2. **Sync to remote** - Use `server push` to sync code to GPU server
3. **Run training** - Use `server run train.py` to start training
4. **Monitor progress** - Use `server logs train.py` to read logs or `server tail train.py` to monitor logs real-time
5. **Iterate** - Repeat as needed


## Motivation

I was tired of using Jupyter for machine learning on remote GPUs, and was looking for quick and simple solution for running my training scripts on on-demand servers over ssh without any server-side setup.

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.
