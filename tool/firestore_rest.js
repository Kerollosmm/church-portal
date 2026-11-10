// Pure Web-API Firestore REST and Google OAuth2 client (zero native Node dependencies).
// Compatible with both Cloudflare Workers (workerd) and Node.js 22+.

/**
 * Converts a PEM-encoded RSA private key to a binary DER ArrayBuffer.
 * Works with PKCS#8 keys (standard for Google Cloud service accounts).
 */
export function pemToDer(pem) {
  const cleanPem = pem
    .replace(/-----BEGIN[ A-Z0-9_-]+-----/g, '')
    .replace(/-----END[ A-Z0-9_-]+-----/g, '')
    .replace(/\s+/g, '');
  const binaryString = atob(cleanPem);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

/**
 * Base64URL-encodes an ArrayBuffer or Uint8Array without padding.
 */
export function base64UrlFromBytes(bytes) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = '';
  for (let i = 0; i < arr.length; i++) {
    binary += String.fromCharCode(arr[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/**
 * Base64URL-encodes a UTF-8 string without padding.
 */
export function base64UrlEncode(str) {
  return base64UrlFromBytes(new TextEncoder().encode(str));
}

/**
 * Mints an OAuth2 Google Access Token using standard Web Crypto RS256 signing.
 * Stateless per-run (< 1ms execution, no isolate caching required).
 *
 * @param {object} sa Parsed Google Service Account JSON.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @param {number} [nowMs=Date.now()] Current timestamp in ms.
 * @returns {Promise<string>} Bearer access token.
 */
export async function mintAccessToken(sa, fetchImpl = fetch, nowMs = Date.now()) {
  const tokenUri = sa.token_uri || 'https://oauth2.googleapis.com/token';
  const nowSec = Math.floor(nowMs / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
    aud: tokenUri,
    exp: nowSec + 3600,
    iat: nowSec,
  };

  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);

  const derKey = pemToDer(sa.private_key);
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    derKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, signInput);
  const sigB64 = base64UrlFromBytes(signature);
  const jwt = `${headerB64}.${payloadB64}.${sigB64}`;

  const params = new URLSearchParams();
  params.set('grant_type', 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  params.set('assertion', jwt);

  const res = await fetchImpl(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to mint Google OAuth token (${res.status}): ${text}`);
  }

  const json = await res.json();
  return json.access_token;
}

let _l1Token = null;
let _l1ExpiresAt = 0;

export function _resetL1TokenCacheForTesting() {
  _l1Token = null;
  _l1ExpiresAt = 0;
}

/**
 * Two-tier Google OAuth2 access token cache (ADR-060):
 * - L1: In-memory module cache (valid within the same isolate invocation)
 * - L2: Cloudflare Workers KV cache (PUSH_KV binding, 55 min TTL)
 * Fail-open: falls back to minting fresh token if KV errors or is absent.
 *
 * @param {object} sa Parsed Google Service Account JSON.
 * @param {object} [env=null] Cloudflare Workers env (may contain PUSH_KV).
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @param {number} [nowMs=Date.now()] Current timestamp in ms.
 * @returns {Promise<string>} Bearer access token.
 */
export async function getCachedAccessToken(sa, env = null, fetchImpl = fetch, nowMs = Date.now()) {
  const marginMs = 5 * 60 * 1000; // 5 minute safety buffer

  // Check L1 cache
  if (_l1Token && nowMs < _l1ExpiresAt - marginMs) {
    return _l1Token;
  }

  const kvKey = `oauth_token_${sa.client_email || 'default'}`;

  // Check L2 KV cache if available
  if (env?.PUSH_KV) {
    try {
      const kvVal = await env.PUSH_KV.get(kvKey, { type: 'json' });
      if (kvVal?.token && typeof kvVal.expiresAt === 'number' && nowMs < kvVal.expiresAt - marginMs) {
        _l1Token = kvVal.token;
        _l1ExpiresAt = kvVal.expiresAt;
        return _l1Token;
      }
    } catch (_) {
      // Fail-open: KV read error does not block execution
    }
  }

  // Mint new token
  const token = await mintAccessToken(sa, fetchImpl, nowMs);
  const expiresAt = nowMs + 3600 * 1000;
  _l1Token = token;
  _l1ExpiresAt = expiresAt;

  // Persist to L2 KV (55 min TTL = 3300s)
  if (env?.PUSH_KV?.put) {
    try {
      await env.PUSH_KV.put(
        kvKey,
        JSON.stringify({ token, expiresAt }),
        { expirationTtl: 3300 },
      );
    } catch (_) {
      // Fail-open: KV write error does not block execution
    }
  }

  return token;
}

/**
 * Converts a JS value to a Firestore REST Value object.
 */
export function toFirestoreValue(v) {
  if (v === null || v === undefined) {
    return { nullValue: null };
  }
  if (typeof v === 'boolean') {
    return { booleanValue: v };
  }
  if (typeof v === 'number') {
    if (Number.isInteger(v)) {
      return { integerValue: String(v) };
    }
    return { doubleValue: v };
  }
  if (typeof v === 'string') {
    return { stringValue: v };
  }
  if (v instanceof Date) {
    return { timestampValue: v.toISOString() };
  }
  if (Array.isArray(v)) {
    return { arrayValue: { values: v.map(toFirestoreValue) } };
  }
  if (typeof v === 'object') {
    return { mapValue: { fields: toFirestoreFields(v) } };
  }
  return { stringValue: String(v) };
}

/**
 * Converts a JS object to a map of Firestore REST field values.
 */
export function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) {
      fields[k] = toFirestoreValue(v);
    }
  }
  return fields;
}

/**
 * Converts a Firestore REST Value object to a native JS value.
 */
export function fromFirestoreValue(v) {
  if (!v || typeof v !== 'object') return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return parseInt(v.integerValue, 10);
  if ('doubleValue' in v) return v.doubleValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) {
    return (v.arrayValue?.values || []).map(fromFirestoreValue);
  }
  if ('mapValue' in v) {
    return fromFirestoreFields(v.mapValue?.fields || {});
  }
  return null;
}

/**
 * Converts a map of Firestore REST field values to a native JS object.
 */
export function fromFirestoreFields(fields) {
  const obj = {};
  for (const [k, v] of Object.entries(fields || {})) {
    obj[k] = fromFirestoreValue(v);
  }
  return obj;
}

/**
 * Batch-gets multiple Firestore documents in a single HTTP subrequest.
 * Consumes exactly 1 read per found document.
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {string[]} docPaths Relative paths, e.g. ['settings/features', 'settings/notifications'].
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @returns {Promise<Map<string, { data: object|null, updateTime: string|null }>>} Map of docPath -> doc info.
 */
export async function batchGetDocs(projectId, token, docPaths, fetchImpl = fetch) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:batchGet`;
  const prefix = `projects/${projectId}/databases/(default)/documents/`;
  const documents = docPaths.map((p) => `${prefix}${p}`);

  const res = await fetchImpl(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ documents }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore batchGet failed (${res.status}): ${text}`);
  }

  const results = new Map();
  for (const p of docPaths) {
    results.set(p, { data: null, updateTime: null });
  }

  // Response can be a JSON array or a stream of chunked JSON objects
  const rawText = await res.text();
  let items = [];
  try {
    const parsed = JSON.parse(rawText);
    items = Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    // Array of concatenated JSON objects
    const re = /\{"found":\{.*?\}\},"readTime":"[^"]+"\}|\{"missing":"[^"]+","readTime":"[^"]+"\}/g;
    const matches = rawText.match(re) || [];
    for (const m of matches) {
      try {
        items.push(JSON.parse(m));
      } catch {}
    }
  }

  for (const item of items) {
    if (item.found) {
      const fullPath = item.found.name || '';
      const docIdx = fullPath.indexOf('/documents/');
      const relPath = docIdx !== -1 ? fullPath.slice(docIdx + '/documents/'.length) : (fullPath.startsWith(prefix) ? fullPath.slice(prefix.length) : fullPath);
      results.set(relPath, {
        data: fromFirestoreFields(item.found.fields),
        updateTime: item.found.updateTime || null,
      });
    }
  }

  return results;
}

/**
 * Patches a Firestore document with explicit field mask and optional updateTime precondition.
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {string} docPath Relative path, e.g. 'settings/notifications'.
 * @param {object} fields JS object of field values to patch.
 * @param {string[]} maskFields List of field paths to update.
 * @param {string|null} [currentUpdateTime=null] Precondition: document updateTime must match.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @returns {Promise<{ data: object, updateTime: string }>}
 */
export async function patchDoc(
  projectId,
  token,
  docPath,
  fields,
  maskFields,
  currentUpdateTime = null,
  fetchImpl = fetch,
) {
  const query = new URLSearchParams();
  for (const f of maskFields) {
    query.append('updateMask.fieldPaths', f);
  }
  if (currentUpdateTime) {
    query.set('currentDocument.updateTime', currentUpdateTime);
  }

  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}?${query.toString()}`;
  const firestoreFields = toFirestoreFields(fields);

  const res = await fetchImpl(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: firestoreFields }),
  });

  if (res.status === 409 || res.status === 412) {
    const text = await res.text();
    const err = new Error(`Precondition failed on ${docPath}: ${text}`);
    err.status = res.status;
    err.isConflict = true;
    throw err;
  }

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore patch failed on ${docPath} (${res.status}): ${text}`);
  }

  const json = await res.json();
  return {
    data: fromFirestoreFields(json.fields),
    updateTime: json.updateTime || null,
  };
}

/**
 * Lists documents in a Firestore collection (e.g. 'seasons').
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {string} collectionId Collection name.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @returns {Promise<Array<{ id: string, data: object, updateTime: string }>>}
 */
export async function listCollection(projectId, token, collectionId, fetchImpl = fetch) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collectionId}?pageSize=100`;

  const res = await fetchImpl(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore listCollection failed on ${collectionId} (${res.status}): ${text}`);
  }

  const json = await res.json();
  const docs = json.documents || [];
  return docs.map((d) => {
    const id = d.name.split('/').pop();
    return {
      id,
      data: fromFirestoreFields(d.fields || {}),
      updateTime: d.updateTime || null,
    };
  });
}

/**
 * Escapes field paths for Firestore updateMask.fieldPaths.
 * Wraps segments containing '-' or other special chars in backticks.
 * e.g. "topics.web_rem_lit-sun1_60_ar" -> "topics.`web_rem_lit-sun1_60_ar`"
 *
 * @param {string} path Field path.
 * @returns {string} Escaped field path.
 */
export function escapeFieldPath(path) {
  return path
    .split('.')
    .map((seg) => (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(seg) ? seg : `\`${seg}\``))
    .join('.');
}

