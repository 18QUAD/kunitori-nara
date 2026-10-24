(function (root, factory) {
    // Hack to make all exports of this module sha256 function object properties.
    var exports = {};
    factory(exports);
    var sha256 = exports["default"];
    for (var k in exports) {
        sha256[k] = exports[k];
    }
        
    if (typeof module === 'object' && typeof module.exports === 'object') {
        module.exports = sha256;
    } else if (typeof define === 'function' && define.amd) {
        define(function() { return sha256; }); 
    } else {
        root.sha256 = sha256;
    }
})(this, function(exports) {
"use strict";
exports.__esModule = true;
// SHA-256 (+ HMAC and PBKDF2) for JavaScript.
//
// Written in 2014-2016 by Dmitry Chestnykh.
// Public domain, no warranty.
//
// Functions (accept and return Uint8Arrays):
//
//   sha256(message) -> hash
//   sha256.hmac(key, message) -> mac
//   sha256.pbkdf2(password, salt, rounds, dkLen) -> dk
//
//  Classes:
//
//   new sha256.Hash()
//   new sha256.HMAC(key)
//
exports.digestLength = 32;
exports.blockSize = 64;
// SHA-256 constants
var K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b,
    0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
    0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7,
    0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152,
    0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
    0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
    0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f,
    0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]);
