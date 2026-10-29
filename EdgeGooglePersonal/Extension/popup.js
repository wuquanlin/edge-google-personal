let result = null;
function render(value) {
  result = value;
  document.querySelector("#summary").textContent = value?.ok ? "已验证：默认搜索请求发往 Google。" : value ? "尚未通过实际校验，请查看原因。" : "等待首次校验。";
  document.querySelector("#detail").textContent = value ? JSON.stringify(value, null, 2) : "无结果";
}
chrome.storage.local.get("lastResult").then(data => render(data.lastResult));
chrome.storage.onChanged.addListener((changes, area) => { if (area === "local" && changes.lastResult) render(changes.lastResult.newValue); });
document.querySelector("#verify").addEventListener("click", async () => {
  document.querySelector("#summary").textContent = "正在通过默认搜索接口校验，请稍候…";
  try { await chrome.runtime.sendMessage({type: "verify"}); }
  catch { document.querySelector("#summary").textContent = "扩展正在重新加载。请稍后重新打开此窗口查看结果。"; }
});
document.querySelector("#export").addEventListener("click", event => {
  event.preventDefault();
  const url = URL.createObjectURL(new Blob([JSON.stringify(result, null, 2)], {type: "application/json"}));
  const a = document.createElement("a"); a.href = url; a.download = "EdgeGoogle-verification.json"; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
});