/**
 * Commits a batch of writes atomically via Firestore REST :commit endpoint.
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {Array<object>} writes Firestore Write objects.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @returns {Promise<{ writeResults: Array<object>, commitTime: string }>}
 */
export async function commitWrites(projectId, token, writes, fetchImpl = fetch) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`;

  const res = await fetchImpl(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ writes }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore commit failed (${res.status}): ${text}`);
  }

  return await res.json();
}

/**
 * Runs a structured query against Firestore via :runQuery endpoint.
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {object} structuredQuery Firestore StructuredQuery object.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @returns {Promise<Array<{ id: string, data: object, createTime: string, updateTime: string }>>}
 */
export async function queryCollection(projectId, token, structuredQuery, fetchImpl = fetch) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;

  const res = await fetchImpl(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ structuredQuery }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore runQuery failed (${res.status}): ${text}`);
  }

  const rawText = await res.text();
  let items = [];
  try {
    const parsed = JSON.parse(rawText);
    items = Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    const re = /\{"document":\{.*?\},"readTime":"[^"]+"\}|\{"readTime":"[^"]+"\}/g;
    const matches = rawText.match(re) || [];
    for (const m of matches) {
      try {
        items.push(JSON.parse(m));
      } catch {}
    }
  }

  const results = [];
  for (const item of items) {
    if (item.document) {
      const fullPath = item.document.name || '';
      const id = fullPath.split('/').pop();
      results.push({
        id,
        data: fromFirestoreFields(item.document.fields || {}),
        createTime: item.document.createTime || null,
        updateTime: item.document.updateTime || null,
      });
    }
  }
  return results;
}

/**
 * Sets (creates or overwrites) a document in Firestore.
 *
 * @param {string} projectId Google Cloud Project ID.
 * @param {string} token Google OAuth2 Bearer token.
 * @param {string} docPath Relative document path.
 * @param {object} fields Document data.
 * @param {typeof fetch} [fetchImpl=fetch] Fetch implementation.
 * @returns {Promise<{ data: object, updateTime: string }>}
 */
export async function setDocRest(projectId, token, docPath, fields, fetchImpl = fetch) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}`;
  const firestoreFields = toFirestoreFields(fields);

  const res = await fetchImpl(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: firestoreFields }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore setDoc failed on ${docPath} (${res.status}): ${text}`);
  }

  const json = await res.json();
  return {
    data: fromFirestoreFields(json.fields),
    updateTime: json.updateTime || null,
  };
}

