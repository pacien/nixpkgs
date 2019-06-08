{ config, pkgs, lib, ... }:

with lib;

let
  dataDir = "/var/lib/matrix-appservice-irc";
in {
  options = {
    services.matrix-appservice-irc = {
      enable = mkEnableOption "a Node.js IRC bridge for Matrix";

      port = mkOption {
        type = types.port;
        default = 9999; # from https://github.com/matrix-org/matrix-appservice-irc/blob/0.12.0/README.md#4-running
        description = ''
          Port number on which the bridge should listen for internal communication with the Matrix homeserver.
        '';
      };

      config = mkOption rec {
        type = types.attrs;
        apply = recursiveUpdate default;
        default = {
          ircService = {
            databaseUri = "nedb://${dataDir}/data";
            passwordEncryptionKeyPath = "${dataDir}/passkey.pem";
          };
        };
        example = literalExample ''
          {
            homeserver = {
              url = "http://localhost:8008";
              domain = "localhost";
            };
            ircService.servers = {
              "irc.example.com" = {
                name = "ExampleNet";
                dynamicChannels.groupId = "+myircnetwork:localhost";
              };
            };
          }
        '';
        description = ''
          <filename>config.yaml</filename> configuration as a Nix attribute set.

          Configuration options should match those described in
          <link xlink:href="https://github.com/matrix-org/matrix-appservice-irc/blob/0.12.0/config.sample.yaml">
          config.sample.yaml</link>.

          Secret tokens should be specified using <option>environmentFile</option>
          instead of this world-readable attribute set.
        '';
      };

      localpart = mkOption {
        type = types.string;
        default = "ircbot";
        description = ''
          The user ID localpart to assign to the application service bot.
        '';
      };

      homeserverService = mkOption {
        type = types.nullOr types.string;
        default = "matrix-synapse.service";
        description = ''
          Matrix homeserver service to wait for when starting the application service.
        '';
      };
    };
  };

  config = let
    cfg = config.services.matrix-appservice-irc;
    configFile = pkgs.writeText "matrix-appservice-irc-config.json" (builtins.toJSON cfg.config);
    registrationFile = pkgs.runCommand "matrix-appservice-irc-registration.yaml" { preferLocalBuild = true; } ''
      ${pkgs.nodePackages.matrix-appservice-irc}/bin/matrix-appservice-irc \
        --generate-registration \
        --url='http://localhost:${toString cfg.port}' \
        --config='${configFile}' \
        --localpart='${cfg.localpart}' \
        --file="$out"
    '';
  in mkIf cfg.enable {
    systemd.services.matrix-appservice-irc = {
      description = "Node.js IRC bridge for Matrix.";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ] ++ optional (cfg.homeserverService != null) cfg.homeserverService;
      after = [ "network-online.target" ] ++ optional (cfg.homeserverService != null) cfg.homeserverService;

      preStart = ''
        if [ ! -f '${cfg.config.ircService.passwordEncryptionKeyPath}' ]; then
          echo "Generating password encryption key..."
          ${pkgs.openssl}/bin/openssl genpkey \
            -out '${cfg.config.ircService.passwordEncryptionKeyPath}' \
            -outform PEM \
            -algorithm RSA \
            -pkeyopt rsa_keygen_bits:4096
        fi
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.nodePackages.matrix-appservice-irc}/bin/matrix-appservice-irc \
            --file='${registrationFile}' \
            --config='${configFile}' \
            --port='${toString cfg.port}'
        '';
        Restart = "always";
        DynamicUser = true;
        StateDirectory = baseNameOf dataDir;
      };
    };

    # TODO: define a common option to be used by all future Matrix homeserver implementations
    # instead of assuming the use of Synapse.
    services.matrix-synapse.app_service_config_files = [ registrationFile ];
  };

  meta.maintainers = with maintainers; [ pacien ];
}

