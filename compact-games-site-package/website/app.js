const FALLBACK_RELEASE_PAGE =
  "https://github.com/g1mliii/compact-games/releases/latest";
const ALL_RELEASES_PAGE =
  "https://github.com/g1mliii/compact-games/releases";
const RELEASES_API_URL =
  "https://api.github.com/repos/g1mliii/compact-games/releases?per_page=3";
const FALLBACK_MANIFEST_URL =
  "https://github.com/g1mliii/compact-games/releases/latest/download/latest.json";
const FALLBACK_UNSUPPORTED_LIST_URL =
  "https://github.com/g1mliii/compact-games/releases/latest/download/unsupported_games.json";
const FALLBACK_UNSUPPORTED_BUNDLE_URL =
  "https://github.com/g1mliii/compact-games/releases/latest/download/unsupported_games.bundle.json";
const FAQ_DOWNLOAD_HELP_URL = "./faq.html#download-help";
const CONTACT_EMAIL = "info@anchored.site";
const RELEASE_FETCH_TIMEOUT_MS = 2500;
const ALLOWED_CONNECT_ORIGINS = new Set([
  window.location.origin,
  "https://api.github.com",
  "https://github.com",
]);
const ALLOWED_RELEASE_ORIGINS = new Set(["https://github.com"]);
const ALLOWED_RELEASE_PATH_PREFIXES = [
  "/g1mliii/compact-games/releases/",
];
const CONTACT_LIMITS = {
  name: 80,
  email: 120,
  subject: 140,
  message: 2000,
};

const els = {
  releaseBadge: document.querySelector("#release-badge"),
  manifestVersion: document.querySelector("#manifest-version"),
  manifestDate: document.querySelector("#manifest-date"),
  manifestChecksum: document.querySelector("#manifest-checksum"),
  heroVersionSize: document.querySelector("#hero-version-size"),
  releaseCard: document.querySelector("#release-card"),
  changelogList: document.querySelector("#changelog-list"),
  primaryDownload: document.querySelector("#primary-download"),
  releaseNotesLink: document.querySelector("#release-notes-link"),
  unsupportedListLink: document.querySelector("#unsupported-list-link"),
  unsupportedBundleLink: document.querySelector("#unsupported-bundle-link"),
  platformNote: document.querySelector("#platform-note"),
};

const contactForm = document.querySelector("#contact-form");
const contactNote = document.querySelector("#contact-note");
const copyEmailButton = document.querySelector("#copy-email-button");
const hasReleaseUi =
  els.releaseBadge &&
  els.manifestVersion &&
  els.manifestDate &&
  els.manifestChecksum &&
  els.primaryDownload &&
  els.releaseNotesLink &&
  els.unsupportedListLink &&
  els.unsupportedBundleLink;

const pageState = {
  installerUrl: FALLBACK_RELEASE_PAGE,
  releasePageUrl: FALLBACK_RELEASE_PAGE,
  manifestUrl: FALLBACK_MANIFEST_URL,
  unsupportedListUrl: FALLBACK_UNSUPPORTED_LIST_URL,
  unsupportedBundleUrl: FALLBACK_UNSUPPORTED_BUNDLE_URL,
  noReleaseYet: false,
  hasInstallerDigest: false,
};

const platformContext = detectPlatformContext();

async function loadLatestRelease() {
  if (!hasReleaseUi) {
    return;
  }

  document.body.classList.add("release-is-loading");
  applyPlatformGuidance(true);

  try {
    const releases = await fetchJson(RELEASES_API_URL);
    const latestRelease = Array.isArray(releases) ? releases[0] : null;

    if (!latestRelease) {
      applyFallback({ noReleaseYet: true });
      return;
    }

    applyRelease(latestRelease);
    renderChangelog(releases.slice(0, 3));

    if (!pageState.hasInstallerDigest && canHydrateManifest(pageState.manifestUrl)) {
      scheduleManifestHydration(pageState.manifestUrl);
    }
  } catch (error) {
    applyFallback({ error });
  } finally {
    document.body.classList.remove("release-is-loading");
  }
}

