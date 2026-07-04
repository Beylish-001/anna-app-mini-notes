# Mini Notes — Anna App

本地运行的 **Mini Notes with LLM Summary** 实现，符合 Anna App 平台模型：

```text
Anna App iframe
  -> AnnaAppRuntime.connect()
  -> anna.storage.* 保存 / 读取 notes
  -> anna.tools.invoke(...)
  -> 本地 Executa Tool invoke
  -> reverse JSON-RPC sampling/createMessage
  -> host LLM 或 mock sampling fixture
  -> summary 返回 UI
```

## 项目结构

```text
anna-app-mini-notes/
├── manifest.json              # Anna App manifest (schema 2)
├── package.json               # 前端构建 + anna-app CLI scripts
├── index.html                 # Vite 入口
├── src/                       # 前端源码
│   ├── main.js                # UI + Anna runtime 连接
│   ├── notes.js               # anna.storage.get/set 封装
│   ├── constants.js           # tool_id / storage key
│   └── styles.css
├── bundle/                    # npm run build 产物（manifest ui.bundle.entry 指向 index.html）
├── executas/notes-summarizer/ # Executa Tool (JSON-RPC over stdio + sampling)
│   ├── executa.json
│   ├── notes_summarizer.py
│   ├── pyproject.toml
│   ├── build_binary.ps1       # Windows 本机打包
│   └── build_binary.sh        # macOS / Linux 本机打包
├── fixtures/sampling-mock.jsonl   # --mock-sampling 使用的 fixture
├── scripts/test-rpc.ps1       # 手动 RPC 测试（Windows）
├── scripts/test-rpc.sh        # 手动 RPC 测试（Unix）
├── sdk/python/executa_sdk/    # vendored Executa SDK (sampling client)
└── .github/workflows/release.yml  # 三平台 GitHub Release 构建
```

## 前置依赖

- **Node.js 18+** 与 npm
- **Python 3.10+**
- **uv**（`pip install uv` 或 https://docs.astral.sh/uv/）
- **PyInstaller**（打包二进制时：`pip install pyinstaller`）

可选：`anna-app doctor` 检查环境。

## 安装依赖

```bash
cd anna-app-mini-notes
npm install
cd executas/notes-summarizer
uv sync
```

## 构建前端 bundle

```bash
npm run build
```

产物输出到 `bundle/`，`manifest.json` 的 `ui.bundle.entry` 为 `index.html`。

## 校验 manifest

```bash
npm run validate
# 等价于 anna-app validate --strict
```

## UI harness 本地调试（--no-llm）

```bash
npm run dev:no-llm
# 等价于 anna-app dev --no-llm
# 浏览器打开 http://localhost:5180
```

在 harness 中可：

1. 创建 / 删除笔记 — 数据通过 `anna.storage.get` / `anna.storage.set` 持久化（legacy in-memory runtime_state）
2. 点击 **Summarize** — 前端调用 `anna.tools.invoke` 路由到本地 Executa

### 为什么在 --no-llm 下 Summarize 会报错？

`--no-llm` 模式下 harness **禁用了 LLM / sampling**。Summarize 仍会正常发起 `anna.tools.invoke(...)`，但 Executa 内部的 `sampling/createMessage` 会被 host 拒绝，预期错误类似：

```text
[-32603] harness started with --no-llm
```

这是 **App 调试路径的预期行为**，不代表 Executa Tool 本身实现错误。后端 sampling 需单独用 `--mock-sampling` 验证（见下文）。

### 如何确认 notes 走 anna.storage.*

- 在 harness 右侧 **RPC log** 面板查看 `storage.get` / `storage.set` 调用
- 源码：`src/notes.js` 中所有读写均调用 `anna.storage.get({ key })` 与 `anna.storage.set({ key, value })`
- storage key：`mini-notes:list`

## 单独测试 Executa sampling（--mock-sampling）

```bash
npm run executa:invoke
```

或交互式：

```bash
anna-app executa dev \
  --dir executas/notes-summarizer \
  --mock-sampling fixtures/sampling-mock.jsonl
```

