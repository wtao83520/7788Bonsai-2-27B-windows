# Ternary-Bonsai-2-27B-PQ2_0 本地部署

在本机（Windows）运行 [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) 的 **PQ2_0**（2-bit，7.21 GB）版本，对外提供 **OpenAI 兼容 API**，支持**图片 / 视频输入**与**思考深度控制**。

## 快速开始

仓库**不包含**模型权重（7.7 GB）与 fork 二进制（658 MB），需要先各自下载。

```powershell
# 0) 克隆仓库
git clone https://github.com/wtao83520/7788Bonsai-2-27B-windows.git
cd 7788Bonsai-2-27B-windows

# 1) 下载 PrismML fork 运行时（必须用它，原版 llama.cpp 无法加载 PQ2_0）
#    见 bin/README.md —— 从 PrismML-Eng/llama.cpp Releases 取 win-cuda-13.x 包
#    解压后所有 exe/dll 平铺到 bin/

# 2) 下载模型权重
pip install -U "huggingface_hub[cli]"
hf download prism-ml/Ternary-Bonsai-2-27B-gguf `
    Ternary-Bonsai-2-27B-PQ2_0.gguf --local-dir models
hf download prism-ml/Ternary-Bonsai-2-27B-gguf `
    Ternary-Bonsai-2-27B-mmproj-BF16.gguf --local-dir models   # 可选，图片/视频需要

# 3) 启动（会自动等待模型加载完成并做自检）
.\start-server.cmd
# 或一键重启（停止 → 等显存释放 → 启动 → 自检）
.\restart-server.cmd
```

> 从别处拷来的目录可跳过第 0 步。仓库只含脚本与文档（约 120 KB）。

