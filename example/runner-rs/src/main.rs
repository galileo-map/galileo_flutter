// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

use std::{env, path::PathBuf, process::ExitCode};

use flutter_shell_winit::{ShellConfig, run_application};
use galileo_flutter_example::register_application;

fn main() -> ExitCode {
    let Some(assets_path) = env::args_os().nth(1).map(PathBuf::from) else {
        eprintln!("usage: galileo_flutter_example <flutter-assets-directory>");
        return ExitCode::FAILURE;
    };
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    // build.rs resolves Cargo's PROFILE and forwards it via cargo::rustc-env
    // so this matches the engine directory build.rs linked against, rather
    // than relying on cfg!(debug_assertions) which can diverge from PROFILE.
    let profile = env!("FLUTTER_RS_PROFILE");
    let icu_data_path = manifest_dir
        .join("../.dart_tool/flutter_rs/sdk/lib")
        .join(profile)
        .join("icudtl.dat");
    let aot_library_path = if profile == "debug" {
        String::new()
    } else {
        assets_path.join("app.so").to_string_lossy().into_owned()
    };
    match run_application(
        ShellConfig {
            assets_path: assets_path.to_string_lossy().into_owned(),
            icu_data_path: icu_data_path.to_string_lossy().into_owned(),
            aot_library_path,
            ..ShellConfig::default()
        },
        register_application,
    ) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("failed to run galileo_flutter_example: {error}");
            ExitCode::FAILURE
        }
    }
}