function applyRelease(release) {
  const version = normalizeVersion(release.tag_name || release.name);
  const publishedAt = formatDate(release.published_at);
  const installerAsset = findAsset(
    release.assets,
    (asset) => /^CompactGames-Setup-.*\.exe$/i.test(asset.name),
  );
  const manifestAsset = findAsset(
    release.assets,
    (asset) => asset.name === "latest.json",
  );
  const unsupportedListAsset = findAsset(
    release.assets,
    (asset) => asset.name === "unsupported_games.json",
  );
  const unsupportedBundleAsset = findAsset(
    release.assets,
    (asset) => asset.name === "unsupported_games.bundle.json",
  );

  pageState.installerUrl = safeReleaseUrl(
    installerAsset?.browser_download_url,
    FALLBACK_RELEASE_PAGE,
  );
  pageState.manifestUrl = safeReleaseUrl(
    manifestAsset?.browser_download_url,
    FALLBACK_MANIFEST_URL,
  );
  pageState.releasePageUrl = safeReleaseUrl(
    release.html_url,
    FALLBACK_RELEASE_PAGE,
  );
  pageState.unsupportedListUrl = safeReleaseUrl(
    unsupportedListAsset?.browser_download_url,
    FALLBACK_UNSUPPORTED_LIST_URL,
  );
  pageState.unsupportedBundleUrl = safeReleaseUrl(
    unsupportedBundleAsset?.browser_download_url,
    FALLBACK_UNSUPPORTED_BUNDLE_URL,
  );
  pageState.noReleaseYet = false;
  pageState.hasInstallerDigest = Boolean(extractSha256Digest(installerAsset?.digest));

  setReleaseCardFallback(false);
  els.releaseBadge.textContent = `${version} published`;
  els.manifestVersion.textContent = version;
  els.manifestDate.textContent = publishedAt;
  els.manifestChecksum.textContent =
    extractSha256Digest(installerAsset?.digest) ||
    (manifestAsset ? "SHA-256 published in latest.json" : "Checksum unavailable");
  if (els.heroVersionSize) {
    els.heroVersionSize.textContent = formatVersionAndSize(
      version,
      installerAsset?.size,
    );
  }
  els.releaseNotesLink.href = pageState.releasePageUrl;
  els.unsupportedListLink.href = pageState.unsupportedListUrl;
  els.unsupportedBundleLink.href = pageState.unsupportedBundleUrl;

  applyPlatformGuidance(false);
}

function scheduleManifestHydration(manifestUrl) {
  const run = async () => {
    try {
      const manifest = await fetchJson(manifestUrl);
      applyManifestDetails(manifest);
    } catch (_error) {
      return;
    }
  };

  if ("requestIdleCallback" in window) {
    window.requestIdleCallback(() => {
      void run();
    }, { timeout: 1200 });
    return;
  }

  window.setTimeout(() => {
    void run();
  }, 120);
}

function canHydrateManifest(manifestUrl) {
  if (!manifestUrl) {
    return false;
  }

  try {
    const parsedUrl = new URL(manifestUrl);
    return ALLOWED_CONNECT_ORIGINS.has(parsedUrl.origin);
  } catch (_error) {
    return false;
  }
}

function applyManifestDetails(manifest) {
  const checksum = manifest?.checksum_sha256
    ? shortenChecksum(manifest.checksum_sha256)
    : "Checksum unavailable";
  els.manifestChecksum.textContent = checksum;
}

function applyFallback({ noReleaseYet = false, error = null } = {}) {
  pageState.installerUrl = FALLBACK_RELEASE_PAGE;
  pageState.releasePageUrl = FALLBACK_RELEASE_PAGE;
  pageState.manifestUrl = FALLBACK_MANIFEST_URL;
  pageState.unsupportedListUrl = FALLBACK_UNSUPPORTED_LIST_URL;
  pageState.unsupportedBundleUrl = FALLBACK_UNSUPPORTED_BUNDLE_URL;
  pageState.noReleaseYet = noReleaseYet;
  pageState.hasInstallerDigest = false;

  els.releaseBadge.textContent = noReleaseYet
    ? "Official GitHub release page"
    : "GitHub release details unavailable";
  els.manifestVersion.textContent = noReleaseYet
    ? "Waiting"
    : "Latest release";
  els.manifestDate.textContent = noReleaseYet
    ? "Public release not posted yet"
    : "Check GitHub Releases";
  els.manifestChecksum.textContent = noReleaseYet
    ? "No public checksum yet"
    : "Checksum unavailable";
  els.releaseNotesLink.href = pageState.releasePageUrl;
  els.unsupportedListLink.href = pageState.unsupportedListUrl;
  els.unsupportedBundleLink.href = pageState.unsupportedBundleUrl;
  setReleaseCardFallback(Boolean(error));

  applyPlatformGuidance(true);
}

