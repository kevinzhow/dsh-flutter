import React, { useState } from 'react';

type Props = { label: string; onPick?: (id: number) => void };

export function Button({ label, onPick }: Props) {
  const [n, setN] = useState<number>(0);
  return (
    <button className="btn" onClick={() => { setN(n + 1); onPick?.(n); }}>
      {label}: {n}
    </button>
  );
}

const el = <div id="root" data-x={1}><span>text</span></div>;
