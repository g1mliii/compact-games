function compactSql(sql) {
  return sql.replace(/\s+/g, " ").trim().toLowerCase();
}

function reportKey(installId, folderName) {
  return `${installId}\u0000${folderName}`;
}

class FakeStatement {
  constructor(db, sql) {
    this.db = db;
    this.sql = compactSql(sql);
    this.bindings = [];
  }

  bind(...bindings) {
    this.bindings = bindings;
    return this;
  }

  async first() {
    return this.db.executeFirst(this.sql, this.bindings);
  }

  async all() {
    return { results: this.db.executeAll(this.sql, this.bindings) };
  }

  async run() {
    return this.db.executeWrite(this.sql, this.bindings);
  }
}

export class FakeD1Database {
  constructor() {
    this.clientSubmissions = new Map();
    this.clientReports = new Map();
    this.clientReportHistory = new Map();
    this.clientSubmissionHistory = [];
    this.nextSubmissionHistoryId = 1;
    this.ipSubmissionHistory = [];
    this.nextIpSubmissionHistoryId = 1;
  }

  prepare(sql) {
    return new FakeStatement(this, sql);
  }

  async batch(statements) {
    const results = [];
    for (const statement of statements) {
      results.push(await statement.run());
    }
    return results;
  }

  seedClientSubmission(row) {
    this.clientSubmissions.set(row.install_id, { ...row });
  }

  seedClientReport(row) {
    this.clientReports.set(reportKey(row.install_id, row.folder_name), { ...row });
  }

  seedClientReportHistory(row) {
    this.clientReportHistory.set(reportKey(row.install_id, row.folder_name), { ...row });
  }

  seedClientSubmissionHistory(row) {
    this.clientSubmissionHistory.push({
      id: row.id ?? this.nextSubmissionHistoryId++,
      ...row,
    });
  }

  seedIpSubmissionHistory(row) {
    this.ipSubmissionHistory.push({
      id: row.id ?? this.nextIpSubmissionHistoryId++,
      ...row,
    });
  }

  executeFirst(sql, bindings) {
    if (
      sql.startsWith(
        "select count(*) as cnt from client_submission_history where install_id = ? and submitted_at_ms >= ?",
      )
    ) {
      const [installId, minSubmittedAtMs] = bindings;
      const count = this.clientSubmissionHistory.filter(
        (row) =>
          row.install_id === installId && row.submitted_at_ms >= minSubmittedAtMs,
      ).length;
      return { cnt: count };
    }

    if (
      sql.startsWith(
        "select count(*) as cnt from ip_submission_history where ip = ? and submitted_at_ms >= ?",
      )
    ) {
      const [ip, minSubmittedAtMs] = bindings;
      const count = this.ipSubmissionHistory.filter(
        (row) => row.ip === ip && row.submitted_at_ms >= minSubmittedAtMs,
      ).length;
      return { cnt: count };
    }

    if (
      sql.startsWith(
        "select count(distinct install_id) as cnt from ip_submission_history where ip = ? and is_new_reporter = 1 and submitted_at_ms >= ?",
      )
    ) {
      const [ip, minSubmittedAtMs] = bindings;
      const distinct = new Set(
        this.ipSubmissionHistory
          .filter(
            (row) =>
              row.ip === ip &&
              row.is_new_reporter === 1 &&
              row.submitted_at_ms >= minSubmittedAtMs,
          )
          .map((row) => row.install_id),
      );
      return { cnt: distinct.size };
    }

    if (
      sql.startsWith(
        "select count(*) as active_installs, sum(case when report_count > 0 then 1 else 0 end) as installs_with_reports from client_submissions where submitted_at_ms >= ?",
      )
    ) {
      const [minSubmittedAtMs] = bindings;
      const rows = [...this.clientSubmissions.values()].filter(
        (row) => row.submitted_at_ms >= minSubmittedAtMs,
      );
      return {
        active_installs: rows.length,
        installs_with_reports: rows.filter((row) => row.report_count > 0).length,
      };
    }

    if (
      sql.startsWith(
        "select count(distinct install_id) as unique_reporters from client_reports where submitted_at_ms >= ?",
      )
    ) {
      const [minSubmittedAtMs] = bindings;
      const uniqueReporters = new Set(
        [...this.clientReports.values()]
          .filter((row) => row.submitted_at_ms >= minSubmittedAtMs)
          .map((row) => row.install_id),
      );
      return { unique_reporters: uniqueReporters.size };
    }

    if (
      sql.startsWith(
        "select install_id from client_submissions where install_id = ? limit 1",
      )
    ) {
      const [installId] = bindings;
      const row = this.clientSubmissions.get(installId);
      return row ? { install_id: row.install_id } : null;
    }

    if (
      sql.startsWith(
        "select install_id from client_report_history where install_id = ? limit 1",
      )
    ) {
      const [installId] = bindings;
      const row = [...this.clientReportHistory.values()].find(
        (candidate) => candidate.install_id === installId,
      );
      return row ? { install_id: row.install_id } : null;
    }

    throw new Error(`Unsupported first() query in fake D1: ${sql}`);
  }

