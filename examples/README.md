# WASM-4 games

Install a current Roc nightly and WASM-4 2.7.1 or later. From this directory:

```sh
roc build basic/main.roc --target=wasm32 --opt=size --output=basic.wasm
w4 run basic.wasm
```

Build games with `--opt=size` for distribution: WASM-4 carts must fit in 64 KiB.
Use the same commands for `rocci-bird`, `snake` or `sound`.

The repository points these games at the local platform. A release archive
points them at its immutable bundle. Keep all companion modules and data files.
The `support/run-cart.mjs` adapter is for the locked Chromium CI environment;
manual play uses the ordinary WASM-4 CLI above.
