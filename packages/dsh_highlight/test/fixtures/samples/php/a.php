<?php
declare(strict_types=1);

namespace App\Models;

use InvalidArgumentException;

interface Shape { public function area(): float; }

abstract class Base implements Shape
{
    public const VERSION = '1.0';
    protected static int $count = 0;

    public function __construct(
        private readonly string $name,
        protected ?int $size = null,
    ) {
        self::$count++;
    }

    abstract public function area(): float;

    public function describe(array $opts = []): string
    {
        $text = "Name: {$this->name} and $this->size \"q\"\n";
        $raw = 'single \'quoted\' $notExpanded';
        $doc = <<<EOT
            heredoc {$this->name}
            EOT;
        if (empty($opts) || !isset($opts['x'])) {
            throw new InvalidArgumentException("empty");
        }
        foreach ($opts as $key => $value) {
            echo $key . '=' . $value, PHP_EOL;
        }
        return $text . $raw . $doc;
    }
}

function helper(int ...$nums): int {
    return array_sum(array_map(fn($n) => $n * 2, $nums));
}
// comment
# hash comment
/* block */
?>
<p>Inline <?= htmlspecialchars($title) ?> html</p>
