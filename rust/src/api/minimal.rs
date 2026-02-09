/// Smoke-test function exposed to Dart via flutter_rust_bridge.
/// Replace with real API surface as features land.
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello from PressPlay, {name}!")
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_app() -> String {
    env_logger::try_init().ok();
    log::info!("PressPlay core initialized");
    String::from("PressPlay core ready")
}
