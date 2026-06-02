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
            AB: () => Date.now(),
      AC: (map, o, v) => map.set(o, v),
      B: s => printToConsole(s),
      BB: () => 1000 * performance.now(),
      BC: () => new WeakMap(),
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: x0 => new WeakRef(x0),
      CC: (a, s, e) => a.slice(s, e),
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: x0 => x0.deref(),
      DC: s => s.trimRight(),
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: () => globalThis.WeakRef,
      EC: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      F: () => new Error().stack,
      FB: s => s.toUpperCase(),
      FC: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      G: s => JSON.stringify(s),
      GB: Object.is,
      GC: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (string, token) => string.split(token),
      HC: o => o.byteOffset,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: o => o instanceof Array,
      IC: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      J: o => o,
      JB: (a, i) => a[i],
      JC: Function.prototype.call.bind(DataView.prototype.getUint8),
      K: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      KB: (a, i) => a.push(i),
      KC: Function.prototype.call.bind(DataView.prototype.setUint8),
      L: x0 => x0.index,
      LB: a => a.length,
      LC: o => o.buffer,
      M: o => String(o),
      MB: (a, i, v) => a[i] = v,
      MC: (b, o) => new DataView(b, o),
      N: o => o === undefined,
      NB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      NC: (b, o, l) => new DataView(b, o, l),
      O: (x0,x1) => x0.exec(x1),
      OB: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      OC: Function.prototype.call.bind(DataView.prototype.getInt32),
      P: (x0,x1) => { x0.lastIndex = x1 },
      PB: (x0,x1) => x0.test(x1),
      PC: Function.prototype.call.bind(DataView.prototype.getUint16),
      Q: o => o,
      QB: x0 => x0.pop(),
      QC: Function.prototype.call.bind(DataView.prototype.getUint32),
      R: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      RB: x0 => x0.flags,
      RC: Function.prototype.call.bind(DataView.prototype.setUint32),
      S: o => o instanceof RegExp,
      SB: Function.prototype.call.bind(String.prototype.toLowerCase),
      SC: o => o.byteLength,
      T: (string, times) => string.repeat(times),
      TB: (x0,x1) => x0[x1],
      TC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      U: o => o,
      UB: (o, p, r) => o.replace(p, () => r),
      V: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      VB: (o, p, r) => o.replaceAll(p, () => r),
      W: x0 => x0.dotAll,
      WB: (decoder, codeUnits) => decoder.decode(codeUnits),
      X: x0 => x0.unicode,
      XB: () => new TextDecoder("utf-8", {fatal: true}),
      Y: x0 => x0.ignoreCase,
      YB: () => new TextDecoder("utf-8", {fatal: false}),
      Z: x0 => x0.multiline,
      ZB: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      a: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      aB: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      b: (module,f) => finalizeWrapper(f, function(x0,x1,x2) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_12(f,arguments.length,x0,x1,x2) }),
      bB: x0 => { globalThis.dartAnalyzerInit = x0 },
      c: (module,f) => finalizeWrapper(f, function(x0) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_13(f,arguments.length,x0) }),
      cB: (s) => +s,
      d: x0 => { globalThis.dartAnalyze = x0 },
      dB: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      e: (module,f) => finalizeWrapper(f, function(x0,x1) { return module.exports._JS_Trampoline_FunctionToJSExportedDartFunction_get_toJS_9(f,arguments.length,x0,x1) }),
      eB: s => s.trim(),
      f: x0 => new Promise(x0),
      fB: x0 => x0.length,
      g: (x0,x1,x2) => x0.call(x1,x2),
      gB: x0 => x0.clearMarks(),
      h: (o, p, v) => o[p] = v,
      hB: x0 => x0.clearMeasures(),
      i: (o,s,v) => o[s] = v,
      iB: (x0,x1) => x0.parse(x1),
      j: () => Symbol("jsBoxedDartObjectProperty"),
      jB: (x0,x1,x2) => x0.mark(x1,x2),
      k: () => ({}),
      kB: (x0,x1,x2,x3) => x0.measure(x1,x2,x3),
      l: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      lB: (o) => {
        const typeofValue = typeof o;
        return (typeofValue === 'object') ||
            typeofValue === 'function';
      },
      m: x0 => new Array(x0),
      mB: () => globalThis.JSON,
      n: o => [o],
      nB: x0 => x0.clearMarks,
      o: (o0, o1) => [o0, o1],
      oB: x0 => x0.clearMeasures,
      p: (o0, o1, o2) => [o0, o1, o2],
      pB: x0 => x0.mark,
      q: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      qB: x0 => x0.measure,
      r: (x0,x1,x2) => { x0[x1] = x2 },
      rB: () => globalThis.performance,
      s: (o, p) => o[p],
      sB: (a, s) => a.join(s),
      t: () => globalThis,
      tB: (a, i) => a.splice(i, 1),
      u: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      uB: (a, i) => a.splice(i, 1)[0],
      v: (l, r) => l === r,
      vB: a => a.pop(),
      w: x0 => x0.random(),
      wB: s => new Date(s * 1000).getTimezoneOffset() * 60,
      x: () => globalThis.Math,
      xB: Date.now,
      y: (s, p, i) => s.lastIndexOf(p, i),
      yB: (a, l) => a.length = l,
      z: () => typeof dartUseDateNowForTicks !== "undefined",
      zB: (map, o) => map.get(o),

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