function hashBlocks(w, v, p, pos, len) {
    var a, b, c, d, e, f, g, h, u, i, j, t1, t2;
    while (len >= 64) {
        a = v[0];
        b = v[1];
        c = v[2];
        d = v[3];
        e = v[4];
        f = v[5];
        g = v[6];
        h = v[7];
        for (i = 0; i < 16; i++) {
            j = pos + i * 4;
            w[i] = (((p[j] & 0xff) << 24) | ((p[j + 1] & 0xff) << 16) |
                ((p[j + 2] & 0xff) << 8) | (p[j + 3] & 0xff));
        }
        for (i = 16; i < 64; i++) {
            u = w[i - 2];
            t1 = (u >>> 17 | u << (32 - 17)) ^ (u >>> 19 | u << (32 - 19)) ^ (u >>> 10);
            u = w[i - 15];
            t2 = (u >>> 7 | u << (32 - 7)) ^ (u >>> 18 | u << (32 - 18)) ^ (u >>> 3);
            w[i] = (t1 + w[i - 7] | 0) + (t2 + w[i - 16] | 0);
        }
        for (i = 0; i < 64; i++) {
            t1 = (((((e >>> 6 | e << (32 - 6)) ^ (e >>> 11 | e << (32 - 11)) ^
                (e >>> 25 | e << (32 - 25))) + ((e & f) ^ (~e & g))) | 0) +
                ((h + ((K[i] + w[i]) | 0)) | 0)) | 0;
            t2 = (((a >>> 2 | a << (32 - 2)) ^ (a >>> 13 | a << (32 - 13)) ^
                (a >>> 22 | a << (32 - 22))) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
            h = g;
            g = f;
            f = e;
            e = (d + t1) | 0;
            d = c;
            c = b;
            b = a;
            a = (t1 + t2) | 0;
        }
        v[0] += a;
        v[1] += b;
        v[2] += c;
        v[3] += d;
        v[4] += e;
        v[5] += f;
        v[6] += g;
        v[7] += h;
        pos += 64;
        len -= 64;
    }
    return pos;
}
// Hash implements SHA256 hash algorithm.
var Hash = /** @class */ (function () {
    function Hash() {
        this.digestLength = exports.digestLength;
        this.blockSize = exports.blockSize;
        // Note: Int32Array is used instead of Uint32Array for performance reasons.
        this.state = new Int32Array(8); // hash state
        this.temp = new Int32Array(64); // temporary state
        this.buffer = new Uint8Array(128); // buffer for data to hash
        this.bufferLength = 0; // number of bytes in buffer
        this.bytesHashed = 0; // number of total bytes hashed
        this.finished = false; // indicates whether the hash was finalized
        this.reset();
    }
    // Resets hash state making it possible
    // to re-use this instance to hash other data.
    Hash.prototype.reset = function () {
        this.state[0] = 0x6a09e667;
        this.state[1] = 0xbb67ae85;
        this.state[2] = 0x3c6ef372;
        this.state[3] = 0xa54ff53a;
        this.state[4] = 0x510e527f;
        this.state[5] = 0x9b05688c;
        this.state[6] = 0x1f83d9ab;
        this.state[7] = 0x5be0cd19;
        this.bufferLength = 0;
        this.bytesHashed = 0;
        this.finished = false;
        return this;
    };
    // Cleans internal buffers and re-initializes hash state.
    Hash.prototype.clean = function () {
        for (var i = 0; i < this.buffer.length; i++) {
            this.buffer[i] = 0;
        }
        for (var i = 0; i < this.temp.length; i++) {
            this.temp[i] = 0;
        }
        this.reset();
    };
    // Updates hash state with the given data.
    //
    // Optionally, length of the data can be specified to hash
    // fewer bytes than data.length.
    //
    // Throws error when trying to update already finalized hash:
    // instance must be reset to use it again.
    Hash.prototype.update = function (data, dataLength) {
        if (dataLength === void 0) { dataLength = data.length; }
        if (this.finished) {
            throw new Error("SHA256: can't update because hash was finished.");
        }
        var dataPos = 0;
        this.bytesHashed += dataLength;
        if (this.bufferLength > 0) {
            while (this.bufferLength < 64 && dataLength > 0) {
                this.buffer[this.bufferLength++] = data[dataPos++];
                dataLength--;
            }
            if (this.bufferLength === 64) {
                hashBlocks(this.temp, this.state, this.buffer, 0, 64);
                this.bufferLength = 0;
            }
        }
        if (dataLength >= 64) {
            dataPos = hashBlocks(this.temp, this.state, data, dataPos, dataLength);
            dataLength %= 64;
        }
        while (dataLength > 0) {
            this.buffer[this.bufferLength++] = data[dataPos++];
            dataLength--;
        }
        return this;
    };
    // Finalizes hash state and puts hash into out.
    //
    // If hash was already finalized, puts the same value.
    Hash.prototype.finish = function (out) {
        if (!this.finished) {
            var bytesHashed = this.bytesHashed;
            var left = this.bufferLength;
            var bitLenHi = (bytesHashed / 0x20000000) | 0;
            var bitLenLo = bytesHashed << 3;
            var padLength = (bytesHashed % 64 < 56) ? 64 : 128;
            this.buffer[left] = 0x80;
            for (var i = left + 1; i < padLength - 8; i++) {
                this.buffer[i] = 0;
            }
            this.buffer[padLength - 8] = (bitLenHi >>> 24) & 0xff;
            this.buffer[padLength - 7] = (bitLenHi >>> 16) & 0xff;
            this.buffer[padLength - 6] = (bitLenHi >>> 8) & 0xff;
            this.buffer[padLength - 5] = (bitLenHi >>> 0) & 0xff;
            this.buffer[padLength - 4] = (bitLenLo >>> 24) & 0xff;
            this.buffer[padLength - 3] = (bitLenLo >>> 16) & 0xff;
            this.buffer[padLength - 2] = (bitLenLo >>> 8) & 0xff;
            this.buffer[padLength - 1] = (bitLenLo >>> 0) & 0xff;
            hashBlocks(this.temp, this.state, this.buffer, 0, padLength);
            this.finished = true;
        }
        for (var i = 0; i < 8; i++) {
            out[i * 4 + 0] = (this.state[i] >>> 24) & 0xff;
            out[i * 4 + 1] = (this.state[i] >>> 16) & 0xff;
            out[i * 4 + 2] = (this.state[i] >>> 8) & 0xff;
            out[i * 4 + 3] = (this.state[i] >>> 0) & 0xff;
        }
        return this;
    };
    // Returns the final hash digest.
    Hash.prototype.digest = function () {
        var out = new Uint8Array(this.digestLength);
        this.finish(out);
        return out;
    };
    // Internal function for use in HMAC for optimization.
    Hash.prototype._saveState = function (out) {
        for (var i = 0; i < this.state.length; i++) {
            out[i] = this.state[i];
        }
    };
    // Internal function for use in HMAC for optimization.
    Hash.prototype._restoreState = function (from, bytesHashed) {
        for (var i = 0; i < this.state.length; i++) {
            this.state[i] = from[i];
        }
        this.bytesHashed = bytesHashed;
        this.finished = false;
        this.bufferLength = 0;
    };
    return Hash;
}());
exports.Hash = Hash;
// HMAC implements HMAC-SHA256 message authentication algorithm.
var HMAC = /** @class */ (function () {
    function HMAC(key) {
        this.inner = new Hash();
        this.outer = new Hash();
        this.blockSize = this.inner.blockSize;
        this.digestLength = this.inner.digestLength;
        var pad = new Uint8Array(this.blockSize);
        if (key.length > this.blockSize) {
            (new Hash()).update(key).finish(pad).clean();
        }
        else {
            for (var i = 0; i < key.length; i++) {
                pad[i] = key[i];
            }
        }
        for (var i = 0; i < pad.length; i++) {
            pad[i] ^= 0x36;
        }
        this.inner.update(pad);
        for (var i = 0; i < pad.length; i++) {
            pad[i] ^= 0x36 ^ 0x5c;
        }
        this.outer.update(pad);
        this.istate = new Uint32Array(8);
        this.ostate = new Uint32Array(8);
        this.inner._saveState(this.istate);
        this.outer._saveState(this.ostate);
        for (var i = 0; i < pad.length; i++) {
            pad[i] = 0;
        }
    }
    // Returns HMAC state to the state initialized with key
    // to make it possible to run HMAC over the other data with the same
    // key without creating a new instance.
    HMAC.prototype.reset = function () {
        this.inner._restoreState(this.istate, this.inner.blockSize);
        this.outer._restoreState(this.ostate, this.outer.blockSize);
        return this;
    };
    // Cleans HMAC state.
    HMAC.prototype.clean = function () {
        for (var i = 0; i < this.istate.length; i++) {
            this.ostate[i] = this.istate[i] = 0;
        }
        this.inner.clean();
        this.outer.clean();
    };
    // Updates state with provided data.
    HMAC.prototype.update = function (data) {
        this.inner.update(data);
        return this;
    };
    // Finalizes HMAC and puts the result in out.
    HMAC.prototype.finish = function (out) {
        if (this.outer.finished) {
            this.outer.finish(out);
        }
        else {
            this.inner.finish(out);
            this.outer.update(out, this.digestLength).finish(out);
        }
        return this;
    };
    // Returns message authentication code.
    HMAC.prototype.digest = function () {
        var out = new Uint8Array(this.digestLength);
        this.finish(out);
        return out;
    };
    return HMAC;
}());
exports.HMAC = HMAC;
// Returns SHA256 hash of data.
function hash(data) {
    var h = (new Hash()).update(data);
    var digest = h.digest();
    h.clean();
    return digest;
}
exports.hash = hash;
// Function hash is both available as module.hash and as default export.
exports["default"] = hash;
// Returns HMAC-SHA256 of data under the key.
function hmac(key, data) {
    var h = (new HMAC(key)).update(data);
    var digest = h.digest();
    h.clean();
    return digest;
}
exports.hmac = hmac;
// Fills hkdf buffer like this:
// T(1) = HMAC-Hash(PRK, T(0) | info | 0x01)
function fillBuffer(buffer, hmac, info, counter) {
    // Counter is a byte value: check if it overflowed.
    var num = counter[0];
    if (num === 0) {
        throw new Error("hkdf: cannot expand more");
    }
    // Prepare HMAC instance for new data with old key.
    hmac.reset();
    // Hash in previous output if it was generated
    // (i.e. counter is greater than 1).
    if (num > 1) {
        hmac.update(buffer);
    }
    // Hash in info if it exists.
    if (info) {
        hmac.update(info);
    }
    // Hash in the counter.
    hmac.update(counter);
    // Output result to buffer and clean HMAC instance.
    hmac.finish(buffer);
    // Increment counter inside typed array, this works properly.
    counter[0]++;
}
var hkdfSalt = new Uint8Array(exports.digestLength); // Filled with zeroes.
function hkdf(key, salt, info, length) {
    if (salt === void 0) { salt = hkdfSalt; }
    if (length === void 0) { length = 32; }
    var counter = new Uint8Array([1]);
    // HKDF-Extract uses salt as HMAC key, and key as data.
    var okm = hmac(salt, key);
    // Initialize HMAC for expanding with extracted key.
    // Ensure no collisions with `hmac` function.
    var hmac_ = new HMAC(okm);
    // Allocate buffer.
    var buffer = new Uint8Array(hmac_.digestLength);
    var bufpos = buffer.length;
    var out = new Uint8Array(length);
    for (var i = 0; i < length; i++) {
        if (bufpos === buffer.length) {
            fillBuffer(buffer, hmac_, info, counter);
            bufpos = 0;
        }
        out[i] = buffer[bufpos++];
    }
    hmac_.clean();
    buffer.fill(0);
    counter.fill(0);
    return out;
}
exports.hkdf = hkdf;
// Derives a key from password and salt using PBKDF2-HMAC-SHA256
// with the given number of iterations.
//
// The number of bytes returned is equal to dkLen.
//
// (For better security, avoid dkLen greater than hash length - 32 bytes).
function pbkdf2(password, salt, iterations, dkLen) {
    var prf = new HMAC(password);
    var len = prf.digestLength;
    var ctr = new Uint8Array(4);
    var t = new Uint8Array(len);
    var u = new Uint8Array(len);
    var dk = new Uint8Array(dkLen);
    for (var i = 0; i * len < dkLen; i++) {
        var c = i + 1;
        ctr[0] = (c >>> 24) & 0xff;
        ctr[1] = (c >>> 16) & 0xff;
        ctr[2] = (c >>> 8) & 0xff;
        ctr[3] = (c >>> 0) & 0xff;
        prf.reset();
        prf.update(salt);
        prf.update(ctr);
        prf.finish(u);
        for (var j = 0; j < len; j++) {
            t[j] = u[j];
        }
        for (var j = 2; j <= iterations; j++) {
            prf.reset();
            prf.update(u).finish(u);
            for (var k = 0; k < len; k++) {
                t[k] ^= u[k];
            }
        }
        for (var j = 0; j < len && i * len + j < dkLen; j++) {
            dk[i * len + j] = t[j];
        }
    }
    for (var i = 0; i < len; i++) {
        t[i] = u[i] = 0;
    }
    for (var i = 0; i < 4; i++) {
        ctr[i] = 0;
    }
    prf.clean();
    return dk;
}
exports.pbkdf2 = pbkdf2;
});

