kind: stack

(?):
- arch == "x86_64":
    depends:
      - bluefin/tailscale-x86_64.bst
- arch == "aarch64":
    depends:
      - bluefin/tailscale-aarch64.bst
