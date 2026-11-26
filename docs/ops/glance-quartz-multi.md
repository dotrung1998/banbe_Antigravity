# Glance + Quartz — ba site trong tailnet

Dựng ngày 2026-11-26. Một Glance (3 trang) + ba site Quartz tĩnh, mỗi site một cổng.
Chỉ vào được qua Tailscale; không funnel, không URL công khai.

## Bảng site

| slug | Vault (content) | GitHub repo | Serve (loopback) | Tailnet |
|---|---|---|---|---|
| `banbe` | `/Users/thetrungdo/Downloads/banbe/docs/second-brain` | `dotrung1998/banbe_Antigravity` | `127.0.0.1:8082` | `:8082` |
| `jlu-spez` | `/Applications/JLU Spezializierungsmodul/Obsidian` | `dotrung1998/Trung_Do_Spezializierungsmodul` | `127.0.0.1:8083` | `:8083` |
| `jlu-vis` | `/Applications/Vorlesung_mit_Übung_07-BDS-15__07-MDS-06__07-MDA-11_Informationsvisualisierung/Wissen_Informationsvisualisierung` | `dotrung1998/JLU_Informationsvisualisierung` | `127.0.0.1:8084` | `:8084` |

Nguồn duy nhất cho bảng này là `ops/notes/sites.tsv` (6 cột, tab thật). Mọi script
đọc file đó; không hardcode slug trong script.

Khác với prompt gốc, có ghi rõ:

- Repo thật của checkout banbe là `dotrung1998/banbe_Antigravity` (remote `origin`),
  không phải `dotrung1998/banbe`. Glance theo repo thật để Actions khớp thứ được push.
- Tailnet này **chưa bật HTTPS certificate** (`CertDomains` rỗng; `tailscale serve --https`
  treo chờ cert). Vì vậy dùng `--http` và cổng tailnet trùng cổng loopback:
  8080/8082/8083/8084. Khi owner bật HTTPS trong admin console thì đổi `public_port`
  trong `sites.tsv`, chạy lại `make-configs.sh` + `build-all.sh` và thêm mapping
  `--https=8443/8444/8445`.

## URL thật

```
Glance            http://macbook-air-von-the.tail8ab714.ts.net:8080
banbe             http://macbook-air-von-the.tail8ab714.ts.net:8082
JLU Spez          http://macbook-air-von-the.tail8ab714.ts.net:8083
JLU Vis           http://macbook-air-von-the.tail8ab714.ts.net:8084
```

Chỉ trong tailnet. Không có `tailscale funnel`; `tailscale funnel status` phải là
"No serve config" ở phần funnel.

## Kiến trúc

- Quartz pin `v5.1.0` (commit `2ec28dd`) tại `~/quartz-banbe`, **ngoài repo**. Clone đầy
  đủ (không shallow) vì plugin `created-modified-date` đọc git history.
- Mỗi site build vào `~/quartz-sites/<slug>/public`; `content-<slug>` là symlink tới vault.
- Ba server tĩnh `ops/notes/serve.py` (stdlib), mỗi site một cổng, bind `127.0.0.1`.
  Clean URL: `/foo` → `foo.html`, `/foo/` → `foo/index.html`, miss → `404.html` (404).
  Không directory listing.
- Glance chạy Docker, publish `127.0.0.1:8080`, auth bật, đúng 3 trang:
  `Hôm nay` (banbe), `Study` (hai repo JLU), `Notes` (3 vault).
- Tailscale serve: 8080 → Glance, 8082 → banbe, 8083 → jlu-spez, 8084 → jlu-vis.

## Start / stop / restart

```bash
cd /Users/thetrungdo/Downloads/banbe

# build lại cả ba site (sau khi sửa vault hoặc config)
bash ops/notes/make-configs.sh      # sinh quartz.config.<slug>.yaml từ base
bash ops/notes/build-all.sh         # build tuần tự, dọn public/ cũ trước

# server tĩnh
bash ops/notes/start-servers.sh     # pidfile: ~/Library/Logs/banbe-notes-<slug>.pid
for s in banbe jlu-spez jlu-vis; do
  kill "$(cat "$HOME/Library/Logs/banbe-notes-$s.pid")"
done

# Glance
cd ops/glance
docker compose up -d
docker compose restart
docker compose down
docker compose ps
docker compose logs --tail=100
```

Log:

- Quartz serve: `~/Library/Logs/banbe-notes-<slug>.log`
- Glance: `docker compose logs` (container `glance`)
- Build: stdout của `build-all.sh` (không ghi file)

PID: `~/Library/Logs/banbe-notes-<slug>.pid`. `start-servers.sh` chỉ kill PID cũ khi
`ps` xác nhận đúng `ops/notes/serve.py`, và exit 1 nếu cổng vẫn bận — không kill
process lạ. Cổng 8082–8084 phải trống trước khi start.

Trong phiên dựng này ba server được chạy bằng process manager của runtime (PID
8201/8203/8205 đã ghi vào pidfile). Nếu runtime đóng, chạy lại `start-servers.sh`.

## Mật khẩu Glance

```bash
security find-generic-password -s banbe-glance -w
```

Không có mật khẩu trong repo, không trong `.env`, không trong log. `.env` chỉ có
secret-key, password-hash, token và ba URL.

## Thêm một khóa học mới

1. Thêm một dòng 6 cột vào `ops/notes/sites.tsv` (slug, vault, repo, title, serve_port,
   public_port). Không sửa script.