/* Compressed map bytes live on disk, independently of Flutter/GPU image caches. */
'use strict';
const REVISION = 'ce69613e7487d12f709a4b47bb5ce2cbecc1e1afd47bc8aa21373ff72180818d';
const APP_BUILD = 'outside-primary-recovery-20261024-v1';
const ROOT = new URL('./', self.location.href);
const STORE = 'kunitori-map-images-v1';
const PACK_STORE = 'kunitori-map-packs-v1';
const META = 'kunitori-map-images-meta-v1';
const BATCH = 48;
const CONCURRENCY = 2;
// Initial packs stream directly to disk, before the rendering engine starts.
// Refill each of eight slots independently instead of waiting for a slow partner.
// Packs are <= 1 MiB; there are no decoded images or retained download buffers.
const DOWNLOAD_CONCURRENCY = 8;
const DOWNLOAD_WINDOW_MS = 1200;
const DOWNLOAD_WINDOW_PACKS = 32;
let inventoryPromise;
let warming;
const transfers = new Map();
const keyFor = entry => new URL(`${entry[0]}?map-sha256=${entry[1]}`, ROOT).href;
const progressKey = new URL(`__map_progress__/${REVISION}`, ROOT).href;

// Exact, reversible tile IDs. The 417k-entry inventory must not retain a String
// and a Map slot per filename outside the configured image cache budget.
const TILE_LAYERS = ['background','city','overview','pref','town'];
function tileCode(name) {
  const m = /^(-[1-3]|[0-8])_(0|[1-9]\d*)_(0|[1-9]\d*)_(background|city|overview|pref|town)\.webp$/.exec(name);
  if (!m) return null;
  const x=Number(m[2]),y=Number(m[3]);
  if(x>=4096 || y>=2048) return null;
  return (Number(m[1])+3)*67108864+x*16384+y*8+TILE_LAYERS.indexOf(m[4]);
}
function tileName(code) {
  return `${Math.floor(code/67108864)-3}_${Math.floor(code/16384)%4096}_${Math.floor(code/8)%2048}_${TILE_LAYERS[code%8]}.webp`;
}
function tileIndex(data,name) {
  if(!data.codes) return data.byPath.get(name); // Older generic pack fixtures.
  const code=tileCode(name);
  if(code===null) return;
  let low=0,high=data.sortedIndices.length;
  while(low<high){
    const mid=(low+high)>>>1;
    if(data.codes[data.sortedIndices[mid]]<code) low=mid+1; else high=mid;
  }
  const i=data.sortedIndices[low];
  return i!==undefined && data.codes[i]===code ? i : undefined;
}

