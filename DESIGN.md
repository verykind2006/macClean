# macClean 设计文档

> 版本：v1.1（2026-11-16）　状态：规则随安装包发布；保留清单改为用户数据
> 形式：原生 Mac App（SwiftUI）　删除方式：分情况（能重新生成的直接删，用户文件进废纸篓）

## 1. 目标

把 2026-11-16 那次手工清理（30G → 120G）的经验做成一个工具，两台机器（Mac mini、MacBook）都能用。

**原则**
1. **先分析、后删除**：扫描只读，不改任何东西；每一项删除都要用户勾选并二次确认。
2. **效果以 `df` 为准**：列表里的大小只是「估计」，因为 APFS 克隆会让统计数字虚高；删完后显示 `df` 的前后对比。
3. **OneDrive 目录绝不 rm**：`~/Library/CloudStorage/OneDrive-个人/` 下的路径在代码里写死拒绝，不靠规则文件。
4. **看得清**：强制浅色模式，正文 17–18pt，状态用「符号 + 文字」表示，不只靠颜色区分。

## 2. 使用流程

```
打开 App
  → 顶部显示磁盘：总量 / 已用 / 可用（来自 statfs，和 df 一致）
  → 点「扫描」：按规则逐项统计大小，并运行几项异常检测
  → 列表分三组显示：
       ✅ 可以删　　默认不勾选，用户自己勾
       ❓ 要核对　　显示核对结果（如「成片已在 OneDrive，逐字节一致」）
       ⛔ 不能动　　只展示占用，不提供删除按钮
  → 勾选后点「删除选中的 N 项（估计 X G）」
  → 确认页：逐条列出路径、删除方式（直接删 / 进废纸篓 / 运行命令）、删前检查结果
  → 执行 → 结果页：每项成功/失败 + df 前后对比（实际释放 X G）
  → 本次记录写入运行日志
```

## 3. 规则文件（核心）

规则不写死在代码里，而是放在 `rules.json` 中。它是**默认规则，随安装包发布**：源码在本项目里，`build-app.sh` 打包时放进 App，App 只从包里读。改规则要重新打包。
以后发现新的可清理项目，只需改规则，不用改代码。

```jsonc
{
  "id": "onedrive-logs",
  "name": "OneDrive 日志",
  "level": "safe",                 // safe | ask | never
  "paths": ["~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Logs/Personal/*.{odl,odlgz,odlsent,aodl}"],
  "action": "delete",              // delete | trash | command | finder（需要管理员权限时让用户在 Finder 里操作）
  "olderThanDays": null,           // 只处理多少天以前的（Codex sessions 用 7）
  "keepNewest": null,
  "preconditions": ["onedrive-paused"],
  "note": "先暂停同步；keystore 和设置文件保留",
  "regenerates": true              // 删了能自动重新生成
}
```

- `action: "command"` 用于 `uv cache clean`、`npm cache clean --force`、`brew cleanup -s` 这类由工具自己清理的情况。
- 初始规则直接从记忆里的「可删 / 要问 / 不能动」分类转写过来。
- **用户的保留清单**是用户数据，不进安装包，也不进仓库：`~/Library/Application Support/macClean/decisions.json`。一开始是空的，用户在界面上点「保留」（可填理由）逐条记录，可以保留单项或整条规则，随时「取消保留」。已保留的不能勾选，以后扫描也不再提醒。

## 4. 删除前检查（preconditions）

| 检查项 | 怎么判断 | 不通过时 |
|---|---|---|
| 应用是否在运行 | `NSWorkspace.runningApplications` 按 bundle id 查找 | 提示「请先退出 XX」，该项不可勾选 |
| Codex 后台服务 | 查找 `codex app-server` 进程 | 提示用户在终端运行 `pkill -f "codex app-server"` |
| 数据库正在使用 | 存在 `-wal` 文件且有进程打开它 | 跳过 |
| OneDrive 是否暂停同步 | 检测 OneDrive 进程和同步状态 | 提示先暂停 |
| 路径在 OneDrive 目录下 | 解析真实路径后做前缀比较 | **硬性拒绝**，代码写死 |
| 路径在 ⛔ 名单里 | `.git`、`~/.claude`、`~/.ssh`、照片图库等 | **硬性拒绝**，代码写死 |
| 需要管理员权限 | 对上级目录没有写权限 | 改为「在 Finder 中显示」，让用户自己拖进废纸篓 |

