// Basic declarations, strings, template literals and comments.
const limit: number = 42; // trailing comment
let name = 'it\'s "quoted"';
const greeting = `hello ${name.toUpperCase()} and ${limit + 1}`;

/**
 * Adds two numbers.
 * @param a first value
 * @param b second value
 */
function add(a: number, b = 2): number {
  return a + b;
}

const nested = `outer ${`inner ${limit}`} done`;
const pattern = /^[a-z]+\d{2,}(?:x|y)$/gi;
const text = "line one\nline two\ttabbed é";

export default function main(argv: string[]): void {
  if (argv.length > limit && !name) {
    console.log(greeting, add(1, 2));
  } else {
    throw new Error(`bad ${argv.join(",")}`);
  }
}