  executeAll(sql, bindings) {
    if (
      sql.startsWith(
        "select current.folder_name, count(*) as reporter_count, sum(case when history.server_submission_count >= 2 then 1 else 0 end) as repeat_reporter_count",
      )
    ) {
      const [minSubmittedAtMs, minReporters, minRepeatReporters] = bindings;
      const grouped = new Map();

      for (const current of this.clientReports.values()) {
        if (current.submitted_at_ms < minSubmittedAtMs) {
          continue;
        }

        const history = this.clientReportHistory.get(
          reportKey(current.install_id, current.folder_name),
        );
        if (!history) {
          continue;
        }

        let aggregate = grouped.get(current.folder_name);
        if (!aggregate) {
          aggregate = {
            folder_name: current.folder_name,
            reporter_count: 0,
            repeat_reporter_count: 0,
            total_server_submission_count: 0,
            first_server_seen_at_ms: history.first_server_seen_at_ms,
            last_server_seen_at_ms: history.last_server_seen_at_ms,
            last_current_submission_at_ms: current.submitted_at_ms,
          };
          grouped.set(current.folder_name, aggregate);
        }

        aggregate.reporter_count += 1;
        aggregate.repeat_reporter_count += history.server_submission_count >= 2 ? 1 : 0;
        aggregate.total_server_submission_count += history.server_submission_count;
        aggregate.first_server_seen_at_ms = Math.min(
          aggregate.first_server_seen_at_ms,
          history.first_server_seen_at_ms,
        );
        aggregate.last_server_seen_at_ms = Math.max(
          aggregate.last_server_seen_at_ms,
          history.last_server_seen_at_ms,
        );
        aggregate.last_current_submission_at_ms = Math.max(
          aggregate.last_current_submission_at_ms,
          current.submitted_at_ms,
        );
      }

      return [...grouped.values()]
        .filter(
          (row) =>
            row.reporter_count >= minReporters &&
            row.repeat_reporter_count >= minRepeatReporters,
        )
        .sort((left, right) => {
          if (right.reporter_count !== left.reporter_count) {
            return right.reporter_count - left.reporter_count;
          }
          if (right.repeat_reporter_count !== left.repeat_reporter_count) {
            return right.repeat_reporter_count - left.repeat_reporter_count;
          }
          if (
            right.total_server_submission_count !== left.total_server_submission_count
          ) {
            return (
              right.total_server_submission_count -
              left.total_server_submission_count
            );
          }
          return left.folder_name.localeCompare(right.folder_name);
        });
    }

    throw new Error(`Unsupported all() query in fake D1: ${sql}`);
  }

