"""Condenses a Claude Code transcript (.jsonl) into a dense digest for another AI to review: user requests, Claude's text
and reasoning (trimmed), tool calls (name + trimmed input) and trimmed results. Email addresses are replaced."""
import json
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
EMAIL = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')


def clean(s, n):
    s = EMAIL.sub('[email]', s or '')
    s = re.sub(r'\s+', ' ', s).strip()
    return s if len(s) <= n else s[:n] + '...'


out = []
for line in open(src, encoding='utf-8', errors='replace'):
    try:
        rec = json.loads(line)
    except Exception:
        continue
    kind = rec.get('type')
    msg = rec.get('message') or {}
    content = msg.get('content')
    if kind == 'user':
        if isinstance(content, str):
            if '<system-reminder>' in content[:200] or 'task-notification' in content[:300]:
                continue
            out.append('U: ' + clean(content, 600))
        elif isinstance(content, list):
            for b in content:
                if b.get('type') == 'text':
                    t = b.get('text', '')
                    if t.startswith('<system-reminder>') or '<task-notification>' in t[:300]:
                        continue
                    out.append('U: ' + clean(t, 600))
                elif b.get('type') == 'tool_result':
                    c = b.get('content')
                    if isinstance(c, list):
                        c = ' '.join(x.get('text', '') for x in c if isinstance(x, dict))
                    out.append('R: ' + clean(str(c), 220))
    elif kind == 'assistant' and isinstance(content, list):
        for b in content:
            t = b.get('type')
            if t == 'text':
                out.append('C: ' + clean(b.get('text'), 900))
            elif t == 'thinking':
                out.append('T: ' + clean(b.get('thinking'), 700))
            elif t == 'tool_use':
                inp = b.get('input') or {}
                desc = inp.get('description') or ''
                body = inp.get('command') or inp.get('prompt') or inp.get('file_path') or json.dumps(inp)[:400]
                out.append('A: %s [%s] %s' % (b.get('name'), clean(desc, 80), clean(str(body), 260)))
text = '\n'.join(out)
open(dst, 'w', encoding='utf-8').write(text)
print(len(out), 'entries', len(text), 'chars')
