# markdown-new

A Dify tool plugin that converts a URL into Markdown via `https://markdown.new/`.

## Features

- No API key required.
- Input a URL and extraction options in Dify tool panel.
- Supports markdown.new options:
  - `method`: `auto` / `ai` / `browser`
  - `retain_images`: keep image references in Markdown
- Returns:
  - Plain Markdown text output
  - Optional JSON metadata (tokens and rate-limit headers)

## Tool Parameters

- `url` (required): Target HTTP/HTTPS URL
- `method` (optional, default `auto`): Extraction strategy
- `retain_images` (optional, default `false`): Preserve images
- `timeout_seconds` (optional, default `60`): Request timeout
- `include_response_meta` (optional, default `true`): Return metadata JSON

## Output

When `include_response_meta=true`, the tool emits:

- JSON with:
  - `markdown`
  - `meta.x_markdown_tokens`
  - `meta.x_rate_limit_remaining`
  - `meta.x_rate_limit_limit`
  - `meta.x_rate_limit_reset`
- Plain markdown text

## Development

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```
