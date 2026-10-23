'use strict';
const path = require('path');
const { a, b: renamed, ...rest } = require('./mod');

class Counter {
  #n = 0;
  static create() { return new Counter(); }
  get value() { return this.#n; }
  inc(by = 1) { this.#n += by; return this; }
}

const re = /(\d+)-(?<word>\w+)\/[^/]*/u;
const s1 = 'single \' quote';
const s2 = "double \" quote";
const tpl = `a${1 + 2}b${`c${path.sep}`}`;

async function* gen() {
  for await (const x of source()) yield x;
}

label: for (let i = 0; i < 3; i++) {
  if (i === 1) continue label;
  switch (i) {
    case 0: console.log('zero'); break;
    default: console.log(i);
  }
}

const obj = { key: 1, 'quoted-key': 2, [`computed${1}`]: 3, fn() { return null; } };
export { Counter, obj as default };
