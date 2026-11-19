# 本地试用部署包（macOS / localhost）

这份包让你**在自己的 Mac 上**用浏览器跑一个完整的 1.12.1 realm（CMaNGOS + wenilla 客户端 + 管理面板），不需要 VM、域名或公网端口。它是正式部署到 Linux VM 之前的验证环境。

> 本包**不含任何游戏数据**。你提供自己的 1.12.1 客户端 `Data/`（版权原因，见 `LEGAL.md`）。

## 包里有什么

| 文件 | 内容 |
|---|---|
| `compose.yaml` | 六个容器：mariadb、db-init、realmd、mangosd、realm、caddy；只有 caddy 发布端口 |
| `realmctl` | 运维 CLI：`extract` / `up` / `status` / `logs` / `update` / `backup` |
| `docker/` | 镜像构建配方与服务端启动脚本（CI 已构建好，Mac 上不用自己 build） |
| `caddy/Caddyfile` | HTTPS 终止；`localhost` 走内部 CA |
| `.env` | **已生成**：`REALM_DOMAIN=localhost`、指向你本机确认过的 1.12.1 Data、三个随机 DB 密码、`EXTRACT_MMAPS=1`、`MANGOSD_MEM=3g`。mode 600，**不要提交** |
| `.env.local-trial.example` | 同上的模板（密码是占位符），供以后换机器参考 |
| `wenilla-launch` | **原生 arm64 二进制启动器**（80 KB）：检查 Docker/compose/Data → 首次 `extract` → `up` → 等 healthz → 显示 setup token → 打开页面 |
| `wenilla-launch.swift` | 启动器源码；`swiftc -O wenilla-launch.swift -o wenilla-launch` 重建 |
| `Wenilla Local Trial.app` | 双击包装：开 Terminal 跑上面的二进制。路径写死在本仓库，移动仓库需改 `.applescript` 重编 |

已确认的数据目录：`/Users/kubbo.ai/games/twmoa_1181_cn/twmoa_1181/Data`（`WoW.exe` = Build 5875，2006-09-19，即 1.12.1）。

## 开始之前：三个必须先解决的前提

1. **Docker 没启动**：当前 `docker` 指向 OrbStack 的 socket，但 daemon 没起来（`docker version` 连不上）。先启动 OrbStack（或 Docker Desktop）。
2. **缺 compose 插件**：`docker compose version` 当前失败。启动 Docker 后确认它输出版本号；没有就装 Compose v2 插件。
3. **架构不匹配**：你的 Mac 是 `arm64`，而 `ghcr.io/arnesen/wenilla-realm{,-mangos}` 镜像由 CI 在 `ubuntu-latest`（amd64）构建，没有多架构清单。Docker 会在模拟模式下运行，**明显变慢**。尤其是第 3 步的 mmaps 生成，amd64 模拟下可能要一夜甚至更久。

另外：`mmaps` 是**硬性必需**（`SETUP.md` §4）——没有 movement maps，`mangosd` 不会启动。所以第 3 步不能跳过。

## 步骤

### 方式 A：一键启动器（推荐）

双击 `Wenilla Local Trial.app`（或在终端里跑 `./wenilla-launch`）。它会：检查 Docker 并尝试拉起 → 检查 compose 插件和 `.env` 的 `CLIENT_DATA` → 首次自动跑 `./realmctl extract`（用 `.local-trial-extracted` 标记避免重复）→ `./realmctl up` → 轮询 `healthz` 最多 15 分钟 → 打印 setup token → `open https://localhost/`。

刚才实测：Docker 没起时它会尝试拉起 OrbStack/Docker，失败后给出明确提示并退出——所以你仍需先把 OrbStack/Docker Desktop 装上并启动（本机目前 `docker` 指向 OrbStack socket，但 daemon 没响应，且没找到 OrbStack/Docker 的 .app）。

> 注意：`extract` 在 arm64 模拟下可能要一夜。启动器会把实时输出留在 Terminal 里，别关窗口。

