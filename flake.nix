{
  description = "Notion App Electron (version 4.5.0) based on mateushonorato/notion-app-electron-aur";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    notionAur = {
      url = "github:mateushonorato/notion-app-electron-aur?rev=8e24cc590cec0338a88040b24e1c184aa3cefc15";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, notionAur, ... }@inputs:
    let
      mkNotionPackage = pkgsArg: pkgsArg.stdenv.mkDerivation rec {
        pname = "notion-app-electron";
        version = "4.5.0";

        _bettersqlite3ver = "11.8.1";
        _elecronver       = "132";

        notionExe = pkgsArg.fetchurl {
          url = "https://desktop-release.notion-static.com/Notion%20Setup%20${version}.exe";
          sha256 = "decc67442d306d2e680bc47aea37588b1f19ab02f3c0fa8f6c00d5580bc92f45";
        };

        betterSqlite3 = pkgsArg.fetchurl {
          url = "https://github.com/WiseLibs/better-sqlite3/releases/download/v${_bettersqlite3ver}/better-sqlite3-v${_bettersqlite3ver}-electron-v${_elecronver}-linux-x64.tar.gz";
          sha256 = "b79098043fb352c28306d13ec51906f8465f5d176619a40aa75dda0bdffb4542";
        };

        nativeBuildInputs = [
          pkgsArg.p7zip
          pkgsArg.asar
          pkgsArg.makeWrapper
        ];

        buildInputs = [
          pkgsArg.electron_34
          pkgsArg.gcc-unwrapped
          pkgsArg.libglvnd
        ];

        unpackPhase = "true";

        configurePhase = ''
          # Create a temporary plugin directory
          mkdir -p "$PWD/pluginDir"

          # Extract the embedded 7z archive from the Notion Setup exe:
          7z x "${notionExe}" "\$PLUGINSDIR/app-64.7z" -y -bse0 -bso0
          7z x "./\$PLUGINSDIR/app-64.7z" "resources/app.asar" "resources/app.asar.unpacked" -y -bse0 -bso0

          # Extract the ASAR contents into a directory for patching
          asar e resources/app.asar asar_patched

          # Unpack better-sqlite3 tarball and move its binary into place.
          mkdir -p tmp-bs && tar -xf ${betterSqlite3} -C tmp-bs

          cp tmp-bs/build/Release/better_sqlite3.node resources/app.asar.unpacked/node_modules/better-sqlite3/build/Release/

          # Add tray icon
          cp ${notionAur}/notion.png asar_patched/.webpack/main/trayIcon.png

          # Apply sed patches to fix tray icon behavior, fake the user agent, disable auto updates,
          # avoid duplicated instances and use the Windows tray menu:
          sed -i "s|process\.cwd(),\"package\.json\"|\"$out/usr/lib/notion-app/\",\"package.json\"|g" asar_patched/.webpack/main/index.js
          sed -i 's|this.tray.on("click",(()=>{this.onClick()}))|this.tray.setContextMenu(this.trayMenu),this.tray.on("click",(()=>{this.onClick()}))|g' asar_patched/.webpack/main/index.js
          sed -i 's|getIcon(){[^}]*}|getIcon(){return require("path").resolve(__dirname, "trayIcon.png");}|g' asar_patched/.webpack/main/index.js
          sed -i 's|e.setUserAgent(`''${e.getUserAgent()} WantsServiceWorker`),|e.setUserAgent(`''${e.getUserAgent().replace("Linux", "Windows")} WantsServiceWorker`),|g' asar_patched/.webpack/main/index.js
          sed -i 's|if("darwin"===process.platform){const e=l.systemPreferences?.getUserDefault(C,"boolean"),t=_.Store.getState().app.preferences?.isAutoUpdaterDisabled,r=_.Store.getState().app.preferences?.isAutoUpdaterOSSupportBypass,n=(0,v.isOsUnsupportedForAutoUpdates)();return Boolean(e\|\|t\|\|!r&&n)}return!1|return!0|g' asar_patched/.webpack/main/index.js
          sed -i 's|handleOpenUrl);else if("win32"===process.platform)|handleOpenUrl);else if("linux"===process.platform)|g' asar_patched/.webpack/main/index.js
          sed -i 's|async function(){await(0,m.setupObservability)(),|o.app.requestSingleInstanceLock() ? async function(){await(0,m.setupObservability)(),|g' asar_patched/.webpack/main/index.js
          sed -i 's|setupAboutPanel)()}()}()|setupAboutPanel)()}()}() : o.app.quit();|g' asar_patched/.webpack/main/index.js
          sed -i 's|r="win32"===process.platform?function(e,t)|r="linux"===process.platform?function(e,t)|g' asar_patched/.webpack/main/index.js

          # Repack the patched ASAR archive (unpacking *.node files)
          asar p asar_patched app.asar --unpack "*.node"
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/usr/lib/notion-app
          cp app.asar $out/usr/lib/notion-app/
          cp -r resources/app.asar.unpacked $out/usr/lib/notion-app/
          cp -r asar_patched/package.json $out/usr/lib/notion-app/

          mkdir -p $out/bin
          install -Dm755 ${notionAur}/notion-app $out/bin/notion-app
          substituteInPlace $out/bin/notion-app \
            --replace "/usr/lib/notion-app/app.asar" "$out/usr/lib/notion-app/app.asar" \
            --replace "electron33" "${pkgsArg.electron_34}/bin/electron"
            
          wrapProgram $out/bin/notion-app \
            --prefix LD_LIBRARY_PATH : "${pkgsArg.lib.makeLibraryPath [ pkgsArg.gcc-unwrapped.lib pkgsArg.libglvnd ]}" \
            --prefix PATH : "${pkgsArg.lib.makeBinPath [ pkgsArg.gcc-unwrapped ]}"

          mkdir -p $out/usr/share/applications
          install -Dm644 ${notionAur}/notion.desktop $out/share/applications/notion.desktop
          substituteInPlace $out/share/applications/notion.desktop \
            --replace "Exec=notion-app" "Exec=$out/bin/notion-app" \
            --replace "Icon=notion" "Icon=$out/usr/share/icons/hicolor/256x256/apps/notion.png"

          mkdir -p $out/usr/share/icons/hicolor/256x256/apps
          install -Dm644 ${notionAur}/notion.png $out/usr/share/icons/hicolor/256x256/apps/notion.png
          runHook postInstall
        '';
        
        meta = with pkgsArg.lib; {
          description = "Notion App Electron – Your connected workspace for wiki, docs & projects";
          homepage = "https://www.notion.so/desktop";
          license = licenses.unfree;
          platforms = [ "x86_64-linux" ];
        };
      };
    in
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = mkNotionPackage pkgs;
      }
    )) // {
      overlays.default = final: prev: {
        notion-app-electron = mkNotionPackage final;
      };

      package.default = { ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
      };
    };
}
