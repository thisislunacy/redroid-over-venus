> [!IMPORTANT]
> For educational purposes only. Do not use this for commercial project.

# Requirements
- **nvidia-drm.modeset=1**: required for `dmabuf` to work;
- **nvidia-open** kernel modules, not proprietary, version **595.71+** (**610.xx** is recommended);
- **psi=1** in kernel parameters;
- **binder_linux** (binderfs) in kernel modules;
- Available **/dev/udmabuf** (`boot.kernelModules = [ "udmabuf" ];` on **NixOS**);
- Nix package manager

The `venus.service` daemon checks the driver version, udmabuf, and modeset at runtime before initialization — before launching redroid, verify via journalctl that the preflight check hasn't produced any errors.

# How to use outside of NixOS?
The repository contains only [NixOS](https://nixos.org/download/) configurations.

# Why Venus instead of the open Mesa stack (nouveau+nvk+zink)?
The open stack for NVIDIA is still fairly young despite its progress. It delivers on average 70–80% of native proprietary driver performance, and it does build for Android via the NDK — but SurfaceFlinger still doesn't handle **zink** and **nvk** properly. Proprietary drivers with open kernel modules (**nvidia-open**) give native performance, and Venus has almost no overhead (see below).

# What's the performance cost?
Venus itself is just a Vulkan command serializer (encoder/decoder), not a source of overhead. The overhead comes from the transport: with classic virtio-gpu on top of a real VM, that means vmenter/vmexit switches between guest and host, plus extra hypervisor layers. In vtest mode (used here), the transport is a lightweight unix-socket IPC on the same host with no VM boundary — which is why overhead stays under 10%.

The path for an x86_64 host looks roughly like this:
```mermaid
flowchart TD
    A["app (ARM64)"] --> B[libhoudini]
    B --> C["x86_64 Vulkan"]
    C --> D["guest Mesa Venus<br/>(vulkan.virtio.so)"]
    D --> E["/dev/venus/venus.sock<br/>(vtest)"]
    E --> F["virgl_test_server<br/>--multi-clients"]
    F --> G[virgl_render_server]
    G --> H[NVIDIA driver]
    H --> I[Your GPU]
    J["gralloc: minigbm (cros)"] --> K[gbm_mesa]
    K --> L["libgbm_mesa_wrapper.so<br/>(vtest)"]
    L --> M["host-side VkImage block-linear<br/>(VCMD_RESOURCE_ALLOC_GPU)"]
```

# Original project
[Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia) is the original project this work is based on — the source of the core patches, and the equivalent project for **waydroid**.

# Contribution
Open an issue and submit a PR if you think something could be improved.

# License
Original code in `/vendor/src` is **MIT**. Files under `/vendor/patches/` are derivative works of their respective upstreams and carry those upstreams' licenses.
