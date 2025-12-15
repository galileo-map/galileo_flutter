````markdown

## Galileo flutter integration

### Architecture
- core logic in `./rust`
- interop functions and types under `./rust/api`
- flutter abstractions in `./lib`

### How to build
1. Rust obviously.
2. Install Flutter 3.29 (should probably work for any recent version) from https://docs.flutter.dev/install/archive.
3. If you change anything related to the Rust interop with Flutter, you'd need to install `flutter_rust_bridge` and run:
   ```bash
   flutter_rust_bridge_codegen generate
````

### Run the example app

1. `cd ./example && flutter run` — you'd need to use the desktop variant when prompted (not the web one).

### Run integration tests

1. Ensure you are in the `example` directory:

   ```bash
   cd ./example
   ```
2. Run the tests using `flutter test` (recommended):

   ```bash
   flutter test integration_test/galileo_stability_test.dart
   ```

   or run all integration tests:

   ```bash
   flutter test integration_test
   ```
3. Alternatively, for desktop targets, you can run with `flutter drive`:

   ```bash
   flutter drive \
     --driver=test_driver/integration_test.dart \
     --target=integration_test/galileo_stability_test.dart \
     -d linux
   ```
4. Watch the logs — successful runs should report all tests passed, and you’ll see the Galileo map session logs.

**Note:** Make sure the `integration_test` folder exists and contains your test files. The `flutter drive` command relies on `test_driver/integration_test.dart` as the driver entry point.

```