## 5. 异常检测（扫描时顺带运行）

1. **OneDrive 日志风暴**：统计 `Logs/Personal/*.odl` 最近 10 分钟新增了多少个（正常约 3 个/分钟），并读取 `SyncDiagnostics.log` 中的 `FilesToUpload`。
2. **OneDrive 里的零碎文件**：项目目录下的 `.build`、`node_modules`、`.venv`，以及 git 松散对象数量过多的仓库。
3. **git 空对象**：只检测并提示，不自动修复（修复步骤见记忆里的「踩过的坑」第 3 条）。
4. **APFS 克隆虚高**：已知的克隆密集目录（Chrome 签名副本、uv 缓存）在列表上标注「实际释放可能远小于此数」。

### 体检的实现（M3）

| 检测 | 判断依据 | 严重 / 注意 |
|---|---|---|
| OneDrive 日志风暴 | 最近 10 分钟新建的 `.odl` 数量；`SyncDiagnostics.log` 的 `FilesToUpload`；日志总大小 | 每分钟 >10 个或待上传 >1 万 / 每分钟 >5 个、待上传 >1000 或日志 >3G |
| 最近变动最多的目录 | 遍历整个 OneDrive，按二级目录统计最近 6 小时修改过的文件数 | 单个目录 >1 万 / >2000 |
| 项目里的零碎文件 | `projects/*` 下的 `.build`、`node_modules`、`.venv` 等的文件数；`.git/objects` 的松散对象和空对象 | 空对象、>5000 个文件、>1 万个松散对象 / 其余超过阈值的 |
| 和上次扫描相比 | 上次扫描时的可用空间和 OneDrive 内部数据库大小（存在 UserDefaults） | — / 数据库涨 >5G 或可用空间少 >10G |

体检只读；给出的 git 命令只复制到剪贴板，由用户自己在终端运行。

### M4 的实现

- **Codex 数据库整理**（动作 `codex-trim`）：以对话为单位，最后活动早于 7 天的整段删除（`thread_items`、`thread_turns`、`thread_realtime_items`、`thread_history_projection_state` 四张表），然后 `wal_checkpoint(TRUNCATE)` → `VACUUM` → `integrity_check`，结果不是 `ok` 就报失败。删前检查：Codex 后台服务必须已退出；剩余空间要大于「数据库大小 + 2G」（VACUUM 需要临时空间）；没有旧对话就不执行。卡片上显示的大小是「旧对话的内容字节数」，不是数据库文件的大小。只读估算在缺 `-shm` 时退回 `immutable=1`。
- **核对成片**（规则字段 `verify: "onedrive-copy"`）：列出工程里 5MB 以上的视频，在 OneDrive 里找大小相同的文件，逐字节比较。OneDrive 那份如果是 dataless（只在云端），不下载，只报「大小一致」。只读，结果不影响勾选，由用户判断。
- **OneDrive 本机占用明细**（体检里的「参考」卡片）：按二级目录统计本机占用（已分配大小）、逻辑大小和 dataless 文件数，用来确认「释放空间」是否生效。

## 6. 技术方案

- **Swift Package + 打包脚本**，不建 Xcode 工程。
- ⚠️ **编译产物绝不放在 OneDrive 里**：`swift build --scratch-path ~/Library/Developer/macClean-build`，打包好的 `.app` 放到 `~/Applications/macClean.app`。项目目录里只放源码、规则和文档。
- **不开沙盒**（要访问 `~/Library` 各处），需要用户在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里授权一次。
- 大小统计：`URLResourceValues.totalFileAllocatedSize`，后台并发遍历，界面上实时显示进度。
- 磁盘可用空间：`statfs("/")`，与 `df` 一致。
- 删除：直接删用 `FileManager.removeItem`；进废纸篓用 `FileManager.trashItem`。
- 运行日志：每次一份，写到 `~/Library/Logs/macClean/`；同时向 `~/Library/Application Support/macClean/HISTORY.md` 追加一行摘要（日期、机器、释放了多少）。App 不依赖 OneDrive 项目目录。

**目录结构**

