const FALLBACK_RELEASE_PAGE =
  "https://github.com/g1mliii/compact-games/releases/latest";
const RELEASES_API_URL =
  "https://api.github.com/repos/g1mliii/compact-games/releases?per_page=1";
const FALLBACK_MANIFEST_URL =
  "https://github.com/g1mliii/compact-games/releases/latest/download/latest.json";
const FALLBACK_UNSUPPORTED_LIST_URL =
  "https://github.com/g1mliii/compact-games/releases/latest/download/unsupported_games.json";
const FALLBACK_UNSUPPORTED_BUNDLE_URL =
  "https://github.com/g1mliii/compact-games/releases/latest/download/unsupported_games.bundle.json";
const FAQ_DOWNLOAD_HELP_URL = "./faq.html#download-help";
const CONTACT_EMAIL = "info@anchored.site";
const RELEASE_FETCH_TIMEOUT_MS = 2500;
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
};

const platformContext = detectPlatformContext();

async function loadLatestRelease() {
  if (!hasReleaseUi) {
    return;
  }

  applyPlatformGuidance(true);

  try {
    const releases = await fetchJson(RELEASES_API_URL);
    const latestRelease = Array.isArray(releases) ? releases[0] : null;

    if (!latestRelease) {
      applyFallback({ noReleaseYet: true });
      return;
    }

    applyRelease(latestRelease);

    if (pageState.manifestUrl) {
      scheduleManifestHydration(pageState.manifestUrl);
    }
  } catch (error) {
    applyFallback({ error });
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

  els.releaseBadge.textContent = `${version} published`;
  els.manifestVersion.textContent = version;
  els.manifestDate.textContent = publishedAt;
  els.manifestChecksum.textContent = manifestAsset
    ? "Available in latest.json"
    : "Checksum unavailable";
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
      els.manifestChecksum.textContent = "Checksum unavailable";
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

function applyManifestDetails(manifest) {
  const checksum = manifest?.checksum_sha256
    ? shortenChecksum(manifest.checksum_sha256)
    : "Checksum unavailable";
  els.manifestChecksum.textContent = checksum;
}

function applyFallback({ noReleaseYet = false } = {}) {
  pageState.installerUrl = FALLBACK_RELEASE_PAGE;
  pageState.releasePageUrl = FALLBACK_RELEASE_PAGE;
  pageState.manifestUrl = FALLBACK_MANIFEST_URL;
  pageState.unsupportedListUrl = FALLBACK_UNSUPPORTED_LIST_URL;
  pageState.unsupportedBundleUrl = FALLBACK_UNSUPPORTED_BUNDLE_URL;
  pageState.noReleaseYet = noReleaseYet;

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
    ? "No public build yet"
    : "Official GitHub release path";
  els.releaseNotesLink.href = pageState.releasePageUrl;
  els.unsupportedListLink.href = pageState.unsupportedListUrl;
  els.unsupportedBundleLink.href = pageState.unsupportedBundleUrl;

  applyPlatformGuidance(true);
}

async function fetchJson(url) {
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => {
    controller.abort();
  }, RELEASE_FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      cache: "no-store",
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

function shortenChecksum(value) {
  if (value.length <= 20) {
    return value;
  }

  return `${value.slice(0, 12)}...${value.slice(-12)}`;
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

        contactNote.textContent = `Copied ${email} to your clipboard.`;
      } catch (_error) {
        contactNote.textContent =
          `Could not copy automatically. Use ${email} directly.`;
      }
    });
  }
}

loadLatestRelease();

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    initContactForm();
  });
} else {
  initContactForm();
}
