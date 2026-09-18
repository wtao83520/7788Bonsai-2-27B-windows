@{
    # ==========================================================================
    #  Ternary-Bonsai-2-27B-PQ2_0  ·  OpenAI 兼容 API 服务配置
    #  修改本文件后执行 .\start-server.ps1 -Force 即可生效
    #  路径可写相对路径（相对于本目录）或绝对路径
    # ==========================================================================

    # ---------------------------- 模型设置 -----------------------------------
    Model = @{
        Path           = "models\Ternary-Bonsai-2-27B-PQ2_0.gguf"  # 模型文件位置
        Alias          = "ternary-bonsai-2-27b"    # /v1/models 中显示的模型名，客户端用它调用
        # ⚠ ContextSize 是【所有并发槽位的总上下文】，单路可用长度 = ContextSize / Parallel
        # 本模型为混合注意力（64 层中仅 16 层是完整注意力层，`full_attention_interval=4`，
        # 其余为 SSM 线性层），故 KV cache 只按 16 层增长，约 64 KiB / token（f16）。
        #
        # ── 实测一：KV 精度对显存的影响（Parallel=4，RTX 4090 24GB）──
        #   ContextSize    KV精度   显存占用   空闲    单路速度    总吞吐
        #      196608      f16     21169MiB  2974MiB  70.2 tok/s  160.5 tok/s
        #      229376      f16     23225MiB   918MiB     -           -
        #      262144      f16     24127MiB    16MiB  52.3 tok/s  138.4 tok/s  ← 溢出!
        #      262144      q8_0    18581MiB  5562MiB  67.5 tok/s  158.6 tok/s  ← 最优 ✓
        #
        #   ⚠ 262144 + f16 时按 64KiB/token 推算需 25265MiB > 物理 24564MiB，
        #     Windows(WDDM) 会把部分 KV 分页到内存，导致速度掉 ~15%，务必避免！
        #
        # ── 实测二：并发路数对吞吐的影响（ContextSize=131072）──
        #   并发1路 262144上下文 → 显存 24135MiB 单路 70.8 tok/s  总吞吐  70.8
        #   并发4路  32768上下文 → 显存 17075MiB 单路 44.2 tok/s  总吞吐 171.8  ← 吞吐最优
        #   并发8路  16384上下文 → 显存 17677MiB 单路 28.5 tok/s  总吞吐 166.5  ← 吞吐已饱和
        #   结论: 总吞吐上限约 170 tok/s（受显存带宽限制），4 路已用满带宽，
        #         再加路数只摊薄单路速度、不再提升总吞吐。
        #
        # ── 结论: 4 路并发的最佳配置 = ContextSize 262144 + q8_0 KV ──
        #   即每路 64K 上下文（模型上限），显存 18581MiB 仍余 5.5GB，速度几乎无损。
        #   q8_0 KV 长程记忆已验证：48K token 上下文中埋点仍能准确检索。
        #   若追求极致精度可改回 f16，但需把 ContextSize 降到 196608（每路 48K）。
        ContextSize    = 242000      # 总上下文（= 单路上限 × Parallel）
        GpuLayers      = 99          # 卸载到 GPU 的层数，99 = 全部（0 = 纯 CPU）
        FlashAttention = "on"        # on / off / auto
        Parallel       = 1           # 并发请求槽位数（每条占用一份 KV cache）
                                     #   1=单用户最大上下文  4=4人同时用(推荐)  8=更多人但更慢
                                     #   改这里时记得同步调整 ContextSize
        BatchSize      = 2048        # 逻辑批大小
        UbatchSize     = 512         # 物理批大小（显存紧张时调小，如 256）
        CacheTypeK     = "f16"       # K 缓存精度: f32/f16/bf16/q8_0/q4_0/q5_0...
        CacheTypeV     = "f16"       # V 缓存精度: 同上
                                     #   q8_0 可省约一半 KV 显存（130000 上下文省 3.3GB），
                                     #   速度几乎无损、长程检索质量已验证（48K 埋点可准确召回）。
                                     #   f16 精度更高但更占显存，可按需选择。
                                     #   注: 推测解码的收益与 KV 精度【无关】——
                                     #       实测复述任务 f16=370.3 与 q8_0=369.5 tok/s 完全相同。
        UseMmap        = $true       # $false 时模型完全读入内存（加载稍慢，运行更稳）
        UseJinja       = $true       # 必须为 $true，否则思考/工具调用模板失效

        # ------------------------- 推测解码（加速）--------------------------
        # ⚠ 本模型【不支持 MTP】！实测运行时明确报错：
        #     "context type MTP requested but model doesn't contain MTP layers"
        #   原因：MTP 需要 GGUF 内有 qwen35.nextn_predict_layers 键 + 额外的 nextn 层，
        #   本 GGUF 无此键，64 层全部是主干层（blk.0~63），故无法启用 MTP。
        #   运行时（llama.cpp）本身支持 qwen35 的 MTP，只是这个模型没有相应的权重。
        #
        # 但 n-gram 推测解码【不需要额外权重、不占显存】，实测免费加速：
        #   ┌────────────────────────┬──────────┬──────────┬────────┐
        #   │ 场景                   │ 复述任务 │ 自由生成 │ 显存   │
        #   ├────────────────────────┼──────────┼──────────┼────────┤
        #   │ 关闭推测解码           │  83.9    │  85.2    │  —     │
        #   │ ngram-map-k 干净上下文 │ 370.3    │  84.6    │  0     │  ← 4.4x
        #   │ ngram-map-k 已有上下文 │ 159.4    │  84.6    │  0     │  ← 1.9x
        #   └────────────────────────┴──────────┴──────────┴────────┘
        #   重复性内容（复述、摘要引用、代码改写、模板填充）可提速 4 倍以上；
        #   自由创作任务仅有 <1% 的开销，可忽略。
        #   ⚠ "已有上下文"指前面先跑过无关任务：n-gram 索引会被旧内容稀释，
        #     草稿长度从 29 降到 19，收益从 4.4x 降到 1.9x（仍为正收益）。
        SpecType       = "ngram-map-k"
                                     # none            = 关闭推测解码
                                     # ngram-map-k     = 推荐，重复内容提速约 4.3x
                                     # ngram-simple    = 同类，效果相近
                                     # ngram-mod       = 哈希式，长文本更省内存
                                     # draft-mtp       = ✗ 本模型不支持，会启动失败
                                     # draft-simple / draft-eagle3 / draft-dflash
                                     #                 = 需要独立的草稿模型权重，当前未部署
        SpecNgramSizeN = 12          # ngram 查找长度（调大更保守，命中率降但更准）
        SpecNgramSizeM = 48          # ngram 草稿长度（一次最多推测多少 token）
    }

    # ----------------------- 图片 / 视频输入（视觉）-------------------------
    # 启用后即可在 /v1/chat/completions 中发送 image_url 或 input_video 类型的 content。
    # 纯文本使用时不会有额外开销（视觉塔仅在收到图片/视频请求时才参与计算）。
    #
    # ⚠⚠ 极重要：带媒体的请求务必在请求体里加 "cache_prompt": false
    #    llama.cpp 的 prompt cache 只按 token id 匹配前缀，而所有视觉占位 token 的 id
    #    完全相同，服务端的媒体记录也只记位置、不比对内容哈希 —— 于是「问题文本相同、
    #    只有视频不同」时服务端会直接复用上一个请求的 KV，返回逐字符相同的错误答案。
    #    实测：视频颜色顺序测试 4 组，开着缓存全部被答成「红,橙,绿,蓝」(0/4)，
    #          关掉缓存后 4/4 全对；运动方向测试 1/6 → 6/6。
    #    图片请求实测未受影响，但建议一律关闭。
    Vision = @{
        Enabled       = $true        # 是否启用图片/视频输入
        MmprojPath    = "models\Ternary-Bonsai-2-27B-mmproj-BF16.gguf"
                                     # 视觉投影层文件。BF16 约 0.87 GB（精度参考版）；
                                     # 可换成 Q8_0 版（约 0.60 GB，更省显存）：
                                     #   hf download prism-ml/Ternary-Bonsai-2-27B-gguf `
                                     #       Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf --local-dir models
                                     # 注意：该 mmproj 无音频编码器 → 不支持音频输入。
        Offload       = $true        # 视觉塔是否放显存。$false 则留在内存（省显存，图片处理变慢）
        ImageMinTokens = $null       # 每张图最少 token 数，$null = 用模型默认
        ImageMaxTokens = $null       # 每张图最多 token 数（图片细节上限），$null = 用模型默认
                                     #   显存/上下文紧张时可设小，如 1024
        MediaPath     = "images"     # 允许用 file:// 引用本地文件的目录（相对项目根）。
                                     #   留空 "" 则只能传 URL 或 base64。
                                     #   例：{"url": "file://demo.png"} 会读取 images\demo.png
                                     #       {"url": "file://demo.mp4"} 会读取 images\demo.mp4

        # --------------------------- 视频（抽帧）---------------------------
        # 视频先由 ffprobe 探测、再由 ffmpeg 按 VideoFps 抽帧，
        # 每帧交给【同一个 2D 视觉塔】，并在文本里插入时间戳让模型感知先后。
        # ⚠ 需要系统里有 ffmpeg 与 ffprobe（已在 PATH，或设置 VideoFfmpegDir）。
        #
        # Token 开销实测（源帧率完全不影响抽帧数量）：
        #   时长(2fps,256px)  tokens     分辨率(10s,2fps)  tokens
        #        2 s            331         128 px           388
        #        5 s            727         256 px          1396
        #       10 s           1396         512 px          5428
        #       20 s           2736         768 px         12148
        #       40 s           5416
        #   近似: token ≈ 时长(s) × 抽帧fps ÷ 2 × 单帧token
        #   按 ContextSize=130000、4 fps、512px 估算 → 单次约 24 秒视频上限。
        #
        # ⚠ 重要：本仓库的二进制 prism-b10685 **不支持**下面三个参数
        #   （`llama-server --help` 里没有 --video-fps / --video-timestamp-interval /
        #     --video-ffmpeg-dir）。启动脚本会自动探测并跳过它们，视频按内置默认工作：
        #     抽帧 4 fps、每 5000 ms 一条时间戳、ffmpeg 从系统 PATH 查找。
        #   保留这三个键是为了日后升级到支持它们的版本时能直接生效。
        VideoFps            = 4.0    # 抽帧帧率（内置默认 4.0）。调大 = 更细腻但 token 线性增长
                                     #   源视频帧率（如 24fps）不影响抽帧数，勿混淆
        VideoTimestampInterval = 5000 # 每 N 毫秒插入一条文本时间戳（内置默认 5000，0 = 关闭）
                                     #   这是模型判断「先后顺序」的关键线索，建议保留
        VideoFfmpegDir      = ""     # ffmpeg/ffprobe 所在目录。
                                     #   留空 = 从系统 PATH 查找（本机为 C:\ffmpeg\bin）
                                     #   若不在 PATH 可填绝对路径，例如 "C:\ffmpeg\bin"
                                     #   ⚠ 本分支不支持 --video-ffmpeg-dir，填了也只会提示你把该
                                     #     目录加入系统 PATH
    }

    # ---------------------------- 服务设置 -----------------------------------
    Server = @{
        Host           = "0.0.0.0"   # "127.0.0.1" = 仅本机；"0.0.0.0" = 允许局域网访问
        Port           = 2345
        ApiKey         = ""          # 留空表示不需要鉴权；★局域网环境下强烈建议填写（如 "sk-换成你自己的密钥"）
                                     #   填写后客户端须带 header: Authorization: Bearer <key>
        AllowedOrigins = "*"         # CORS 允许来源，局域网共享建议收窄，如 "http://192.168.1.50"
        WebUI          = $true       # 是否开启内置网页界面 (http://host:port/)
        Metrics        = $true       # 是否开启 /metrics 监控端点
        SlotsMonitor   = $true       # 是否开启 /slots 槽位监控
        TimeoutSeconds = 3600        # 读写超时（秒），长思维链建议保持较大
        ThreadsHttp    = -1          # HTTP 处理线程数，-1 = 自动
    }

    # ------------------------ 采样参数（API 默认值）--------------------------
    # 客户端若在请求体里自带 temperature/top_p 等，会覆盖这里的值；
    # 若客户端未传，则使用下面的值。
    Sampling = @{
        Preset          = "thinking" # thinking | instruct | custom
                                     #   thinking : temp=1.0 top_p=0.95 pres_pen=0.0（推荐，深度推理）
                                     #   instruct : temp=0.7 top_p=0.80 pres_pen=1.5（简短直接）
                                     #   custom   : 使用下面手工填写的数值
        Temperature     = 1.0
        TopP            = 0.95
        TopK            = 20
        MinP            = 0.0
        PresencePenalty = 0.0
        RepeatPenalty   = 1.0
    }

    # --------------------- 思考（推理）开关与深度 ----------------------------
    #
    #  【重要】本模型的 chat template 只接受三个 effort 值：low / medium / xhigh，
    #          传其它值（如 high、max、minimal）会导致请求报 500 错误！
    #
    #  · 服务端默认（下面这几项）—— 客户端未指定时生效
    #  · 请求级覆盖（推荐，客户端按需传参，无需重启服务）：
    #      思考关闭:  {"reasoning_effort": "none"}
    #                 或 {"chat_template_kwargs": {"enable_thinking": false}}
    #      思考深度:  {"reasoning_effort": "low" | "medium" | "xhigh"}
    #      限制预算:  {"reasoning_effort": "none"} 之外无请求级预算参数，
    #                 token 预算只能在此处或启动参数上设置
    #
    Reasoning = @{
        Effort  = "default"  # default | low | medium | xhigh
                             #   default = 模型自带（等同 xhigh，推理最充分、最慢）
                             #   medium  = 更快更短，质量略降（官方推荐折中档）
                             #   xhigh   = 深思熟虑（官方默认档）
                             #   low     = 模型未真正支持，行为近似 xhigh
                             #   ⚠ 不要填 high/max/minimal —— 模板会拒绝并报错
        Budget  = -1         # 思考 token 预算（服务端默认）: -1 = 不限, 0 = 直接结束, N>0 = 上限
                             #   想强制"默认不思考"就设为 0
        Format  = "deepseek" # none | deepseek | deepseek-legacy
                             #   deepseek = 思考内容放入 message.reasoning_content（推荐）
        Preserve = $true     # 完整对话历史中保留思维链（多轮质量更好，更耗 token）
        Control  = $false    # 是否允许 /v1/chat/completions/control 实时结束思考（实验特性）
    }
}







