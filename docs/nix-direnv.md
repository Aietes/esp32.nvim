# Nix and direnv

This example makes Neovim inherit an existing ESP-IDF environment whenever you
enter a project. It does not package or install ESP-IDF with Nix.

That distinction avoids a common failure mode: `idf_tools.py install esp-clang`
cannot write tools into an immutable `/nix/store` ESP-IDF checkout.

## Prerequisites

- ESP-IDF installed through EIM or a manual checkout
- Nix with flakes enabled
- [direnv](https://direnv.net/) and
  [nix-direnv](https://github.com/nix-community/nix-direnv)
- the [direnv shell hook](https://direnv.net/docs/hook.html) configured

## File placement

Put both files in the ESP-IDF project root, beside its top-level
`CMakeLists.txt`:

```text
your-project/
├── .envrc
├── CMakeLists.txt
├── flake.nix
├── main/
└── sdkconfig
```

## `flake.nix`

The version name must match the activation script created by EIM:

```nix
{
  description = "ESP-IDF activation shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    nixpkgs.lib.genAttrs
      [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
      (system: {
        devShells.default =
          let
            pkgs = nixpkgs.legacyPackages.${system};
            idfVersion = "v6.0.2";
            eimActivation = "$HOME/.espressif/tools/activate_idf_${idfVersion}.sh";
            manualActivation = "$HOME/esp/esp-idf/export.sh";
          in
          pkgs.mkShell {
            shellHook = ''
              if [ -f "${eimActivation}" ]; then
                source "${eimActivation}"
              elif [ -f "${manualActivation}" ]; then
                source "${manualActivation}"
              else
                echo "ESP-IDF activation script not found." >&2
                echo "Update idfVersion or manualActivation in flake.nix." >&2
                return 1
              fi
            '';
          };
      });
}
```

The development shell intentionally does not add its own CMake, Python, or
toolchains. The ESP-IDF activation script supplies the versions selected for
that installation. Add unrelated project tools to `packages` only when needed.

If you use fish, point the shell hook at a POSIX-compatible activation script
or adapt the activation outside `mkShell`; Nix shell hooks run as shell code and
cannot source fish syntax.

## `.envrc`

```bash
use flake
```

Allow it once:

```bash
direnv allow
```

`nix-direnv` watches `.envrc`, `flake.nix`, and `flake.lock`, so changes reload
the environment. Commit `flake.lock` when the project should use a reproducible
Nixpkgs revision.

## Verify

From the project directory:

```bash
direnv status
idf.py --version
clangd --version
nvim
```

Inside Neovim, run `:ESPInfo`.

If `idf_tools.py install esp-clang` tries to write under `/nix/store`, the active
ESP-IDF still comes from a Nix-packaged checkout. Install `esp-clang` through
that package definition, or use this activation-only approach with a writable
EIM/manual installation.