2. `bash ops/notes/make-configs.sh && bash ops/notes/build-all.sh`
3. `bash ops/notes/start-servers.sh`
4. `tailscale serve --bg --http=<port> http://127.0.0.1:<port>`
5. Thêm bookmark vào trang `Notes` trong `ops/glance/config/glance.yml` và một URL
   `QUARTZ_<SLUG>` vào `.env`, rồi `docker compose up -d`.

## Rotate token / mật khẩu

Token GitHub (Glance dùng để đọc repo + Actions):

```bash
cd /Users/thetrungdo/Downloads/banbe/ops/glance
TOKEN=$(gh auth token)            # không in ra
sed -i '' "s|^GITHUB_TOKEN=.*|GITHUB_TOKEN=$TOKEN|" .env
docker compose up -d --force-recreate
```

Mật khẩu Glance:

```bash
cd ops/glance
PW=$(openssl rand -base64 18)
HASH=$(docker run --rm glanceapp/glance password:hash "$PW")
security add-generic-password -a "$USER" -s banbe-glance -w "$PW" -U
# thay dòng GLANCE_PASSWORD_HASH trong .env bằng "$HASH" (không echo ra terminal)
docker compose up -d --force-recreate
```

`setup.sh` không ghi đè `.env` đã tồn tại; rotate phải làm tay như trên.

Secret-key Glance: `docker run --rm glanceapp/glance secret:make`, thay `GLANCE_SECRET`,
recreate container (mọi session cũ bị đăng xuất).

## Bị loại khỏi Quartz

`ignorePatterns` dùng chung: `raw/**`, `.obsidian/**`, `.trash/**`, `Templates/**`,
`node_modules/**`, `.git/**`, `**/__pycache__/**`. `publishAssets: "referenced"` nên chỉ
asset được note tham chiếu mới được copy.

- `Templates/**` bị loại vì frontmatter mẫu kiểu `<skill-name>` không phải YAML hợp lệ —
  build sẽ chết ở `Templates/sop.md`. Bản một repo cũng loại thư mục này.
- `raw/` của banbe chứa inbox/compiled và không bao giờ được publish.

## Cảnh báo private

Ba vault (đặc biệt `docs/second-brain`: Code map, audits, Decisions) là nội bộ.
Không deploy Vercel/Cloudflare/Pages, không tạo DNS, không `tailscale funnel`, không
đổi repo JLU sang private (đã PUBLIC theo quyết định của owner — không đụng visibility).
Hai thư mục `/Applications/JLU ...` là read-only: chỉ đọc, không commit/push/checkout.

## Ba phát hiện của Quartz v5.1.0

1. `quartz build --help` **không có `-C/--config`** → mỗi lần build phải `cp` config của
   site vào `quartz.config.yaml` trước (đúng như `build-all.sh` làm).
2. `quartz plugin install --help` **không có `-C`**; `--from-config` chỉ đọc
   `quartz.config.yaml` → chạy **một lần** sau khi đã đặt một config bất kỳ vào đó
   (ba config dùng chung plugin).
3. `--baseDir` có trong `build --help` nhưng chỉ là "base path to serve your local server
   on"; output tĩnh dùng URL tương đối (`./index-*.css`), không prefix. Vì vậy dùng
   **mỗi site một cổng**, không prefix.

Thêm hai điều học được trong lần dựng này:

4. Plugin `folder-page` chỉ sinh `index.html` cho thư mục con, **không** cho content root.
   Vault không có `index.md` sẽ không có `/index.html`. `build-all.sh` fallback: copy
   `home.html` (hoặc `readme.html`, `start-here.html`) thành `index.html`.
5. Tailnet chưa bật HTTPS cert thì `tailscale serve --https` treo, không báo lỗi. Dùng
   `--http` và kiểm bằng `curl` tới đúng host tailnet.

## Nâng Quartz (đổi tag có chủ đích, không merge branch)

```bash
cd ~/quartz-banbe
git fetch --tags
git checkout v5.2.0            # tag mới, số cụ thể
npm i
cp quartz.config.yaml quartz.config.base.yaml
npx quartz plugin install --from-config     # một lần, không có -C
```

Rồi chạy lại `make-configs.sh` + `build-all.sh`. Checkout phải sạch trước khi đổi tag;
có thay đổi chưa commit thì dừng (`blocked: quartz checkout dirty`), không reset.

## Rollback

```bash
cd /Users/thetrungdo/Downloads/banbe/ops/glance && docker compose down
tailscale serve --http=8080 off
tailscale serve --http=8082 off
tailscale serve --http=8083 off
tailscale serve --http=8084 off
for s in banbe jlu-spez jlu-vis; do
  kill "$(cat "$HOME/Library/Logs/banbe-notes-$s.pid")" 2>/dev/null || true
done
# giữ ~/quartz-banbe và ~/quartz-sites nếu muốn thử lại; xoá nếu bỏ hẳn
# revert commit ops/** + docs/ops/** nếu cần
```

Không dùng `tailscale serve reset` (xoá mapping khác của máy).

## Chưa làm / chưa kiểm

- Đăng nhập Glance thật: mới kiểm trang login (303 + form password), owner phải đăng nhập.
- Điện thoại qua Tailscale: chưa kiểm.
- Actions runs thật của hai repo JLU: widget đọc API GitHub, chưa xác nhận có run.
- Sống qua reboot: chưa làm. Docker Desktop → start at login; server tĩnh cần launchd
  plist hoặc chạy lại `start-servers.sh`.
