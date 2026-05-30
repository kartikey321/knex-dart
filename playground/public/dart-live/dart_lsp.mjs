// Compiles a dart2wasm-generated main module from `source` which can then
// instantiatable via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm modules from `bytes` which is then
// instantiatable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

// DEPRECATED: Please use `compile` or `compileStreaming` to get a compiled app,
// use `instantiate` method to get an instantiated app and then call
// `invokeMain` to invoke the main function.
export async function instantiate(modulePromise, importObjectPromise) {
  var moduleOrCompiledApp = await modulePromise;
  if (!(moduleOrCompiledApp instanceof CompiledApp)) {
    moduleOrCompiledApp = new CompiledApp(moduleOrCompiledApp);
  }
  const instantiatedApp = await moduleOrCompiledApp.instantiate(await importObjectPromise);
  return instantiatedApp.instantiatedModule;
}

// DEPRECATED: Please use `compile` or `compileStreaming` to get a compiled app,
// use `instantiate` method to get an instantiated app and then call
// `invokeMain` to invoke the main function.
export const invoke = (moduleInstance, ...args) => {
  moduleInstance.exports.$invokeMain(args);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arugments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arugments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: (a, i, v) => a[i] = v,
      AC: Function.prototype.call.bind(DataView.prototype.setUint8),
      AD: x0 => new Array(x0),
      AE: x0 => x0.url,
      B: s => printToConsole(s),
      BB: a => a.length,
      BC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      BD: o => [o],
      BE: x0 => x0.status,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      CC: Function.prototype.call.bind(DataView.prototype.getInt8),
      CD: (o0, o1) => [o0, o1],
      CE: x0 => x0.getReader(),
      D: Function.prototype.call.bind(String.prototype.indexOf),
      DB: (x0,x1) => x0.test(x1),
      DC: Function.prototype.call.bind(DataView.prototype.setInt8),
      DD: (o0, o1, o2) => [o0, o1, o2],
      DE: x0 => x0.read(),
      E: o => o,
      EB: x0 => x0.pop(),
      EC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      ED: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      EE: x0 => x0.value,
      F: s => JSON.stringify(s),
      FB: x0 => x0.flags,
      FC: o => o.length,
      FD: (x0,x1,x2) => { x0[x1] = x2 },
      FE: x0 => x0.done,
      G: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      GB: (a, i) => a.push(i),
      GC: (o, i) => o[i],
      GD: x0 => x0.reason,
      GE: x0 => x0.body,
      H: x0 => x0.index,
      HB: (a, b) => a == b ? 0 : (a > b ? 1 : -1),
      HC: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      HD: x0 => x0.code,
      HE: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      I: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      IB: (o, p, r) => o.replace(p, () => r),
      IC: (o, p) => o[p],
      ID: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      IE: x0 => x0.headers,
      J: () => new Error().stack,
      JB: (o, p, r) => o.replaceAll(p, () => r),
      JC: x0 => x0.groups,
      JD: (o, c) => o instanceof c,
      JE: x0 => x0.signal,
      K: o => String(o),
      KB: (decoder, codeUnits) => decoder.decode(codeUnits),
      KC: x0 => x0.clearMarks(),
      KD: () => globalThis,
      KE: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      L: o => o === undefined,
      LB: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      LC: x0 => x0.clearMeasures(),
      LD: (o, t) => typeof o === t,
      M: (x0,x1) => x0.exec(x1),
      MB: () => new TextDecoder("utf-8", {fatal: true}),
      MC: (x0,x1) => x0.parse(x1),
      MD: x0 => x0.data,
      N: (x0,x1) => { x0.lastIndex = x1 },
      NB: () => new TextDecoder("utf-8", {fatal: false}),
      NC: (x0,x1,x2) => x0.mark(x1,x2),
      ND: (x0,x1,x2) => x0.close(x1,x2),
      O: o => o,
      OB: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      OC: (x0,x1,x2,x3) => x0.measure(x1,x2,x3),
      OD: x0 => x0.close(),
      P: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      PB: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      PC: (o) => {
        const typeofValue = typeof o;
        return (typeofValue === 'object') ||
            typeofValue === 'function';
      },
      PD: (x0,x1) => x0.send(x1),
      Q: o => o instanceof RegExp,
      QB: () => typeof dartUseDateNowForTicks !== "undefined",
      QC: () => globalThis.JSON,
      QD: () => ({}),
      R: (string, times) => string.repeat(times),
      RB: () => Date.now(),
      RC: x0 => x0.clearMarks,
      RD: (o, p, v) => o[p] = v,
      S: o => o,
      SB: () => 1000 * performance.now(),
      SC: x0 => x0.clearMeasures,
      SD: () => [],
      T: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      TB: x0 => new WeakRef(x0),
      TC: x0 => x0.mark,
      TD: x0 => new Int8Array(x0),
      U: x0 => x0.dotAll,
      UB: x0 => x0.deref(),
      UC: x0 => x0.measure,
      UD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      V: x0 => x0.unicode,
      VB: () => globalThis.WeakRef,
      VC: () => globalThis.performance,
      VD: x0 => new Uint8Array(x0),
      W: x0 => x0.ignoreCase,
      WB: (a, i) => a.splice(i, 1),
      WC: (a, s) => a.join(s),
      WD: x0 => new Uint8ClampedArray(x0),
      X: x0 => x0.multiline,
      XB: (o, p) => p in o,
      XC: (b, o) => new DataView(b, o),
      XD: x0 => new Int16Array(x0),
      Y: Function.prototype.call.bind(Number.prototype.toString),
      YB: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      YC: (b, o, l) => new DataView(b, o, l),
      YD: x0 => new Uint16Array(x0),
      Z: Function.prototype.call.bind(BigInt.prototype.toString),
      ZB: f => f.dartFunction,
      ZC: (a, i) => a.splice(i, 1)[0],
      ZD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      a: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      aB: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_14(f,arguments.length,x0) }),
      aC: a => a.pop(),
      aD: x0 => new Int32Array(x0),
      b: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_12(f,arguments.length,x0,x1) }),
      bB: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_15(f,arguments.length,x0,x1) }),
      bC: o => o.byteOffset,
      bD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      c: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_13(f,arguments.length,x0) }),
      cB: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      cC: o => o.byteLength,
      cD: x0 => new Uint32Array(x0),
      d: x0 => { globalThis.lspSend = x0 },
      dB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      dC: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      dD: x0 => new Float32Array(x0),
      e: (x0,x1,x2) => x0.call(x1,x2),
      eB: o => o.buffer,
      eC: () => Date.now(),
      eD: x0 => new Float64Array(x0),
      f: () => globalThis.lspReceive,
      fB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      fC: (handle) => clearInterval(handle),
      fD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      g: (l, r) => l === r,
      gB: (t, s) => t.set(s),
      gC: (handle) => clearTimeout(handle),
      gD: x0 => new ArrayBuffer(x0),
      h: x0 => x0.random(),
      hB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      hC: (a, l) => a.length = l,
      hD: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      i: () => globalThis.Math,
      iB: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      iC: (map, o, v) => map.set(o, v),
      iD: (x0,x1,x2) => new DataView(x0,x1,x2),
      j: (s, p, i) => s.lastIndexOf(p, i),
      jB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      jC: (map, o) => map.get(o),
      jD: (o, p) => o[p],
      k: (s) => +s,
      kB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      kC: () => new WeakMap(),
      kD: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      l: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      lB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      lC: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      lD: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      m: s => s.trim(),
      mB: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      mC: (a, s, e) => a.slice(s, e),
      mD: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      n: x0 => { globalThis.lspStart = x0 },
      nB: Function.prototype.call.bind(DataView.prototype.setUint32),
      nC: s => s.trimRight(),
      nD: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      o: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      oB: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      oC: x0 => x0.cancel(),
      oD: o => o instanceof Uint16Array,
      p: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      pB: Function.prototype.call.bind(DataView.prototype.getUint32),
      pC: x0 => x0.name,
      pD: o => o instanceof Int16Array,
      q: s => new Date(s * 1000).getTimezoneOffset() * 60,
      qB: Function.prototype.call.bind(DataView.prototype.getInt32),
      qC: (d, digits) => d.toFixed(digits),
      qD: o => o instanceof Uint8ClampedArray,
      r: Date.now,
      rB: Function.prototype.call.bind(DataView.prototype.setInt32),
      rC: () => new Array(),
      rD: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      s: Function.prototype.call.bind(String.prototype.toLowerCase),
      sB: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      sC: (x0,x1) => new WebSocket(x0,x1),
      sD: x0 => x0.protocol,
      t: Object.is,
      tB: Function.prototype.call.bind(DataView.prototype.getUint16),
      tC: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      tD: () => new AbortController(),
      u: s => s.toUpperCase(),
      uB: Function.prototype.call.bind(DataView.prototype.setUint16),
      uC: b => !!b,
      uD: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      v: (x0,x1) => x0[x1],
      vB: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      vC: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_18(f,arguments.length,x0) }),
      vD: (x0,x1) => globalThis.fetch(x0,x1),
      w: x0 => x0.length,
      wB: Function.prototype.call.bind(DataView.prototype.getInt16),
      wC: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      wD: (x0,x1) => x0.get(x1),
      x: (string, token) => string.split(token),
      xB: Function.prototype.call.bind(DataView.prototype.setInt16),
      xC: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_17(f,arguments.length,x0) }),
      xD: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_16(f,arguments.length,x0,x1,x2) }),
      y: o => o instanceof Array,
      yB: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      yC: x0 => x0.readyState,
      yD: (x0,x1) => x0.forEach(x1),
      z: (a, i) => a[i],
      zB: Function.prototype.call.bind(DataView.prototype.getUint8),
      zC: (x0,x1) => { x0.binaryType = x1 },
      zD: x0 => x0.statusText,

    };

    const baseImports = {
      dart2wasm: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });
    dartInstance.exports.$setThisModule(dartInstance);

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
