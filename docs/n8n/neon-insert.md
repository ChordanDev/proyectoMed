# n8n Neon insert node

The last node of the flow stores each generated case as one **pending** row of the `cases` table in Neon (Postgres). It implements the insert contract of the [format spec](../case-format/README.md#inserting-a-case-n8n-contract) (issue #331); `backend/test/backend/stations/case_format_n8n_samples_test.exs` runs the SQL below against that table and checks it is the same as the contract.

## What n8n sets and what Postgres sets

| Column | Set by | Value |
|---|---|---|
| `area` | n8n | The `[ÁREA]` of the case, spelled exactly as in the generator prompt's list (the admin panel filters on the exact text). |
| `theme` | n8n | The `[TEMA]` of the case. |
| `markdown` | n8n | The whole case text returned by the generator (after the reviewer loop), UTF-8, unchanged. |
| `number` | Postgres | Sequential number (`GENERATED ALWAYS AS IDENTITY`). Never send it: an insert that sets it is refused. It may skip a value after a failed insert. |
| `status` | Postgres | Defaults to `pending`. Never send it: only the admin panel approves or disapproves. |
| `id`, `inserted_at`, `updated_at` | Postgres | Defaults. |

The insert does not validate the format. A case that still has format errors after the reviewer loop is stored as pending, and the admin panel shows its located errors at the top.

## Node configuration

1. **Credential** (Postgres): host, database, user and password of the Neon branch used in production; **SSL: Require**. Use a role that can only `INSERT` into `cases` (and `SELECT` for `RETURNING`).
2. **Operation:** *Execute Query*.
3. **Query:**

   ```sql
   INSERT INTO cases (area, theme, markdown)
   VALUES ($1, $2, $3)
   RETURNING number;
   ```

4. **Options → Query Parameters:** pass the three values as one **array expression**, not as comma-separated text. The case text contains commas, and a comma-separated list would split it into extra parameters:

   ```
   {{ [ $json.area, $json.theme, $json.markdown ] }}
   ```

5. **Output:** one item with `number`. Log it (or send it to the team channel) so doctors can be told which numbers are new.

## Taking `area` and `theme` from the case

Read them from the case text, so the row always matches what the parser and the admin panel see. In a *Code* node before the insert:

```js
const markdown = $json.markdown;
const tag = (name) => {
  const match = markdown.match(new RegExp(`^\\[${name}\\]\\s*(.+)$`, "mu"));
  return match ? match[1].trim() : null;
};
// The parser accepts [ÁREA] and [AREA]; so does this.
return [{ json: { markdown, area: tag("(?:ÁREA|AREA)"), theme: tag("TEMA") } }];
```

If either is missing, the case is broken beyond what the reviewer fixed: fall back to the área and tema the flow asked for, so the row is still stored and the admin panel shows the parser errors.
