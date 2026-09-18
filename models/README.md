# models/ — 模型权重

> ⚠ **本目录不在版本控制中**（见根目录 `.gitignore`）。
> 权重合计约 **7.7 GB**，请自行下载到本目录。

## 需要下载的文件

| 文件 | 大小 | 必需 | 说明 |
|---|---|---|---|
| `Ternary-Bonsai-2-27B-PQ2_0.gguf` | 6.87 GiB (7.21 GB) | ✅ | 主模型权重，PQ2_0 三元量化（2-bit，2.13 bpw，group 128） |
| `Ternary-Bonsai-2-27B-mmproj-BF16.gguf` | 888 MB | 可选 | 视觉塔，**图片/视频输入**需要；纯文本推理无需此文件 |

**可选替换：**

| 文件 | 大小 | 说明 |
|---|---|---|
| `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` | 629 MB | 视觉塔的 Q8_0 版，比 BF16 省 259 MB 显存，精度略低 |
| `Ternary-Bonsai-2-27B-PTQ1_0.gguf` | 5.95 GB | 另一种打包（1-bit）。显存紧张可换；40 系 decode 略快 |
| `Ternary-Bonsai-2-27B-F16.gguf` | ~54 GB | 全精度，一般不需要 |

下载后目录应长这样：

```
models/
├── Ternary-Bonsai-2-27B-PQ2_0.gguf            # 必需
└── Ternary-Bonsai-2-27B-mmproj-BF16.gguf      # 可选（视觉）
```

## 下载方式

### 方式一：Hugging Face CLI（推荐）

```powershell
pip install -U "huggingface_hub[cli]"

# 下载主模型（7.21 GB）
hf download prism-ml/Ternary-Bonsai-2-27B-gguf `
    Ternary-Bonsai-2-27B-PQ2_0.gguf --local-dir models

# 下载视觉塔（888 MB，需要图片/视频输入时才下）
hf download prism-ml/Ternary-Bonsai-2-27B-gguf `
    Ternary-Bonsai-2-27B-mmproj-BF16.gguf --local-dir models
```

> 旧版 CLI 命令是 `huggingface-cli download`，参数相同。

### 方式二：直接下载

在 [模型页面](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) 的
**Files and versions** 标签页里逐个下载，放到本目录即可。国内网络可用
`https://hf-mirror.com` 替换域名。

### 方式三：Python

```python
from huggingface_hub import hf_hub_download
for f in ["Ternary-Bonsai-2-27B-PQ2_0.gguf",
          "Ternary-Bonsai-2-27B-mmproj-BF16.gguf"]:
    hf_hub_download("prism-ml/Ternary-Bonsai-2-27B-gguf", f, local_dir="models")
```

## 校验

下载后确认文件大小：

```powershell
Get-ChildItem models\*.gguf | Select-Object Name, @{n='GB';e={[math]::Round($_.Length/1GB,2)}}
```

预期：

```
Ternary-Bonsai-2-27B-PQ2_0.gguf           7.21
Ternary-Bonsai-2-27B-mmproj-BF16.gguf     0.87
```

> 主模型 `PQ2_0.gguf` 的准确字节数是 `7206168928`。若明显偏小说明下载中断，
> 删掉重下即可（`hf download` 默认会断点续传）。

## ⚠ 重要：必须用 PrismML fork 加载

PQ2_0 / PTQ1_0 是自定义的 ternary g128 格式（权重经过区块 Hadamard 旋转）。

- **原版 llama.cpp 会拒绝加载 `PQ2_0`**，或静默按 `Q2_0` 加载后输出乱码。
- 必须使用 PrismML 的 fork，见 [`../bin/README.md`](../bin/README.md)。

## 模型信息

| 项目 | 值 |
|---|---|
| 架构 | `qwen35`（派生自 Qwen3.8-27B） |
| 参数量 | 26,895,998,464（26.9 B） |
| 层数 | 64（混合注意力：每 4 层 1 层完整注意力，其余 48 层为 SSM 线性层） |
| 词表 | 248,320 |
| 训练上下文 | 262,144 |
| 量化 | PQ2_0 — 2.13 bpw (group 128) |
| 许可 | apache-2.0 |

更多实测数据（显存、并发、速度）见项目根目录 [`README.md`](../README.md)。