function setReleaseCardFallback(isFallback) {
  if (!els.releaseCard) {
    return;
  }

  const existingLink = els.releaseCard.closest(".release-card-link");
  if (isFallback) {
    els.releaseCard.classList.add("release-card-fallback");
    if (existingLink) {
      existingLink.href = ALL_RELEASES_PAGE;
      return;
    }

    const link = document.createElement("a");
    link.className = "release-card-link";
    link.href = ALL_RELEASES_PAGE;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.setAttribute(
      "aria-label",
      "Open Compact Games releases on GitHub",
    );
    els.releaseCard.before(link);
    link.append(els.releaseCard);
    return;
  }

  els.releaseCard.classList.remove("release-card-fallback");
  if (existingLink) {
    existingLink.replaceWith(els.releaseCard);
  }
}

async function fetchJson(url) {
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => {
    controller.abort();
  }, RELEASE_FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      cache: "default",
      headers: {
        Accept: "application/vnd.github+json",
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      const error = new Error(`${url} failed with ${response.status}`);
      error.status = response.status;
      throw error;
    }

    return response.json();
  } finally {
    window.clearTimeout(timeoutId);
  }
}

function safeReleaseUrl(rawUrl, fallbackUrl) {
  if (!rawUrl) {
    return fallbackUrl;
  }

  try {
    const parsedUrl = new URL(rawUrl);
    const isAllowedOrigin = ALLOWED_RELEASE_ORIGINS.has(parsedUrl.origin);
    const isAllowedPath = ALLOWED_RELEASE_PATH_PREFIXES.some((prefix) =>
      parsedUrl.pathname.startsWith(prefix),
    );

    if (
      parsedUrl.protocol !== "https:" ||
      !isAllowedOrigin ||
      !isAllowedPath
    ) {
      return fallbackUrl;
    }

    return parsedUrl.toString();
  } catch (_error) {
    return fallbackUrl;
  }
}

function sanitizeContactValue(rawValue, maxLength) {
  if (!rawValue) {
    return "";
  }

  return rawValue
    .toString()
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim()
    .slice(0, maxLength);
}

function findAsset(assets = [], predicate) {
  return assets.find(predicate) || null;
}

function normalizeVersion(raw) {
  if (!raw) {
    return "Latest release";
  }

  return raw.startsWith("v") ? raw : `v${raw}`;
}

function formatDate(raw) {
  if (!raw) {
    return "Date unavailable";
  }

  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    return raw;
  }

  return new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(date);
}

function extractSha256Digest(digest) {
  const match = String(digest || "").match(/^sha256:([a-f0-9]{64})$/i);
  return match ? shortenChecksum(match[1]) : "";
}

function formatVersionAndSize(version, sizeBytes) {
  if (!sizeBytes || Number.isNaN(Number(sizeBytes))) {
    return `${version} - Windows installer`;
  }

  return `${version} - ${formatFileSize(sizeBytes)}`;
}

function formatFileSize(sizeBytes) {
  return `${(Number(sizeBytes) / 1_000_000).toFixed(1)} MB`;
}

function shortenChecksum(value) {
  if (value.length <= 20) {
    return value;
  }

  return `${value.slice(0, 12)}...${value.slice(-12)}`;
}

function renderChangelog(releases) {
  if (!els.changelogList || !Array.isArray(releases) || releases.length === 0) {
    return;
  }

  els.changelogList.replaceChildren(
    ...releases.map((release) => createChangelogEntry(release)),
  );
}

function createChangelogEntry(release) {
  const item = document.createElement("li");
  item.className = "changelog-entry";

  const versionBlock = document.createElement("div");
  versionBlock.className = "changelog-version";
  versionBlock.append(
    normalizeVersion(release.tag_name || release.name),
    createChangelogDate(release.published_at),
  );

  const body = document.createElement("div");
  body.className = "changelog-body";
  const rendered = renderReleaseMarkdown(release.body);
  if (rendered.childNodes.length === 0) {
    const fallback = document.createElement("p");
    fallback.textContent = "Release notes published. Open the release history for the full notes.";
    body.append(fallback);
  } else {
    body.append(rendered);
  }

  item.append(versionBlock, body);
  return item;
}