async function inventory() {
  if (!inventoryPromise) {
    inventoryPromise = (async () => {
      const meta = await caches.open(META);
      const url = new URL(`map-image-manifest.json?packs=1&v=${REVISION}`, ROOT).href;
      let response = await meta.match(url);
      let value;
      if (!response) {
        response = await fetch(url, {cache: 'no-cache'});
        if (!response.ok) throw new Error(`Map inventory HTTP ${response.status}`);
        // Validate before persisting; a deployment can briefly serve mixed files.
        const bytes = await response.arrayBuffer();
        value = JSON.parse(new TextDecoder().decode(bytes));
        if (value.schema !== 1 || value.revision !== REVISION) throw new Error('Map inventory version mismatch');
        await meta.put(url, new Response(bytes, {headers: {'Content-Type': 'application/json'}}));
      } else {
        value = await response.json();
      }
      const assetCount = value.assets.length;
      const byteOffsets = new Float64Array(assetCount + 1);
      if (value.packSchema === 2) {
        const codes = new Uint32Array(assetCount);
        const locations = new Uint32Array(assetCount * 3);
        let numeric = true;
        value.packs.forEach((pack, index) => {
          let offset = 0;
          for (let i=pack[3];i<pack[4];i++) {
            const [name, length] = value.assets[i];
            const code=tileCode(name);
            if(code===null) numeric=false; else codes[i]=code;
            locations.set([length,index,offset], i*3);
            byteOffsets[i+1] = byteOffsets[i]+length;
            offset += length;
          }
          if (offset !== pack[2]) throw new Error('Map pack index mismatch');
        });
        const {assets, ...metadata} = value;
        if(numeric){
          // Preserve download/pack order; only the lookup permutation is sorted.
          const sortedIndices = Uint32Array.from({length:assetCount},(_,i)=>i);
          sortedIndices.sort((a,b)=>codes[a]-codes[b]);
          for(let i=1;i<assetCount;i++){
            if(codes[sortedIndices[i]]===codes[sortedIndices[i-1]]) throw new Error('Duplicate map tile');
          }
          return {...metadata,codes,sortedIndices,locations,assetCount,byteOffsets};
        }
        // Pack schemas also support non-map assets in legacy installations.
        const names=assets.map(entry=>entry[0]);
        return {...metadata,names,locations,byPath:new Map(names.map((name,i)=>[name,i])),assetCount,byteOffsets};
      }
      if (value.packSchema === 1) {
        value.packs.forEach((pack, index) => {
          let offset = 0;
          for (let i = pack[3]; i < pack[4]; i++) {
            value.assets[i].push(index, offset, i);
            offset += value.assets[i][2];
          }
          if (offset !== pack[2]) throw new Error('Map pack index mismatch');
        });
      }
      const byPath = new Map(value.assets.map(entry => [new URL(entry[0], ROOT).pathname, entry]));
      value.assets.forEach((entry, i) => {byteOffsets[i + 1] = byteOffsets[i] + entry[2];});
      return {...value, byPath, assetCount, byteOffsets};
    })().catch(error => {inventoryPromise = null; throw error;});
  }
  return inventoryPromise;
}

