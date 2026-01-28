# FIXME: could be an import element instead?
kind: manual

sources:
# - kind: git_repo
#   url: github:ublue-os/artwork.git
#   track: main
- kind: tar
  url: github_files:ublue-os/artwork/releases/download/bluefin-v2025-12-14/bluefin-wallpapers-gnome.tar.zstd
  ref: 5c243462d74bf4a1fa60659972f2fdf45fd16b226bd2d4f7c2d27701176d5eb6
  base-dir: '' 

build-depends:
- freedesktop-sdk.bst:components/sed.bst
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ''

config:
  install-commands:
  - | 
    sed -i 's|~\/\.local\/share|\/usr\/share|' *.xml gnome-background-properties/*.xml
    mkdir -p "%{install-root}%{datadir}/backgrounds/bluefin"
    cp -r *.jxl *.xml "%{install-root}%{datadir}/backgrounds/bluefin"
    cp -r gnome-background-properties "%{install-root}%{datadir}/gnome-background-properties"
  - "%{install-extra}"