  executeWrite(sql, bindings) {
    if (sql === "delete from client_reports where install_id = ?") {
      const [installId] = bindings;
      for (const key of [...this.clientReports.keys()]) {
        if (this.clientReports.get(key)?.install_id === installId) {
          this.clientReports.delete(key);
        }
      }
      return { success: true };
    }

    if (
      sql.startsWith(
        "delete from client_reports where install_id = ? and folder_name not in (",
      )
    ) {
      const [installId, ...folderNames] = bindings;
      const keep = new Set(folderNames);
      for (const key of [...this.clientReports.keys()]) {
        const row = this.clientReports.get(key);
        if (!row || row.install_id !== installId) {
          continue;
        }
        if (!keep.has(row.folder_name)) {
          this.clientReports.delete(key);
        }
      }
      return { success: true };
    }

    if (
      sql.startsWith(
        "insert into client_report_history ( install_id, folder_name, first_server_seen_at_ms, last_server_seen_at_ms, server_submission_count ) values (?, ?, ?, ?, 1) on conflict(install_id, folder_name) do update set last_server_seen_at_ms = excluded.last_server_seen_at_ms, server_submission_count = client_report_history.server_submission_count + 1",
      )
    ) {
      const [installId, folderName, firstSeenAtMs, lastSeenAtMs] = bindings;
      const key = reportKey(installId, folderName);
      const existing = this.clientReportHistory.get(key);
      if (existing) {
        existing.last_server_seen_at_ms = lastSeenAtMs;
        existing.server_submission_count += 1;
      } else {
        this.clientReportHistory.set(key, {
          install_id: installId,
          folder_name: folderName,
          first_server_seen_at_ms: firstSeenAtMs,
          last_server_seen_at_ms: lastSeenAtMs,
          server_submission_count: 1,
        });
      }
      return { success: true };
    }

    if (
      sql.startsWith(
        "insert into client_reports ( install_id, folder_name, app_version, first_reported_at_ms, active_since_ms, last_reported_at_ms, last_withdrawn_at_ms, report_count, payload_generated_at_ms, submitted_at_ms ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      )
    ) {
      const [
        installId,
        folderName,
        appVersion,
        firstReportedAtMs,
        activeSinceMs,
        lastReportedAtMs,
        lastWithdrawnAtMs,
        reportCount,
        payloadGeneratedAtMs,
        submittedAtMs,
      ] = bindings;
      this.clientReports.set(reportKey(installId, folderName), {
        install_id: installId,
        folder_name: folderName,
        app_version: appVersion,
        first_reported_at_ms: firstReportedAtMs,
        active_since_ms: activeSinceMs,
        last_reported_at_ms: lastReportedAtMs,
        last_withdrawn_at_ms: lastWithdrawnAtMs,
        report_count: reportCount,
        payload_generated_at_ms: payloadGeneratedAtMs,
        submitted_at_ms: submittedAtMs,
      });
      return { success: true };
    }

    if (
      sql.startsWith(
        "insert into client_submissions ( install_id, app_version, generated_at_ms, submitted_at_ms, report_count ) values (?, ?, ?, ?, ?) on conflict(install_id) do update set app_version = excluded.app_version, generated_at_ms = excluded.generated_at_ms, submitted_at_ms = excluded.submitted_at_ms, report_count = excluded.report_count",
      )
    ) {
      const [installId, appVersion, generatedAtMs, submittedAtMs, reportCount] =
        bindings;
      this.clientSubmissions.set(installId, {
        install_id: installId,
        app_version: appVersion,
        generated_at_ms: generatedAtMs,
        submitted_at_ms: submittedAtMs,
        report_count: reportCount,
      });
      return { success: true };
    }

    if (
      sql.startsWith(
        "delete from client_submission_history where install_id = ? and submitted_at_ms < ?",
      )
    ) {
      const [installId, minSubmittedAtMs] = bindings;
      this.clientSubmissionHistory = this.clientSubmissionHistory.filter(
        (row) =>
          row.install_id !== installId || row.submitted_at_ms >= minSubmittedAtMs,
      );
      return { success: true };
    }

    if (
      sql.startsWith(
        "delete from client_submission_history where submitted_at_ms < ?",
      )
    ) {
      const [minSubmittedAtMs] = bindings;
      this.clientSubmissionHistory = this.clientSubmissionHistory.filter(
        (row) => row.submitted_at_ms >= minSubmittedAtMs,
      );
      return { success: true };
    }

    if (
      sql.startsWith(
        "delete from ip_submission_history where ip = ? and submitted_at_ms < ?",
      )
    ) {
      const [ip, minSubmittedAtMs] = bindings;
      this.ipSubmissionHistory = this.ipSubmissionHistory.filter(
        (row) => row.ip !== ip || row.submitted_at_ms >= minSubmittedAtMs,
      );
      return { success: true };
    }

    if (
      sql.startsWith(
        "delete from ip_submission_history where submitted_at_ms < ?",
      )
    ) {
      const [minSubmittedAtMs] = bindings;
      this.ipSubmissionHistory = this.ipSubmissionHistory.filter(
        (row) => row.submitted_at_ms >= minSubmittedAtMs,
      );
      return { success: true };
    }

    if (
      sql.startsWith(
        "insert into client_submission_history ( install_id, submitted_at_ms, report_count ) values (?, ?, ?)",
      )
    ) {
      const [installId, submittedAtMs, reportCount] = bindings;
      this.clientSubmissionHistory.push({
        id: this.nextSubmissionHistoryId++,
        install_id: installId,
        submitted_at_ms: submittedAtMs,
        report_count: reportCount,
      });
      return { success: true };
    }

    if (
      sql.startsWith(
        "insert into ip_submission_history ( ip, install_id, is_new_reporter, submitted_at_ms, report_count ) values (?, ?, ?, ?, ?)",
      )
    ) {
      const [ip, installId, isNewReporter, submittedAtMs, reportCount] = bindings;
      this.ipSubmissionHistory.push({
        id: this.nextIpSubmissionHistoryId++,
        ip,
        install_id: installId,
        is_new_reporter: isNewReporter,
        submitted_at_ms: submittedAtMs,
        report_count: reportCount,
      });
      return { success: true };
    }

    throw new Error(`Unsupported write query in fake D1: ${sql}`);
  }
}