function assetEntry(data, index) {
  if (index == null || index < 0 || index >= data.assetCount) return;
  if (data.packSchema !== 2) return data.assets[index];
  const p=index*3;
  const name=data.codes ? tileName(data.codes[index]) : data.names[index];
  return [data.assetPrefix+name, null, data.locations[p],data.locations[p+1],data.locations[p+2],index];
}
function findAsset(data, pathname) {
  if(data.packSchema !== 2) return data.byPath.get(pathname);
  const prefix=ROOT.pathname+data.assetPrefix;
  if(!pathname.startsWith(prefix)) return;
  return assetEntry(data,tileIndex(data,pathname.slice(prefix.length)));
}

async function storedImage(entry, mustStore = false) {
  const data = await inventory();
  if (data.packSchema >= 1) return packedImage(data, entry);
  const key = keyFor(entry);
  const store = await caches.open(STORE);
  const local = await store.match(key);
  if (local) {
    if (mustStore) { await local.body?.cancel(); return; }
    return local;
  }
  if (!transfers.has(key)) {
    const pending = (async () => {
      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), 20000);
      let bytes;
      try {
        const response = await fetch(new URL(`${entry[0]}?map-sha256=${entry[1]}`, ROOT), {cache: 'no-store', signal: abort.signal});
        if (!response.ok) throw new Error(`Map image HTTP ${response.status}`);
        bytes = await response.arrayBuffer();
      } finally { clearTimeout(timeout); }
      if (bytes.byteLength !== entry[2]) throw new Error('Map image length mismatch');
      const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
        .map(byte => byte.toString(16).padStart(2, '0')).join('');
      if (digest !== entry[1]) throw new Error('Map image checksum mismatch');
      const saved = new Response(bytes, {headers: {
        'Content-Type': entry[0].endsWith('.json') ? 'application/json' : 'image/webp',
        'Content-Length': String(bytes.byteLength),
      }});
      let storageError;
      // Cache.put consumes the only response body. An unread clone/tee can keep
      // native byte buffers alive long after a background download finishes.
      try { await store.put(key, saved); } catch (error) { storageError = error; }
      return storageError ? {bytes, storageError} : {};
    })().finally(() => transfers.delete(key));
    transfers.set(key, pending);
  }
  const result = await transfers.get(key);
  if (mustStore && result.storageError) throw result.storageError;
  if (mustStore) return;
  if (result.storageError) {
    return new Response(result.bytes, {headers: {'Content-Type': entry[0].endsWith('.json') ? 'application/json' : 'image/webp'}});
  }
  const response = await store.match(key);
  if (!response) throw new Error('Stored map image unavailable');
  return response;
}

// Packs reduce tens of thousands of HTTP and CacheStorage operations to a few
// hundred. Each transfer is <= 1 MiB (apart from a single larger source asset).
async function storedPack(pack, storeName = PACK_STORE, downloadBase = ROOT) {
  const key = keyFor(pack);
  const store = await caches.open(storeName);
  const cached = await store.match(key);
  if (cached) {await cached.body?.cancel(); return;}
  if (!transfers.has(key)) {
    const pending = (async () => {
      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), 60000);
      const hash = new sha256.Hash();
      let length = 0;
      try {
        const response = await fetch(new URL(`${pack[0]}?map-sha256=${pack[1]}`, downloadBase), {cache: 'no-store', signal: abort.signal});
        if (!response.ok) throw new Error(`Map pack HTTP ${response.status}`);
        const checked = response.body.pipeThrough(new TransformStream({
          transform(chunk, controller) {
            length += chunk.byteLength;
            if (length > pack[2]) throw new Error('Map pack length mismatch');
            hash.update(chunk);
            controller.enqueue(chunk);
          },
          flush() {
            if (length !== pack[2]) throw new Error('Map pack length mismatch');
            const digest = [...hash.digest()].map(byte => byte.toString(16).padStart(2, '0')).join('');
            if (digest !== pack[1]) throw new Error('Map pack checksum mismatch');
          },
        }));
        // Consume the network stream once, validating it before Cache.put commits.
        // Never materialize a whole pack or copy it into a second Response body.
        await store.put(key, new Response(checked));
      } catch (error) {
        await store.delete(key);
        throw error;
      } finally {clearTimeout(timeout); hash.clean();}
    })().finally(() => transfers.delete(key));
    transfers.set(key, pending);
  }
  await transfers.get(key);
}

