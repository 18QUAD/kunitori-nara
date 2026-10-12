import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {affiliateUrl, itemAds, hotelAds, handleRequest} from './worker.mjs';
import regions from './regions.json' with {type: 'json'};

const env = {RAKUTEN_APPLICATION_ID: 'test-app', RAKUTEN_ACCESS_KEY: 'test-key',
  RAKUTEN_AFFILIATE_ID: 'test-affiliate'};
const link = 'https://hb.afl.rakuten.co.jp/hgc/test/?pc=test';
const product = {shopCode: 'suncoco', shopName: 'ふとんのマルソウ',
  itemName: 'テスト用の商品', availability: 1, affiliateRate: 2, affiliateUrl: link};
const request = city => new Request(`https://worker.example/ads?city=${city}`,
  {headers: {Origin: 'https://18quad.github.io'}});
const context = {waitUntil(promise) {return promise;}};

test('all 39 game municipality IDs are configured', () => {
  const atlas = JSON.parse(fs.readFileSync('../../assets/data/nara.json'));
  assert.deepEqual(Object.keys(regions).sort(), atlas.cities.map(c => c.id).sort());
});

test('local products require a verified shop, availability, and affiliate URL', () => {
  const data = {Items: [product, {...product, shopCode: 'outside'},
    {...product, availability: 0}, {...product, affiliateRate: 0},
    {...product, affiliateUrl: 'https://item.rakuten.co.jp/test'}]};
  const ads = itemAds(data, '29201', regions['29201'], 'product', regions['29201'].shops[0]);
  assert.equal(ads.length, 1);
  assert.equal(ads[0].advertiser, 'ふとんのマルソウ');
  assert.equal(affiliateUrl('https://hb.afl.rakuten.co.jp.evil.test/'), null);
  assert.equal(affiliateUrl('javascript:alert(1)'), null);
});

test('furusato discovery accepts only exact municipality shops and excludes donation-only', () => {
  const item = {...product, shopCode: 'f294461-tenkawa', shopName: '奈良県天川村'};
  const data = {Items: [{Item: item}, {Item: {...item, shopName: '奈良県奈良市'}},
    {Item: {...item, itemName: 'ふるさと納税 返礼品なし'}}]};
  assert.equal(itemAds(data, '29446', regions['29446'], 'furusato', null).length, 1);
});

test('hotel address must match Nara and the municipality including county prefixes', () => {
  const hotel = {hotelName: 'テスト旅館', hotelInformationUrl: link,
    address1: '奈良県', address2: '吉野郡吉野町吉野山1'};
  const data = {hotels: [hotel, {...hotel, address1: '徳島県'},
    {...hotel, address2: '吉野郡大淀町1'}].map(h => ({hotel: [{hotelBasicInfo: h}]}))};
  assert.equal(hotelAds(data, '29441', regions['29441']).length, 1);
  assert.equal(hotelAds({hotels: [{hotel: [{hotelBasicInfo: {...hotel,
    address2: '奈良市1'}}]}]}, '29201', regions['29201']).length, 1);
});

test('unknown regions, disallowed origins, and missing credentials never call Rakuten', async () => {
  const options = {fetcher() {throw new Error('unexpected call');}};
  assert.equal((await handleRequest(request('13101'), env, context, options)).status, 400);
  assert.equal((await handleRequest(request('29201'), {}, context, options)).status, 503);
  const bad = new Request('https://worker.example/ads?city=29201',
    {headers: {Origin: 'https://evil.test'}});
  assert.equal((await handleRequest(bad, env, context, options)).status, 403);
});

test('credentials stay upstream; category failures do not hide valid ads; cache expires', async () => {
  let time = new Date('2026-10-12T00:00:00Z');
  let calls = 0;
  const entries = new Map();
  const cache = {async match(key) {return entries.get(key.url)?.clone();},
    async put(key, response) {entries.set(key.url, response);}};
  const options = {cache, now: () => time, pause: async () => {},
    fetcher: async (url, init) => {
      calls++;
      assert.equal(init.headers.accessKey, env.RAKUTEN_ACCESS_KEY);
      assert.equal(url.searchParams.get('applicationId'), env.RAKUTEN_APPLICATION_ID);
      assert.equal(url.searchParams.get('affiliateId'), env.RAKUTEN_AFFILIATE_ID);
      if (url.pathname.includes('Travel')) return new Response('', {status: 429});
      const items = url.searchParams.get('shopCode') === 'suncoco' ? [product] : [];
      return Response.json({Items: items});
    }};
  const response = await handleRequest(request('29201'), env, context, options);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  const body = await response.json();
  assert.equal(body.ads.length, 1);
  assert.equal(body.expiresAt, '2026-10-12T00:05:00.000Z');
  assert.equal(JSON.stringify(body).includes('test-key'), false);
  assert.equal(JSON.stringify(body).includes('test-app'), false);
  const firstCalls = calls;
  await handleRequest(request('29201'), env, context, options);
  assert.equal(calls, firstCalls);
  time = new Date('2026-10-12T00:06:00Z');
  await handleRequest(request('29201'), env, context, options);
  assert.ok(calls > firstCalls);
});
