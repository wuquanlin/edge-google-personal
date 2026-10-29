import {verifyDefaultSearch} from "./verify.js";

let busy = false;
async function badge(text, color) {
  await chrome.action.setBadgeText({text});
  await chrome.action.setBadgeBackgroundColor({color});
}
async function checkRequest(manualId) {
  if (busy) return;
  busy = true;
  try {
    const request = manualId ? {id: manualId} : await (await fetch(chrome.runtime.getURL("login-request.json"), {cache: "no-store"})).json();
    if (typeof request.id !== "string" || request.id.length > 128) throw new Error("Invalid local request id");
    const previous = await chrome.storage.local.get(["completedRequestId", "retryRequestId"]);
    if (previous.completedRequestId === request.id) return;
    await badge("…", "#64748b");
    const result = {...await verifyDefaultSearch(chrome), requestId: request.id};
    if (!result.ok && previous.retryRequestId !== request.id) {
      await chrome.storage.local.set({retryRequestId: request.id, lastResult: {...result, status: "retrying", error: "第一次校验未通过，正在重新加载本扩展一次，然后复验。"}});
      // Request reactivation of our own declared settings; the next search decides success.
      // No other extension, protected preference, policy or security setting is changed.
      chrome.runtime.reload();
      return;
    }
    await chrome.storage.local.set({completedRequestId: request.id, retryRequestId: null, lastResult: result});
    await badge(result.ok ? "OK" : "!", result.ok ? "#15803d" : "#b91c1c");
  } catch (e) {
    await chrome.storage.local.set({lastResult: {ok: false, status: "error", checkedAt: new Date().toISOString(), error: String(e?.message || e)}});
    await badge("!", "#b91c1c");
  } finally { busy = false; }
}

chrome.runtime.onInstalled.addListener(() => { void checkRequest(); });
chrome.runtime.onStartup.addListener(() => { void checkRequest(); });
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "local-login-request") void checkRequest(); });
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.type !== "verify" || sender.id !== chrome.runtime.id) return;
  checkRequest(`manual-${Date.now()}`).then(() => respond({accepted: true}));
  return true;
});
// Only reads a local request once per minute; no search occurs without a new request.
void chrome.alarms.create("local-login-request", {periodInMinutes: 1});
void checkRequest();