// One eighth of the shared retained-image budget is compressed bytes;
// Flutter owns the remaining shared decoded-background/boundary budget.
// Foreground-only compressed LRU. Downloading never fills this memory cache.
// Keep the selected byte limit resident and at most two one-pack disk reads in flight; these
// bytes are not decoded pixels or GPU surfaces.
const MEMORY_CHOICES = [32, 64, 128, 256];
const memorySettingsKey = new URL('__map_memory_settings__', ROOT).href;
let mapMemoryMegabytes = 32;
let packMemoryLimit = mapMemoryMegabytes * 1024 * 1024 / 8;
let memorySettingsPromise;
let memorySettingsQueue = Promise.resolve();
function loadMemorySettings() {
  if (!memorySettingsPromise) memorySettingsPromise = (async () => {
    const response = await (await caches.open(META)).match(memorySettingsKey);
    const value = response ? (await response.json()).megabytes : 32;
    mapMemoryMegabytes = MEMORY_CHOICES.includes(value) ? value : 32;
    packMemoryLimit = mapMemoryMegabytes * 1024 * 1024 / 8;
  })().catch(() => {memorySettingsPromise = null;});
  return memorySettingsPromise;
}
function trimPackMemory() {
  while (packMemoryBytes > packMemoryLimit) {
    const oldest = packMemory.keys().next().value;
    packMemoryBytes -= packMemory.get(oldest).length;
    packMemory.delete(oldest);
  }
}
function setMemorySettings(megabytes) {
  const operation = memorySettingsQueue.then(async () => {
    if (!MEMORY_CHOICES.includes(megabytes)) throw new Error('Invalid map memory size');
    await loadMemorySettings();
    await (await caches.open(META)).put(memorySettingsKey, new Response(JSON.stringify({megabytes})));
    mapMemoryMegabytes = megabytes;
    packMemoryLimit = megabytes * 1024 * 1024 / 8;
    trimPackMemory();
    return {megabytes};
  });
  memorySettingsQueue = operation.catch(() => {});
  return operation;
}
const packMemory = new Map();
const packReads = new Map();
const packReadWaiters = [];
let packMemoryBytes = 0;
let packReading = 0;
async function readStoredBytes(pack, storeName = PACK_STORE) {
  await loadMemorySettings();
  const key = keyFor(pack);
  const cached = packMemory.get(key);
  if (cached) {
    packMemory.delete(key);
    packMemory.set(key, cached);
    return cached;
  }
  if (packReads.has(key)) return packReads.get(key);
  const pending = (async () => {
    if (packReading < 2) packReading++;
    else await new Promise(resolve => packReadWaiters.push(resolve));
    try {
      const response = await (await caches.open(storeName)).match(key);
      if (!response) return;
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.length !== pack[2]) throw new Error('Stored map pack truncated');
      if (bytes.length <= packMemoryLimit) {
        while (packMemoryBytes + bytes.length > packMemoryLimit) {
          const oldest = packMemory.keys().next().value;
          packMemoryBytes -= packMemory.get(oldest).length;
          packMemory.delete(oldest);
        }
        packMemory.set(key, bytes);
        packMemoryBytes += bytes.length;
      }
      return bytes;
    } finally {
      if (packReadWaiters.length) packReadWaiters.shift()();
      else packReading--;
    }
  })().finally(() => packReads.delete(key));
  packReads.set(key, pending);
  return pending;
}

async function packedImage(data, entry) {
  const legacyKey = keyFor(entry);
  const residentLegacy = data.packSchema === 1 && packMemory.get(legacyKey);
  if (residentLegacy) {
    packMemory.delete(legacyKey);
    packMemory.set(legacyKey, residentLegacy);
    return imageResponse(residentLegacy, entry, 0);
  }
  const pack = data.packs[entry[3]];
  let bytes = await readStoredBytes(pack);
  if (!bytes) {
    const legacy = data.packSchema === 1 && await readStoredBytes(entry, STORE);
    if (legacy) return imageResponse(legacy, entry, 0);
    await storedPack(pack, PACK_STORE, data.packBaseUrl || ROOT);
    bytes = await readStoredBytes(pack);
  }
  if (!bytes) throw new Error('Stored map pack unavailable');
  // Response copies only the requested image, not its entire compressed pack.
  return imageResponse(bytes, entry, entry[4]);
}

function imageResponse(bytes, entry, offset) {
  return new Response(bytes.subarray(offset, offset + entry[2]), {headers: {
    'Content-Type': entry[0].endsWith('.json') ? 'application/json' : 'image/webp',
    'Content-Length': String(entry[2]),
  }});
}

async function downloadPackWindow(packs, first, storeName, downloadBase = ROOT) {
  const deadline = Date.now() + DOWNLOAD_WINDOW_MS;
  const end = Math.min(first + DOWNLOAD_WINDOW_PACKS, packs.length);
  const completed = new Set();
  let cursor = first, failure;
  await Promise.all(Array.from({length: DOWNLOAD_CONCURRENCY}, async () => {
    while (!failure && cursor < end && Date.now() < deadline) {
      const index = cursor++;
      try {
        await storedPack(packs[index], storeName, downloadBase);
        completed.add(index);
      } catch (error) {failure = error;}
    }
  }));
  // Out-of-order successes remain on disk. Persist only the uninterrupted
  // prefix so a failed/interrupted request cannot be mistaken for a saved pack.
  let next = first;
  while (completed.has(next)) next++;
  return {next, failure};
}

async function warmPacks(data, meta, progress) {
  const start = progress.next;
  if (start === data.assetCount && progress.cleaned) return progressReport(data, start, true);
  const first = assetEntry(data,start)?.[3] ?? data.packs.length;
  const result = await downloadPackWindow(data.packs, first, PACK_STORE, data.packBaseUrl || ROOT);
  const end = result.next > first ? data.packs[result.next - 1][4] : start;
  const legacy = progress.legacy ?? start;
  const complete = end === data.assetCount;
  await meta.put(progressKey, new Response(JSON.stringify({next: end, legacy})));
  if (result.failure) throw result.failure;
  if (complete) {
    await removeOldVersions(data, meta);
    await meta.put(progressKey, new Response(JSON.stringify({next: end, legacy, cleaned: true})));
  }
  return progressReport(data, end, complete);
}