启动后即可用 OpenAI SDK 调用：

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:2345/v1", api_key="not-needed")
resp = client.chat.completions.create(
    model="ternary-bonsai-2-27b",
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.choices[0].message.content)
```

> **视频/图片请求务必带 `"cache_prompt": false`**，否则不同视频会复用同一段 KV 缓存、
> 返回完全错误的答案。详见下文「多模态输入」章节。
>
> 首次运行若提示脚本被禁用，先执行
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。

**环境要求**：Windows + NVIDIA GPU（本机在 RTX 4090 24 GB 上实测）、
NVIDIA 驱动支持 CUDA 13.x、可选 ffmpeg（用视频输入时）。
显存建议 ≥16 GB；12 GB 需把 `ContextSize` 调小。

## 硬件评估结论：可以部署 ✅

| 项目 | 本机配置 | 需求/说明 |
|---|---|---|
| GPU | NVIDIA RTX 4090 (24 GB) | PQ2_0 权重 7.21 GB，可全部 offload（`-ngl 99`），显存充裕 |
| CPU | Intel i9-14900K (8P+16E, 32 线程) | 满足要求；CPU-only 也可跑但慢很多 |
| RAM | 127.8 GB | 远超需求（模型仅 ~7.2 GB） |
| CUDA | nvcc release 13.0 (V13.0.48) | 使用 fork 的 `win-cuda-13.3` 预编译包（自带 cudart，无需系统 CUDA） |

**本机实测 decode ≈ 81.9 tok/s** — 与官方 RTX 4090 基准（81.2 tok/s）完全吻合。

## 目录结构

带 🚫 的目录**不纳入版本控制**（体积过大），需按 📥 说明自行下载：

```
bonsai/
├── bin/                          # 🚫 PrismML-Eng/llama.cpp fork (prism-b10685, CUDA 13.3)
│   ├── llama-cli.exe             # 命令行推理（必须用此 fork，原版 llama.cpp 无法加载 PQ2_0）
│   ├── llama-server.exe          # OpenAI 兼容 API 服务
│   ├── *.dll                     # cudart / cublas 等运行时库
│   └── README.md                 # 📥 下载与安装说明
├── models/                       # 🚫
│   ├── Ternary-Bonsai-2-27B-PQ2_0.gguf        # 模型权重 (7.21 GB)
│   ├── Ternary-Bonsai-2-27B-mmproj-BF16.gguf  # 视觉塔（可选，图片/视频输入用）
│   └── README.md                 # 📥 下载说明 + 模型信息
├── logs/                         # 🚫 服务日志与状态（自动生成）
├── images/                       # media-path 目录（file:// 引用的本地图片/视频放这里）
├── .gitignore / .gitattributes   # 排除大文件；锁定 UTF-8 BOM 不被转换
├── LICENSE                       # MIT
├── server-config.psd1            # ★ 服务配置文件（所有参数在此调整）
├── start-server.ps1 / .cmd       # 一键启动 API 服务
├── restart-server.ps1 / .cmd     # 一键重启（停止 → 等显存释放 → 启动 → 自检）
├── stop-server.ps1  / .cmd       # 一键停止 API 服务
├── allow-firewall.ps1 / .cmd     # 放行防火墙（局域网访问用，需管理员）
├── common.ps1                    # 共享工具（局域网地址探测）
├── run-chat.ps1                  # 命令行交互对话
├── api-examples.py               # Python 调用示例（含图片/视频/思考控制）
└── README.md
```

---

## 一、API 服务（推荐）

### 一键启动 / 停止 / 重启

```powershell
.\start-server.cmd        # 双击或运行即可启动（含加载等待与就绪提示）
.\restart-server.cmd      # 一键重启（停止 → 等显存释放 → 启动 → 自检）
.\stop-server.cmd         # 停止并释放显存
```

也可用 PowerShell 直接调用，支持参数覆盖：

```powershell
.\start-server.ps1                 # 按配置启动
.\start-server.ps1 -Status         # 查看运行状态（PID / 地址 / 已运行时长）
.\start-server.ps1 -Force          # 已在运行时重启
.\start-server.ps1 -Port 9000 -Context 65536
.\start-server.ps1 -SamplingPreset instruct   # 临时切到 instruct 模式
.\start-server.ps1 -Foreground     # 前台运行，Ctrl+C 退出（调试用）
```

#### `restart-server.ps1` — 一键重启

按「**停止 → 等待显存释放 → 启动 → 自检**」四步执行，全程无需手动干预。
停止与启动都复用 `stop-server.ps1` / `start-server.ps1`，保证行为与配置完全一致。

```powershell
.\restart-server.ps1                    # 标准重启（带自检）
.\restart-server.ps1 -Quiet              # 静默模式，只输出关键结果（适合计划任务）
.\restart-server.ps1 -NoVerify           # 跳过自检，更快
.\restart-server.ps1 -Port 9000          # 换端口重启
.\restart-server.ps1 -Context 196608     # 换上下文重启
.\restart-server.ps1 -SamplingPreset instruct
.\restart-server.ps1 -Force              # 强杀旧进程，不做优雅等待
.\restart-server.ps1 -ConfigFile .\my.psd1
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Port` / `-Context` / `-SamplingPreset` | 取配置 | 临时覆盖，不写入配置文件 |
| `-StopTimeout` | `5` | 优雅停止的等待秒数，超时后强杀 |
| `-VramTimeout` | `30` | 等待显存释放的上限秒数 |
| `-Quiet` | — | 静默模式，只输出关键结果 |
| `-NoVerify` | — | 跳过启动后自检 |
| `-Force` | — | 立即强杀旧进程 |
| `-ConfigFile` | `server-config.psd1` | 指定其他配置文件 |

**它比手动执行的区别：**

1. **等待显存真正释放**（实测 23755 → 1 MiB，约 0.1 s）
   不等就启动，旧模型的权重可能尚未卸载完，新进程会和残留显存抢空间，
   在 24 GB 卡上直接表现为 `CUDA out of memory` 或触发 WDDM 分页掉速。
2. **清理游离进程**：除了状态文件记录的 PID，还会扫描所有 `llama-server` 进程，
   处理「手动启动过 / 换端口启动过 / 状态文件丢失」导致的端口占用。
3. **启动后自动自检**：`/health`、`/props`（含 `modalities`）、`/v1/models`（含 `capabilities`）
   三项逐一验证，失败时直接回显日志尾部，不用再去翻日志文件。

典型输出（`-Quiet`）：

```
  一键重启 Ternary-Bonsai-2-27B API 服务
  ✓ 自检全部通过
  重启完成 ✓   PID 73136   总耗时 10.8s

  本机访问 : http://127.0.0.1:2345/v1
  局域网   : http://192.168.1.100:2345/v1
  媒体请求 : 务必带 "cache_prompt": false，否则不同视频会复用同一 KV 缓存
