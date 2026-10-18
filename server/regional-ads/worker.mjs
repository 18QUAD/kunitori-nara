import regions from './regions.json' with { type: 'json' };

const ITEM_API = 'https://openapi.rakuten.co.jp/ichibams/api/IchibaItem/Search/20260701';
const HOTEL_API = 'https://openapi.rakuten.co.jp/engine/api/Travel/KeywordHotelSearch/20260731';
const TTL = 3600;
const text = value => typeof value === 'string' ? value.trim() : '';
const normalize = value => text(value).replace(/[\s　]/g, '');

export function affiliateUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname === 'hb.afl.rakuten.co.jp' &&
      !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

function imageUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password &&
      ['thumbnail.image.rakuten.co.jp', 'image.rakuten.co.jp',
        'img.travel.rakuten.co.jp'].includes(url.hostname) ? url.href : null;
  } catch { return null; }
}

export function itemAds(data, cityId, region, category, shop) {
  const result = [];
  for (const entry of data.Items ?? []) {
    const item = entry.Item ?? entry;
    const code = text(item.shopCode);
    const merchant = normalize(item.shopName);
    // Unknown municipality shops are accepted only on an exact municipality name.
    const correctShop = shop ? code === shop.code :
      [region.taxName, `${region.prefecture}${region.taxName}`].map(normalize).includes(merchant) &&
        code.startsWith(`f${region.taxCityId}`) && /^f\d{6}(?:-|$)/.test(code);
    const url = affiliateUrl(item.affiliateUrl);
    if (!correctShop || !url || !text(item.itemName) ||
        Number(item.availability) !== 1 || !(Number(item.affiliateRate) > 0)) continue;
    if (category === 'furusato' && /返礼品なし|返礼品無し|寄附のみ|寄付のみ|災害支援/.test(item.itemName)) continue;
    result.push({
      cityId, category, name: text(item.itemName),
      advertiser: shop?.name ?? text(item.shopName), url,
      imageUrl: imageUrl(item.mediumImageUrls?.[0]?.imageUrl),
    });
    if (result.length === 2) break;
  }
  return result;
}

export function hotelAds(data, cityId, region) {
  const result = [];
  for (const entry of data.hotels ?? []) {
    const hotel = (entry.hotel ?? []).find(part => part.hotelBasicInfo)?.hotelBasicInfo;
    if (!hotel) continue;
    const address = normalize(`${text(hotel.address1)}${text(hotel.address2)}`);
    // Hotel names and search keywords alone do not establish the location.
    const prefecture = normalize(region.prefecture);
    const localAddress = address.startsWith(prefecture) ? address.slice(prefecture.length) : '';
    const local = localAddress.startsWith(normalize(region.name)) ||
      (/[町村]$/.test(region.name) && new RegExp(`^[^郡]+郡${region.name}`).test(localAddress));
    const url = affiliateUrl(hotel.hotelInformationUrl);
    if (!local || !url || !text(hotel.hotelName)) continue;
    result.push({cityId, category: 'hotel', name: text(hotel.hotelName),
      advertiser: text(hotel.hotelName), url,
      imageUrl: imageUrl(hotel.hotelImageUrl)});
    if (result.length === 2) break;
  }
  return result;
}

async function requestApi(endpoint, parameters, env, fetcher) {
  const url = new URL(endpoint);
  url.search = new URLSearchParams({
    applicationId: env.RAKUTEN_APPLICATION_ID,
    affiliateId: env.RAKUTEN_AFFILIATE_ID, format: 'json', ...parameters,
  });
  const response = await fetcher(url, {
    headers: {accessKey: env.RAKUTEN_ACCESS_KEY,
      Origin: env.ALLOWED_ORIGIN ?? 'https://18quad.github.io'},
    signal: AbortSignal.timeout(8000),
  });
  if (response.status === 404) return {};
  if (!response.ok) throw new Error(`Rakuten HTTP ${response.status}`);
  return response.json();
}

