/**
 * Darling File —— 中转服务 v2（relay.darling02.de5.net）
 * 无存储中转：Durable Objects + WebSocket 实时转发，数据流过即走、不落盘。
 *  - 登录复用 Darling AI 账号（同一 JWT_SECRET + D1）
 *  - POST /api/session           创建传输会话（发送端），返回 sessionId
 *  - GET  /api/session/{id}      查询会话信息（供接收端加入）
 *  - GET  /api/myip              返回客户端公网出口 IP:PORT（用于 P2P 打洞候选）
 *  - WS   /api/ws/{id}           中转管道：发送端发数据块 → DO 转发给接收端
 *  - 会话空闲 10 分钟自动清理（不占存储）
 */

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

// ---------- JWT（与主 API Worker 同算法/同密钥，账号互通） ----------
function b64url(buf) {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
async function verifyJwt(token, secret) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('HMAC', key, b64urlDecode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
    if (!ok) return null;
    const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

function json(resp, status = 200) {
  return new Response(JSON.stringify(resp), { status, headers: JSON_HEADERS });
}

async function authUser(req, env) {
  let token = '';
  const ah = req.headers.get('Authorization') || '';
  if (ah.startsWith('Bearer ')) token = ah.slice(7);
  if (!token) {
    const u = new URL(req.url);
    token = u.searchParams.get('token') || '';
  }
  if (!token) return null;
  // 通过 service binding 调用主 API 验证（JWT 由主 API 的线上 secret 签发）
  try {
    const resp = await env.MAINAPI.fetch('https://darling-ai-cloud/internal/verify', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'X-Internal-Key': env.INTERNAL_KEY || '',
      },
    });
    if (resp.status !== 200) return null;
    const data = await resp.json();
    if (!data.ok || !data.id) return null;
    return { sub: String(data.id), email: data.email, role: data.role };
  } catch {
    return null;
  }
}

// ============================================================
// Durable Object：一个会话一个实例，纯内存转发（不落盘）
// ============================================================
export class Relay {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.clients = new Map(); // ws -> {role: 'send'|'recv', meta}
    this.meta = null;
    state.blockConcurrencyWhile(async () => {
      this.meta = await state.storage.get('meta') || null;
    });
  }

  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname.includes('/api/ws/')) {
      if (req.headers.get('Upgrade') !== 'websocket') return json({ error: 'ws required' }, 400);
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      const role = url.searchParams.get('role') || 'recv';
      server.accept();
      this.clients.set(server, { role });
      server.addEventListener('message', (ev) => {
        // 二进制块直接转发给另一端；JSON 控制消息同样转发并记录 meta
        if (typeof ev.data === 'string') {
          try {
            const j = JSON.parse(ev.data);
            if (j.type === 'meta') {
              this.meta = j;
              this.state.storage.put('meta', j);
            }
          } catch {}
        }
        for (const [other, info] of this.clients) {
          if (other !== server) {
            other.send(ev.data);
          }
        }
      });
      server.addEventListener('close', () => {
        this.clients.delete(server);
        // 通知另一端：对端已断开
        for (const [other] of this.clients) {
          try { other.send(JSON.stringify({ type: 'peer_closed' })); } catch {}
        }
        if (this.clients.size === 0) {
          // 会话结束：清除元数据（不落盘文件，仅清状态）
          this.state.storage.delete('meta').catch(() => {});
        }
      });
      // 会话空闲 10 分钟自动清理
      this.state.storage.setAlarm(Date.now() + 10 * 60 * 1000);
      return new Response(null, { status: 101, webSocket: client });
    }
    if (url.pathname.endsWith('/status')) {
      return json({ ok: true, clients: this.clients.size, meta: this.meta });
    }
    if (url.pathname.endsWith('/close')) {
      // 发送端停止闪传：踢掉所有连接并清状态
      for (const [ws] of this.clients) {
        try { ws.close(1000, 'session closed'); } catch {}
      }
      this.clients.clear();
      await this.state.storage.deleteAll();
      return json({ ok: true });
    }
    return json({ error: 'not found' }, 404);
  }

  async alarm() {
    if (this.clients.size === 0) {
      await this.state.storage.deleteAll();
    }
  }
}

// 会话口令字符集：大写字母(去 I/O) + 数字(去 0/1)，避免看错
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LEN = 6;
const SESSION_TTL = 10 * 60; // 10 分钟

