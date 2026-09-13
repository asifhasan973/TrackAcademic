#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const PROJECT_ID = "trackacademic-c0d1c";

async function getGoogleCloudToken() {
  const configPath = path.join(os.homedir(), ".config/configstore/firebase-tools.json");
  if (!fs.existsSync(configPath)) {
    throw new Error("Firebase CLI login required. Run 'firebase login' first.");
  }
  const data = JSON.parse(fs.readFileSync(configPath, "utf8"));
  let token = data.tokens.access_token;
  if (data.tokens.refresh_token) {
    const res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho85qd6.apps.googleusercontent.com",
        client_secret: null,
        refresh_token: data.tokens.refresh_token,
        grant_type: "refresh_token",
      }),
    });
    const tData = await res.json();
    if (tData.access_token) token = tData.access_token;
  }
  return token;
}

async function verifyUser(target) {
  if (!target) {
    console.error("Usage: node scripts/verify_user_email.mjs <email_or_uid>");
    process.exit(1);
  }

  const token = await getGoogleCloudToken();

  // 1. Download accounts to find target user
  const dlRes = await fetch(
    "https://www.googleapis.com/identitytoolkit/v3/relyingparty/downloadAccount",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        targetProjectId: PROJECT_ID,
        maxResults: 1000,
      }),
    }
  );

  const dlData = await dlRes.json();
  const users = dlData.users || [];
  const matched = users.find(
    (u) =>
      u.localId === target ||
      (u.email && u.email.toLowerCase() === target.toLowerCase())
  );

  if (!matched) {
    console.error(`❌ User not found with email or UID: ${target}`);
    process.exit(1);
  }

  const uid = matched.localId;
  const email = matched.email;

  // 2. Set emailVerified in Firebase Auth
  const authRes = await fetch(
    "https://www.googleapis.com/identitytoolkit/v3/relyingparty/setAccountInfo",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        targetProjectId: PROJECT_ID,
        localId: uid,
        emailVerified: true,
      }),
    }
  );

  if (!authRes.ok) {
    const err = await authRes.text();
    throw new Error(`Failed to update Auth: ${err}`);
  }

  // 3. Set emailVerified in Firestore user profile
  await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}?updateMask.fieldPaths=emailVerified`,
    {
      method: "PATCH",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: {
          emailVerified: { booleanValue: true },
        },
      }),
    }
  );

  console.log(`✔ SUCCESS: ${email} (UID: ${uid}) is now verified!`);
}

const target = process.argv[2];
verifyUser(target).catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
