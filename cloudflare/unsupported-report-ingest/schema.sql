CREATE TABLE IF NOT EXISTS client_submissions (
    install_id TEXT PRIMARY KEY,
    app_version TEXT NOT NULL,
    generated_at_ms INTEGER NOT NULL,
    submitted_at_ms INTEGER NOT NULL,
    report_count INTEGER NOT NULL,
    CHECK(length(install_id) BETWEEN 1 AND 64),
    CHECK(length(app_version) BETWEEN 1 AND 64),
    CHECK(generated_at_ms >= 0),
    CHECK(submitted_at_ms >= 0),
    CHECK(report_count >= 0)
);

CREATE TABLE IF NOT EXISTS client_reports (
    install_id TEXT NOT NULL,
    folder_name TEXT NOT NULL,
    app_version TEXT NOT NULL,
    first_reported_at_ms INTEGER NOT NULL,
    active_since_ms INTEGER NOT NULL,
    last_reported_at_ms INTEGER NOT NULL,
    last_withdrawn_at_ms INTEGER,
    report_count INTEGER NOT NULL,
    payload_generated_at_ms INTEGER NOT NULL,
    submitted_at_ms INTEGER NOT NULL,
    PRIMARY KEY (install_id, folder_name),
    CHECK(length(install_id) BETWEEN 1 AND 64),
    CHECK(length(folder_name) BETWEEN 1 AND 160),
    CHECK(length(app_version) BETWEEN 1 AND 64),
    CHECK(first_reported_at_ms >= 0),
    CHECK(active_since_ms >= 0),
    CHECK(last_reported_at_ms >= 0),
    CHECK(last_withdrawn_at_ms IS NULL OR last_withdrawn_at_ms >= 0),
    CHECK(report_count >= 1),
    CHECK(payload_generated_at_ms >= 0),
    CHECK(submitted_at_ms >= 0)
);

CREATE TABLE IF NOT EXISTS client_report_history (
    install_id TEXT NOT NULL,
    folder_name TEXT NOT NULL,
    first_server_seen_at_ms INTEGER NOT NULL,
    last_server_seen_at_ms INTEGER NOT NULL,
    server_submission_count INTEGER NOT NULL,
    PRIMARY KEY (install_id, folder_name),
    CHECK(length(install_id) BETWEEN 1 AND 64),
    CHECK(length(folder_name) BETWEEN 1 AND 160),
    CHECK(first_server_seen_at_ms >= 0),
    CHECK(last_server_seen_at_ms >= 0),
    CHECK(server_submission_count >= 1)
);

CREATE TABLE IF NOT EXISTS client_submission_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    install_id TEXT NOT NULL,
    submitted_at_ms INTEGER NOT NULL,
    report_count INTEGER NOT NULL,
    CHECK(length(install_id) BETWEEN 1 AND 64),
    CHECK(submitted_at_ms >= 0),
    CHECK(report_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_client_submissions_submitted_at
    ON client_submissions(submitted_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_submissions_submitted_report_count
    ON client_submissions(submitted_at_ms DESC, report_count);

CREATE INDEX IF NOT EXISTS idx_client_reports_folder_submission
    ON client_reports(folder_name, submitted_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_reports_submission_folder
    ON client_reports(submitted_at_ms DESC, folder_name);

CREATE INDEX IF NOT EXISTS idx_client_reports_submission_install
    ON client_reports(submitted_at_ms DESC, install_id);

CREATE INDEX IF NOT EXISTS idx_client_reports_folder_version_submission
    ON client_reports(folder_name, app_version, submitted_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_reports_folder_last_reported
    ON client_reports(folder_name, last_reported_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_report_history_folder_last_seen
    ON client_report_history(folder_name, last_server_seen_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_report_history_install_last_seen
    ON client_report_history(install_id, last_server_seen_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_submission_history_install_submitted_at
    ON client_submission_history(install_id, submitted_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_client_submission_history_submitted_at
    ON client_submission_history(submitted_at_ms DESC);
