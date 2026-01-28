kind: manual

sources:
- kind: git_repo
  url: github:projectbluefin/common.git
  track: main
  ref: v2026.01-122-gd5ab4f23ff3cfde86fb619f5cf87f0bb2f24da33
- kind: git_module
  url: github:projectbluefin/branding/
  path: bluefin-branding
  ref: f5213ca61615bb79a8315fc4c5378a80ca93922e

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- freedesktop-sdk.bst:components/sed.bst

variables:
  strip-binaries: ''

config:
  install-commands:
#   - install -Dm644 -t "%{install-root}%{sysconfdir}/" etc/*
#   - install -Dm644 -t "%{install-root}%{sysconfdir}/" etc/*
  - |
    HARDCODED_MONTH="12"
    CURRENT_MONTH=$(date +%m)
    sed -i "/picture-uri/ s/${HARDCODED_MONTH}/${CURRENT_MONTH}/g" "system_files/bluefin/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override"

    cp -r system_files/bluefin/usr/./ "%{install-root}%{prefix}/"
    cp -r system_files/shared/usr/./ "%{install-root}%{prefix}/"
    cp -r system_files/bluefin/etc/./ "%{install-root}%{sysconfdir}/"
    cp -r system_files/shared/etc/./ "%{install-root}%{sysconfdir}/"
    cp -r bluefin-branding/system_files/etc/./ "%{install-root}%{sysconfdir}/"
  - "%{install-extra}"
