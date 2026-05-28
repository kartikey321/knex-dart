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
  //   compiler when the `load-ids` option is passed. Each load ID maps to one
  //   or more wasm files as specified in the emitted JSON file. It also takes a
  //   callback that should be invoked for each loaded module with 2 arugments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
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
            AB: x0 => x0.random(),
      AC: o => o.buffer,
      B: s => printToConsole(s),
      BB: o => o,
      BC: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      CC: Function.prototype.call.bind(DataView.prototype.getUint8),
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: () => globalThis.Math,
      DC: (b, o, l) => new DataView(b, o, l),
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: (string, token) => string.split(token),
      EC: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      F: () => new Error().stack,
      FB: (s, p, i) => s.lastIndexOf(p, i),
      FC: Function.prototype.call.bind(DataView.prototype.getFloat64),
      G: s => JSON.stringify(s),
      GB: Function.prototype.call.bind(String.prototype.toLowerCase),
      GC: Function.prototype.call.bind(DataView.prototype.setFloat64),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: Object.is,
      HC: Function.prototype.call.bind(DataView.prototype.getFloat32),
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: (x0,x1) => x0.test(x1),
      IC: Function.prototype.call.bind(DataView.prototype.setFloat32),
      J: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      JB: o => o,
      JC: Function.prototype.call.bind(DataView.prototype.getUint32),
      K: o => o === undefined,
      KB: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      KC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      L: o => String(o),
      LB: x0 => x0.unicode,
      LC: Function.prototype.call.bind(DataView.prototype.setUint32),
      M: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_12(f,arguments.length,x0,x1,x2) }),
      MB: x0 => x0.index,
      MC: Function.prototype.call.bind(DataView.prototype.getInt32),
      N: x0 => { globalThis.dartCompile = x0 },
      NB: (x0,x1) => x0[x1],
      NC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      O: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_9(f,arguments.length,x0,x1) }),
      OB: (x0,x1) => x0.exec(x1),
      OC: Function.prototype.call.bind(DataView.prototype.setInt32),
      P: x0 => new Promise(x0),
      PB: (x0,x1) => { x0.lastIndex = x1 },
      PC: Function.prototype.call.bind(DataView.prototype.getUint16),
      Q: (x0,x1,x2) => x0.call(x1,x2),
      QB: x0 => x0.dotAll,
      QC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      R: (o, p, v) => o[p] = v,
      RB: x0 => x0.ignoreCase,
      RC: Function.prototype.call.bind(DataView.prototype.setUint16),
      S: (o,s,v) => o[s] = v,
      SB: x0 => x0.multiline,
      SC: Function.prototype.call.bind(DataView.prototype.getInt16),
      T: () => Symbol("jsBoxedDartObjectProperty"),
      TB: x0 => x0.pop(),
      TC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      U: () => ({}),
      UB: x0 => x0.flags,
      UC: Function.prototype.call.bind(DataView.prototype.setInt16),
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      VC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      W: x0 => new Array(x0),
      WB: o => o instanceof RegExp,
      WC: Function.prototype.call.bind(DataView.prototype.getInt8),
      X: o => [o],
      XB: (o, p, r) => o.replaceAll(p, () => r),
      XC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      Y: (o0, o1) => [o0, o1],
      YB: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      YC: Function.prototype.call.bind(DataView.prototype.setInt8),
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      ZC: o => o.length,
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: (s) => +s,
      aC: (o, i) => o[i],
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      bC: o => {
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
      c: o => o,
      cB: s => s.trim(),
      cC: x0 => x0.groups,
      d: (o, p) => o[p],
      dB: (decoder, codeUnits) => decoder.decode(codeUnits),
      dC: s => new Date(s * 1000).getTimezoneOffset() * 60,
      e: () => globalThis,
      eB: () => new TextDecoder("utf-8", {fatal: true}),
      eC: Date.now,
      f: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      fB: () => new TextDecoder("utf-8", {fatal: false}),
      fC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      g: x0 => new Uint8Array(x0),
      gB: s => s.toUpperCase(),
      gC: (a, i) => a[i],
      h: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      hB: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      hC: a => a.length,
      i: (t, s) => t.set(s),
      iB: () => Date.now(),
      iC: o => o instanceof Array,
      j: Function.prototype.call.bind(DataView.prototype.setUint8),
      jB: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      jC: (a, i) => a.splice(i, 1)[0],
      k: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      kB: () => typeof dartUseDateNowForTicks !== "undefined",
      kC: (a, l) => a.length = l,
      l: x0 => x0.clearMarks(),
      lB: () => Date.now(),
      lC: (a, i, v) => a.splice(i, 0, v),
      m: x0 => x0.clearMeasures(),
      mB: () => 1000 * performance.now(),
      mC: (a, s, e) => a.slice(s, e),
      n: (x0,x1) => x0.parse(x1),
      nB: (d, digits) => d.toFixed(digits),
      nC: (a, b) => a == b ? 0 : (a > b ? 1 : -1),
      o: (x0,x1,x2) => x0.mark(x1,x2),
      oB: (map, o, v) => map.set(o, v),
      oC: (a, i) => a.push(i),
      p: (x0,x1,x2,x3) => x0.measure(x1,x2,x3),
      pB: (map, o) => map.get(o),
      pC: (a, l) => a.length = l,
      q: (o) => {
        const typeofValue = typeof o;
        return (typeofValue === 'object') ||
            typeofValue === 'function';
      },
      qB: () => new WeakMap(),
      qC: (a, i, v) => a[i] = v,
      r: () => globalThis.JSON,
      rB: x0 => x0.length,
      s: x0 => x0.clearMarks,
      sB: (o, p) => p in o,
      t: x0 => x0.clearMeasures,
      tB: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      u: x0 => x0.mark,
      uB: f => f.dartFunction,
      v: x0 => x0.measure,
      vB: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_13(f,arguments.length,x0) }),
      w: () => globalThis.performance,
      wB: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_14(f,arguments.length,x0,x1) }),
      x: (l, r) => l === r,
      xB: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      y: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      yB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      z: (string, times) => string.repeat(times),
      zB: o => o.byteOffset,

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