function genCode() {
  let s = '';
  const rnd = new Uint8Array(CODE_LEN);
  crypto.getRandomValues(rnd);
  for (let i = 0; i < CODE_LEN; i++) s += CODE_CHARS[rnd[i] % CODE_CHARS.length];
  return s;
}

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: JSON_HEADERS });
    const url = new URL(req.url);
    const path = url.pathname;

    // ---------- 创建会话（发送端，登录；生成唯一 6 位口令） ----------
    if (path === '/api/session' && req.method === 'POST') {
      const user = await authUser(req, env);
      if (!user) return json({ error: '未登录或登录已过期' }, 401);
      let body = {};
      try { body = await req.json(); } catch {}
      const now = Math.floor(Date.now() / 1000);
      // 顺手清理过期会话
      await env.DB.prepare('DELETE FROM relay_sessions WHERE expires_at < ?').bind(now).run();
      // 生成不重复的 6 位口令
      let code = '';
      for (let i = 0; i < 10; i++) {
        code = genCode();
        const exists = await env.DB.prepare('SELECT code FROM relay_sessions WHERE code = ?').bind(code).first();
        if (!exists) break;
        code = '';
      }
      if (!code) return json({ error: '口令生成繁忙，请重试' }, 503);
      const sessionId = crypto.randomUUID().replace(/-/g, '').slice(0, 20);
      const expiresAt = now + SESSION_TTL;
      await env.DB.prepare(
        'INSERT INTO relay_sessions (code, session_id, user_id, created_at, expires_at) VALUES (?,?,?,?,?)'
      ).bind(code, sessionId, user.sub, now, expiresAt).run();
      const base = env.PUBLIC_BASE || `https://${url.host}`;
      return json({
        ok: true,
        code,
        sessionId,
        wsUrl: `${base.replace(/^http/, 'ws')}/api/ws/${sessionId}`,
        url: `${base}/${code}`,
        expiresAt,
      });
    }

    // ---------- 查询会话（接收端，免登录，输入网址+口令） ----------
    if (path.startsWith('/api/session/') && req.method === 'GET') {
      const code = (path.split('/')[3] || '').toUpperCase();
      if (!code || code.length !== CODE_LEN) return json({ error: '口令无效' }, 400);
      const row = await env.DB.prepare('SELECT * FROM relay_sessions WHERE code = ?').bind(code).first();
      if (!row) return json({ error: '口令不存在或已失效（发送方可能已停止闪传）' }, 404);
      const now = Math.floor(Date.now() / 1000);
      if (row.expires_at < now) {
        await env.DB.prepare('DELETE FROM relay_sessions WHERE code = ?').bind(code).run();
        return json({ error: '口令已过期' }, 404);
      }
      const base = env.PUBLIC_BASE || `https://${url.host}`;
      return json({
        ok: true,
        code: row.code,
        sessionId: row.session_id,
        wsUrl: `${base.replace(/^http/, 'ws')}/api/ws/${row.session_id}`,
        url: `${base}/${row.code}`,
      });
    }

    // ---------- 释放口令（发送端关闭应用/停止闪传时调用，登录且仅本人） ----------
    if (path.startsWith('/api/session/') && req.method === 'DELETE') {
      const user = await authUser(req, env);
      if (!user) return json({ error: '未登录' }, 401);
      const code = (path.split('/')[3] || '').toUpperCase();
      const row = await env.DB.prepare('SELECT * FROM relay_sessions WHERE code = ?').bind(code).first();
      if (!row) return json({ error: '口令不存在' }, 404);
      if (String(row.user_id) !== String(user.sub)) return json({ error: '无权释放' }, 403);
      await env.DB.prepare('DELETE FROM relay_sessions WHERE code = ?').bind(code).run();
      // 清理 DO 会话状态
      const id = env.RELAY.idFromName(row.session_id);
      const stub = env.RELAY.get(id);
      try { await stub.fetch(`https://relay/close`); } catch {}
      return json({ ok: true });
    }

    // ---------- 中转管道（WS → DO 转发） ----------
    if (path.startsWith('/api/ws/') && req.method === 'GET') {
      const sessionId = path.split('/')[3];
      if (!sessionId) return json({ error: 'missing session' }, 400);
      const id = env.RELAY.idFromName(sessionId);
      const stub = env.RELAY.get(id);
      return stub.fetch(req);
    }

    // ---------- 公网出口 IP（打洞候选） ----------
    if (path === '/api/myip' && req.method === 'GET') {
      const cf = req.headers.get('CF-Connecting-IP') || 'unknown';
      return json({ ok: true, ip: cf });
    }

    if (path === '/api/ping') return json({ ok: true, service: 'darling-file-relay-v2' });
    return json({ error: 'not found' }, 404);
  },
};
