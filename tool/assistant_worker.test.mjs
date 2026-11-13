import test from 'node:test';
import assert from 'node:assert/strict';
import { ASSISTANT_APP_ID, ASSISTANT_LIMITS, cairoDayKey, handleAssistantRequest } from './assistant_worker.js';

function kv() {
  const m = new Map();
  return {
    async get(k) {
      return m.has(k) ? m.get(k) : null;
    },
    async put(k, v) {
      m.set(k, v);
    },
  };
}

function call(env, body, { device = 'ab'.repeat(16), headers = {}, now, ip = '203.0.113.5', fetchImpl } = {}) {
  return handleAssistantRequest(
    new Request('https://worker.example/assistant', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-church-app': ASSISTANT_APP_ID, 'x-church-device': device, ...headers },
      body: JSON.stringify(body),
    }),
    env,
    { now, ip, fetchImpl },
  );
}

const okBody = {
  model: 'gemini-3.1-flash-lite',
  instruction: 'church only',
  history: [],
  prompt: 'متى القداس؟',
};

test('cairo day is yyyymmdd in winter (UTC+2)', () => {
  assert.equal(cairoDayKey(new Date('2026-11-13T22:30:00Z')), '20261114');
  assert.equal(cairoDayKey(new Date('2026-11-13T21:30:00Z')), '20261113');
});

test('rejects a missing app id and a short device id', async () => {
  const env = { GEMINI_API_KEY: 'secret', PUSH_KV: kv() };
  const missing = await call(env, okBody, { headers: { 'x-church-app': '' } });
  assert.equal(missing.status, 403);
  const bad = await call(env, okBody, { device: 'nope' });
  assert.equal(bad.status, 400);
});

test('does not call Gemini when the device cap is already reached', async () => {
  let called = 0;
  const store = kv();
  const day = cairoDayKey(new Date('2026-11-13T10:00:00Z'));
  const device = 'cd'.repeat(16);
  await store.put(`asst:${day}`, JSON.stringify({ n: 1, d: { [device]: ASSISTANT_LIMITS.devicePerDay }, i: {}, m: {} }));
  const res = await call(
    { GEMINI_API_KEY: 'secret', PUSH_KV: store },
    okBody,
    {
      device,
      now: new Date('2026-11-13T10:00:00Z'),
      fetchImpl: async () => {
        called += 1;
        return new Response('{}', { status: 200 });
      },
    },
  );
  assert.equal(res.status, 429);
  assert.equal(called, 0);
  assert.equal(JSON.parse(await res.text()).error, 'device_cap');
});

test('returns the model text and counts the question', async () => {
  const store = kv();
  const res = await call(
    { GEMINI_API_KEY: 'secret', PUSH_KV: store },
    okBody,
    {
      now: new Date('2026-11-13T10:00:00Z'),
      fetchImpl: async (_url, init) => {
        assert.equal(init.headers['x-goog-api-key'], 'secret');
        const sent = JSON.parse(init.body);
        assert.equal(sent.systemInstruction.parts[0].text, 'church only');
        assert.equal(sent.generationConfig.temperature, 0.2);
        assert.equal(sent.generationConfig.maxOutputTokens, 1024);
        return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'الجمعة ٦ م' }] } }] }), { status: 200 });
      },
    },
  );
  assert.equal(res.status, 200);
  assert.equal(JSON.parse(await res.text()).text, 'الجمعة ٦ م');
  const saved = JSON.parse(await store.get(`asst:${cairoDayKey(new Date('2026-11-13T10:00:00Z'))}`));
  assert.equal(saved.n, 1);
});

test('accepts a grounding instruction the old 24000 cap rejected, and a reply-sized history turn', async () => {
  let called = 0;
  const instruction = 'خ'.repeat(29085);
  const reply = 'ر'.repeat(ASSISTANT_LIMITS.maxTurnChars);
  const res = await call(
    { GEMINI_API_KEY: 'secret', PUSH_KV: kv() },
    {
      model: 'gemini-3.1-flash-lite',
      instruction,
      history: [{ user: false, text: reply }, { user: true, text: 'متى القداس؟' }],
      prompt: '[Current Cairo time: 2026-11-13 14:41 (Friday)]\nمتى القداس؟',
    },
    {
      now: new Date('2026-11-13T12:00:00Z'),
      fetchImpl: async () => {
        called += 1;
        return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'الجمعة' }] } }] }), { status: 200 });
      },
    },
  );
  assert.equal(res.status, 200);
  assert.equal(called, 1);
});

test('rejects an instruction past 150000 and a history turn past 8000 without calling Gemini', async () => {
  let called = 0;
  const fetchImpl = async () => {
    called += 1;
    return new Response('{}', { status: 200 });
  };
  const env = { GEMINI_API_KEY: 'secret', PUSH_KV: kv() };
  const tooLong = await call(env, { ...okBody, instruction: 'x'.repeat(ASSISTANT_LIMITS.maxInstruction + 1) }, { fetchImpl });
  assert.equal(tooLong.status, 400);
  assert.equal(JSON.parse(await tooLong.text()).error, 'bad_request');
  const turn = await call(
    env,
    { ...okBody, history: [{ user: false, text: 'y'.repeat(ASSISTANT_LIMITS.maxTurnChars + 1) }] },
    { fetchImpl },
  );
  assert.equal(turn.status, 400);
  assert.equal(called, 0);
});
