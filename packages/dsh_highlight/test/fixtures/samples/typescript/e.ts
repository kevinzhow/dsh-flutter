// Decorators, generics, regex vs division, unicode and edge syntax.
@Component({ selector: 'app-root', template: `<div>{{ title }}</div>` })
export class AppComponent<T extends Record<string, unknown> = {}> {
  @Input() title = 'héllo wörld 日本語 🚀';
  @Output() changed = new EventEmitter<T>();
  private readonly #secret?: number;
  static #count = 0;
  declare foo: string;

  constructor(@Inject(TOKEN) private readonly svc: Service) {}

  get half(): number { return this.total / 2 / 3; }
  isMatch(s: string) { return /ab+c/.test(s) ? s.length / 2 : /\//.test(s); }
}

const satisfied = { a: 1 } satisfies Record<string, number>;
const asserted = <HTMLInputElement>document.getElementById('x');
const nonNull = maybe!.value!;
let tuple: [string, number?, ...boolean[]] = ['a'];
type Fn = new (...args: any[]) => object;
type Mapped<T> = { readonly [K in keyof T as `get${Capitalize<string & K>}`]?: () => T[K] };
function assertIsString(val: any): asserts val is string {}
namespace Outer.Inner { export const v = 1; }
const big = 123n ** 2n, hex = 0xFF_FF, oct = 0o17, bin = 0b1010, flt = .5e-10;
a ||= b; c &&= d; e ??= f;
label: { break label; }
if (a < b && c > d) { /* generic or compare? */ }
const x = y as unknown as Array<Map<string, Set<number>>>;
export * as utils from './utils';
import json from './data.json' with { type: 'json' };
