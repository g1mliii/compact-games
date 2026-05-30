-- Drop indexes that are not used by the Worker query paths.
-- This reduces D1 write amplification for accepted submissions.
DROP INDEX IF EXISTS idx_client_submissions_submitted_at;
DROP INDEX IF EXISTS idx_client_reports_folder_name;
DROP INDEX IF EXISTS idx_client_reports_submitted_at;
DROP INDEX IF EXISTS idx_client_reports_folder_version_submission;
DROP INDEX IF EXISTS idx_client_reports_folder_last_reported;
DROP INDEX IF EXISTS idx_client_report_history_folder_last_seen;
DROP INDEX IF EXISTS idx_client_report_history_install_last_seen;
