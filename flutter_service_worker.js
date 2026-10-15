'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"assets/assets/icons/tap.png": "4923afd3d548324e092dea5cbd7dce3c",
"assets/assets/icons/MaterialIcons_LICENSE.txt": "9272dca46e13bd73dc5617e4ce2852fc",
"assets/assets/fonts/OFL.txt": "9e6561baca2756628871baf0c1e23539",
"assets/assets/fonts/NotoSansJP.ttf": "f11bfc28629ade532e6e551e69d444f9",
"assets/assets/characters/nara_guide.png": "dabb74985fac7a752bef34667ba16882",
"assets/assets/characters/nara_guide_sad.png": "a8c2987412ea07e6f39de2a5b412d5a2",
"assets/assets/characters/nara_guide_joy_face_parts.png": "ea048495e43b5da5ddaf8d2c4c0ce0c1",
"assets/assets/characters/nara_guide_joy.png": "54944cfd6201b9fba37ef28a04c0b6fa",
"assets/assets/characters/nara_guide_sad_face_parts.png": "7403adcfd0eddf67b7f20dbdb7362aab",
"assets/assets/characters/nara_guide_face_parts.png": "123fde33f947ec6e0a18c1f61626794d",
"assets/assets/data/nara_mountains.json": "4f590c8c45a4b96b40b29f9c6d33fc86",
"assets/assets/data/nara_relief.json": "029273224b292d91395737068fdf059d",
"assets/assets/data/affiliate_config.json": "6a9db8bfbb735e68ff2be856f3506f38",
"assets/assets/data/prefectures/12.json": "3ab9757790cf024ac1b6232b89be7d04",
"assets/assets/data/prefectures/32.json": "139d588aac526068354f9769f57a27c9",
"assets/assets/data/prefectures/41.json": "88cae070cafb4235a5fa06ca7067e078",
"assets/assets/data/prefectures/35.json": "0d1302a049f1002ce1536fbcd174a8e8",
"assets/assets/data/prefectures/36.json": "81a4dd3d3f4d85af64b8a96bb27eac68",
"assets/assets/data/prefectures/37.json": "05f8df4891ec580322ae9594f14b0377",
"assets/assets/data/prefectures/10.json": "cb8c71a7cf8e71a72b4c6e8caaf59d2e",
"assets/assets/data/prefectures/16.json": "36a723fa78d0361067a91c25357acaf4",
"assets/assets/data/prefectures/19.json": "8c53a15e452a7e894a398916d9ad3ceb",
"assets/assets/data/prefectures/45.json": "273204916d0e2bcb0a9bd5eabfd97275",
"assets/assets/data/prefectures/04.json": "0ff2b997e59267c8483cb6949b865a2e",
"assets/assets/data/prefectures/33.json": "56c81fd65c8067fa7cb8a12c50d628cc",
"assets/assets/data/prefectures/26.json": "fb5a0d7174df1683b2dd605f396ae5d7",
"assets/assets/data/prefectures/39.json": "170fef07d40276623547b5f06c32eab6",
"assets/assets/data/prefectures/13.json": "b40de4ffe4dc6fdd7be50fa2b93f64bb",
"assets/assets/data/prefectures/43.json": "1b6eba75d951ef1c29fd7ed1e4f12bd3",
"assets/assets/data/prefectures/20.json": "69a969946a2c7cc54cea307b3c822486",
"assets/assets/data/prefectures/22.json": "dfa9958c43e8037277561b8bfbbccace",
"assets/assets/data/prefectures/34.json": "68d585f7eb4f6598417fbcfdb760c230",
"assets/assets/data/prefectures/42.json": "0b4af97428633bda1c859ba0ea9b7429",
"assets/assets/data/prefectures/18.json": "ed4a97452b73bdf68ffef334ed5944b3",
"assets/assets/data/prefectures/05.json": "1e4ba80c2f3c315cac7753431f1525b8",
"assets/assets/data/prefectures/23.json": "5c3a0fa58c796c31c18b5728327cec5b",
"assets/assets/data/prefectures/46.json": "e7254bd17000d3afe9023a6c7a05421b",
"assets/assets/data/prefectures/27.json": "5dd36b383be283b196779e1fe5b47011",
"assets/assets/data/prefectures/47.json": "856700bc249895ba637c32e25de89ecc",
"assets/assets/data/prefectures/14.json": "2e0bad86f56629fc7e6edcc74f0a3aff",
"assets/assets/data/prefectures/15.json": "a9d0ed79f5e90e581bea3fa57e1511f3",
"assets/assets/data/prefectures/40.json": "99d7e5ea987b127d2cdf212fcfa9b8fc",
"assets/assets/data/prefectures/02.json": "fad98c8534aeac75e0c932d38e974d06",
"assets/assets/data/prefectures/30.json": "6a587730f7237450e136181ae84362ef",
"assets/assets/data/prefectures/08.json": "d10aacadefc316c4677a691debc97da7",
"assets/assets/data/prefectures/44.json": "a6e352b681174faadbd3916ca6125fda",
"assets/assets/data/prefectures/09.json": "0194215f475fd2e6896ebc39e697c85c",
"assets/assets/data/prefectures/17.json": "ee6295e00539d75847734524192c7554",
"assets/assets/data/prefectures/38.json": "fc55560cd9b015e5fc5d901a1dbb6189",
"assets/assets/data/prefectures/07.json": "231a0245d14bce7c7051c7875556c6a5",
"assets/assets/data/prefectures/11.json": "fb04c85e1251ea018eda18a2201889c4",
"assets/assets/data/prefectures/03.json": "0af36823af74e6c3b93067c1d34d4cf8",
"assets/assets/data/prefectures/24.json": "536a578e3d5c77ce851ab2a318de93dc",
"assets/assets/data/prefectures/28.json": "82bbf98e6a1711a601c72ac56bf8750d",
"assets/assets/data/prefectures/25.json": "5909393f9936eb7be3ca670ff9ba633f",
"assets/assets/data/prefectures/21.json": "a4c5698b2d43506a8f52027ff1aa8b7a",
"assets/assets/data/prefectures/06.json": "6cbd0aca5f68d69991d1e278e11e2b43",
"assets/assets/data/prefectures/31.json": "2ccf268d88f76662300a58cc32a14f48",
"assets/assets/data/prefectures/01.json": "80df73954920c63b613b9d3ccda7b2f2",
"assets/assets/data/japan.json": "d95592634d4b916bf06fe004c560e76c",
"assets/assets/data/nara_urban.json": "d241ff9af8a59f8363ed5d8d20245613",
"assets/assets/data/nara_offices.json": "ce95449f8723cf76fbd99954b216ae3f",
"assets/assets/data/nara.json": "46b6a886846067ffce779acc2dcda8a8",
"assets/assets/data/japan_import_report.json": "e2d7ea16cb66c60e909b3b57f08342d7",
"assets/assets/data/nara_water.json": "0eade779e246104f380353760245673b",
"assets/assets/data/nara_relief.png": "d441464e315ff51ebc85edfc1fa29e9a",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "aac8aea4eb7fa7cbeb3ab9f76a5539d2",
"assets/fonts/MaterialIcons-Regular.otf": "c16505874998a43d904236db32cbf701",
"assets/NOTICES": "407d7a2067daea98d6b543a04e81b6b3",
"assets/FontManifest.json": "66e11fc8edb84031e838e918630054ca",
"assets/AssetManifest.json": "214581d32a13306298f6246f57bbf0b4",
"assets/AssetManifest.bin": "76a96b9e31cbc130fc8c443fac43e3da",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"manifest.json": "8251a2fd4e43cebd590784a53ad4df4c",
"version.json": "8c276741097b0c1809b7cf9bd0c2d84d",
"main.dart.js": "74b787d83bc5382fc71e8aa531e39423",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"index.html": "1bb6f33ad15e1d5112c2cbfa37949157",
"/": "1bb6f33ad15e1d5112c2cbfa37949157",
"flutter_bootstrap.js": "fe5693e86b4ba91a7727fe3055f890a4"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