```

> 首次运行若提示脚本被禁用，先执行：
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

### 配置文件 `server-config.psd1`

所有参数集中在此，修改后 `.\start-server.ps1 -Force` 生效：

| 分组 | 关键项 | 默认值 | 说明 |
|---|---|---|---|
| **Model** | `Path` | `models\Ternary-Bonsai-2-27B-PQ2_0.gguf` | 模型位置 |
| | `Alias` | `ternary-bonsai-2-27b` | `/v1/models` 中的模型名 |
| | `ContextSize` | `131072` | **总**上下文（最大 262144）；单路长度 = 此值 ÷ `Parallel` |
| | `GpuLayers` | `99` | GPU 层数，99=全部，0=纯 CPU |
| | `FlashAttention` | `on` | on / off / auto |
| | `Parallel` | `4` | 并发槽位数：1=单人最大上下文，4=4 人同时用（推荐），8=更多但更慢 |
| | `BatchSize`/`UbatchSize` | `2048`/`512` | 显存紧张时调小 ubatch |
| | `CacheTypeK`/`CacheTypeV` | `f16` | 改 `q8_0` 可省约一半 KV 显存 |
| | `UseMmap` | `$true` | `$false` = 全量读入内存 |
| **Vision** | `Enabled` | `$true` | 是否支持图片/视频输入 |
| | `MmprojPath` | `models\...mmproj-BF16.gguf` | 视觉投影层文件 |
| | `Offload` | `$true` | 视觉塔是否放显存 |
| | `MediaPath` | `images` | 允许 `file://` 引用的本地文件目录（图片与视频通用） |
| | `VideoFps` | `4.0` | 抽帧帧率 ⚠ 本分支不支持该参数，按内置默认 4 fps |
| | `VideoTimestampInterval` | `5000` | 时间戳间隔 ms ⚠ 同上，按内置默认 5000 |
| | `VideoFfmpegDir` | `""` | ffmpeg 目录 ⚠ 同上，改为从 PATH 查找 |
| | `SpecType` | `ngram-map-k` | 推测解码类型（`none` 可关闭，详见下文） |
| **Server** | `Host`/`Port` | `0.0.0.0`/`2345` | `127.0.0.1`=仅本机，`0.0.0.0`=允许局域网 |
| | `ApiKey` | `""` | 留空=免鉴权；★局域网下建议填写 |
| | `AllowedOrigins` | `*` | CORS 允许来源，可收窄为指定 IP |
| | `WebUI` | `$true` | 内置网页界面 |
| | `Metrics` | `$true` | `/metrics` 监控端点 |
| | `TimeoutSeconds` | `3600` | 读写超时 |
| **Sampling** | `Preset` | `thinking` | `thinking`/`instruct`/`custom` |
| | 各数值 | temp=1.0, top_p=0.95, top_k=20 | 仅 `custom` 时生效 |
| **Reasoning** | `Effort` | `default` | = 模型自带 xhigh；仅支持 `low`/`medium`/`xhigh` |
| | `Format` | `deepseek` | 思考内容放入 `reasoning_content` |
| | `Budget` | `-1` | 思考 token 上限：-1 不限，0 不思考 |

### 并发能力（实测数据）

**核心结论：`ContextSize` 是显存占用的唯一决定因素，`Parallel` 只决定怎么切分它。**

KV 显存 ∝ 总上下文，与并发路数无关 —— 实测 `4 路 × 65536` 与 `1 路 × 262144` 占用几乎相同
（24127 MiB vs 24135 MiB）。所以 4 路每路能分到多少上下文，等价于总量能开多大，
且瓶颈**永远是显存容量**，不是并发数。

本模型为**混合注意力**架构（64 层中仅 16 层是完整注意力层，`full_attention_interval=4`，
其余是 SSM 线性层），故 KV cache 只按 16 层增长，约 **64 KiB / token**（f16）。

#### 实测一：KV 精度决定能开多大上下文（Parallel=4，RTX 4090 24GB）

| ContextSize | 每路上下文 | KV 精度 | 显存占用 | 空闲 | 单路速度 | 总吞吐 |
|---|---|---|---|---|---|---|
| 196608 | 49152 | f16 | 21169 MiB | 2974 MiB | 70.2 tok/s | 160.5 tok/s |
| 229376 | 57344 | f16 | 23225 MiB | 918 MiB | — | — |
| 262144 | 65536 | f16 | 24127 MiB | **16 MiB** | 52.3 tok/s | 138.4 tok/s ⚠ |
| **262144** | **65536** | **q8_0** | **18581 MiB** | **5562 MiB** | **67.5 tok/s** | **158.6 tok/s** ✅ |

> ⚠ **262144 + f16 是个陷阱**：按 64 KiB/token 推算需要 25265 MiB，超过物理显存的
> 24564 MiB。Windows 的 WDDM 会把超出的 KV 分页到内存，实测速度掉约 15%
> （总吞吐 160.5 → 138.4）。显存显示"只剩 16 MiB"就是这个信号，**务必避免**。

#### 实测二：并发路数对吞吐的影响（ContextSize=131072，f16）

| 并发 | 单路 ctx | 显存 | 单路 | 总吞吐 |
|---|---|---|---|---|
| 1 | 131072 | 17075 MiB | 70.8 tok/s | 70.8 tok/s |
| 4 | 32768 | 17075 MiB | 44.2 tok/s | **171.8 tok/s** |
| 8 | 16384 | 17677 MiB | 28.5 tok/s | 166.5 tok/s |

总吞吐上限约 **170 tok/s**（受显存带宽限制，与官方 4090 参考值吻合）。4 路已用满带宽，
加到 8 路总吞吐不再提升，只是把速度平摊给更多人。

