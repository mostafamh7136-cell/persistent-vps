#!/usr/bin/env node
/**
 * pin-link.js — 将本实例的公网链接固定到唯一的 pinned ID 子域。
 *
 * 平台真实通道：POST http://codebuddy.auth-proxy.local/v2/agentos/artifact-releases
 * （鉴权由沙箱 space-auth-proxy 自动注入）。releaseConfig.useAppNameAsDomain=true 使
 * URL 子域取自 appName；因此 appName = .pinned_id 中的 16 位十六进制唯一 ID，
 * 跨容器重启（AGENTOS_RUNTIME_ID 变化）后重新执行本脚本即可拿回同一 URL。
 */
const fs = require("fs");
const path = require("path");
const http = require("http");

const ID_FILE = path.join("/workspace/debian13-server", ".pinned_id");
const DOMAIN = "sg.agentos-app.run";
const PORT = 6080;
const PUBLISH_BASE = "http://codebuddy.auth-proxy.local";
const EXPIRE_SECONDS = 157680000; // ~5 years

let PINNED_NAME = "";
if (fs.existsSync(ID_FILE)) {
  PINNED_NAME = fs.readFileSync(ID_FILE, "utf8").trim();
}
if (!PINNED_NAME || PINNED_NAME.length < 8) {
  PINNED_NAME = require("crypto").randomBytes(8).toString("hex");
  fs.writeFileSync(ID_FILE, PINNED_NAME, "utf8");
}
// DNS label 不能以数字开头
if (/^[0-9]/.test(PINNED_NAME)) PINNED_NAME = "a" + PINNED_NAME;

const runtimeId = (process.env.AGENTOS_RUNTIME_ID || "").trim();
if (!/^[1-9]\d*$/.test(runtimeId)) {
  console.error("缺少合法的 AGENTOS_RUNTIME_ID 环境变量");
  process.exit(1);
}

function requestJson(method, url, rawBody) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port || 80,
        path: u.pathname + u.search,
        method,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(rawBody || ""),
        },
        timeout: 30000,
      },
      (res) => {
        let text = "";
        res.on("data", (c) => (text += c));
        res.on("end", () => {
          let json = null;
          try { json = JSON.parse(text); } catch {}
          resolve({ status: res.statusCode, text, json });
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error("timeout")));
    if (rawBody) req.write(rawBody);
    req.end();
  });
}

async function main() {
  const releaseConfig = {
    port: PORT,
    skipFork: true,
    appName: PINNED_NAME,
    useAppNameAsDomain: true,
    expire: EXPIRE_SECONDS,
  };
  const rawBody =
    `{"runtimeId":${runtimeId},"artifactType":"web","persistent":true,` +
    `"releaseConfig":${JSON.stringify(releaseConfig)}}`;

  let shareLink = null;
  let releaseId = null;
  try {
    const res = await requestJson("POST", `${PUBLISH_BASE}/v2/agentos/artifact-releases`, rawBody);
    if (res.status >= 200 && res.status < 300 && res.json && res.json.code === 0 && res.json.data) {
      const d = res.json.data;
      shareLink = d.shareUrl ||
        (d.domains && Array.isArray(d.domains.friendlyDomains) && d.domains.friendlyDomains[0]
          ? `https://${d.domains.friendlyDomains[0]}`
          : null) ||
        d.releaseUrl || null;
      const m = /"releaseId"\s*:\s*"?(\d+)"?/.exec(res.text || "");
      releaseId = m ? m[1] : null;
    } else {
      console.error(`发布接口返回异常 (HTTP ${res.status}): ${(res.text || "").slice(0, 300)}`);
    }
  } catch (e) {
    console.error(`发布接口请求失败: ${e.message}`);
  }

  const link = shareLink || `https://${PINNED_NAME}.${DOMAIN}`;
  fs.writeFileSync(path.join("/workspace/debian13-server", "LINK.txt"), link + "\n", "utf8");
  if (releaseId) {
    fs.writeFileSync(path.join("/workspace/debian13-server", ".release_id"), releaseId, "utf8");
  }
  console.log(link);
}

main().catch((e) => { console.error(e.message); process.exit(1); });