```
macClean/                 （OneDrive 里，只放少量文本文件）
├── CLAUDE.md
├── DESIGN.md
├── Package.swift
├── rules.json
├── scripts/build-app.sh  （编译 → 组装 .app → 签名 → 复制到 ~/Applications）
└── Sources/macClean/
    ├── App.swift          界面入口，强制浅色模式
    ├── Rules.swift        读取规则和决定
    ├── Scanner.swift      遍历并统计大小
    ├── Guards.swift       硬性拒绝名单 + 删前检查
    ├── Detectors.swift    异常检测
    ├── Executor.swift     执行删除 / 命令，df 前后对比
    └── Views/             列表、确认页、结果页
```

## 7. 分期

| 阶段 | 内容 | 能用来做什么 |
|---|---|---|
| **M1 只读报告** ✅ | 骨架、规则文件、扫描、三组列表、df 显示 | 看哪里占空间，不会误删任何东西 |
| **M2 安全删除** ✅ | 勾选、确认页、删前检查、硬性拒绝、直接删/进废纸篓、df 对比、日志 | 清理缓存、日志、编译产物 |
| **M3 命令与检测** ✅ | `command` 类动作、按天数过滤（Codex sessions）、日志风暴和 git 检测 | 上次清理的大部分项目都能在 App 里完成 |
| **M4 高级项** ✅ | Codex sqlite 删除旧记录后 VACUUM；`~/Movies` 视频工程与 OneDrive 成片逐字节核对；OneDrive 文件是否已「释放空间」（dataless 标记） | 处理需要核对的 ❓ 项 |

## 8. 调试与自检

- `macClean --selftest`：在 `~/Library/Caches/macClean-selftest` 建临时文件，验证直接删除、移到废纸篓，以及 12 条硬性拒绝（OneDrive、.ssh、.claude、范围过大、`..`、范围外路径等）。
- `macClean --snapshot <out.png>`：扫描后把主页、操作栏、确认页、结果页渲染成 PNG（执行用演练模式，不会真删）。
- git 数据放在 OneDrive 外：`~/Library/Developer/macClean-git`（`--separate-git-dir`），项目里的 `.git` 只是一个指针文件。在 MacBook 上要用 git，请另外 clone。

## 9. 待定问题

1. ~~签名~~：已定，用钥匙串里现有的自签名证书「vInput Dev」，重新编译后完全磁盘访问权限不会失效（`MACCLEAN_SIGN_ID` 可改）。
1. **语言服务**：`.sourcekit-lsp/config.json` 把 sourcekit-lsp 的编译目录也指到 OneDrive 外面，并关掉后台索引。
2. **App 名称**：macClean。
2. **图标**（2026-11-16 定 A 版）：codex 生成方形图稿（提示词见 `assets/AppIcon-prompt.txt`），由 `scripts/make-icon.swift` 按 macOS 图标网格裁成圆角方形、加投影，导出 `assets/AppIcon.icns`；`build-app.sh` 打包时自动带上。
3. **MacBook**：目录结构基本相同，但第一次在 MacBook 上运行时，需要核对规则里的路径是否都存在。

### 零碎文件一键整理（2026-11-18）

「零碎文件」卡片上的「一键整理…」：列出目标 → 用户勾选确认 → 退出 OneDrive（停止同步）→ 逐项处理 → 重新打开 OneDrive → 显示前后对比，并写入 `~/Library/Logs/macClean/*_整理零碎文件.log`。

| 目标 | 做法 | 拦下的情况 |
|---|---|---|
| git 松散对象 ≥1000 的仓库 | `git gc --quiet`，默认勾选 | 有 `index.lock`；有空对象；`.git` 里有文件只在云端（dataless，OneDrive 退出时读不到） |
| `node_modules` / `.venv` / `venv` / `.build` / `.xcbuild` | 移到废纸篓，默认不勾，须勾「我知道云端和 MacBook 上会一起删除」 | 不是 `projects/<项目>/<目录>` 这一层；是链接；没有标记（package.json / pyvenv.cfg / Package.swift / .xcbuild 里的 info.plist + Build） |

**这是「OneDrive 目录不能删」的唯一例外**（用户 2026-11-18 决定），只走废纸篓、不用 rm，检查写在 `ClutterFix.trashBlock`；`Guards.deletionBlock` 本身没放宽，常规删除仍然拒绝 OneDrive 里的一切。自检覆盖以上各条。