function createChangelogDate(publishedAt) {
  const date = document.createElement("span");
  date.className = "changelog-date";
  date.textContent = formatDate(publishedAt);
  return date;
}

// ---------------------------------------------------------------------------
// Minimal markdown renderer for GitHub release bodies. Builds DOM nodes via
// textContent/appendChild only — never innerHTML — so the page CSP stays
// intact. Supports: ## / ### headings, paragraphs, - list items, ---
// horizontal rules, **bold**, `code`, and [text](url) links (https only).
// ---------------------------------------------------------------------------
function renderReleaseMarkdown(body) {
  const fragment = document.createDocumentFragment();
  const source = String(body || "").replace(/\r\n/g, "\n");
  if (!source.trim()) {
    return fragment;
  }

  const lines = source.split("\n");
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed === "") {
      i += 1;
      continue;
    }

    if (/^-{3,}$/.test(trimmed)) {
      fragment.append(document.createElement("hr"));
      i += 1;
      continue;
    }

    const headingMatch = /^(#{1,6})\s+(.+)$/.exec(trimmed);
    if (headingMatch) {
      // Release bodies start at ## so their outermost heading lives inside
      // the page's existing h2 section. Shift down one level: ## → h3, etc.
      const level = Math.max(3, Math.min(headingMatch[1].length + 1, 6));
      const heading = document.createElement(`h${level}`);
      appendInlineMarkdown(heading, headingMatch[2].trim());
      fragment.append(heading);
      i += 1;
      continue;
    }

    if (/^[-*]\s+/.test(trimmed)) {
      const list = document.createElement("ul");
      while (i < lines.length && /^[-*]\s+/.test(lines[i].trim())) {
        const itemText = lines[i].trim().replace(/^[-*]\s+/, "");
        const li = document.createElement("li");
        appendInlineMarkdown(li, itemText);
        list.append(li);
        i += 1;
      }
      fragment.append(list);
      continue;
    }

    const paragraphLines = [];
    while (
      i < lines.length &&
      lines[i].trim() !== "" &&
      !/^#{1,6}\s+/.test(lines[i].trim()) &&
      !/^[-*]\s+/.test(lines[i].trim()) &&
      !/^-{3,}$/.test(lines[i].trim())
    ) {
      paragraphLines.push(lines[i].trim());
      i += 1;
    }
    if (paragraphLines.length > 0) {
      const paragraph = document.createElement("p");
      appendInlineMarkdown(paragraph, paragraphLines.join(" "));
      fragment.append(paragraph);
    }
  }

  return fragment;
}

// Inline-span renderer: **bold**, `code`, [text](url). Everything else is
// appended as a text node. Links only render when the URL is https and to a
// trusted origin — other URLs fall back to plain text.
function appendInlineMarkdown(parent, text) {
  const pattern = /(\*\*[^*\n]+\*\*)|(`[^`\n]+`)|(\[[^\]\n]+\]\([^)\n]+\))/g;
  let cursor = 0;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > cursor) {
      parent.append(document.createTextNode(text.slice(cursor, match.index)));
    }
    const token = match[0];
    if (token.startsWith("**")) {
      const strong = document.createElement("strong");
      strong.textContent = token.slice(2, -2);
      parent.append(strong);
    } else if (token.startsWith("`")) {
      const code = document.createElement("code");
      code.textContent = token.slice(1, -1);
      parent.append(code);
    } else {
      const linkMatch = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(token);
      if (linkMatch) {
        const safeUrl = safeChangelogLinkUrl(linkMatch[2]);
        if (safeUrl) {
          const anchor = document.createElement("a");
          anchor.href = safeUrl;
          anchor.target = "_blank";
          anchor.rel = "noopener noreferrer";
          anchor.textContent = linkMatch[1];
          parent.append(anchor);
        } else {
          parent.append(document.createTextNode(linkMatch[1]));
        }
      }
    }
    cursor = match.index + token.length;
  }
  if (cursor < text.length) {
    parent.append(document.createTextNode(text.slice(cursor)));
  }
}