async function removeOldVersions(data, meta) {
  const store = await caches.open(STORE);
  // All new prepared packs are verified before this point. The legacy image
  // store is separate from game saves and can be retired in one operation,
  // instead of tens of thousands of serialized Cache.delete calls on iOS.
  if (data.packSchema === 2) await caches.delete(STORE);
  // Do not enumerate 44,000 CacheStorage Request objects. Only obsolete
  // manifests describe image versions that actually need deleting.
  for (const request of await meta.keys()) {
    if (request.url !== memorySettingsKey && request.url !== progressKey &&
        request.url !== new URL(`map-image-manifest.json?packs=1&v=${REVISION}`, ROOT).href) {
      if (new URL(request.url).pathname.endsWith('/map-image-manifest.json')) {
        const old = await (await meta.match(request)).json();
        const currentPacks = new Set((data.packs || []).map(pack => keyFor(pack)));
        const packedStore = await caches.open(PACK_STORE);
        for (const pack of old.packs || []) {
          if (!currentPacks.has(keyFor(pack))) await packedStore.delete(keyFor(pack));
        }
        for (const entry of data.packSchema === 2 || old.packSchema === 2 ? [] : old.assets) {
          const current = findAsset(data,new URL(entry[0], ROOT).pathname);
          if (!current || current[1] !== entry[1]) await store.delete(keyFor(entry));
        }
      }
      await meta.delete(request);
    }
  }
}

function progressReport(data, next, done) {
  return {done, saved: next, total: data.assetCount, savedBytes: data.byteOffsets[next], bytes: data.bytes};
}

async function imageStorageStatus() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  return progressReport(data, progress.next, progress.next === data.assetCount && !!progress.cleaned);
}

async function imageWarmBatch() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  if (data.packSchema >= 1) return warmPacks(data, meta, progress);
  const start = progress.next;
  if (start === data.assetCount && progress.cleaned) {
    return progressReport(data, start, true);
  }
  const end = Math.min(start + BATCH, data.assetCount);
  let cursor = start;
  let failure;
  await Promise.all(Array.from({length: CONCURRENCY}, async () => {
    while (cursor < end && !failure) {
      const entry = assetEntry(data,cursor++);
      try { await storedImage(entry, true); } catch (error) { failure = error; }
    }
  }));
  // A failed batch is resumed from its beginning; already saved images are reused.
  if (failure) throw failure;
  if (start !== end || !saved) {
    await meta.put(progressKey, new Response(JSON.stringify({next: end})));
  }
  if (end === data.assetCount) {
    await removeOldVersions(data, meta);
    await meta.put(progressKey, new Response(JSON.stringify({next: end, cleaned: true})));
  }
  return progressReport(data, end, end === data.assetCount);
}


// All non-image runtime files are verified on disk too. Large files use bounded
// gzip chunks; neither initial download nor disk reads buffer a complete county.
const RUNTIME_REVISION = 'cb4f85d65709f573b45b4f4e9a3f11023e583ffa2a8ec308c8d6f6abe46d11fa';
const RUNTIME_STORE = 'kunitori-runtime-data-v1';
const RUNTIME_META = 'kunitori-runtime-meta-v1';
let runtimeInventoryPromise;
async function runtimeInventory() {
  // Source-only legacy fixtures have no prepared runtime manifest.
  if (RUNTIME_REVISION.startsWith('__')) return {chunks:[],files:[],bytes:0,byPath:new Map()};
  if (!runtimeInventoryPromise) runtimeInventoryPromise = (async () => {
    const meta = await caches.open(RUNTIME_META);
    const key = new URL(`runtime-data-manifest.json?v=${RUNTIME_REVISION}`, ROOT).href;
    let response = await meta.match(key), data;
    if (response) data = await response.json();
    else {
      response = await fetch(key,{cache:'no-cache'});
      if (!response.ok) throw Error(`Runtime inventory HTTP ${response.status}`);
      data = await response.json();
      if (data.revision !== RUNTIME_REVISION) throw Error('Runtime inventory version mismatch');
      await meta.put(key,new Response(JSON.stringify(data)));
    }
    data.byPath = new Map(data.files.map(f=>[new URL(f.path,ROOT).pathname,f]));
    return data;
  })().catch(error=>{runtimeInventoryPromise=null;throw error;});
  return runtimeInventoryPromise;
}
async function runtimeProgress(data, warm=false) {
  const meta = await caches.open(RUNTIME_META);
  const key = new URL(`__runtime_progress__/${RUNTIME_REVISION}`,ROOT).href;
  const saved = await meta.match(key);
  let next = saved ? (await saved.json()).next : 0;
  if (warm && next<data.chunks.length) {
    const result = await downloadPackWindow(data.chunks, next, RUNTIME_STORE);
    next=result.next;
    await meta.put(key,new Response(JSON.stringify({next})));
    if (result.failure) throw result.failure;
  }
  return {done:next===data.chunks.length,saved:next,total:data.chunks.length,
    savedBytes:data.chunks.slice(0,next).reduce((n,c)=>n+c[2],0),bytes:data.bytes};
}
function combinedProgress(images,runtime) {
  return {done:images.done&&runtime.done,saved:images.saved+runtime.saved,total:images.total+runtime.total,
    savedBytes:images.savedBytes+runtime.savedBytes,bytes:images.bytes+runtime.bytes};
}
async function storageStatus() {
  return combinedProgress(await imageStorageStatus(),await runtimeProgress(await runtimeInventory()));
}
async function warmBatch() {
  const before=await imageStorageStatus();
  const images=before.done ? before : await imageWarmBatch();
  // One transfer phase per message bounds the time until a progress response,
  // including on a slow connection. The next message starts runtime chunks.
  return combinedProgress(images,await runtimeProgress(await runtimeInventory(),before.done));
}
async function runtimeResponse(data,file) {
  let index=0, reader;
  const stream = new ReadableStream({
    async pull(controller) {
      try {
        for (;;) {
          if (!reader) {
            if (index===file.chunks.length) {controller.close();return;}
            const chunk=data.chunks[file.chunks[index++]];
            let response=await (await caches.open(RUNTIME_STORE)).match(keyFor(chunk));
            if (!response) {await storedPack(chunk,RUNTIME_STORE);response=await (await caches.open(RUNTIME_STORE)).match(keyFor(chunk));}
            reader=response.body.getReader();
          }
          const result=await reader.read();
          if (result.done) {reader.releaseLock();reader=null;continue;}
          controller.enqueue(result.value);return;
        }
      } catch(error) {controller.error(error);}
    },
    cancel(reason) {return reader?.cancel(reason);},
  });
  return new Response(stream.pipeThrough(new DecompressionStream('gzip')),{headers:{
    'Content-Type':file.mime,'Content-Length':String(file.bytes),
  }});
}
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  if(event.request.method!=='GET'||url.origin!==ROOT.origin) return;
  const relative=url.pathname.slice(ROOT.pathname.length);
  const shell=relative===''||['index.html','flutter_bootstrap.js','map-cache.js','diagnostics.js'].includes(relative);
  const asset=relative==='main.dart.js'||relative.startsWith('assets/')||relative.startsWith('canvaskit/');
  if(!shell&&!asset || relative.startsWith('assets/assets/data/map_images/') && relative.endsWith('.webp')) return;
  event.respondWith((async()=>{
    const pinnedShell = shell && APP_BUILD && !APP_BUILD.startsWith('__') &&
      (url.searchParams.get('app-build') === APP_BUILD || url.searchParams.get('v') === APP_BUILD);
    if(shell && !pinnedShell) {try {const response=await fetch(event.request,{cache:'no-store'});if(response.ok)return response;}catch(_) {}}
    const data=await runtimeInventory();
    const file=findAsset(data,url.pathname)|| (relative==='' ? data.byPath.get(new URL('index.html',ROOT).pathname):null);
    return file ? runtimeResponse(data,file) : fetch(event.request);
  })());
});

