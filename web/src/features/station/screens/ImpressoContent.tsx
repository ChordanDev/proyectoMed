import { Fragment, type ReactNode } from "react";

/**
 * Renders impresso content written in the Markdown subset the station
 * packages use: `### ` headings, `**bold**`, `- ` bullet lists, paragraphs
 * separated by blank lines and single line breaks.
 *
 * Everything becomes React elements and text nodes, so markup in package
 * content is shown as literal text and can never inject HTML. Anything outside
 * the subset is rendered verbatim.
 */
type Block =
  | { kind: "heading"; text: string }
  | { kind: "list"; items: string[] }
  | { kind: "paragraph"; lines: string[] };

const HEADING = /^#{1,6}\s+(.*)$/;
const BULLET = /^[-*]\s+(.*)$/;

function parseBlocks(content: string): Block[] {
  const blocks: Block[] = [];
  let current: Block | null = null;

  const flush = () => {
    if (current) blocks.push(current);
    current = null;
  };

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();

    if (line === "") {
      flush();
      continue;
    }

    const heading = HEADING.exec(line);
    if (heading) {
      flush();
      blocks.push({ kind: "heading", text: heading[1] });
      continue;
    }

    const bullet = BULLET.exec(line);
    if (bullet) {
      if (current?.kind !== "list") {
        flush();
        current = { kind: "list", items: [] };
      }
      current.items.push(bullet[1]);
      continue;
    }

    if (current?.kind !== "paragraph") {
      flush();
      current = { kind: "paragraph", lines: [] };
    }
    current.lines.push(line);
  }

  flush();
  return blocks;
}

/** Splits `**bold**` spans; an unclosed marker stays literal text. */
function renderInline(text: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  const pattern = /\*\*(.+?)\*\*/g;
  let cursor = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > cursor) nodes.push(text.slice(cursor, match.index));
    nodes.push(<strong key={match.index}>{match[1]}</strong>);
    cursor = match.index + match[0].length;
  }

  if (cursor < text.length) nodes.push(text.slice(cursor));
  return nodes;
}

export function ImpressoContent({ content }: { content: string }) {
  const blocks = parseBlocks(content);

  return (
    <div className="impresso-content">
      {blocks.map((block, index) => {
        switch (block.kind) {
          case "heading":
            return (
              <h4 key={index} className="impresso-content__heading">
                {renderInline(block.text)}
              </h4>
            );
          case "list":
            return (
              <ul key={index} className="impresso-content__list">
                {block.items.map((item, itemIndex) => (
                  <li key={itemIndex}>{renderInline(item)}</li>
                ))}
              </ul>
            );
          case "paragraph":
            return (
              <p key={index} className="impresso-content__paragraph">
                {block.lines.map((line, lineIndex) => (
                  <Fragment key={lineIndex}>
                    {lineIndex > 0 && <br />}
                    {renderInline(line)}
                  </Fragment>
                ))}
              </p>
            );
        }
      })}
    </div>
  );
}