const CHANGELOG_LINK_ALLOWED_ORIGINS = new Set([
  "https://github.com",
  "https://www.github.com",
]);

function safeChangelogLinkUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== "https:") {
      return null;
    }
    if (!CHANGELOG_LINK_ALLOWED_ORIGINS.has(parsed.origin)) {
      return null;
    }
    return parsed.toString();
  } catch (_error) {
    return null;
  }
}

function detectPlatformContext() {
  const userAgent = navigator.userAgent || "";
  const platform =
    navigator.userAgentData?.platform ||
    navigator.platform ||
    "";
  const maxTouchPoints = navigator.maxTouchPoints || 0;
  const normalized = `${userAgent} ${platform}`.toLowerCase();
  const isIPad =
    normalized.includes("ipad") ||
    (platform === "MacIntel" && maxTouchPoints > 1);
  const isIPhone = /iphone|ipod/.test(normalized);
  const isAndroid = normalized.includes("android");
  const isAndroidPhone = isAndroid && normalized.includes("mobile");
  const isAndroidTablet = isAndroid && !isAndroidPhone;
  const isWindows = normalized.includes("win") && !isIPad;
  const isMac = normalized.includes("mac") && !isIPad;
  const isLinux = /linux|x11/.test(normalized) && !isAndroid;
  const isPhone = isIPhone || isAndroidPhone;
  const isTablet = isIPad || isAndroidTablet;

  let label = "this device";
  if (isIPad) {
    label = "your iPad";
  } else if (isIPhone) {
    label = "your iPhone";
  } else if (isAndroidPhone) {
    label = "your Android phone";
  } else if (isAndroidTablet) {
    label = "your Android tablet";
  } else if (isMac) {
    label = "your Mac";
  } else if (isLinux) {
    label = "your Linux device";
  } else if (isWindows) {
    label = "your Windows PC";
  }

  return {
    isWindows,
    isPhone,
    isTablet,
    isIPad,
    label,
  };
}

function getPlatformNoteText() {
  if (platformContext.isWindows) {
    if (pageState.noReleaseYet) {
      return "No public Windows installer is posted yet. Until one is published, the button opens the GitHub Releases page instead of a direct .exe download.";
    }

    return "This installer is for Windows 10 and Windows 11. Download it on this PC.";
  }

  if (platformContext.isIPad) {
    if (pageState.noReleaseYet) {
      return "You are on an iPad, and there is no public Windows installer posted yet. Check GitHub Releases from a Windows 10 or 11 PC once a build is published.";
    }

    return "You are on an iPad. Compact Games installs with a Windows .exe, so open this page on a Windows 10 or 11 PC to install it.";
  }

  if (platformContext.isPhone || platformContext.isTablet) {
    if (pageState.noReleaseYet) {
      return `You are on ${platformContext.label}, and there is no public Windows installer posted yet. Check GitHub Releases from a Windows 10 or 11 PC once a build is published.`;
    }

    return `You are on ${platformContext.label}. Compact Games installs with a Windows .exe, so use a Windows 10 or 11 PC for the actual download and install.`;
  }

  if (pageState.noReleaseYet) {
    return `You are on ${platformContext.label}. Compact Games is Windows-only, and there is no public installer posted yet. Check GitHub Releases from a Windows 10 or 11 PC once a build is published.`;
  }

  return `You are on ${platformContext.label}. Compact Games is Windows-only, so use a Windows 10 or 11 PC for the installer download.`;
}

function applyPlatformGuidance(useFallbackLabels) {
  if (!hasReleaseUi) {
    return;
  }

  if (els.platformNote) {
    els.platformNote.textContent = getPlatformNoteText();
  }

  if (platformContext.isWindows) {
    const primaryLabel = useFallbackLabels
      ? els.primaryDownload.dataset.fallbackLabel
      : els.primaryDownload.dataset.liveLabel;

    els.primaryDownload.href = pageState.installerUrl;
    els.primaryDownload.textContent = primaryLabel || "Download for Windows";
    els.primaryDownload.target = "_blank";
    els.primaryDownload.rel = "noopener noreferrer";
    els.primaryDownload.removeAttribute("aria-describedby");
    return;
  }

  els.primaryDownload.href = FAQ_DOWNLOAD_HELP_URL;
  els.primaryDownload.textContent =
    els.primaryDownload.dataset.helpLabel || "See Windows download help";
  els.primaryDownload.removeAttribute("target");
  els.primaryDownload.removeAttribute("rel");

  if (els.platformNote) {
    els.primaryDownload.setAttribute("aria-describedby", "platform-note");
  }
}