#### 24GB 显存 4 路并发的推荐档位

| 目标 | ContextSize | 每路上下文 | KV 精度 | 显存 | 说明 |
|---|---|---|---|---|---|
| **最大上下文（默认）** | **262144** | **65536** | **q8_0** | 18581 MiB | 4 人各 64K，余 5.5GB，速度无损 ✅ |
| 最高精度 | 196608 | 49152 | f16 | 21169 MiB | 4 人各 48K，KV 全精度 |
| 省显存 | 262144 | 65536 | q4_0 | 约 13 GB | 精度有损，一般不需要 |

**q8_0 KV 质量已验证**：在 48K token 长度的噪声文本中间埋入校验码，模型仍能准确检索，
长程记忆完好。

#### 通用换算公式

```
固定开销 ≈ 10.0 GB（权重 6.7 + 视觉塔 0.87 + 计算缓冲区/CUDA 上下文约 2.4）
可用 KV 显存 ≈ 24564 - 10000 - 安全余量(建议 ≥2000) ≈ 12.5 GB
支持总 token ≈ 12.5 GB ÷ KV每token开销
    f16  : 64 KiB/token  → 约 200000 token
    q8_0 : 32 KiB/token  → 约 400000 token（模型上限 262144 已到顶）
```

图片请求的显存开销极小：实测 1280×1280 图片仅额外占用约 90 MiB。

### 推测解码与 MTP

#### 结论：本模型**不支持 MTP**

```
$ llama-server ... --spec-type draft-mtp
W llama_init_from_model: context type MTP requested but model doesn't contain MTP layers
E common_speculative_init_result: failed to create MTP context
E srv llama_server: exiting due to model loading error
```

原因（已核对 GGUF 内部结构与 llama.cpp 源码）：

1. llama.cpp 的 `qwen35` 架构**确实实现了 MTP**（`src/models/qwen35.cpp` 中的 `graph_mtp`），
   但它要求 GGUF 里有 `qwen35.nextn_predict_layers` 键，且运行时断言
   `GGML_ASSERT(hparams.n_layer_nextn > 0)`。
2. 本模型的 GGUF **没有这个键**，KV 里不存在任何 `nextn`/`mtp` 配置。
3. 张量层 `blk.0` ~ `blk.63` 共 64 层，与 `block_count = 64` 完全一致
   （带 MTP 的模型在转换时会把 MTP 层**计入** `block_count`，此处没有多余层）。
4. HF 仓库也未提供独立的 MTP/draft 权重文件（只有 F16 / PQ2_0 / PTQ1_0 与两个 mmproj）。

`start-server.ps1` 已内置前置拦截：配置成 `draft-mtp` 会直接给出上述提示并拒绝启动，
不会浪费一次模型加载。

#### 替代方案：n-gram 推测解码（免费 4.3 倍加速）

好消息是 n-gram 推测解码**不需要额外权重、不占显存**，对重复性内容效果显著。

基准条件：RTX 4090 24GB，`-c 130000 -np 1`，固定种子，512 token

| 场景 | 复述 / 摘要引用 / 代码改写 | 自由创作 / 代码生成 | 显存开销 |
|---|---|---|---|
| 关闭推测解码 | 83.9 tok/s | 85.2 tok/s | — |
| `ngram-map-k`（干净上下文） | **370.3 tok/s**（4.4x） | 84.6 tok/s（−0.7%） | 0 |
| `ngram-map-k`（已有上下文） | 159.4 tok/s（1.9x） | 84.6 tok/s（−0.7%） | 0 |

命中率实测可达 **98.6%**，平均每步验证 29 个草稿 token。

> **关于"已有上下文"这一行**：n-gram 推测解码靠从上下文里找重复片段来猜后续 token。
> 如果前面先跑过无关任务，索引会被旧内容稀释，草稿长度从 29 降到 19，
> 复述类任务的收益从 4.4x 降到 1.9x。**但始终是正收益**，无需担心。
>
> **KV 精度与此无关**：实测 f16（370.3）与 q8_0（369.5）在干净条件下速度完全相同。
> 选 q8_0 的理由只是省一半 KV 显存，不是推测解码。

配置方法（`server-config.psd1`）：

```powershell
SpecType       = "ngram-map-k"   # none 可关闭
SpecNgramSizeN = 12              # 查找长度
SpecNgramSizeM = 48              # 草稿长度
```

原理说明：n-gram 推测解码从已处理的上下文中查找重复片段来"猜"后续 token，
再让主模型一次性批量验证。所以**只有当输出内容与上下文存在重复时才有收益** ——
复述、翻译引用、代码局部改写、模板填充这类任务命中率很高，
而开放式创作几乎没有重复，命中率接近 0（此时仅有约 0.7% 的额外开销）。

