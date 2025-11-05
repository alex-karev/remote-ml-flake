{
  description = "Declarative SSH + Rclone dev environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    ##################
    #    Settings    #
    ##################
    name = "ml";
    packages = pkgs: with pkgs; [];
    shellHook = pkgs: ''
    '';
    environment = pkgs: {
      TERM = "xterm-256color";
    };

    ##################
    # Implementation #
    ##################
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    lib = nixpkgs.lib;
    forEachSystem = lib.genAttrs supportedSystems;
  in {
    devShells = forEachSystem (system: let
      pkgs = import nixpkgs {inherit system;};

      # Initialize the environment
      loadEnv = exit: ''
        set -e
        if [ -f ./.server.env ]; then
          set -a
          source ./.server.env
          set +a
        else
          echo "⚠️  .server.env not found!"
          echo "Run \"server setup\" to create it"
          ${lib.optionalString exit "exit 1"}
        fi
        SSH_KEY=$(eval echo $SSH_KEY)
        LOCAL_PATH=$(pwd)
      '';

      # Base ssh command
      sshBase = "${pkgs.openssh}/bin/ssh -p \"$REMOTE_PORT\" -i \"$SSH_KEY\" \"$REMOTE_USERNAME@$REMOTE_SERVER\"";

      cdProject = "mkdir -p $REMOTE_PATH && cd $REMOTE_PATH || exit 1";

      # Check second argument
      checkArg = action: ''
        if [ -z "$2" ]; then
          echo "Usage: server ${action} <filename>"
          exit 1
        fi
        FILENAME="$2"
      '';

      # Define actions
      actions = {
        setup = {
          description = "Set connection to the server";
          cmd = ''
            set -euo pipefail
            read -rp "Server name or IP: " REMOTE_SERVER
            read -rp "Port (default 22): " REMOTE_PORT
            REMOTE_PORT=''${REMOTE_PORT:-22}
            read -rp "Username (default root): " REMOTE_USERNAME
            REMOTE_USERNAME=''${REMOTE_USERNAME:-root}
            read -rp "Path to SSH key (default ~/.ssh/id_rsa): " SSH_KEY
            SSH_KEY=''${SSH_KEY:-~/.ssh/id_rsa}
            echo "REMOTE_SERVER=$REMOTE_SERVER
            REMOTE_PORT=$REMOTE_PORT
            REMOTE_USERNAME=$REMOTE_USERNAME
            SSH_KEY=$SSH_KEY
            REMOTE_PATH=${name}" > .server.env
            echo "✅ Configuration saved to .server.env"
          '';
        };

        sshkey = {
          description = "Copy ssh id to the server";
          cmd = ''
            ${loadEnv true}
            ${pkgs.openssh}/bin/ssh-copy-id -i $SSH_KEY $REMOTE_USERNAME@$REMOTE_SERVER
          '';
        };

        command = {
          description = "Run command on server and check results";
          hasArgs = true;
          cmd = ''
            ${loadEnv true}
            if [ -z "$2" ]; then
              echo "Usage: server command <command>"
              exit 1
            fi
            COMMAND="''${@:2}"
            ${sshBase} -t "${cdProject}; bash -l -c \"$COMMAND\""
          '';
        };

        push = {
          description = "Sync current project → remote";
          cmd = ''
            ${loadEnv true}
            echo "🚀 Syncing local → remote..."
            touch .rclone-ignore
            if [ -d .git ]; then
              git ls-files --others --ignored --exclude-standard > .rclone-ignore
            fi
            ${pkgs.rclone}/bin/rclone sync --log-level ERROR --transfers 16 --checkers 8 \
              --sftp-use-insecure-cipher --sftp-disable-hashcheck \
              --exclude '*.log' --exclude '*.nix' --exclude '*.env' \
              --exclude '.git*' --exclude 'flake.lock' --exclude 'README.md' \
              --exclude '.rclone-ignore' --exclude-from .rclone-ignore \
              -P "$LOCAL_PATH" ":sftp,host=$REMOTE_SERVER,user=$REMOTE_USERNAME,port=$REMOTE_PORT,key_file=$SSH_KEY:$REMOTE_PATH"
            rm -f .rclone-ignore
          '';
        };

        pull = {
          description = "Download a file from server";
          hasArgs = true;
          cmd = ''
            ${loadEnv true}
            ${checkArg "pull"}
            echo "💾 Downloading $FILENAME..."
            ${pkgs.openssh}/bin/scp -i $SSH_KEY -P $REMOTE_PORT -r $REMOTE_USERNAME@$REMOTE_SERVER:$REMOTE_PATH/$FILENAME ./
          '';
        };

        ssh = {
          description = "Open SSH shell";
          cmd = ''
            ${loadEnv true}
            echo "🔗 Connecting to $REMOTE_USERNAME@$REMOTE_SERVER..."
            ${sshBase} -t "${cdProject}; bash -l"
          '';
        };

        run = {
          description = "Run script in background on remote";
          hasArgs = true;
          cmd = ''
            ${loadEnv true}
            ${checkArg "run"}
            echo "🚀 Running $FILENAME in background on server..."
            ${sshBase} "${cdProject}
              chmod +x ./$FILENAME
              echo \"Output being logged to: $REMOTE_PATH/$FILENAME.log\"
              nohup bash -l -c \"./$FILENAME > ./$FILENAME.log 2>&1 &\""
          '';
        };

        pkill = {
          description = "Kill process on server";
          hasArgs = true;
          cmd = ''
            ${loadEnv true}
            ${checkArg "pkill"}
            echo "💀 Killing process $FILENAME on server..."
            ${sshBase} "pkill $FILENAME"
          '';
        };

        logs = {
          description = "Show logs of a script";
          hasArgs = true;
          cmd = ''
            ${loadEnv true}
            ${checkArg "logs"}
            echo "📊 Checking $FILENAME logs on server..."
            ${sshBase} "cat $REMOTE_PATH/$FILENAME.log 2>/dev/null || echo 'No log file found'"
          '';
        };

        tail = {
          description = "Follow logs in real time";
          hasArgs = true;
          cmd = ''
            ${loadEnv true}
            ${checkArg "tail"}
            echo "📜 Tailing $FILENAME.log on server (Ctrl+C to stop)..."
            ${sshBase} "tail -f $REMOTE_PATH/$FILENAME.log"
          '';
        };
      };

      # Generate case arms from the actions object
      actionCases =
        builtins.concatStringsSep "\n"
        (lib.mapAttrsToList
          (name: value: ''
            ${name})
              ${value.cmd}
              ;;
          '')
          actions);

      # Generate help text dynamically
      helpText = builtins.concatStringsSep "\n" (
        lib.mapAttrsToList
        (name: value: let
          args =
            if value.hasArgs or false
            then "<argument> "
            else "";
        in "      server ${name} ${args}— ${value.description}")
        (actions // {help.description = "Show help message";})
      );

      # Generate help action
      helpAction = ''
        echo "Usage: server <action> [argument]"
        echo
        echo "Available actions:"
        echo "${helpText}"
        exit 1
        ;;
      '';

      # Create bash script
      server = pkgs.writeShellScriptBin "server" ''
        #!${pkgs.bash}/bin/bash
        ACTION="$1"
        case "$ACTION" in
          ${actionCases}
          help)
          ${helpAction}
          *)
          ${helpAction}
        esac
      '';

      # Generate env variables
      envString = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: value: "export ${name}=\"${toString value}\""
        ) (
          if ((environment pkgs) != null)
          then environment pkgs
          else {}
        )
      );
    in {
      default = pkgs.mkShell {
        inherit name;
        packages = [server] ++ packages pkgs;
        shellHook = ''
          ${envString}
          echo "🔧 Loading settings from .server.env..."
          ${loadEnv false}
          if [[ -v REMOTE_SERVER ]]; then
            echo "🔗 Server: $REMOTE_USERNAME@$REMOTE_SERVER:$REMOTE_PORT"
            echo "🔑 SSH key: $SSH_KEY"
            echo "📂 Local path: $LOCAL_PATH"
            echo "📦 Remote path: ~/$REMOTE_PATH"
          fi
          echo
          echo "✅ Commands:"
          echo "${helpText}"
          ${lib.optionalString ((shellHook pkgs) != null) shellHook pkgs}
          echo
        '';
      };
    });

    templates = {
      default = {
        path = ./.;
        description = "SSH + Rclone dev environment";
        welcomeText = ''
          # SSH + Rclone Dev Environment
          Get started:
          1. Edit the top part of "flake.nix". Set project name, description, shell attributes.
          2. Run "nix develop" to enter the shell.
          3. Run "server setup" to setup connection.
          4. Use "server help" to list available commands
        '';
      };
    };

    checks = forEachSystem (system: {
      basic-check = self.devShells.${system}.default;
    });
  };
}
