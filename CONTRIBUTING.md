# Contributing to NotchPal

Thanks for wanting to help!

## Report a bug or suggest an idea

[Open an issue](https://github.com/MohammedSaif29/NotchPal/issues/new/choose). For bugs, please include your Mac model, your macOS version, the NotchPal version (Settings → About), and a screenshot if you can.

## Change the code

1. Fork the repository and make your change on a new branch.
2. Build and test it with `bash Scripts/build-app.sh --run`. You only need the Xcode Command Line Tools.
3. Open a pull request that explains what you changed and why.

A few things that keep NotchPal trustworthy:

- NotchPal never goes online by itself and collects nothing. Changes that add tracking, analytics, ads or network calls won't be accepted.
- Keep the copyright header at the top of each file.
- Swift note: on macOS 27, SwiftUI's `@State` needs a macro plugin that only full Xcode has, so NotchPal stores view state as `State(initialValue:)` values instead. Please follow that pattern.

## Licence

NotchPal is licensed under the GNU GPLv3. By sending a pull request, you agree that your contribution is licensed under the GPLv3 too. The NotchPal name and icon aren't part of that licence; see [TRADEMARKS.md](TRADEMARKS.md).