其它可选类型：`draft-simple`、`draft-eagle3`、`draft-dflash`、`draft-dspark`
都**需要额外的草稿模型权重**，当前未部署，配置后会给出明确提示。

### OpenAI 兼容端点

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/chat/completions` | 对话补全（支持 `stream`） |
| POST | `/v1/completions` | 文本补全 |
| GET | `/v1/models` | 模型列表 |
| GET | `/health` | 健康检查（加载中返回 503） |
| GET | `/` | 内置 Web UI |
| GET | `/metrics` | Prometheus 指标 |

### 调用示例

**curl**

```bash
curl http://127.0.0.1:2345/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"ternary-bonsai-2-27b","messages":[{"role":"user","content":"你好"}]}'
```

**Python（openai SDK）**

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:2345/v1", api_key="not-needed")
resp = client.chat.completions.create(
    model="ternary-bonsai-2-27b",
    messages=[{"role": "user", "content": "解释一下量子计算"}],
)
print(resp.choices[0].message.content)
# 思维链（thinking 模式下）：
# print(resp.choices[0].message.reasoning_content)
```

更多示例见 `api-examples.py`。

**PowerShell 调用（注意中文编码）**

PowerShell 5.1 的 `Invoke-RestMethod -Body` 默认按 ISO-8859-1 编码，中文需先转 UTF-8 字节，否则会变成 `?`：

```powershell
$json = @{ model="ternary-bonsai-2-27b"
           messages=@(@{role="user"; content="你好，介绍一下你自己"})
           max_tokens=1024 } | ConvertTo-Json -Depth 6
$bytes = [Text.Encoding]::UTF8.GetBytes($json)   # ← 关键
$r = Invoke-RestMethod "http://127.0.0.1:2345/v1/chat/completions" `
        -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes
$r.choices[0].message.content
```

> **注意**：该模型默认开启思考，`content` 是最终答案，思维链在 `reasoning_content` 字段。
> `max_tokens` 过小时可能只输出思维链就被截断，thinking 模式建议给 1024+。

---

## 多模态输入（图片 / 视频）

服务已挂载视觉塔，`GET /props` 的能力声明为：

```json
"modalities": { "vision": true, "video": true, "audio": false }
```

`audio: false` —— mmproj 里没有音频编码器，不支持音频输入。

### 图片

三种传法都支持：

```python
# 1) base64（data URI 或直接裸 base64 均可）
{"type": "image_url", "image_url": {"url": "data:image/png;base64,<B64>"}}

# 2) 远程 URL
{"type": "image_url", "image_url": {"url": "https://example.com/a.jpg"}}

# 3) 本地文件（需服务端 --media-path，本仓库配置为 images/）
{"type": "image_url", "image_url": {"url": "file://test.png"}}
```

### 各端点对视频的支持情况

以下为逐项实测结果（**13 / 13 通过**，重启服务后复测仍全过）：

| # | 端点 / 形式 | 视频 | 实测结果 |
|---|---|---|---|
| 1 | `GET /props` → `modalities.video` | — | `true` |
| 2 | `GET /v1/models` → `capabilities` | — | `["completion","multimodal"]` |
| 3 | `POST /v1/chat/completions` · `input_video.data`（base64） | ✅ | 答对「红,绿,蓝」 |
| 4 | 同上，换另一段视频（顺序敏感性） | ✅ | 答对「蓝,绿,红」，**未受缓存污染** |
| 5 | `POST /v1/chat/completions` · `input_video.url`（`file://`） | ✅ | 答对「红色」 |
| 6 | `content` 数组顺序颠倒（视频在前） | ✅ | 答对「黄色」 |
| 7 | 一个请求里放**两段视频** | ✅ | 分别答对各自顺序（prompt_tokens 1101） |
| 8 | **图片 + 视频混合** | ✅ | 图片=红色、视频=蓝→绿→红 |
| 9 | `POST /completion` · `{prompt_string, multimodal_data}` | ✅ | 需套聊天模板；prompt_n 566 vs 无视频 22 |
| 10 | 流式 `stream: true`（SSE） | ✅ | 3 个 chunk，答对「黄色」 |
| 11 | 远程 `https://` URL | ✅ | 外网可达时正常 |
| 12 | `POST /v1/messages`（Anthropic 格式） | ❌ | 端点存在，但本 fork 的 Anthropic 转换器只产出 `image_url`，`data:video/` URI 不被接受 |

**结论与用法建议：**

- **用 `/v1/chat/completions` + `{"type":"input_video", ...}`** —— 这是唯一可靠、功能完整的视频入口，
  上面第 3~11 项能力（多视频、图文混排、流式）它都支持。