self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  if (!event.ports[0]) return;
  if (event.data?.type === 'map-runtime-version') {
    event.ports[0].postMessage({build:APP_BUILD.startsWith('__') ? null : APP_BUILD,revision:RUNTIME_REVISION});
    return;
  }
  if (['map-memory-get', 'map-memory-set', 'map-memory-release'].includes(event.data?.type)) {
    const operation = event.data.type === 'map-memory-set'
      ? setMemorySettings(event.data.megabytes)
      : memorySettingsQueue.then(async () => {
        await loadMemorySettings();
        if (event.data.type === 'map-memory-release') {
          await Promise.allSettled([...packReads.values()]);
          packMemory.clear();
          packMemoryBytes = 0;
        }
        return {megabytes: mapMemoryMegabytes, bytes: packMemoryBytes};
      });
    event.waitUntil(operation.then(
      result => event.ports[0].postMessage(result),
      error => event.ports[0].postMessage({error: String(error)}),
    ));
    return;
  }
  if (event.data?.type === 'map-images-status') {
    event.waitUntil(storageStatus().then(
      result => event.ports[0].postMessage(result),
      error => event.ports[0].postMessage({error: String(error)}),
    ));
    return;
  }
  if (event.data?.type !== 'warm-map-images') return;
  // Multiple tabs share one bounded batch and the same in-flight transfers.
  if (!warming) warming = warmBatch().finally(() => {warming = null;});
  event.waitUntil(warming.then(
    result => event.ports[0].postMessage(result),
    error => event.ports[0].postMessage({error: String(error)}),
  ));
});
let memoryNotice;
function reportMemoryAfterRead() {
  if (!memoryNotice) memoryNotice = new Promise(resolve => {
    setTimeout(async () => {
      try {
        const clients = await self.clients.matchAll({type: 'window'});
        for (const client of clients) client.postMessage({
          type: 'map-memory-state', megabytes: mapMemoryMegabytes,
          bytes: packMemoryBytes,
        });
      } catch (_) {} finally {memoryNotice = null; resolve();}
    }, 1000);
  });
  return memoryNotice;
}

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== ROOT.origin || !url.pathname.endsWith('.webp') ||
      !['map_images'].some(folder =>
        url.pathname.startsWith(`${ROOT.pathname}assets/assets/data/${folder}/`))) return;
  const response = (async () => {
    let data;
    try { data = await inventory(); } catch (_) { return fetch(event.request); }
    const entry = findAsset(data,url.pathname);
    return entry ? storedImage(entry) : fetch(event.request);
  })();
  event.respondWith(response);
  event.waitUntil(response.then(reportMemoryAfterRead, () => {}));
});
