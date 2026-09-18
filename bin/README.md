# bin/ — PrismML llama.cpp fork 运行时

> ⚠ **本目录不在版本控制中**（见根目录 `.gitignore`）。
> 二进制合计约 **658 MB**（其中 19 个 CUDA DLL 就占 656 MB），
> 不适合放进 Git 仓库，请自行下载。

## 为什么必须用这个 fork

Ternary-Bonsai 的 `PQ2_0` / `PTQ1_0` 是**自定义的 ternary g128 格式**
（权重经过区块 Hadamard 旋转），原版 llama.cpp 不认识：

| 情况 | 结果 |
|---|---|
| 原版 llama.cpp 加载 `PQ2_0` | ❌ 直接**拒绝加载**（未知 ftype） |
| 原版 llama.cpp 加载 `PTQ1_0` | ❌ 静默按 `Q2_0` 处理 → **输出乱码** |
| 本 fork（PrismML） | ✅ 正常 |

## 下载与安装

1. 打开 **[PrismML-Eng/llama.cpp — Releases](https://github.com/PrismML-Eng/llama.cpp/releases)**
2. 下载 **Windows + CUDA 13.x** 的预编译包
   （资源名形如 `win-cuda-13.3-*.zip`，自带 cudart，**无需**系统装 CUDA Toolkit）
3. 解压，把里面的 `*.exe` 与 `*.dll` **全部平铺**到本目录（不要保留子目录层级）

本仓库验证通过的版本是 **`prism-b10685-7dffb15`**：

```powershell
.\bin\llama-cli.exe --version
# 期望输出包含：build 10685, commit 7dffb158d
```

> ⚠ **已知问题**：更新的 `prism-b10687-5d80cff` 发布包里**只有 cudart DLL、没有可执行文件**，
> 装不上。请优先选 `prism-b10685`。若 Releases 页面已找不到，可改用其他带 exe 的版本，
> 但需自行确认能加载 PQ2_0。

安装完成后本目录应有 **51 个 `.exe` + 19 个 `.dll`**，其中这两个是本项目真正用到的：

| 文件 | 用途 |
|---|---|
| `llama-server.exe` | ★ OpenAI 兼容 API 服务（`start-server.ps1` 调用） |
| `llama-cli.exe` | 命令行对话（`run-chat.ps1` 调用） |

其余 49 个是 fork 附带的全家桶工具（`llama-bench.exe`、`llama-quantize.exe`、
`llama-mtmd-cli.exe` 等），保留即可，删掉也能正常运行。

## 校验

```powershell
(Get-ChildItem bin -Filter *.exe).Count      # 预期 51
(Get-ChildItem bin -Filter *.dll).Count      # 预期 19
.\bin\llama-server.exe --version
```

驱动要求：NVIDIA 驱动需支持 CUDA 13.x（本机实测驱动 `616.56` 正常）。
