`fast-sha256.js` is the unmodified fast-sha256 1.3.0 source by Dmitry Chestnykh,
from https://registry.npmjs.org/fast-sha256/-/fast-sha256-1.3.0.tgz.
It is public-domain software; see fast-sha256.LICENSE.

prepare_map_cache.py prepends it to the standalone map worker. Only the
incremental SHA-256 Hash class is used, to validate network chunks while they
stream into CacheStorage without retaining a complete download buffer.
