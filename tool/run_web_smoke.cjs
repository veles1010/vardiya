// Supply the browser global used by Dart's JavaScript secure-random backend.
globalThis.self = globalThis;
if (!globalThis.crypto) {
  globalThis.crypto = require('node:crypto').webcrypto;
}
require('../build/web_smoke.js');