成功时 stdout 返回 `data.summary` 为 fixture 中的 mock 文本。

### 如何确认 sampling/createMessage 被发起

1. **mock 路径**：若 invoke 返回 fixture 中的 summary（而非 `(mock) no fixture matched`），说明 Tool 已发起 reverse RPC 且 harness 已响应
2. **fixture 格式**：每行 `{"ns":"sampling","method":"createMessage","result":{...}}`
3. **源码**：`executas/notes-summarizer/notes_summarizer.py` 中 `_summarize_notes` 调用 `sampling.create_message(...)`，`metadata` 携带 `invoke_id`
4. **stderr**：插件启动时会打印 `notes-summarizer plugin started`；negotiate v2 后才会启用 sampling

## 手动测试 Executa JSON-RPC

```bash
# describe
npm run executa:describe

# Windows 一键脚本
powershell -ExecutionPolicy Bypass -File scripts/test-rpc.ps1

# 或直接 pipe（Unix 示例）
cd executas/notes-summarizer
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2.0"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"describe"}' \
  '{"jsonrpc":"2.0","id":3,"method":"invoke","params":{"tool":"summarize_notes","arguments":{"notes":[{"order":1,"content":"test"}]},"invoke_id":"dev-1"}}' \
  | uv run tool-test-notes-summarizer-12345678
```

覆盖的方法：`initialize`、`describe`、`invoke`（以及 `health` / `shutdown`）。

## 本机二进制打包

Windows：

```powershell
cd executas/notes-summarizer
.\build_binary.ps1 -Package
# 可选 -Test 做 describe smoke test
```

macOS / Linux：

```bash
cd executas/notes-summarizer
chmod +x build_binary.sh
./build_binary.sh --package
# 可选 --test
```

产物：

- `dist/packages/tool-test-notes-summarizer-12345678-<platform>.tar.gz`（macOS）
- `dist/packages/tool-test-notes-summarizer-12345678-windows-x86_64.zip`（Windows）

archive 根目录包含可执行文件 + `manifest.json`（符合 [Executa binary distribution](https://staging.anna.partners/developers/tools/executa-binary) 要求）。

## GitHub Actions Release

Workflow：`.github/workflows/release.yml`

**触发方式：**

- 创建 GitHub Release（`release: created`）
- 手动 `workflow_dispatch`

**预期 Release assets（一次发布三平台）：**

- `tool-test-notes-summarizer-12345678-darwin-arm64.tar.gz`
- `tool-test-notes-summarizer-12345678-darwin-x86_64.tar.gz`
- `tool-test-notes-summarizer-12345678-windows-x86_64.zip`

每个 archive 内含二进制 + `manifest.json`。Workflow 含 `describe` smoke test。

## 概念关系（简要）

| 概念 | 在本项目中的角色 |
|------|------------------|
| **manifest.json** | 声明 App 权限、`required_executas`、UI bundle 入口、`host_api` ACL |
| **bundle/** | 静态 SPA，在 Anna iframe 中运行，通过 SDK 调用 host API |
| **Executa Tool** | `notes-summarizer` 插件，stdio JSON-RPC，提供 `summarize_notes` |
| **Anna storage / APS KV** | 笔记通过 `anna.storage.*` 读写；本地 dev 使用 legacy in-memory state |
| **sampling** | Executa 通过 reverse `sampling/createMessage` 借用 host LLM；本地用 fixture mock |
| **binary archive** | PyInstaller 单文件 + manifest，供 Agent 按平台安装 |

## Tool ID 一致性

以下位置必须使用相同的 `tool-test-notes-summarizer-12345678`：

- `executas/notes-summarizer/executa.json` → `tool_id`
- `manifest.json` → `required_executas` / `host_api.tools`（dev 下为 `bundled:notes-summarizer`）
- `src/constants.js` → `TOOL_ID`
- Executa `describe` manifest → `name`
- 二进制 / archive 文件名

## License

MIT
