/**
 * Minimal, dependency-free markdown → HTML for the compiled prompt panels.
 *
 * Safety model: ALL input is HTML-escaped before any tags are produced, so
 * the only HTML in the output is what this module writes. No raw-HTML
 * passthrough, links restricted to http(s).
 *
 * Supported: #–#### headings, fenced code blocks, inline code, bold, links,
 * unordered/ordered lists, blockquotes, horizontal rules, paragraphs
 * (pre-wrap preserves intra-paragraph line breaks).
 */

import { escapeHtml, highlightJsonText } from './highlight'

/** Bold + links, applied only OUTSIDE inline-code spans. */
function inline(escaped: string): string {
  const parts = escaped.split(/(`[^`\n]+`)/g)
  return parts
    .map((part, i) => {
      if (i % 2 === 1) return `<code>${part.slice(1, -1)}</code>`
      return part
        .replaceAll(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
        .replaceAll(
          /\[([^\]\n]+)\]\((https?:\/\/[^)\s]+)\)/g,
          '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>',
        )
    })
    .join('')
}

export function renderMarkdown(src: string): string {
  const lines = src.replaceAll('\r\n', '\n').split('\n')
  const out: string[] = []
  let i = 0

  const paragraph: string[] = []
  function flushParagraph() {
    if (paragraph.length) {
      out.push(`<p>${paragraph.map(inline).join('\n')}</p>`)
      paragraph.length = 0
    }
  }

  while (i < lines.length) {
    const raw = lines[i] ?? ''
    const line = escapeHtml(raw)

    // Fenced code block — verbatim until the closing fence. json fences get
    // syntax highlighting (the Report contract in every user.md is one).
    const fence = /^\s*```(\w*)/.exec(raw)
    if (fence) {
      flushParagraph()
      const code: string[] = []
      i += 1
      while (i < lines.length && !/^\s*```/.test(lines[i] ?? '')) {
        code.push(lines[i] ?? '')
        i += 1
      }
      i += 1
      const text = code.join('\n')
      const body =
        (fence[1] ?? '').toLowerCase() === 'json' ? highlightJsonText(text) : escapeHtml(text)
      out.push(`<pre class="md-code"><code>${body}</code></pre>`)
      continue
    }

    const heading = /^(#{1,4})\s+(.*)$/.exec(raw)
    if (heading?.[1] && heading[2] !== undefined) {
      flushParagraph()
      const level = heading[1].length
      out.push(`<h${level}>${inline(escapeHtml(heading[2]))}</h${level}>`)
      i += 1
      continue
    }

    if (/^\s*(---+|\*\*\*+)\s*$/.test(raw)) {
      flushParagraph()
      out.push('<hr>')
      i += 1
      continue
    }

    if (/^\s*&gt;\s?/.test(line)) {
      flushParagraph()
      const quote: string[] = []
      while (i < lines.length && /^\s*>\s?/.test(lines[i] ?? '')) {
        quote.push(inline(escapeHtml((lines[i] ?? '').replace(/^\s*>\s?/, ''))))
        i += 1
      }
      out.push(`<blockquote>${quote.join('\n')}</blockquote>`)
      continue
    }

    const ulItem = /^\s*[-*]\s+/.test(raw)
    const olItem = /^\s*\d+\.\s+/.test(raw)
    if (ulItem || olItem) {
      flushParagraph()
      const tag = ulItem ? 'ul' : 'ol'
      const marker = ulItem ? /^\s*[-*]\s+/ : /^\s*\d+\.\s+/
      const items: string[] = []
      while (i < lines.length && marker.test(lines[i] ?? '')) {
        items.push(`<li>${inline(escapeHtml((lines[i] ?? '').replace(marker, '')))}</li>`)
        i += 1
      }
      out.push(`<${tag}>${items.join('')}</${tag}>`)
      continue
    }

    if (raw.trim() === '') {
      flushParagraph()
      i += 1
      continue
    }

    paragraph.push(line)
    i += 1
  }
  flushParagraph()
  return out.join('\n')
}
