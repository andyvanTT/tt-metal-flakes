## nix flakes

about: nix flakes for tt-metal development on nixOS/nix can be used to replace 
the setup scripts(still needs tt-build) on 

## setup (once)

```bash
sudo cp tenstorrent-hugepages.nix /etc/nixos/
```

add to `/etc/nixos/configuration.nix`:

```nix
imports = [ ./tenstorrent-hugepages.nix ];
hardware.tenstorrent.enable = true;
```

```bash
sudo nixos-rebuild switch 
sudo reboot
```

## run

test build and run
```bash
cd tt-metal
git submodule update --init --recursive
nix develop path:/path/to/tt-metal-dev
tt-doctor
tt-sfpi-link
tt-venv
tt-build
tt-test smoke
```
