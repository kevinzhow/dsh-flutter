<?php
namespace App\Http;
use App\{Models\User, Support\Str as S};
use function array_map;
use const PHP_EOL;

#[Attribute(Attribute::TARGET_CLASS)]
final class Route { public function __construct(public string $path = '/') {} }

enum Status: string
{
    case Active = 'active';
    case Off = 'off';
    public static function default(): self { return self::Active; }
}

trait Loggable { abstract protected function log(string $m): void; }

abstract class Controller
{
    use Loggable;
    public function __invoke(Request $r, int|string $id, ?callable $cb = null, ...$rest): static|null
    {
        $a = ['k' => 1, 'list' => [1, 2, 3], ...$rest];
        [$x, [, $y]] = [1, [2, 3]];
        $s = "var $x and {$a['k']} and ${y} and \$esc \x41 \u{1F600} \t";
        $h = <<<"HTML"
        <p>$s {$this->name}</p>
        HTML;
        $n = <<<'RAW'
        no $interp here
        RAW;
        $m = match(true) { $x > 1 => 'big', default => 'small' };
        $f = fn(int $n): int => $n * 2;
        $o = new class(1) extends Base implements \Countable { public function count(): int { return 0; } };
        echo $x ?? $y?->z ?: 'default', PHP_EOL;
        print_r(array_map(static fn($v) => $v ** 2, [1, 2]));
        list('a' => $q) = $a;
        goto end; end:
        try { throw new \RuntimeException("e"); } catch (\A | \B $e) { } finally { }
        return 0b11 + 0x1F + 0o17 + 1_000 + 1.5e3;
    }
}
