use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(super) struct UnsupportedReportRecord {
    pub(super) active: bool,
    pub(super) first_reported_at_ms: u64,
    pub(super) activated_at_ms: u64,
    pub(super) last_reported_at_ms: u64,
    pub(super) last_withdrawn_at_ms: Option<u64>,
    pub(super) report_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(super) struct UnsupportedSyncMeta {
    pub(super) install_id: Option<String>,
    pub(super) reporter_token: Option<String>,
    pub(super) last_prepared_at_ms: Option<u64>,
    pub(super) last_prepared_app_version: Option<String>,
    pub(super) last_prepared_payload_hash: Option<String>,
    pub(super) last_submitted_at_ms: Option<u64>,
    pub(super) last_submitted_payload_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(super) struct UnsupportedReportCandidate {
    pub(super) folder_name: String,
    pub(super) first_reported_at_ms: u64,
    pub(super) active_since_ms: u64,
    pub(super) last_reported_at_ms: u64,
    pub(super) last_withdrawn_at_ms: Option<u64>,
    pub(super) report_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(super) struct UnsupportedReportPayload {
    pub(super) install_id: String,
    pub(super) app_version: String,
    pub(super) generated_at_ms: u64,
    pub(super) reports: Vec<UnsupportedReportCandidate>,
}

#[derive(Debug, Serialize)]
pub(super) struct UnsupportedReportPayloadFingerprint<'a> {
    pub(super) install_id: &'a str,
    pub(super) app_version: &'a str,
    pub(super) reports: &'a [UnsupportedReportCandidate],
}

#[derive(Debug, Deserialize)]
pub(super) struct UnsupportedSubmissionResponse {
    #[serde(alias = "reporterId")]
    pub(super) reporter_id: Option<String>,
}

#[derive(Clone, Copy)]
pub(super) enum SaveTarget {
    Community,
    UserReported,
    ReportRecords,
}