function initContactForm() {
  if (!contactForm || !contactNote) {
    return;
  }

  contactForm.addEventListener("submit", (event) => {
    event.preventDefault();

    const formData = new FormData(contactForm);
    const name = sanitizeContactValue(
      formData.get("name"),
      CONTACT_LIMITS.name,
    );
    const email = sanitizeContactValue(
      formData.get("email"),
      CONTACT_LIMITS.email,
    );
    const subject = sanitizeContactValue(
      formData.get("subject"),
      CONTACT_LIMITS.subject,
    );
    const message = sanitizeContactValue(
      formData.get("message"),
      CONTACT_LIMITS.message,
    );

    if (!subject || !message) {
      contactNote.textContent = "Add a subject and message first.";
      return;
    }

    const bodyParts = [];
    if (name) {
      bodyParts.push(`Name: ${name}`);
    }
    if (email) {
      bodyParts.push(`Email: ${email}`);
    }
    bodyParts.push("", message);

    const mailtoUrl =
      `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(subject)}` +
      `&body=${encodeURIComponent(bodyParts.join("\n"))}`;

    contactNote.textContent =
      "Opening your default email app. If nothing happens, use the direct email link below.";
    window.location.href = mailtoUrl;
  });

  if (copyEmailButton) {
    copyEmailButton.addEventListener("click", async () => {
      const email = copyEmailButton.dataset.email || CONTACT_EMAIL;

      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(email);
        } else {
          const tempInput = document.createElement("textarea");
          tempInput.value = email;
          tempInput.setAttribute("readonly", "");
          tempInput.style.position = "absolute";
          tempInput.style.left = "-9999px";
          document.body.append(tempInput);
          tempInput.select();
          document.execCommand("copy");
          tempInput.remove();
        }

        copyEmailButton.textContent = "Copied";
        contactNote.textContent = `Copied ${email} to your clipboard.`;
        window.setTimeout(() => {
          copyEmailButton.textContent = "Copy address";
        }, 2200);
      } catch (_error) {
        contactNote.textContent =
          `Could not copy automatically. Use ${email} directly.`;
      }
    });
  }
}

function initAppShotTabs() {
  const tabs = Array.from(document.querySelectorAll("[data-appshot-tab]"));
  const panels = Array.from(document.querySelectorAll("[data-appshot-panel]"));
  const caption = document.querySelector("#appshots-caption");

  if (tabs.length === 0 || panels.length === 0) {
    return;
  }

  const captions = {
    browse: "Scans your installed libraries and shows saved-space totals per title.",
    warn: "Flags titles that are known to misbehave after compression, and explains the risk before you decide.",
    restore: "Every compressed game can be restored back to its original state, individually or in bulk.",
  };

  const activate = (targetId) => {
    tabs.forEach((tab) => {
      const isActive = tab.dataset.appshotTab === targetId;
      tab.classList.toggle("is-active", isActive);
      tab.setAttribute("aria-selected", String(isActive));
    });

    panels.forEach((panel) => {
      const isActive = panel.dataset.appshotPanel === targetId;
      panel.classList.toggle("is-active", isActive);
      panel.hidden = !isActive;
    });

    if (caption && captions[targetId]) {
      caption.textContent = captions[targetId];
    }
  };

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => {
      activate(tab.dataset.appshotTab);
    });

    tab.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
        return;
      }

      event.preventDefault();
      let nextIndex = index;
      if (event.key === "ArrowLeft") {
        nextIndex = (index - 1 + tabs.length) % tabs.length;
      } else if (event.key === "ArrowRight") {
        nextIndex = (index + 1) % tabs.length;
      } else if (event.key === "Home") {
        nextIndex = 0;
      } else if (event.key === "End") {
        nextIndex = tabs.length - 1;
      }

      tabs[nextIndex].focus();
      activate(tabs[nextIndex].dataset.appshotTab);
    });
  });
}

loadLatestRelease();

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    initContactForm();
    initAppShotTabs();
  });
} else {
  initContactForm();
  initAppShotTabs();
}
