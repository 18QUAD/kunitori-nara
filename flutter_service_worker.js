'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"vendor/README.md": "c69f8570fd1d6466a03b7971a0512c8c",
"vendor/fast-sha256.LICENSE": "911690f51af322440237a253d695d19f",
"vendor/fast-sha256.js": "e9071e419a863be237a1bfabd45197c9",
"diagnostics.js": "94e2e96b28125f2bca323d7b4725f316",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"manifest.json": "8251a2fd4e43cebd590784a53ad4df4c",
"map-cache-worker.js": "85ee82b3e435abfaa36b601aad3d0f9e",
"map-cache.js": "64febe250584af6c3dff86fc05eb3181",
"assets/NOTICES": "407d7a2067daea98d6b543a04e81b6b3",
"assets/FontManifest.json": "66e11fc8edb84031e838e918630054ca",
"assets/AssetManifest.bin.json": "5824e466f59280252f83dad6370dbc01",
"assets/AssetManifest.bin": "8b3010803b9290669d55f47fef53b0e8",
"assets/AssetManifest.json": "3ccf8d2a5fd7a7f89e03ffa0b0b080e9",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/fonts/MaterialIcons-Regular.otf": "6c58da837a4b23a6b837481114bb1372",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/data/prepared_maps/map-image-manifest.json": "43cce94f284264db662acab233011f42",
"assets/assets/fonts/NotoSansJP.ttf": "f11bfc28629ade532e6e551e69d444f9",
"assets/assets/fonts/OFL.txt": "9e6561baca2756628871baf0c1e23539",
"assets/assets/data/nara_mountains.json": "4f590c8c45a4b96b40b29f9c6d33fc86",
"assets/assets/data/japan_offices.json": "629c7c37be791614df09eea458339d7e",
"assets/assets/data/nara_offices.json": "ce95449f8723cf76fbd99954b216ae3f",
"assets/assets/data/mountains/index.json": "c1044d38ddfc093bd27621e24755868e",
"assets/assets/data/mountains/47.json": "3af19fadcb828d796c4471be406f5c0b",
"assets/assets/data/mountains/46.json": "d7081579ec7e27f6fd2ef37f53d0c5e6",
"assets/assets/data/mountains/45.json": "7ddc47e2e5452eaaa08db38acbaef6e4",
"assets/assets/data/mountains/44.json": "614298bc00f390596d4c2fc6b833f237",
"assets/assets/data/mountains/43.json": "5e993761bef3cda623e8e9d6bbc157c8",
"assets/assets/data/mountains/42.json": "b6acbdb641675f6579f9125d2157ed65",
"assets/assets/data/mountains/41.json": "74732aeb0f1962b2322311d9a1c3a04e",
"assets/assets/data/mountains/40.json": "33e84571870c8223aa603c14f04f7b36",
"assets/assets/data/mountains/39.json": "361559843b7dc524c8ebe5d466384a25",
"assets/assets/data/mountains/38.json": "467dcc574df8d05c4cdb727d1fcc3025",
"assets/assets/data/mountains/37.json": "595f6dcb9cdb141e0743ab27e56f8a8f",
"assets/assets/data/mountains/36.json": "0828c92c417a08222bee0e270389f5e7",
"assets/assets/data/mountains/35.json": "c75123b57023221ec08ad056f2e8d36a",
"assets/assets/data/mountains/34.json": "bf3d572aeffb1769bc27b271a20d1ba4",
"assets/assets/data/mountains/33.json": "58d9a60be600ff69a5a445c55e4e50b4",
"assets/assets/data/mountains/32.json": "70963ab1c80d93f3308ae591813c9c02",
"assets/assets/data/mountains/31.json": "7a2955dcf87bfdb2ad1b1aee928edba0",
"assets/assets/data/mountains/30.json": "b0d701e22f25243e2937a7dd4ff33944",
"assets/assets/data/mountains/28.json": "eec6c5fda6553195062e75ce65590d29",
"assets/assets/data/mountains/27.json": "5d6f9262f033d366a52dece4454a0960",
"assets/assets/data/mountains/26.json": "59cb0dcf4dd937c6195c6c4e0acb7f08",
"assets/assets/data/mountains/25.json": "1847c71b26e8b6c75d864afd8bcfb043",
"assets/assets/data/mountains/24.json": "20a2ab6f746c384daaf30790254bdd00",
"assets/assets/data/mountains/23.json": "816f2c37362553048227c3a0ccccaaa8",
"assets/assets/data/mountains/22.json": "204096c0eba1715758a1007f369ddd99",
"assets/assets/data/mountains/21.json": "91a8d16dbced65027128783f37d9b3fc",
"assets/assets/data/mountains/20.json": "da5c8f212a3b06ba193bcc21180a4831",
"assets/assets/data/mountains/19.json": "74ec2a8faa1ec5487383fc2ea3ca750b",
"assets/assets/data/mountains/18.json": "8fb176479b36e576e473b92567d69dfd",
"assets/assets/data/mountains/17.json": "fee805c52220a89f06ada8a1ed385557",
"assets/assets/data/mountains/16.json": "0e73cadeae4843f05c32f10947a07738",
"assets/assets/data/mountains/15.json": "3f5e8289c808a9012b64cec2d08da38c",
"assets/assets/data/mountains/14.json": "7b2476986f8a498e63e2f409342b3671",
"assets/assets/data/mountains/12.json": "70119421bb00481397f727483239daaa",
"assets/assets/data/mountains/13.json": "12bab63c57c7fdcd69815541fc89b92b",
"assets/assets/data/mountains/11.json": "46ce6a766c41d746341ef72194ddee55",
"assets/assets/data/mountains/10.json": "751179037882eaf5266b01e846e7a3a1",
"assets/assets/data/mountains/09.json": "f4bd09e451d8f8db682b09742ce4d13a",
"assets/assets/data/mountains/08.json": "3cebcdda29da894286720aca449cd4ad",
"assets/assets/data/mountains/07.json": "9c30d808b3c0a5967749d1a95947f26b",
"assets/assets/data/mountains/06.json": "e046d10b5af366e7230881a44ecbb264",
"assets/assets/data/mountains/05.json": "9b0014583ee072eead3e7ede868ce701",
"assets/assets/data/mountains/04.json": "3f639a33f6857a20808df36d49f0cc09",
"assets/assets/data/mountains/03.json": "74fc9619d54a246be7cf0258c49f54b0",
"assets/assets/data/mountains/02.json": "d7c145389fda9e31832a9dd250821b6c",
"assets/assets/data/mountains/01.json": "30a9fa59880146d481cddef3fa30435c",
"assets/assets/data/affiliate_config.json": "6a9db8bfbb735e68ff2be856f3506f38",
"assets/assets/data/map_labels/national.json": "45598c583b6aadae2120f51bbe763832",
"assets/assets/data/map_labels/47.json": "43c4ecc786440c9c5f25e205330cc803",
"assets/assets/data/map_labels/46.json": "aa4083a414876c48f8a565ab3387fc3a",
"assets/assets/data/map_labels/45.json": "e100a638c35f36d4822b3a129f36cbc7",
"assets/assets/data/map_labels/44.json": "4b3c1b6ab52e20b24c8c9b13256761df",
"assets/assets/data/map_labels/43.json": "7ee38717d6c591c116412a728170c6c9",
"assets/assets/data/map_labels/42.json": "832604dc20b83b2306b0cb0898b59078",
"assets/assets/data/map_labels/41.json": "03297ffec6ca430eb0f87aa320bc5325",
"assets/assets/data/map_labels/40.json": "5f011ac6a3f2cc659834dd92bd7e16fc",
"assets/assets/data/map_labels/39.json": "57636c378e66a5dce8e570c9225ea28b",
"assets/assets/data/map_labels/38.json": "ee2c15b0e8bb1ba4675c25c4017f5b58",
"assets/assets/data/map_labels/37.json": "8129ea9966853b91323061a5499d8ee4",
"assets/assets/data/map_labels/36.json": "7749477f1d872aaa18f80a01c6390341",
"assets/assets/data/map_labels/35.json": "09e5f56981d7568f13110539fa39bf84",
"assets/assets/data/map_labels/34.json": "37375645f2218890f13c85765cd7979d",
"assets/assets/data/map_labels/33.json": "0da1b405b4c61fe040296a11dda403d8",
"assets/assets/data/map_labels/32.json": "ca3b7d51c6e2cb807da08d08ccaf0c9f",
"assets/assets/data/map_labels/31.json": "9ff348825bdd853fb1c90b7041d92c5c",
"assets/assets/data/map_labels/30.json": "4acf99057d839d4351106a7739ad625d",
"assets/assets/data/map_labels/29.json": "1e9515255c22c9e3db69879815733fcc",
"assets/assets/data/map_labels/28.json": "5154db30cbc30f89b30ef772cb630b30",
"assets/assets/data/map_labels/27.json": "8090e2f54a069e055468ad1f89ea9db2",
"assets/assets/data/map_labels/26.json": "08f6fd06616b8ca8848e7b334d7b74b3",
"assets/assets/data/map_labels/25.json": "ed0e23a36b60cf6d364d2f598c6fc489",
"assets/assets/data/map_labels/24.json": "b52df07c669846e4bcfcb62c3a8de2ad",
"assets/assets/data/map_labels/23.json": "0d9ff51957a11e4a49a8f3f04b253845",
"assets/assets/data/map_labels/22.json": "8cb2825e1f0bda69fbfc696fc739221c",
"assets/assets/data/map_labels/21.json": "0a237226c20b391af3c6b3957f48df23",
"assets/assets/data/map_labels/20.json": "221121ad6965f4de28a75966b4cd2e24",
"assets/assets/data/map_labels/19.json": "6f18027e4336703943f6f9832bb65dbd",
"assets/assets/data/map_labels/18.json": "6d21d9be95aba26c6703d102629cfd07",
"assets/assets/data/map_labels/17.json": "afb1d7a20a6a6570afc7c2fcb1bba278",
"assets/assets/data/map_labels/16.json": "32543850861ffea7f92a076736d0e369",
"assets/assets/data/map_labels/15.json": "480f72e9f7dbcd5df2492288e959b66f",
"assets/assets/data/map_labels/14.json": "06f1f93a2fb892306ca1551a7af0314c",
"assets/assets/data/map_labels/13.json": "d276c7ae155e9060bea2d1bfb6851d56",
"assets/assets/data/map_labels/12.json": "2f18fa06edc02a96bb86fba6c9d9b7b1",
"assets/assets/data/map_labels/11.json": "8efe315fbcc013d6d4c87daa1d9cad6a",
"assets/assets/data/map_labels/10.json": "0c065192bf291f26b251f390015b5098",
"assets/assets/data/map_labels/09.json": "950fd4c57d289a4f371a26ad67f68288",
"assets/assets/data/map_labels/08.json": "c19cabade7ae2f1862a3f27fe904b437",
"assets/assets/data/map_labels/07.json": "cd2c5b080f1e0db7e37e27f4376cf5d5",
"assets/assets/data/map_labels/06.json": "90d04f81a076b43befbe0fbde05475f4",
"assets/assets/data/map_labels/05.json": "0e9ca4fd2e5dc5bf42aeff6d39bef0c5",
"assets/assets/data/map_labels/04.json": "92a63912aff8fa4fad83a095ce3892da",
"assets/assets/data/map_labels/03.json": "df2015c3257fe4344a9c5b80d4151df8",
"assets/assets/data/map_labels/02.json": "a306cd93cd62b94f025adfcfee36c092",
"assets/assets/data/map_labels/01.json": "03313f7e8c8e58da7a6ae1361f8ff38e",
"assets/assets/data/map_images/index.json": "e23d71c34a6cfc6c03738cea3f403a8d",
"assets/assets/data/national_territories/01.bin": "b7c2d452ba935392817253f1a3cd6057",
"assets/assets/data/national_territories/02.bin": "c95d54e755d26db731c9959410c6163f",
"assets/assets/data/national_territories/03.bin": "395184421d7766414169c8dc14067e55",
"assets/assets/data/national_territories/04.bin": "6bc780b52f665f0daecf83aee0408c5f",
"assets/assets/data/national_territories/05.bin": "f98edbf2be68421f046118e442438d78",
"assets/assets/data/national_territories/06.bin": "8674d6223e966aeb3fee9e7a8617762d",
"assets/assets/data/national_territories/07.bin": "df96e617b7a1d7971b124be5f160889b",
"assets/assets/data/national_territories/08.bin": "557d2de684acf14d7e9a99d8dcea1a3b",
"assets/assets/data/national_territories/09.bin": "b10f0da09de5ca7c8034862d9e483b30",
"assets/assets/data/national_territories/10.bin": "bcff9944ff5d7ed85508a5ea911bda8a",
"assets/assets/data/national_territories/11.bin": "a03d1290bb85289e183d70733111e201",
"assets/assets/data/national_territories/12.bin": "90910a6b4ec8ca263e79cd30a4dc3822",
"assets/assets/data/national_territories/13.bin": "34f0e4e0690cfb35a79d6cbf40d1d981",
"assets/assets/data/national_territories/14.bin": "74b16a81661779764406424ab84c8440",
"assets/assets/data/national_territories/15.bin": "4387a8d78b44514b0ca5b0e435544423",
"assets/assets/data/national_territories/16.bin": "d2a6d076c52920ea07edde0b98b0c9e4",
"assets/assets/data/national_territories/17.bin": "ad9ad87e1610769ce1eaa3869b9c7d3b",
"assets/assets/data/national_territories/18.bin": "40747386cd312bc2babd01173b190ec1",
"assets/assets/data/national_territories/19.bin": "70e3bf8d2c6747c3304791e9e23b8e03",
"assets/assets/data/national_territories/20.bin": "53d3e91cf7461a7cdcb780a500e32ba0",
"assets/assets/data/national_territories/21.bin": "8484b93f83aab51eb8824105e9900805",
"assets/assets/data/national_territories/22.bin": "d9732c58aa982e8d5f2ae93b8a679500",
"assets/assets/data/national_territories/23.bin": "28e37372f928f65fc7e862ff451c54f3",
"assets/assets/data/national_territories/24.bin": "a02a5741f3f22caf552868a02259ff21",
"assets/assets/data/national_territories/25.bin": "bd59f94f5ecc77f7964127f962e346cf",
"assets/assets/data/national_territories/26.bin": "cd366c23ecc19df621ab8da1006d8970",
"assets/assets/data/national_territories/27.bin": "f1b523debe4fda6d5e8697188fffc1a5",
"assets/assets/data/national_territories/28.bin": "c65dae2618a6714194500e6051248384",
"assets/assets/data/national_territories/29.bin": "e54f2cccfccb529c828a509b44f04248",
"assets/assets/data/national_territories/30.bin": "cb225d8be647dfec1d14718a7b2c466a",
"assets/assets/data/national_territories/31.bin": "74e9ed959e430945b8386c15760a69fe",
"assets/assets/data/national_territories/32.bin": "c15f3b384ec0f38040dd958f89ac5dea",
"assets/assets/data/national_territories/33.bin": "dc2b927e6c3d6813bd2530f398a2918b",
"assets/assets/data/national_territories/34.bin": "e9616082348629ae2208dc9ea20ed9a9",
"assets/assets/data/national_territories/35.bin": "a436b2fa701ea5b8a068d03e23f165d9",
"assets/assets/data/national_territories/36.bin": "82147c4da9c0a57727a23431856753cc",
"assets/assets/data/national_territories/37.bin": "4899aa56de1086db58beb072684baa60",
"assets/assets/data/national_territories/38.bin": "8fd7c7211070ead8fdcad9adfcc84e8a",
"assets/assets/data/national_territories/39.bin": "851ef7faae515d0f9765a12e97582dc4",
"assets/assets/data/national_territories/40.bin": "f6169ce7c15cdca610b3d60685dc7c45",
"assets/assets/data/national_territories/41.bin": "819123721936f422025cac0b56df7919",
"assets/assets/data/national_territories/42.bin": "5938cf64f39800a8dace305a435ad1ce",
"assets/assets/data/national_territories/43.bin": "3e30fbb0a1493a4192f24194c5ee70e6",
"assets/assets/data/national_territories/44.bin": "b09eb75e6a438839b3c6007f80f584b6",
"assets/assets/data/national_territories/45.bin": "4cfa40d494d106c97e5b6e7263f2da25",
"assets/assets/data/national_territories/46.bin": "497d447665dd595c02458fdb53d8f8e0",
"assets/assets/data/national_territories/47.bin": "fd02b6e8514dd190261c87767d2f69af",
"assets/assets/data/national_territories/index.json": "e0e81e57c2ab133c9f0ae0d9c6672807",
"assets/assets/data/prefectures/01.json": "8155f9d2f4a41256ba244b7664d59f54",
"assets/assets/data/prefectures/02.json": "82619310819c651e45c2737c5fb3fb5c",
"assets/assets/data/prefectures/27.json": "e99924493d9ed206d421970526d8a830",
"assets/assets/data/prefectures/03.json": "ec71750095f65742f83084b2834dc1fa",
"assets/assets/data/prefectures/04.json": "a0b72318606afde39684b7c41bbfdcf1",
"assets/assets/data/prefectures/05.json": "8ba11661a174954c9cb6c1bdf60fc110",
"assets/assets/data/prefectures/06.json": "94a842e0cf31be78ec401b6ac65eee74",
"assets/assets/data/prefectures/07.json": "d93bc12c4ab61ba3195eda62ab8f81ce",
"assets/assets/data/prefectures/08.json": "e31ee1c938facf71a955b6d0d9e1ec6a",
"assets/assets/data/prefectures/09.json": "0194215f475fd2e6896ebc39e697c85c",
"assets/assets/data/prefectures/10.json": "cb8c71a7cf8e71a72b4c6e8caaf59d2e",
"assets/assets/data/prefectures/11.json": "fb04c85e1251ea018eda18a2201889c4",
"assets/assets/data/prefectures/12.json": "a147a4addb93657217b5c076e7ec3e98",
"assets/assets/data/prefectures/13.json": "410328ad4dbdf803e2b7ae0c2fb09609",
"assets/assets/data/prefectures/14.json": "91a1d934d30e84ce64a7f8eb7200e694",
"assets/assets/data/prefectures/15.json": "7ce946ce8bed3351fe448f51dcd77d5b",
"assets/assets/data/prefectures/16.json": "de110dbe2e1bf4921a8d8a582ec61d3d",
"assets/assets/data/prefectures/17.json": "162da3e0133ca1f53174a65cfe58745b",
"assets/assets/data/prefectures/18.json": "0ef5a67add854ba4f6142fe98dcfe43c",
"assets/assets/data/prefectures/19.json": "8c53a15e452a7e894a398916d9ad3ceb",
"assets/assets/data/prefectures/20.json": "69a969946a2c7cc54cea307b3c822486",
"assets/assets/data/prefectures/21.json": "a4c5698b2d43506a8f52027ff1aa8b7a",
"assets/assets/data/prefectures/22.json": "9d85d971f17efdbfdae1b1c830fd577d",
"assets/assets/data/prefectures/23.json": "0568f825646d7165f445db7606d65733",
"assets/assets/data/prefectures/24.json": "6705e339d552c36992c43c83204521be",
"assets/assets/data/prefectures/25.json": "5909393f9936eb7be3ca670ff9ba633f",
"assets/assets/data/prefectures/26.json": "253270a76f9eef03000c819f4bb1b3a6",
"assets/assets/data/prefectures/28.json": "1ce2721895980c8312cdf05e453b20f1",
"assets/assets/data/prefectures/30.json": "833d79300bdef619ac6140d88fb35f7c",
"assets/assets/data/prefectures/31.json": "7e2aca245a1e65f7b6905718a66bfdd0",
"assets/assets/data/prefectures/32.json": "31cf76ad1129a1a847225d7c00e7668f",
"assets/assets/data/prefectures/33.json": "bf374da6d1c1961df65db8fd4ee1d694",
"assets/assets/data/prefectures/34.json": "2fd0aaabd9ff63bc868e97ac6541c4ca",
"assets/assets/data/prefectures/35.json": "19c164edaed5993c7d3fc627fc35cb6b",
"assets/assets/data/prefectures/36.json": "4ac617622b0225f2c174b2686f20e38a",
"assets/assets/data/prefectures/37.json": "73c871403ebbc7e37ad48b79aeb421dc",
"assets/assets/data/prefectures/38.json": "8d72cb90267971eb9d059f3a26b379d1",
"assets/assets/data/prefectures/39.json": "e780189310a3c482fc211ee68d8aaac9",
"assets/assets/data/prefectures/40.json": "a933cc70bb4ee16a1f6a8355a26264b7",
"assets/assets/data/prefectures/41.json": "7aeb7b7e16e84b68a1906a4ddb1c420a",
"assets/assets/data/prefectures/42.json": "ccf35dcfec245de4e141394861429429",
"assets/assets/data/prefectures/43.json": "272c8d62a3b94114d281792cffe224d2",
"assets/assets/data/prefectures/44.json": "f2865388f7bbdbe7276bc34d1fbb17f5",
"assets/assets/data/prefectures/45.json": "af1ef00041d7d7bd59a80323d40b20ee",
"assets/assets/data/prefectures/46.json": "b74fbfb2b340e6900855a8bb48ac2cba",
"assets/assets/data/prefectures/47.json": "214f914ee588e7eaa765361bee64c813",
"assets/assets/data/coastline_import_report.json": "44191b039f95768aad2120c2c691a58a",
"assets/assets/data/japan_import_report.json": "e2d7ea16cb66c60e909b3b57f08342d7",
"assets/assets/data/japan.json": "d1d58ab03f6e578e8fd91002a416960c",
"assets/assets/data/nara_metadata.json": "51ad13177ad633f1d004d1635f0596d7",
"assets/assets/data/nara_outlines.json": "b91dc6b9f2e572fc4684a3d2047a9614",
"assets/assets/data/nara.json": "46b6a886846067ffce779acc2dcda8a8",
"assets/assets/data/tips/index.json": "1027b608a4c72d1b9209c5a89b7ab4f9",
"assets/assets/data/tips/44.json": "938eee54728c97e912108e7569c57d8c",
"assets/assets/data/tips/45.json": "3ba540b2667ae4f556f643a7d612853b",
"assets/assets/data/tips/46.json": "b0541fd3a584dace5e4fdc6a42dba732",
"assets/assets/data/tips/47.json": "fed7390a38223f3f2808feec51e7cf11",
"assets/assets/data/tips/43.json": "08227663bf159a2de3244e23cf0a924c",
"assets/assets/data/tips/42.json": "c4374601f1a5cafe7ef083c4d32c24f2",
"assets/assets/data/tips/41.json": "3ee86ed6e1981c4335c5990e7a98a927",
"assets/assets/data/tips/40.json": "984958c2d109db57e1fb934d274310f2",
"assets/assets/data/tips/39.json": "3b962df13d7e4e45d0d3b23407ab7b08",
"assets/assets/data/tips/38.json": "f30f4632f9882f1483c198b0ce672115",
"assets/assets/data/tips/37.json": "6c8658813570504f2273142679922000",
"assets/assets/data/tips/36.json": "8b426fdaa31fa5b380e232df3575e4f9",
"assets/assets/data/tips/35.json": "af45e8a7d48b9f5bd8aa16af5cedabb0",
"assets/assets/data/tips/34.json": "957aa6a2ee00a4956bb82990ca7648a5",
"assets/assets/data/tips/32.json": "b987f23e7f689eb6a38d671aac33094a",
"assets/assets/data/tips/33.json": "07264540c480214b015a83324c6b13e5",
"assets/assets/data/tips/30.json": "d6bb94d0ec1e2c219e8df79cbdc39318",
"assets/assets/data/tips/31.json": "01c3edd1033e85a839969db2df664bf6",
"assets/assets/data/tips/28.json": "ff8e71df2a3983b7f76fffbc1dcb401a",
"assets/assets/data/tips/27.json": "853e7b62d5906ce26fd2d23c6e2b5e6f",
"assets/assets/data/tips/26.json": "c257a07a6453deacc13a5e4b62d65eb3",
"assets/assets/data/tips/25.json": "63ae18e474fd24776549e21944d73c02",
"assets/assets/data/tips/24.json": "792a8eecc31ae1a75f5a5b19d95c79be",
"assets/assets/data/tips/23.json": "e7974d8e14cfbc1956ae63fdf7a30b07",
"assets/assets/data/tips/22.json": "c1f647b40cc2a1c419519b6247e74ce1",
"assets/assets/data/tips/21.json": "8becf53c27051059d4d7e90d2b7fd45e",
"assets/assets/data/tips/20.json": "bfd4d9c6d27e4e47ebb640e482fce745",
"assets/assets/data/tips/19.json": "53d4c34d323098ac3739565742a60541",
"assets/assets/data/tips/18.json": "81dfc81720d1d7c45e9138f18ccedc87",
"assets/assets/data/tips/17.json": "22d6f8d88aaab87d18dedb58a00f1605",
"assets/assets/data/tips/15.json": "5d3e31b81261811699ee78546136e930",
"assets/assets/data/tips/16.json": "8da58d5ad82898081f53bfbd609fe762",
"assets/assets/data/tips/14.json": "65ba014c42e248cd51d2ceb474af6ba6",
"assets/assets/data/tips/13.json": "3548a637600f1f534efd4566595ff6f8",
"assets/assets/data/tips/12.json": "4386b0f419b10a0013554fc3f454d7f6",
"assets/assets/data/tips/11.json": "b9537f926f8edbc9f26cafa48347c0b9",
"assets/assets/data/tips/10.json": "8339060c144559d7bb0b5601e503e90f",
"assets/assets/data/tips/09.json": "9db0caabd756d9173be1785b807ce3f4",
"assets/assets/data/tips/08.json": "ef9220aca9ae9cdeb8f075192965272a",
"assets/assets/data/tips/07.json": "df69c0eac7c4ee829c6a0bf475fccad3",
"assets/assets/data/tips/06.json": "b51b59386310338fd62282db19d358be",
"assets/assets/data/tips/05.json": "bab89d6ceea1ed1b9cf851e85b121fbf",
"assets/assets/data/tips/04.json": "e38dcfc1dea678d5d1bc293d3a38ae70",
"assets/assets/data/tips/03.json": "29a85f3abe0c7b210b7429023433accb",
"assets/assets/data/tips/02.json": "e5048e00bd8c7cf1c982b2d56131df2d",
"assets/assets/data/tips/01.json": "dd8021c13d3b0faf6d58024056b873d0",
"assets/assets/characters/nara_guide_sad_face_parts.png": "7403adcfd0eddf67b7f20dbdb7362aab",
"assets/assets/characters/nara_guide_sad.png": "a8c2987412ea07e6f39de2a5b412d5a2",
"assets/assets/characters/nara_guide_joy_face_parts.png": "ea048495e43b5da5ddaf8d2c4c0ce0c1",
"assets/assets/characters/nara_guide_joy.png": "54944cfd6201b9fba37ef28a04c0b6fa",
"assets/assets/characters/nara_guide_face_parts.png": "123fde33f947ec6e0a18c1f61626794d",
"assets/assets/characters/nara_guide.png": "dabb74985fac7a752bef34667ba16882",
"assets/assets/icons/tap.png": "4923afd3d548324e092dea5cbd7dce3c",
"assets/assets/icons/MaterialIcons_LICENSE.txt": "9272dca46e13bd73dc5617e4ce2852fc",
"version.json": "8c276741097b0c1809b7cf9bd0c2d84d",
"main.dart.js": "b192ba55db902532ca008de3444a1491",
"index.html": "f2b6b975c4e359c088de8d08428bf4ab",
"/": "f2b6b975c4e359c088de8d08428bf4ab",
"flutter_bootstrap.js": "3044498b414c50047def4c9a3f05d264",
"flutter.js": "76f08d47ff9f5715220992f993002504",
"canvaskit/skwasm_st.js.symbols": "c7e7aac7cd8b612defd62b43e3050bdd",
"canvaskit/skwasm_st.wasm": "56c3973560dfcbf28ce47cebe40f3206",
"canvaskit/canvaskit.wasm": "efeeba7dcc952dae57870d4df3111fad",
"canvaskit/skwasm.wasm": "f0dfd99007f989368db17c9abeed5a49",
"canvaskit/chromium/canvaskit.wasm": "64a386c87532ae52ae041d18a32a3635",
"canvaskit/chromium/canvaskit.js.symbols": "5a23598a2a8efd18ec3b60de5d28af8f",
"canvaskit/chromium/canvaskit.js": "34beda9f39eb7d992d46125ca868dc61",
"canvaskit/canvaskit.js.symbols": "68eb703b9a609baef8ee0e413b442f33",
"canvaskit/skwasm.js.symbols": "80806576fa1056b43dd6d0b445b4b6f7",
"canvaskit/skwasm.js": "f2ad9363618c5f62e813740099a80e63",
"canvaskit/canvaskit.js": "86e461cf471c1640fd2b461ece4589df",
"canvaskit/skwasm_st.js": "d1326ceef381ad382ab492ba5d96f04d"};
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
