const downloadLink = document.getElementById("release-downloads");

async function updateReleaseDownloads() {
  let page = "https://api.github.com/repos/Hendar23/OpenSC/releases?per_page=100";
  let total = 0;

  while (page) {
    const response = await fetch(page, { credentials: "omit" });
    if (!response.ok) throw new Error("GitHub release counts are unavailable.");

    const releases = await response.json();
    for (const release of releases) {
      for (const asset of release.assets) {
        total += asset.download_count;
      }
    }

    page = response.headers.get("Link")?.match(/<([^>]+)>;\s*rel="next"/)?.[1];
  }

  downloadLink.textContent = `${total.toLocaleString()} release downloads`;
}

updateReleaseDownloads().catch(() => {
  // Keep the link to the stats page if GitHub can't provide a complete total.
});