- `/v1/chat/completions` 的 `content[]` **只接受 4 种类型**：
  `text` / `image_url` / `input_audio` / `input_video`。
  传其它类型（如 Anthropic 的 `{"type":"base64",...}` 或 `{"type":"video",...}`）会直接
  `HTTP 400 unsupported content[].type` —— **这不是视频不支持，是用错了端点**。
- `input_video` 与 `image_url` 一样，支持 `data`（base64）/ `url`（远程或 `file://`）两种写法。
- `/completion`（原始补全）也能吃视频，但它是**无聊天模板**的裸补全：
  不套 `<|im_start|>...<|im_end|>` 之类模板时模型会直接 EOS 输出空串。正常场景请用
  `/v1/chat/completions`。
- 不支持音频（`modalities.audio = false`，mmproj 无音频编码器）。

### 视频 ✅ 支持，且**具备真实的时序理解能力**

先看结论：本模型**可以**处理视频，并且不是「看几张静态截图」那种敷衍支持 ——
实测能够正确回答**顺序、运动方向、首末帧、切换点**等必须依赖时序的问题。

#### 工作原理

llama.cpp 的 mtmd 流水线这样处理视频：

```mermaid
flowchart LR
    A["视频文件 / base64"] --> B["ffprobe<br/>探测 宽高/帧率/时长"]
    B --> C["ffmpeg 子进程<br/>-vf fps=N -f rawvideo -pix_fmt rgb24"]
    C --> D["逐帧解析<br/>每帧 = 一张 RGB 位图"]
    D --> E["相邻帧两两合并<br/>fused temporal frames"]
    E --> F["同一个 2D CLIP 视觉塔<br/>768px / patch 16"]
    F --> G["投影到 5120 维<br/>拼入文本序列"]
    G --> H["LLM 因果注意力<br/>+ 文本时间戳"]
```

要点：

- **依赖外部 ffmpeg / ffprobe**（本机在 `C:\ffmpeg\bin\`，已在 PATH）。
  缺失时会报 `ffprobe failed ... (is ffprobe in PATH?)`。也可用 `--video-ffmpeg-dir` 指定。
- **帧数 = 时长 × `--video-fps`（默认 4.0）**。**源视频的帧率完全不影响**抽帧数量
  （被 ffmpeg 的 `fps` 滤镜归一化），实测 1/2/5/10/30 fps 的源视频 token 数完全一致。
- 服务会**自动插入文本时间戳**（默认每 `--video-timestamp-interval` 毫秒，即 5 秒一个），
  形如 `[0m5.00s]`，并以 `Video:` 开头。这就是模型能判断先后的关键线索。
- **相邻两帧会被合并成一批**（`[QWEN_VIDEO]` 时序融合）→ 每帧约占单图一半的 token。
- 视觉塔本身**没有任何时序建模** —— mmproj 里没有一个视频/时序相关的键，
  也没有 5 维（3D）卷积张量，`v.patch_embd` 是标准的 4 维 `[16,16,3,1152]` 纯 2D 卷积。
  顺序理解完全来自 **LLM 的因果注意力 + 时间戳文本**。

> **本分支的参数限制**
> `bin/` 里的 `prism-b10685` **没有** `--video-fps`、`--video-timestamp-interval`、
> `--video-ffmpeg-dir` 这三个开关（`--help` 里查不到，传了会直接 `invalid argument` 启动失败）。
> 因此视频按**编译期默认**工作：**抽帧固定 4 fps、每 5000 ms 一条时间戳、ffmpeg 从 PATH 查找**。
> `start-server.ps1` 已做**特性探测**，只传二进制真正认识的参数；
> `server-config.psd1` 里保留那三个键是为了将来升级到支持的版本时能直接生效。

#### Token 开销（实测，256×256 输入）

| 时长（2fps 源） | prompt_tokens | | 分辨率（10s） | prompt_tokens |
|---|---|---|---|---|
| 2 s | 331 | | 128 px | 388 |
| 5 s | 727 | | 256 px | 1396 |
| 10 s | 1396 | | 512 px | 5428 |
| 20 s | 2736 | | 768 px | 12148 |
| 40 s | 5416 | | | |

近似公式：

$$
\text{token} \approx \text{时长(s)} \times \texttt{video-fps} \times \tfrac{1}{2} \times \text{单帧token}
$$

按当前 `ContextSize = 130000`、`--video-fps 4`、512px 估算，
**一次请求最多约 24 秒视频**；768px 则只有约 10 秒。建议在客户端先自行降分辨率/剪时长。

#### ⚠️ 视频请求必须带 `"cache_prompt": false`

这是本次调试发现的**最严重的一个坑**，务必注意。

llama.cpp 的 prompt cache 按 **token id** 匹配前缀，而所有视觉占位 token 的 id 完全相同；
服务端的媒体记录 `map_idx_to_media` **只记录 token 位置、不比对媒体内容哈希**。
于是当「问题文本相同、只有视频不同」时，服务端会**直接复用上一个请求的 KV 缓存**。

症状：**完全不同的视频返回逐字符完全相同的回答**（`timings.cache_n ≈ 2525`）。

| 测试（同一句提问） | `cache_prompt: true` | `cache_prompt: false` |
|---|---|---|
| 4 组不同颜色顺序的视频 | 4 组全被答成「红,橙,绿,蓝」 | **4 / 4 正确** |
| 白块左右扫动的运动方向 | 6 问只对 1 问 | **6 / 6 正确** |
| 拼接视频的首帧 / 末帧 / 切换方向 | 不同视频输出相同 | **4 / 4 正确** |

> 实测**图片请求未受影响**（换图后 `cache_n = 0`，能正确区分红图/蓝图），
> 但为稳妥起见，建议**所有带媒体的请求都显式关闭缓存**。

关闭方式：

```python
# openai SDK
client.chat.completions.create(
    model="ternary-bonsai-2-27b",
    messages=[...],
    extra_body={"cache_prompt": False},   # ← 关键
)

