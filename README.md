# Requirements
**nvidia-drm.modeset=1**: required for `dmabuf` to work;
**nvidia-open** kernel modules, not proprietary, version **595.71+** (**610.xx** is recommended);
Available **/dev/udmabuf** (`boot.kernelModules = [ "udmabuf" ];` on **NixOS**);
Nix package manager

The `venus.service` daemon checks the driver version, udmabuf, and modeset at runtime before initialization — before launching redroid, verify via journalctl that the preflight check hasn't produced any errors.

# How to use outside of NixOS?
Install the **Nix** package manager from the official [NixOS](https://nixos.org/download/) website

# Contribution
Open an issue and submit a PR if you think something could be improved.

# License
Licensed under **MIT**.
