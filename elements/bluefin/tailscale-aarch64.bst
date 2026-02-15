kind: manual

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

sources:
  - kind: tar
    url: github_files:tailscale/tailscale/releases/download/v1.94.2/tailscale_1.94.2_arm64.tgz
    ref: 76300e808c57eb7853090d69c8bd8806e86341862e244183f6611f9105799bba

variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      install -Dm755 -t "%{install-root}%{bindir}" tailscale tailscaled
    - |
      sed -e 's|/usr/sbin/tailscaled|/usr/bin/tailscaled|g' \
          -e '/^EnvironmentFile=/d' \
          systemd/tailscaled.service > tailscaled.service.patched
      install -Dm644 -t "%{install-root}%{indep-libdir}/systemd/system" tailscaled.service.patched
      mv "%{install-root}%{indep-libdir}/systemd/system/tailscaled.service.patched" \
         "%{install-root}%{indep-libdir}/systemd/system/tailscaled.service"
    - |
      install -Dm644 /dev/stdin "%{install-root}%{indep-libdir}/systemd/system-preset/80-tailscale.preset" <<'PRESET'
      enable tailscaled.service
      PRESET
    - |
      %{install-extra}
