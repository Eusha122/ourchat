const FETCH_TIMEOUT_MS = 4000;

function extractMetaTag(html: string, property: string): string | null {
  const patterns = [
    new RegExp(
      `<meta[^>]+property=["']${property}["'][^>]*content=["']([^"']+)["']`,
      "i",
    ),
    new RegExp(
      `<meta[^>]+content=["']([^"']+)["'][^>]*property=["']${property}["']`,
      "i",
    ),
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match) return match[1]!;
  }
  return null;
}

/**
 * Best-effort Open Graph metadata fetch for link previews. Instagram and
 * Facebook frequently block server-side scraping (login walls, bot
 * detection), so title/image are often unavailable - callers must handle
 * both being null and fall back to showing the raw URL.
 */
export async function fetchLinkMetadata(
  url: string,
): Promise<{ title: string | null; imageUrl: string | null }> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    const response = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (compatible; OurChatLinkPreview/1.0; +https://example.com)",
      },
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!response.ok) return { title: null, imageUrl: null };

    const html = await response.text();
    return {
      title: extractMetaTag(html, "og:title"),
      imageUrl: extractMetaTag(html, "og:image"),
    };
  } catch {
    return { title: null, imageUrl: null };
  }
}
