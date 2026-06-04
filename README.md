# DevOps Interview Wiki 🚀

A file-based DevOps reference wiki. Each topic is a plain `.md` file in the `topics/` folder.
Drop a file in → it appears in the Table of Contents automatically.

## Project Structure

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
