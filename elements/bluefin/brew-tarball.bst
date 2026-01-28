kind: manual

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

runtime-depends:
- bluefin/brew.bst

sources:
- kind: remote
  url: github_files:ublue-os/packages/releases/download/homebrew-2026-01-27-01-30-36/homebrew-x86_64.tar.zst
  ref: e644c70109eae00a01d2a6b09dc08ba5697e88cddb63fee035d6b127187b88ef
variables:
  strip-binaries: ''

config:
  install-commands:
  - |
    mkdir -p "%{install-root}%{datadir}"
    mv homebrew-x86_64.tar.zst "%{install-root}%{datadir}/homebrew.tar.zst"
  - |
    %{install-extra}
