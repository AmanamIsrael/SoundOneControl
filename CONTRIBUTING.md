# Contributing

Contributions are welcome. Keep changes focused on verified Space One Pro behavior and preserve the separation between protocol, transport, controller, and UI concerns.

Before opening a pull request:

```sh
swift test
swift build -c release
./scripts/build-app.sh
```

Hardware-affecting changes should document the firmware version tested, the original setting, the test change, and confirmation that the original setting was restored. Never experiment with firmware-update commands.

By contributing, you agree that your work is licensed under GPL-3.0-or-later.
