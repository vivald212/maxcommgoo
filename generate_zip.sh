#!/usr/bin/env bash
# generate_zip.sh
# Creates the 1.maxcommgoo project files and packages them into 1.maxcommgoo.zip
# Usage:
#   chmod +x generate_zip.sh
#   ./generate_zip.sh
#
# After running you'll have:
#   ./1.maxcommgoo/   (project files)
#   ./1.maxcommgoo.zip

set -euo pipefail

ROOT_DIR="1.maxcommgoo"
ZIP_NAME="${ROOT_DIR}.zip"

echo "Creating project directory: ${ROOT_DIR}"
rm -rf "${ROOT_DIR}"
mkdir -p "${ROOT_DIR}"

# helper to write files
write() {
  local path="$1"
  shift
  mkdir -p "$(dirname "${ROOT_DIR}/${path}")"
  cat > "${ROOT_DIR}/${path}" <<'EOF'
$@
EOF
  echo "Wrote ${ROOT_DIR}/${path}"
}

# Files (README, .env.example, package.json, src, public, Dockerfile, docker-compose, workflows...)
write "README.md" \
"# 1.maxcommgoo

مستودع لأتمتة التطبيقات والبوتات وربط العملاء بواجهات ذكاء اصطناعي متعددة (OpenAI, ChatGPT, Google Gemini).

يحتوي المشروع على:
- واجهة تفاعلية (public/index.html) لإرسال \"طلبات روبوت\" عبر Socket.IO أو HTTP.
- مزج AI قابل للتبديل: OpenAI | ChatGPT | Google Gemini.
- موصلات (Connectors): Telegram (webhook مباشر)، Slack, WhatsApp (Twilio), Discord, HubSpot.
- Dockerfile و docker-compose لتشغيل المحلي بسرعة.
- Workflows أساسي في .github/workflows.

راجع .env.example لإعداد المفاتيح والمتغيرات البيئية اللازمة."

write ".env.example" \
"NODE_ENV=development
PORT=3000

# Default AI provider: openai | chatgpt | google_gemini
AI_PROVIDER=openai

# OpenAI
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini

# Google Gemini (PaLM)
GOOGLE_API_KEY=
GOOGLE_OAUTH_TOKEN=
GOOGLE_GEMINI_MODEL=models/gemini-1.0

# Telegram
TELEGRAM_TOKEN=
TELEGRAM_CHAT_ID=

# Slack
SLACK_BOT_TOKEN=

# Twilio (WhatsApp)
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_WHATSAPP_FROM=whatsapp:+1415xxxxxxx

# Discord
DISCORD_BOT_TOKEN=

# HubSpot
HUBSPOT_API_KEY="

write "package.json" \
'{
  "name": "1-maxcommgoo",
  "version": "0.3.0",
  "description": "Interactive automation & bots with multi-AI provider integration",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "NODE_ENV=development nodemon src/server.js",
    "lint": "eslint . || true",
    "test": "echo \"No tests yet\""
  },
  "engines": {
    "node": ">=18"
  },
  "dependencies": {
    "@slack/web-api": "^6.11.0",
    "axios": "^1.5.0",
    "body-parser": "^1.20.2",
    "dotenv": "^16.0.3",
    "express": "^4.18.2",
    "node-fetch": "^2.6.7",
    "socket.io": "^4.7.2",
    "twilio": "^4.9.0",
    "discord.js": "^14.11.0",
    "hubspot": "^7.0.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22",
    "eslint": "^8.40.0"
  }
}'

# minimal server + modules (same structure as previously provided)
write "src/server.js" \
"const express = require('express');
const http = require('http');
const path = require('path');
const bodyParser = require('body-parser');
const { Server } = require('socket.io');
require('dotenv').config();

const ai = require('./ai');
const telegramBot = require('./bot/telegram');
const slackConnector = require('./connectors/slack');
const whatsappConnector = require('./connectors/whatsapp-twilio');
const discordConnector = require('./connectors/discord');
const hubspotConnector = require('./connectors/hubspot');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, '..', 'public')));

