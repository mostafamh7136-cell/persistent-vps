#!/usr/bin/env node
/**
 * persistent-vps  pin-link.js
 *
 * Reads or generates a completely unique 16-hex-character ID per user
 * deployment, persists it in .pinned_id so the same user keeps the same URL
 * after restarts while every different deployment gets a distinct URL, then
 * pins appName -> port 6080 with the platform gateway and prints the URL.
 *
 * No secrets here: the pinned URL is public infrastructure, not a secret.
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execSync } = require("child_process");

const ID_FILE = path.join("/workspace/debian13-server", ".pinned_id");
const DOMAIN = "sg.agentos-app.run";

let PINNED_NAME = "";

if (fs.existsSync(ID_FILE)) {
  PINNED_NAME = fs.readFileSync(ID_FILE, "utf8").trim();
}

if (!PINNED_NAME || PINNED_NAME.length < 8) {
  // Generate random 16-hex chars unique to this instance
  PINNED_NAME = crypto.randomBytes(8).toString("hex");
  fs.writeFileSync(ID_FILE, PINNED_NAME, "utf8");
}

function pin() {
  try {
    execSync(
      `curl -s -X POST -H "Content-Type: application/json" ` +
      `-d '{"appName":"${PINNED_NAME}","port":6080}' ` +
      `http://127.0.0.1:6080/_agentos/pin 2>/dev/null || true`
    );
  } catch (e) {
    // Platform pin endpoint unavailable  keep the ID persistent anyway.
  }
  console.log(`https://${PINNED_NAME}.${DOMAIN}`);
}

pin();
