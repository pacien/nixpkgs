{ pkgs, stdenv, yarn2nix-moretea, fetchFromGitHub,
  makeWrapper, makeDesktopItem,
  electron_5, riot-web }:

# Notes for maintainers:
# * versions of `riot-web` and `riot-desktop` should be kept in sync.
# * the Yarn dependency expression must be updated with `./update-riot-desktop.sh <git release tag>`

let
  executableName = "riot-desktop";
  version = "1.3.3";
  riot-web-src = fetchFromGitHub {
    owner = "vector-im";
    repo = "riot-web";
    rev = "v${version}";
    sha256 = "1nzzxcz4r9932cha80q1bzn1425m67fsl89pn7n7ybrv6y0jnxpc";
  };

in yarn2nix-moretea.mkYarnPackage rec {
  name = "riot-desktop-${version}";
  inherit version;

  src = "${riot-web-src}/electron_app";

  packageJSON = ./riot-desktop-package.json;
  yarnLock = ./riot-desktop-yarndeps.lock;
  yarnNix = ./riot-desktop-yarndeps.nix;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    # resources
    mkdir -p "$out/share/riot"
    ln -s '${riot-web}' "$out/share/riot/webapp"
    cp -r '${riot-web-src}/origin_migrator' "$out/share/riot/origin_migrator"
    cp -r '.' "$out/share/riot/electron"

    # icons
    for icon in $out/share/riot/electron/build/icons/*.png; do
      mkdir -p "$out/share/icons/hicolor/$(basename $icon .png)/apps"
      ln -s "$icon" "$out/share/icons/hicolor/$(basename $icon .png)/apps/riot.png"
    done

    # desktop item
    mkdir -p "$out/share"
    ln -s "${desktopItem}/share/applications" "$out/share/applications"

    # executable wrapper
    makeWrapper '${electron_5}/bin/electron' "$out/bin/${executableName}" \
      --add-flags "$out/share/riot/electron"
  '';

  # Do not attempt generating a tarball for riot-web again.
  # note: `doDist = false;` does not work.
  distPhase = ''
    true
  '';

  # The desktop item properties should be kept in sync with data from upstream:
  # * productName and description from
  #   https://github.com/vector-im/riot-web/blob/develop/electron_app/package.json
  # * category and StartupWMClass from the build.linux section of
  #   https://github.com/vector-im/riot-web/blob/develop/package.json
  desktopItem = makeDesktopItem {
    name = "riot";
    exec = executableName;
    icon = "riot";
    desktopName = "Riot";
    genericName = "Matrix Client";
    comment = meta.description;
    categories = "Network;InstantMessaging;Chat;";
    extraEntries = ''
      StartupWMClass="riot"
    '';
  };

  meta = with stdenv.lib; {
    description = "A feature-rich client for Matrix.org";
    homepage = https://about.riot.im/;
    license = licenses.asl20;
    maintainers = with maintainers; [ pacien worldofpeace ];
    inherit (electron_5.meta) platforms;
  };
}
