# Development

Build Wiggle from source. It needs macOS 14 (Sonoma) or later and the Swift toolchain.

```sh
git clone https://github.com/marcboeker/wiggle.git && cd wiggle && make run
```

`make run` builds, ad-hoc signs, and opens `build/Wiggle.app`.

## Make targets

| Target | Action |
| --- | --- |
| `make build` | Compile without bundling. |
| `make bundle` | Build, assemble, and sign `build/Wiggle.app`. |
| `make run` | Stop any running copy, bundle, and open it. |
| `make stop` | Quit a running copy. |
| `make install` | Stop any running copy, bundle, and copy it to `/Applications` (or `~/Applications` if `/Applications` is not writable). Set `INSTALL_DIR` to override. |
| `make test` | Run the unit tests. |
| `make logs` | Stream the app's log messages. |
| `make permissions` | Open Privacy & Security → Accessibility. |
| `make clean` | Remove all build output. |

`SIGN_ID` picks the codesigning identity `make bundle` uses; unset, it auto-detects an Apple
Development identity or falls back to an ad hoc signature (`-`, what CI and a release use).