export async function collectAds(cityId, env, {
  fetcher = fetch, pause = () => new Promise(resolve => setTimeout(resolve, 1100)),
  now = () => new Date(),
} = {}) {
  const region = regions[cityId];
  const ads = [];
  let failed = false;
  const jobs = region.shops.map(shop => async () => itemAds(
    await requestApi(ITEM_API, {shopCode: shop.code, availability: '1',
      minAffiliateRate: '1', hits: '10', sort: '-reviewCount'}, env, fetcher),
    cityId, region, 'product', shop,
  ).slice(0, 1));
  jobs.push(async () => {
    const shop = region.furusatoShop ? {code: region.furusatoShop} : null;
    const parameters = shop ? {shopCode: shop.code} :
      {keyword: `ふるさと納税 ${region.prefecture} ${region.taxName}`};
    return itemAds(await requestApi(ITEM_API, {...parameters,
      availability: '1', minAffiliateRate: '1', hits: '30', sort: '-reviewCount'},
      env, fetcher), cityId, region, 'furusato', shop);
  });
  jobs.push(async () => hotelAds(await requestApi(HOTEL_API, {
    keyword: `${region.prefecture} ${region.name}`, hits: '30',
  }, env, fetcher), cityId, region));
  for (let index = 0; index < jobs.length; index++) {
    if (index) await pause();
    try { ads.push(...await jobs[index]()); }
    catch { failed = true; } // Never log API URLs, headers, or credentials.
  }
  // Round robin categories so all three kinds appear early in the rotation.
  ads.sort((a, b) => ['product', 'furusato', 'hotel'].indexOf(a.category) -
    ['product', 'furusato', 'hotel'].indexOf(b.category));
  const ordered = [];
  for (let index = 0; index < 2; index++) {
    for (const category of ['product', 'furusato', 'hotel']) {
      const ad = ads.filter(item => item.category === category)[index];
      if (ad && !ordered.some(item => item.url === ad.url)) ordered.push(ad);
    }
  }
  const fetchedAt = now();
  const ttl = failed ? 300 : TTL;
  return {cityId, fetchedAt: fetchedAt.toISOString(),
    expiresAt: new Date(fetchedAt.getTime() + ttl * 1000).toISOString(), ads: ordered};
}

export async function handleRequest(request, env, context, {
  cache, fetcher = fetch, pause, now = () => new Date(),
} = {}) {
  const url = new URL(request.url);
  const origin = request.headers.get('Origin');
  const allowed = env.ALLOWED_ORIGIN ?? 'https://18quad.github.io';
  const headers = {'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store', 'Vary': 'Origin',
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'X-Content-Type-Options': 'nosniff'};
  const reply = (body, status = 200) => new Response(JSON.stringify(body), {status, headers});
  if (origin && origin !== allowed) return reply({error: 'origin_not_allowed'}, 403);
  if (url.pathname !== '/ads') return reply({error: 'not_found'}, 404);
  if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers});
  if (request.method !== 'GET') return reply({error: 'method_not_allowed'}, 405);
  const cityId = url.searchParams.get('city');
  if (!Object.hasOwn(regions, cityId)) return reply({error: 'unknown_city'}, 400);
  if (!env.RAKUTEN_APPLICATION_ID || !env.RAKUTEN_ACCESS_KEY || !env.RAKUTEN_AFFILIATE_ID) {
    return reply({cityId, ads: [], error: 'not_configured'}, 503);
  }
  const key = new Request(`${url.origin}/internal/v2/${cityId}?account=${encodeURIComponent(env.RAKUTEN_AFFILIATE_ID)}`);
  const cached = await cache?.match(key);
  if (cached) {
    const body = await cached.json();
    if (new Date(body.expiresAt) > now()) return reply(body);
  }
  const body = await collectAds(cityId, env, {fetcher, pause, now});
  if (cache) {
    const ttl = Math.max(1, Math.floor((new Date(body.expiresAt) - now()) / 1000));
    const save = cache.put(key, new Response(JSON.stringify(body), {
      headers: {'Content-Type': 'application/json', 'Cache-Control': `max-age=${ttl}`},
    }));
    context.waitUntil(save);
  }
  return reply(body);
}

export default {
  fetch(request, env, context) {
    return handleRequest(request, env, context, {cache: caches.default});
  },
};
