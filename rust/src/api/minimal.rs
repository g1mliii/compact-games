#[flutter_rust_bridge::frb(sync)]
pub fn init_app() -> String {
    let mut builder =
        env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn"));
    builder.format_timestamp_millis();
    builder.try_init().ok();
    if let Err(e) = rayon::ThreadPoolBuilder::new()
        .num_threads(num_cpus::get().min(8))
        .build_global()
    {
        log::warn!("Failed to configure global thread pool: {e}");
    }
    log::info!("PressPlay core initialized");
    String::from("PressPlay core ready")
}
