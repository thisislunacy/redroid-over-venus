# Requirements
**nvidia-drm.modeset=1**: required for `dmabuf` to work;
**nvidia-open** kernel modules, not proprietary, version **595.71+** (**610.xx** is recommended);
Available **/dev/udmabuf** (`boot.kernelModules = [ "udmabuf" ];` on **NixOS**);
Nix package manager

The `venus.service` daemon checks the driver version, udmabuf, and modeset at runtime before initialization — before launching redroid, verify via journalctl that the preflight check hasn't produced any errors.

# How to use outside of NixOS?
Install the **Nix** package manager from the official [NixOS](https://nixos.org/download/) website

# Why Venus instead of the open Mesa stack (nouveau+nvk+zink)?
The open stack for NVIDIA is still fairly young, despite its progress. It delivers on average 70–80% of native proprietary driver performance, builds for Android via the NDK, but SurfaceFlinger still doesn't handle zink and nvk properly. Proprietary drivers with open kernel modules (**nvidia-open**) give native performance, and Venus has almost no overhead (5–10%) due to the lack of virtualization.

```
app (ARM64) → libhoudini → x86_64 Vulkan → guest Mesa Venus (vulkan.virtio.so)
    → /dev/venus/venus.sock (vtest) → virgl_test_server --multi-clients
    → virgl_render_server → NVIDIA driver → Your GPU
gralloc: minigbm (cros) → gbm_mesa → libgbm_mesa_wrapper.so (vtest)
    → host-side VkImage block-linear (VCMD_RESOURCE_ALLOC_GPU)
```

# Contribution
Open an issue and submit a PR if you think something could be improved.

# License
Licensed under **MIT**.
