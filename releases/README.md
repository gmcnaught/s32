# releases/

Drop target for **`s32.rbf`** and **`s32v25.rbf`**.

This directory does **not** contain a prebuilt bitstream — an RBF is a
synthesized FPGA image and must be produced by Quartus (see
[../docs/BUILD.md](../docs/BUILD.md)). It is intentionally not committed as a
binary blob.

Build locally with `tools\build-s32.bat` and `tools\build-s32v25.bat`.
The qualified wrappers stage both files here after fit, multicorner timing,
assembly, freshness and hash checks pass.

RBFs are git-ignored so local builds do not accidentally commit binaries.
