# Historical Prompts

## Rewrite `kaya-firefox` to `kaya-wxt` to support all browsers

Read and follow the instructions in [@PLAN.md](file:///home/steven/work/deobald/kaya-firefox/doc/plan/PLAN.md).

Port the entire project found at [@kaya-firefox](file:///home/steven/work/deobald/kaya-firefox/) to [WXT](https://wxt.dev/) in **this repository** with the intention of supporting all major browsers.

### Browser Support

* Firefox
* Chrome
* Edge
* Chromium-based browsers (Opera, Brave, Ungoogled Chromium, SRWare Iron, Iridium, Vivaldi, Arc, Sidekick, DuckDuckGo Browser, etc.)
* Safari
* Orion
* Epiphany

Because Safari, Orion, and Epiphany are "outliers" in terms of extension support, they can be handled with separate plans. Safari, in particular, will require an entirely separate packaging strategy as a MacOS app.

### Operating System Support & Packaging

Because `kaya-firefox` uses a native host to provide direct access to disk, and all browsers will require this same support, it is important that each browser extension has proper packaging for all 3 major operating systems:

* Windows (`.msi` via `cargo-wix` via `cargo-dist`)
* MacOS (`.pkg` via `cargo-packager` via `cargo-dist`)
* Linux, which has 3 major native packaging formats, and from-source:
  * RPM (`.rpm` via `cargo-generate-rpm` via `cargo-dist`)
  * DEB (`.deb` via `cargo-deb` via `cargo-dist`)
  * AUR (`PKGBUILD` via `cargo-aur` directly, consuming `cargo-dist` output)
  * `install.sh` for users who want to install from source

The native host Rust crate can receive a `--install` flag and then use the `install()` function from the `native_messaging` crate to assist with placing JSON files in specific browser folders.

### Automation: CI/CD

The `kaya-firefox` repo currently has a `.github/workflows/sign-extension.yml` GitHub Actions workflow that does some of the above work. All packages for all 6 distribution targets (Windows, MacOS, RPM, DEB, AUR, `./install.sh`) should be built automatically by GitHub Actions. Any signing, notarizing, etc. should also happen in the GitHub Actions workflow(s).
