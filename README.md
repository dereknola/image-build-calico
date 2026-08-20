# rancher/image-build-calico

This repo builds hardened, statically-linked Go binaries from
[projectcalico/calico](https://github.com/projectcalico/calico) and packages them in a minimal
SLE BCI ([bci-minimal](https://registry.suse.com/repositories/bci-bci-minimal-16-0)) based image.

Binaries are compiled against [`rancher/hardened-build-base`](https://github.com/rancher/image-build-base),
which provides the latest supported Go toolchain (FIPS/BoringCrypto-enabled on amd64).


## Public Images produced

- `rancher/hardened-calico` — main calico binary

## PRIME Images produced
- `rancher/hardened-calico-ctl` — calicoctl binary
- `rancher/hardened-calico-typha` — calico-typha binary
- `rancher/hardened-calico-pod2daemon-flexvol` — calico pod2daemon-flexvol binary