# 或直接发 HTTP
{"model": "...", "messages": [...], "cache_prompt": false}
```

#### 视频请求示例

```python
import base64, json, urllib.request

b64 = base64.b64encode(open("test.mp4", "rb").read()).decode()
body = json.dumps({
    "model": "ternary-bonsai-2-27b",
    "messages": [{"role": "user", "content": [
        {"type": "text", "text": "这段视频里人物按时间顺序做了哪些动作？"},
        {"type": "input_video", "input_video": {"data": b64}},
    ]}],
    "max_tokens": 512,
    "reasoning_effort": "none",
    "cache_prompt": False,          # ← 必须
}, ensure_ascii=False).encode("utf-8")

req = urllib.request.Request("http://127.0.0.1:2345/v1/chat/completions",
                             data=body, headers={"Content-Type": "application/json"})
print(json.load(urllib.request.urlopen(req))["choices"][0]["message"]["content"])
```

`input_video` 同样支持三种形式：`{"data": "<base64>"}`、`{"url": "https://..."}`、
`{"url": "file://test.mp4"}`（需 `--media-path`）。

#### 实测证据（素材取自 `本地 ComfyUI 输出目录`，252 个 mp4）

- **单帧描述准确**：能正确读出「两位汉服女子、茶园、油纸伞、比耶手势」，
  以及另一个视频里的「电脑桌面 + 敦煌飞天壁纸 + 鼠标指针」。
- **运动方向 6/6**：白块从左到右 / 从右到左两段视频，
  首帧位置、末帧位置、运动方向全部答对。
- **颜色顺序 4/4**：红-绿-蓝、蓝-绿-红、绿-蓝-红、红-白-蓝 四段不同顺序全部答对。
- **拼接顺序 4/4**：`X = 汉女→桌面`、`Y = 桌面→汉女`，
  首帧/末帧选择全对；切换描述为
  「从两位古装女子，变成了电脑桌面背景」/「从电脑桌面壁纸，变成了真人古装剧照」。
- **倒放交叉验证**：把同一视频倒放后，
  倒放的「开场」描述（手持油纸伞）= 正放的「结尾」描述，
  倒放的「结尾」描述（手提高篮、转身相视）= 正放的「开场」描述。

### 思考开关与思考深度

| 需求 | 请求参数 | 说明 |
|---|---|---|
| 关闭思考 | `"reasoning_effort": "none"` | ✅ 已验证，思考 token 为 0 |
| 关闭思考（等价） | `"chat_template_kwargs": {"enable_thinking": false}` | ✅ 已验证 |
| 浅思考 | `"reasoning_effort": "low"` | ✅ |
| 中等思考 | `"reasoning_effort": "medium"` | ✅ |
| 深度思考 | `"reasoning_effort": "xhigh"` | ✅ |
| ❌ 不可用 | `"reasoning_effort": "high"` / `"max"` / `"minimal"` | 模板直接抛异常 → **HTTP 500** |

注意：

- 思考内容放在 `reasoning_content`，最终答案在 `content`（由 `Reasoning.Format = "deepseek"` 决定）。
- `thinking_budget` / `reasoning_budget` 这类**请求级**预算参数会被**忽略**，
  预算只能通过服务端启动参数设置。
- `start-server.ps1` 已在启动时校验 `Reasoning.Effort`，填了 `high`/`max`/`minimal`
  会直接报错，避免撞上运行时 500。

---

## 局域网访问

当前已配置为局域网可访问模式（`Host = "0.0.0.0"`）。

### 1. 放行防火墙（只需一次，**必须管理员权限**）

Windows 防火墙默认阻止入站连接，其他设备要访问必须放行端口：

> **右键点击 `allow-firewall.cmd` → 以管理员身份运行**
>
> 或在「管理员 PowerShell」中执行：
> ```powershell
> cd <项目目录>
> .\allow-firewall.ps1
> ```

脚本会自动读取配置端口，并**只放行本机所在子网**（如 `192.168.1.0/24`），
不会暴露给所有网络。相关操作：

```powershell
.\allow-firewall.ps1 -Status      # 查看规则
.\allow-firewall.ps1 -Remove      # 删除规则
.\allow-firewall.ps1 -Port 9000   # 指定端口
```

### 2. 获取访问地址

启动脚本会自动探测并打印可用地址（只显示已连接网卡的地址，自动忽略断开的网卡）：

```
.\start-server.ps1 -Status
→ 局域网   : http://192.168.1.100:2345
```

### 3. 其他设备上使用

把 base URL 换成局域网地址即可，其余完全一致：

```python
from openai import OpenAI
client = OpenAI(base_url="http://192.168.1.100:2345/v1", api_key="not-needed")
```

浏览器直接打开 `http://192.168.1.100:2345/` 也能使用内置 Web UI。

