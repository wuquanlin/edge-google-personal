// Uses the browser's default search provider; never constructs a Google navigation.
export function matchesGoogle(raw, probe) {
  try {
    const u = new URL(raw);
    return u.protocol === "https:" && u.hostname === "www.google.com" &&
      u.port === "" && u.pathname === "/search" && u.searchParams.get("q") === probe;
  } catch { return false; }
}

export async function verifyDefaultSearch(api, {timeoutMs = 15000, sleep = ms => new Promise(r => setTimeout(r, ms)), now = Date.now} = {}) {
  const probe = `EdgeGoogleGuard-${now()}-${Math.random().toString(36).slice(2, 9)}`;
  let tabId;
  try {
    const tab = await api.tabs.create({url: "about:blank", active: false});
    tabId = tab.id;
    // tabId confines the test to the one background tab created above.
    await api.search.query({text: probe, tabId});
    const deadline = now() + timeoutMs;
    do {
      const state = await api.tabs.get(tabId);
      if ([state.url, state.pendingUrl].some(url => matchesGoogle(url, probe))) {
        return {ok: true, status: "google-route-verified", checkedAt: new Date().toISOString(),
          provider: "Google", evidence: "chrome.search.query generated an HTTPS www.google.com/search navigation with the exact test query", pageReachabilityTested: false};
      }
      await sleep(300);
    } while (now() < deadline);
    return {ok: false, status: "not-verified", checkedAt: new Date().toISOString(),
      error: "未观察到默认搜索接口生成 Google 搜索请求。可能是其他引擎、权限不足或导航失败；不能判定成功。"};
  } catch (e) {
    return {ok: false, status: "error", checkedAt: new Date().toISOString(), error: String(e?.message || e)};
  } finally {
    if (tabId !== undefined) {
      try { await api.tabs.remove(tabId); } catch { /* The user may already have closed the test tab. */ }
    }
  }
}