### 方式 B：手动敲命令

```bash
cd /Users/kubbo.ai/github/wenilla-realm

# 0. 确认 Docker 可用（先启动 OrbStack / Docker Desktop）
docker version --format '{{.Server.Os}}/{{.Server.Arch}}'   # 应输出 linux/amd64 或 linux/arm64
docker compose version                                      # 必须输出版本号

# 1. 生成服务端地图数据（一次性；mmaps 在模拟下非常慢，可以挂着过夜）
./realmctl extract

#    如果你已经有另一台机器生成的 dbc/ maps/ vmaps/ mmaps/，跳过 extract，改：
#    ./realmctl import-datapack /path/to/pack

# 2. 启动整栈（拉取预构建镜像，不需要本地 build）
./realmctl up
#    屏幕会打印一次性 SETUP TOKEN；也随时可以：
#    docker compose exec realm cat /state/setup-token

# 3. 等服务就绪（首次加载世界 2–5 分钟）
./realmctl status
./realmctl logs mangosd        # 看到世界加载完成

# 4. 首次配置：浏览器打开 https://localhost/
#    - 自签证书告警 → 高级 / 继续（仅 localhost 如此）
#    - 粘贴 SETUP TOKEN
#    - 起你的 realm 名字、创建管理员账号
#    向导最后一步会连世界服务器，所以务必等 mangosd healthy 再做

# 5. 邀请玩家：管理面板 → Users → Invite a friend
#    把 https://localhost/ 发给对方；每个玩家用自己的 WebGPU 浏览器打开。
#    注册是关闭的，账号全部由你创建。
```

玩家端要求：WebGPU 浏览器（Chrome/Edge；Linux Chrome 需要 `chrome://flags/#enable-unsafe-webgpu`）。手机不支持。

## 已知问题 / 预期现象

- **`_G` 报错仍在**：当前 `upstreams.env` 的 `WENILLA_COMMIT=ba8ab06d`，不包含我们刚做的 glue 兼容修复。所以 realm 列表的 `OnLoad` 仍可能报 `attempt to index global '_G' (a nil value)`（行标签可能错位，但列表一般仍可用）。等你把修复合并进 wenilla `main`、pin bot 更新、CI 出新镜像（约 25 分钟）后，在 Mac 上执行：
  ```bash
  ./realmctl update realm      # 只换客户端/服务，不动世界服务器
  ```
  重新加载页面即可。
- **私服客户端的自定义 UI**：这份 Data 来自 `apac.capycraft.io`，带 `patch-Z.MPQ` 等自定义补丁和 `Interface/` 目录，可能带来别的 Lua 报错。这是数据本身，不是 wenilla 的问题。
- **localhost 自签证书**：浏览器告警一次属正常；公网部署必须用真实域名（Caddy 申请 Let's Encrypt）。
- **首次加载慢**：~20 MB 压缩 wasm + 按需拉取游戏资源；arm64 模拟下更慢。

## 常用命令

```bash
./realmctl status              # 健康状态、重启次数
./realmctl logs realm          # 客户端/服务日志
./realmctl logs mangosd        # 世界服务器日志
./realmctl version             # 运行中镜像 revision vs upstreams.env pin
./realmctl update realm        # 只更新客户端/服务（改客户端后用这个）
./realmctl backup              # 数据库 + 服务状态 → backups/
```

## 上正式环境时

不要在 Mac 上长期跑这个。正式给朋友用：找一台 x86-64 Linux VM（2 vCPU/4 GB 起，4 vCPU/8 GB 舒适）、域名 A 记录指向它、80/443 开放，把 `Data/` rsync 上去，然后在新 checkout 里 `./realmctl init --domain <你的域名> --client-data /srv/client/Data --mmaps 1 --yes`，再 `extract` + `up` + `/setup`。完整流程见 `README.md` 和 `docs/SETUP.md`。

## 法律

非商业、私密、仅供你和受邀的朋友。不含也不分发暴雪的游戏数据。见 `docs/LEGAL.md`。
