# DevOps Interview Wiki 🚀

A file-based DevOps reference wiki. Each topic is a plain `.md` file in the `topics/` folder.
Drop a file in → it appears in the Table of Contents automatically.

## Project Structure

Here's everything used to build your DevOps Interview Wiki:
Frontend Structure

Pure HTML5 — single index.html, no build step needed
Vanilla JavaScript (ES6+) — all logic written from scratch, no framework

Markdown Rendering

Marked.js (v9.1.6) — converts your .md files into HTML at runtime, loaded from cdnjs CDN

Fonts (loaded from Google Fonts)

JetBrains Mono — code blocks, badges, monospace elements
Syne — headings, titles, logo
DM Sans — body text, general UI

CSS

Pure CSS3 — custom properties (variables), flexbox layout, CSS Grid, media queries for print
No Tailwind, no Bootstrap, no preprocessor — everything hand-written

Data Layer

No database — topics are just .md files in a topics/ folder
Browser fetch() API loads each file at runtime
localStorage not used — stateless on every load

PDF Export

Browser's native window.print() with a dedicated @media print CSS block — no library needed

Hosting

Works as a static site — just open index.html in a browser or drop it on GitHub Pages, Netlify, S3, or any static host


That's it — no Node.js, no npm, no bundler, no backend. The entire wiki is one HTML file + a folder of markdown files.

```
devops-wiki/
├── index.html          ← the entire app (single file)
├── topics/             ← one .md file per topic
│   ├── 01-nginx-vs-alb.md
│   ├── 02-auto-scaling-group.md
│   └── ...             ← add your own here
├── Dockerfile
└── docker-compose.yml
```

## Adding a New Topic

1. Create a markdown file in `topics/`:
   ```
   topics/25-squid-proxy.md
   ```

2. Start the file with an H1 title:
   ```markdown
   # Squid Proxy

   ### What is Squid
   - Forward proxy used for caching HTTP requests
   - ...
   ```

3. Register it in `index.html` — find `TOPIC_FILES` array and add:
   ```js
   "topics/25-squid-proxy.md",
   ```

4. Refresh the page — it appears in the TOC with the correct number.

## Running

### Docker (recommended)
```bash
docker compose up -d
# open http://localhost:8080
```

### Docker only
```bash
docker build -t devops-wiki .
docker run -d -p 8080:80 devops-wiki
```

### No server (local file)
```bash
# Won't work directly due to browser fetch() CORS on file://
# Use a local server instead:
npx serve .
# or
python3 -m http.server 8080
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `←` / `↑` | Previous topic |
| `→` / `↓` | Next topic |
| `/` | Focus search bar |
| `Esc` | Unfocus search |

## Download Topic as PDF

1. Open any topic
2. Click **⬇ Download PDF**
3. In browser print dialog → destination → **Save as PDF**

## Markdown Cheatsheet for Topics

```markdown
# Topic Title          ← shown in header (required)

### Section            ← green uppercase heading

**bold**, *italic*, `inline code`

- bullet point
- another point

> blockquote / tip

| Col A | Col B |
|-------|-------|
| val 1 | val 2 |

```bash
code block
```
```
