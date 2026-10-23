/* eslint-disable */
var self = this, undefinedVar = void 0;
function Legacy(name) {
  if (!(this instanceof Legacy)) return new Legacy(name);
  this.name = name || "anon";
}
Legacy.prototype.greet = function () {
  return 'Hello, ' + this.name + '!\n' + "tab\tquote\"";
};
var s = 'line one \
line two';
var re1 = /[/\]]+\/(?=x)/gimsuy, re2 = a / b / c;
var obj = { get x() { return 1 }, set x(v) {}, async *gen() {}, 'a-b': 2, 3: 'three' };
var t = `multi
line ${ obj.x > 1 ? `yes ${1}` : 'no' } end`;
do { i++ } while (i < 10)
try { JSON.parse(t) } catch { console.error('bad') } finally { done() }
new Promise((resolve, reject) => setTimeout(resolve, 100)).then(() => 1).catch(e => e);
export default class extends Legacy { static x = 1; #p = 2; }
if (typeof window !== 'undefined' && window.document?.body) console.log(`<${'div'}>`);
var arrow = async ({ a, b = 2 }, [c, , d], ...rest) => await a;