// HTTP robot request
app.post('/api/request', async (req, res) => {
  try {
    const reqBody = req.body;
    const providerResponse = await ai.requestCompletion(reqBody);
    res.json({ ok: true, result: providerResponse });
  } catch (err) {
    console.error('/api/request error', err);
    res.status(500).json({ ok: false, error: String(err) });
  }
});

// Telegram webhook endpoint
app.post('/api/telegram/webhook', telegramBot.webhookHandler);

// Endpoints to call connectors
app.post('/api/send/slack', async (req, res) => {
  const { text, channel } = req.body;
  try {
    await slackConnector.sendMessage(channel, text);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err) });
  }
});

app.post('/api/send/whatsapp', async (req, res) => {
  const { text, to } = req.body;
  try {
    await whatsappConnector.sendWhatsApp(to, text);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err) });
  }
});

app.post('/api/send/discord', async (req, res) => {
  const { channelId, text } = req.body;
  try {
    await discordConnector.sendMessage(channelId, text);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err) });
  }
});

app.post('/api/hubspot/contact', async (req, res) => {
  try {
    const result = await hubspotConnector.createContact(req.body);
    res.json({ ok: true, result });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err) });
  }
});

// Socket.IO interactive channel
io.on('connection', (socket) => {
  console.log('Socket connected:', socket.id);

  socket.on('robot_request', async (payload) => {
    try {
      socket.emit('status', { status: 'processing' });
      const result = await ai.requestCompletion(payload);
      socket.emit('robot_response', { ok: true, result });
    } catch (err) {
      console.error('robot_request error', err);
      socket.emit('robot_response', { ok: false, error: String(err) });
    }
  });

  socket.on('disconnect', () => {
    console.log('Socket disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(\`1.maxcommgoo running on port \${PORT}\`);
});"

write "src/ai/index.js" \
"const openai = require('./openai-client');
const chatgpt = require('./chatgpt-client');
const gemini = require('./gemini-client');

const DEFAULT = process.env.AI_PROVIDER || 'openai';

async function requestCompletion(robotRequest = {}) {
  const provider = (robotRequest.options && robotRequest.options.provider) || DEFAULT;
  switch (provider.toLowerCase()) {
    case 'openai':
      return openai.requestCompletion(robotRequest);
    case 'chatgpt':
      return chatgpt.requestCompletion(robotRequest);
    case 'google_gemini':
    case 'gemini':
      return gemini.requestCompletion(robotRequest);
    default:
      throw new Error(\`Unknown AI provider: \${provider}\`);
  }
}

module.exports = { requestCompletion };"

write "src/ai/openai-client.js" \
"const fetch = require('node-fetch');
const OPENAI_KEY = process.env.OPENAI_API_KEY;

if (!OPENAI_KEY) {
  console.warn('OPENAI_API_KEY not set — OpenAI calls will fail.');
}

async function requestCompletion(robotRequest = {}) {
  const model = (robotRequest.options && robotRequest.options.model) || process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const messages = robotRequest.messages || [{ role: 'user', content: robotRequest.context || 'Hello' }];
  const body = {
    model,
    messages,
    max_tokens: (robotRequest.options && robotRequest.options.max_tokens) || 800,
    temperature: (robotRequest.options && robotRequest.options.temperature) || 0.2
  };

  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': \`Bearer \${OPENAI_KEY}\`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(\`OpenAI error \${res.status}: \${txt}\`);
  }
  const json = await res.json();
  return json;
}

module.exports = { requestCompletion };"

write "src/ai/chatgpt-client.js" \
"// For compatibility: uses same OpenAI-style endpoint; adapt if you have a different ChatGPT API.
const openai = require('./openai-client');

async function requestCompletion(robotRequest = {}) {
  return openai.requestCompletion(robotRequest);
}

module.exports = { requestCompletion };"

write "src/ai/gemini-client.js" \
"const axios = require('axios');

const GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
const GOOGLE_OAUTH_TOKEN = process.env.GOOGLE_OAUTH_TOKEN;
const DEFAULT_MODEL = process.env.GOOGLE_GEMINI_MODEL || 'models/gemini-1.0';

if (!GOOGLE_API_KEY && !GOOGLE_OAUTH_TOKEN) {
  console.warn('Google Gemini credentials not set (GOOGLE_API_KEY or GOOGLE_OAUTH_TOKEN). Calls will fail until provided.');
}

async function requestCompletion(robotRequest = {}) {
  const model = (robotRequest.options && robotRequest.options.model) || DEFAULT_MODEL;
  const promptMessages = robotRequest.messages || [{ role: 'user', content: robotRequest.context || 'Hello' }];
  const promptText = promptMessages.map(m => `${m.role}: ${m.content}`).join('\\n\\n');

  const body = {
    prompt: { text: promptText },
    temperature: (robotRequest.options && robotRequest.options.temperature) || 0.2,
    maxOutputTokens: (robotRequest.options && robotRequest.options.max_tokens) || 800
  };

  const url = `https://generativelanguage.googleapis.com/v1/${model}:generateText${GOOGLE_API_KEY ? `?key=${GOOGLE_API_KEY}` : ''}`;
  const headers = { 'Content-Type': 'application/json' };
  if (GOOGLE_OAUTH_TOKEN) headers['Authorization'] = `Bearer ${GOOGLE_OAUTH_TOKEN}`;

  const res = await axios.post(url, body, { headers });
  if (res.status < 200 || res.status >= 300) {
    throw new Error(\`Gemini error \${res.status}: \${JSON.stringify(res.data)}\`);
  }
  return res.data;
}

module.exports = { requestCompletion };"

write "src/bot/telegram.js" \
"const fetch = require('node-fetch');
require('dotenv').config();
const ai = require('../ai');

const TELEGRAM_TOKEN = process.env.TELEGRAM_TOKEN;
const TELEGRAM_API = TELEGRAM_TOKEN ? `https://api.telegram.org/bot${TELEGRAM_TOKEN}` : null;

async function webhookHandler(req, res) {
  try {
    const update = req.body;
    if (!update || !update.message) return res.json({ ok: true });
    const chatId = update.message.chat.id;
    const userText = update.message.text || '';

    const robotRequest = {
      type: 'chat',
      user_id: String(chatId),
      messages: [{ role: 'user', content: userText }],
      options: { model: process.env.OPENAI_MODEL || undefined, provider: process.env.AI_PROVIDER }
    };

    const aiResp = await ai.requestCompletion(robotRequest);

    let reply = 'لم أحصل على إجابة.';
    if (aiResp && aiResp.choices && aiResp.choices[0] && aiResp.choices[0].message) {
      reply = aiResp.choices[0].message.content;
    } else if (aiResp && aiResp.candidates) {
      reply = aiResp.candidates[0].content || reply;
    } else if (aiResp && aiResp.outputs && aiResp.outputs[0] && aiResp.outputs[0].content) {
      reply = aiResp.outputs[0].content[0].text || reply;
    } else if (typeof aiResp === 'string') {
      reply = aiResp;
    }

    if (TELEGRAM_API) {
      await fetch(`${TELEGRAM_API}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chatId, text: reply })
      });
    } else {
      console.log('[Telegram] token not configured; would reply:', reply);
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('Telegram webhook error', err);
    res.status(500).json({ ok: false, error: String(err) });
  }
}

module.exports = { webhookHandler };"

write "src/connectors/slack.js" \
"const { WebClient } = require('@slack/web-api');
const token = process.env.SLACK_BOT_TOKEN;
const client = token ? new WebClient(token) : null;

async function sendMessage(channel, text) {
  if (!client) throw new Error('SLACK_BOT_TOKEN not configured');
  await client.chat.postMessage({ channel, text });
}

module.exports = { sendMessage };"

write "src/connectors/whatsapp-twilio.js" \
"const twilio = require('twilio');
const sid = process.env.TWILIO_ACCOUNT_SID;
const token = process.env.TWILIO_AUTH_TOKEN;
const from = process.env.TWILIO_WHATSAPP_FROM;
const client = sid && token ? twilio(sid, token) : null;

async function sendWhatsApp(to, text) {
  if (!client) throw new Error('Twilio credentials not configured (TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN/TWILIO_WHATSAPP_FROM)');
  return client.messages.create({ from, to, body: text });
}

module.exports = { sendWhatsApp };"

write "src/connectors/discord.js" \
"const { Client, GatewayIntentBits } = require('discord.js');
const token = process.env.DISCORD_BOT_TOKEN;
let client = null;

function init() {
  if (!token) return null;
  client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages] });
  client.login(token).catch(err => console.error('Discord login failed', err));
  client.on('ready', () => console.log(`Discord bot logged in as ${client.user.tag}`));
  return client;
}

async function sendMessage(channelId, text) {
  if (!client) init();
  if (!client) throw new Error('DISCORD_BOT_TOKEN not configured');
  const channel = await client.channels.fetch(channelId);
  if (!channel) throw new Error('Discord channel not found');
  await channel.send(text);
}

module.exports = { sendMessage };"

write "src/connectors/hubspot.js" \
"const Hubspot = require('@hubspot/api-client');
const key = process.env.HUBSPOT_API_KEY;
const client = key ? new Hubspot.Client({ apiKey: key }) : null;

async function createContact(data) {
  if (!client) throw new Error('HUBSPOT_API_KEY not configured');
  const contactObj = {
    properties: {
      email: data.email || '',
      firstname: data.firstName || '',
      lastname: data.lastName || '',
      phone: data.phone || ''
    }
  };
  const res = await client.crm.contacts.basicApi.create(contactObj);
  return res;
}

module.exports = { createContact };"

write "public/index.html" \
"<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\" />
  <title>1.maxcommgoo — Interactive Robot Requests</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 20px; }
    textarea { width: 100%; height: 120px; }
    #log { white-space: pre-wrap; background:#f7f7f7; padding:10px; border:1px solid #ddd; height:200px; overflow:auto; }
  </style>
</head>
<body>
  <h2>1.maxcommgoo — واجهة تفاعلية</h2>

  <label>User ID: <input id=\"user_id\" value=\"user-123\" /></label><br/><br/>
  <label>Provider:
    <select id=\"provider\">
      <option value=\"openai\">OpenAI</option>
      <option value=\"chatgpt\">ChatGPT</option>
      <option value=\"google_gemini\">Google Gemini</option>
    </select>
  </label><br/>
  <label>Model: <input id=\"model\" placeholder=\"model (optional)\" /></label><br/>
  <label>Message:</label>
  <textarea id=\"message\">اكتب سؤالك هنا ...</textarea><br/>
  <button id=\"send\">أرسل عبر Socket.IO</button>
  <button id=\"httpSend\">أرسل عبر HTTP</button>

  <h3>Log</h3>
  <div id=\"log\"></div>

  <script src=\"/socket.io/socket.io.js\"></script>
  <script>
    const socket = io();
    const logEl = document.getElementById('log');
    const append = (t) => { logEl.innerText += t + \"\\n\"; logEl.scrollTop = logEl.scrollHeight; };

    socket.on('connect', () => append('Socket connected: ' + socket.id));
    socket.on('status', (s) => append('STATUS: ' + JSON.stringify(s)));
    socket.on('robot_response', (r) => append('RESPONSE: ' + JSON.stringify(r)));

    document.getElementById('send').addEventListener('click', () => {
      const user_id = document.getElementById('user_id').value;
      const message = document.getElementById('message').value;
      const provider = document.getElementById('provider').value;
      const model = document.getElementById('model').value || undefined;
      const payload = {
        type: 'chat',
        user_id,
        messages: [{ role:'user', content: message }],
        options: { provider, model }
      };
      append('Sending via socket: ' + JSON.stringify(payload));
      socket.emit('robot_request', payload);
    });

    document.getElementById('httpSend').addEventListener('click', async () => {
      const user_id = document.getElementById('user_id').value;
      const message = document.getElementById('message').value;
      const provider = document.getElementById('provider').value;
      const model = document.getElementById('model').value || undefined;
      const payload = { type:'chat', user_id, messages:[{role:'user', content:message}], options:{provider, model} };
      append('Sending via HTTP POST: ' + JSON.stringify(payload));
      try {
        const res = await fetch('/api/request', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const json = await res.json();
        append('HTTP RESPONSE: ' + JSON.stringify(json));
      } catch (err) {
        append('HTTP ERROR: ' + err);
      }
    });
  </script>
</body>
</html>"

write "Dockerfile" \
"FROM node:18-alpine
WORKDIR /usr/src/app
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY . .
EXPOSE 3000
CMD [\"node\", \"src/server.js\"]"

write "docker-compose.yml" \
"version: '3.8'
services:
  app:
    build: .
    ports:
      - \"3000:3000\"
    environment:
      - PORT=3000
      - AI_PROVIDER=${AI_PROVIDER}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - GOOGLE_API_KEY=${GOOGLE_API_KEY}
      - GOOGLE_OAUTH_TOKEN=${GOOGLE_OAUTH_TOKEN}
      - TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
      - SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}
      - TWILIO_ACCOUNT_SID=${TWILIO_ACCOUNT_SID}
      - TWILIO_AUTH_TOKEN=${TWILIO_AUTH_TOKEN}
      - DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
      - HUBSPOT_API_KEY=${HUBSPOT_API_KEY}
    volumes:
      - ./:/usr/src/app
    restart: unless-stopped"

write ".github/workflows/ci.yml" \
"name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

permissions:
  contents: read

jobs:
  node-ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
      - name: Install
        run: npm ci
      - name: Lint
        run: npm run lint || true
      - name: Run tests
        run: npm test || true"

write ".gitignore" \
"node_modules/
.env
.DS_Store
.vscode/
.idea/
npm-debug.log
dist/
build/"

write "scripts/run-automation.sh" \
"#!/usr/bin/env bash
set -e
echo \"Starting scheduled automation tasks...\"
if [ -f ./src/bot/telegram.js ]; then
  echo \"No-op: place automation commands here (curl, node scripts, etc.)\"
else
  echo \"No automation script found.\"
fi
echo \"Done.\"
"
chmod +x "${ROOT_DIR}/scripts/run-automation.sh" || true

echo "All files created under ./${ROOT_DIR}"

# create zip
if command -v zip >/dev/null 2>&1; then
  echo "Creating ZIP archive: ${ZIP_NAME}"
  rm -f "${ZIP_NAME}"
  (cd "${ROOT_DIR}" && zip -r "../${ZIP_NAME}" .) >/dev/null
  echo "Created ${ZIP_NAME}"
else
  echo "zip not found. To create the archive run:"
  echo "  cd ${ROOT_DIR} && zip -r ../${ZIP_NAME} ."
fi

echo "Done. Next steps:"
echo "1) cd ${ROOT_DIR}"
echo "2) npm ci"
echo "3) cp .env.example .env  # edit .env and add your API keys"
echo "4) npm run dev            # development server"
echo ""
echo "To create private GitHub repo and push (requires gh CLI):"
echo "  git init"
echo "  git add ."
echo "  git commit -m \"Initial commit — 1.maxcommgoo\""
echo "  gh repo create vivald212/1.maxcommgoo --private --source=. --remote=origin --push"
