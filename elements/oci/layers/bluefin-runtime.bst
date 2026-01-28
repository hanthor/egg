kind: compose

build-depends:
- oci/layers/bluefin-stack.bst

config:
  exclude:
  - devel
  - debug
  - static-blocklist