### ⚠ 安全提示

局域网开放时若无鉴权，**同网段任何人都能调用本服务**（已弃用显存/算力）。
建议在 `server-config.psd1` 中设置：

```powershell
ApiKey         = "sk-换成你自己的密钥"      # 客户端须带 Authorization: Bearer sk-换成你自己的密钥
AllowedOrigins = "http://192.168.1.50" # 可选：限制 CORS 来源
```

改完执行 `.\start-server.ps1 -Force` 生效。也可把 `Host` 改回 `127.0.0.1` 完全关闭局域网访问。

---

## 二、命令行对话（无需启动服务）

```powershell
.\run-chat.ps1                 # thinking 模式（默认，temp=1.0 top_p=0.95）
.\run-chat.ps1 -NoThink        # instruct 模式（更快更短，temp=0.7 pres_pen=1.5）
.\run-chat.ps1 -Context 65536  # 调整上下文长度（最大 262144）
```

### 单条提问

```powershell
.\bin\llama-cli.exe -m .\models\Ternary-Bonsai-2-27B-PQ2_0.gguf `
    -ngl 99 -fa on -c 32768 --temp 1.0 --top-p 0.95 --top-k 20 `
    -p "Explain quantum computing in simple terms." -n 256
```

---

## 三、重要说明

- **必须使用 PrismML fork**：PQ2_0/PTQ1_0 是自定义 ternary g128 格式（权重经区块 Hadamard 旋转），原版 llama.cpp 会拒绝加载 `PQ2_0`，或静默加载 `Q2_0` 后输出乱码。`bin/` 已包含正确的预编译二进制（prism-b10685）。
- **采样参数**（官方推荐，已写入配置）：
  - thinking：`temp=1.0, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=0.0`
  - instruct：`temp=0.7, top_p=0.80, top_k=20, min_p=0.0, presence_penalty=1.5`
- **推理力度**：默认 `xhigh`；`medium` 更快更短；**`low` 不被模型支持**，会退化为接近 xhigh。
- **Packing 选择**：PQ2_0 在 Ada 架构（40/50 系）prompt 处理更快；PTQ1_0（5.95 GB）在 40 系 decode 略快且更省显存，显存紧张可换。
- **视觉/视频输入**：需 `--mmproj models\Ternary-Bonsai-2-27B-mmproj-BF16.gguf`（888 MB，本仓库默认）；
  纯文本推理无需加载。视频还需系统里有 **ffmpeg + ffprobe**。
- **多模态请求务必带 `"cache_prompt": false`**：否则内容不同的视频会复用同一段 KV 缓存，
  返回完全错误的答案（详见上文「多模态输入」章节）。

## 参考数据

| 平台 | tg128 (decode) | pp512 (prefill) |
|---|---|---|
| RTX 4090 (24 GB)，官方 | 81.2 tok/s | 3124 tok/s |
| **本机实测** | **81.9 tok/s** | — |

---

## 许可

本项目（脚本与文档）采用 **MIT License**，见 [`LICENSE`](LICENSE)。

### 第三方组件

本项目**不打包**第三方代码或模型权重，需自行下载，各自遵循原协议：

| 组件 | 协议 | 说明 |
|---|---|---|
| [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) fork | MIT | `bin/` 中的推理二进制，本项目仅提供下载说明 |
| [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) | apache-2.0 | 模型权重（含 mmproj 视觉塔），一并遵循其模型卡使用条款 |
| 上游 [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) | MIT | fork 的上游项目 |

> 使用模型权重前建议阅读其 [模型卡](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf)
> 中的用途限制说明。
