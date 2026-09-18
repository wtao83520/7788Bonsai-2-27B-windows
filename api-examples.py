"""
Ternary-Bonsai-2-27B · OpenAI 兼容 API 调用示例

前置：先启动服务   .\\start-server.cmd
依赖：pip install openai      (或仅用标准库 requests / urllib)
"""

import json
import time
import urllib.request

BASE_URL = "http://127.0.0.1:2345/v1"
MODEL = "ternary-bonsai-2-27b"
API_KEY = ""  # 若在 server-config.psd1 中设置了 ApiKey，请填入


# --------------------------------------------------------------------------
# 方式一：官方 openai SDK（推荐）
# --------------------------------------------------------------------------
def example_openai_sdk():
    from openai import OpenAI

    client = OpenAI(base_url=BASE_URL, api_key=API_KEY or "not-needed")

    # 1) 非流式
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": "You are a helpful assistant"},
            {"role": "user", "content": "用一句话解释什么是三元权重神经网络。"},
        ],
        max_tokens=1024,  # thinking 模式建议 >= 1024，否则可能被思维链占满
        temperature=1.0,
        top_p=0.95,
        extra_body={"top_k": 20},  # top_k 非 OpenAI 标准参数，需走 extra_body
    )
    print("【答案】", resp.choices[0].message.content)
    reasoning = getattr(resp.choices[0].message, "reasoning_content", None)
    if reasoning:
        print(f"【思维链 {len(reasoning)} 字符】", reasoning[:200], "...")
    print("【用量】", resp.usage)

    # 2) 流式，实时打印
    print("\n【流式输出】")
    stream = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": "数 1 到 5。"}],
        max_tokens=256,
        stream=True,
    )
    for chunk in stream:
        delta = chunk.choices[0].delta
        if getattr(delta, "reasoning_content", None):
            print(delta.reasoning_content, end="", flush=True)
        if delta.content:
            print(delta.content, end="", flush=True)
    print()


# --------------------------------------------------------------------------
# 方式二：纯标准库（无需安装任何依赖）
# --------------------------------------------------------------------------
def example_stdlib(prompt: str = "17 乘以 23 等于多少？", max_tokens: int = 512):
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 1.0,
        "top_p": 0.95,
    }
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            **({"Authorization": f"Bearer {API_KEY}"} if API_KEY else {}),
        },
        method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=600) as r:
        data = json.loads(r.read().decode("utf-8"))
    elapsed = time.time() - t0

    msg = data["choices"][0]["message"]
    print("【答案】", msg.get("content"))
    if msg.get("reasoning_content"):
        print("【思维链】", msg["reasoning_content"][:200], "...")
    usage = data["usage"]
    print(
        f"【用量】prompt={usage['prompt_tokens']} "
        f"completion={usage['completion_tokens']} "
        f"耗时={elapsed:.2f}s "
        f"({usage['completion_tokens'] / elapsed:.1f} tok/s)"
    )
    return data


# --------------------------------------------------------------------------
# 方式三：列出可用模型
# --------------------------------------------------------------------------
def example_list_models():
    with urllib.request.urlopen(f"{BASE_URL}/models", timeout=30) as r:
        data = json.loads(r.read().decode("utf-8"))
    for m in data.get("data", []):
        meta = m.get("meta", {})
        print(f"模型 ID   : {m['id']}")
        print(f"  上下文  : {meta.get('n_ctx')} (训练 {meta.get('n_ctx_train')})")
        print(f"  参数量  : {meta.get('n_params', 0) / 1e9:.2f} B")
        print(f"  量化    : {meta.get('ftype')}")


# --------------------------------------------------------------------------
# 方式四：流式请求（requests 库）
# --------------------------------------------------------------------------
def example_stream_requests(prompt: str = "写一首关于秋天的四行诗。"):
    import requests

    with requests.post(
        f"{BASE_URL}/chat/completions",
        json={
            "model": MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 512,
            "stream": True,
        },
        headers={"Authorization": f"Bearer {API_KEY}"} if API_KEY else {},
        stream=True,
        timeout=600,
    ) as r:
        for line in r.iter_lines():
            if not line or not line.startswith(b"data: "):
                continue
            body = line[6:]
            if body == b"[DONE]":
                break
            delta = json.loads(body)["choices"][0]["delta"]
            print(delta.get("reasoning_content") or "", end="", flush=True)
            print(delta.get("content") or "", end="", flush=True)
    print()


# --------------------------------------------------------------------------
# 方式五：图片输入
# --------------------------------------------------------------------------
def example_image(image_path: str = "images/demo.png",
                  question: str = "描述这张图片的内容。"):
    """图片三种传法演示：base64 / 本地 file:// / 远程 URL。

    ⚠ 带媒体的请求一定要加 "cache_prompt": False
      llama.cpp 的 prompt cache 按 token id 匹配前缀，而所有视觉占位 token 的 id
      完全相同；开着缓存会让服务端复用上一个请求的 KV，返回与本次图片无关的答案。
    """
    import base64
    import os

    body = {
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "image_url",
                 "image_url": {"url": "data:image/png;base64," +
                                      base64.b64encode(open(image_path, "rb").read()).decode()}},
            ],
        }],
        "max_tokens": 512,
        "reasoning_effort": "none",
        "cache_prompt": False,          # ← 关键
    }
    req = urllib.request.Request(f"{BASE_URL}/chat/completions",
                                 data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=1800) as r:
        data = json.loads(r.read().decode("utf-8"))
    print("【图片描述】", data["choices"][0]["message"].get("content"))
    print("【用量】", data["usage"])

    # 等价写法（需服务端 --media-path，本仓库配置为 images/）：
    #   {"type": "image_url", "image_url": {"url": "file://demo.png"}}
    #   {"type": "image_url", "image_url": {"url": "https://example.com/a.jpg"}}


# --------------------------------------------------------------------------
# 方式六：视频输入
# --------------------------------------------------------------------------
def example_video(video_path: str = "images/demo.mp4",
                  question: str = "这段视频里发生了什么？请按时间顺序描述。"):
    """视频输入演示。

    服务端处理流程：
      ffprobe 探测 → ffmpeg 按 fps 抽帧 → 逐帧交给同一个 2D 视觉塔
      → 文本中插入时间戳（默认每 5000 ms 一条）→ LLM 因果注意力感知先后

    依赖：系统需有 ffmpeg 与 ffprobe（本机在 C:\\AI\\ffmpeg-7.1.1\\bin）。
    token 开销 ≈ 时长(s) × fps ÷ 2 × 单帧token，按时长与分辨率线性增长。

    ⚠ 必须 "cache_prompt": False，否则不同视频会复用同一 KV 缓存、返回相同答案！
      实测：开着缓存 4 组不同颜色顺序的视频全部被答成「红,橙,绿,蓝」（0/4），
            关掉后 4/4 全对；运动方向测试 1/6 → 6/6。
    """
    import base64

    b64 = base64.b64encode(open(video_path, "rb").read()).decode()
    body = {
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "input_video", "input_video": {"data": b64}},
            ],
        }],
        "max_tokens": 1024,
        "reasoning_effort": "none",
        "temperature": 0.0,
        "top_k": 1,
        "cache_prompt": False,          # ← 关键
    }
    req = urllib.request.Request(f"{BASE_URL}/chat/completions",
                                 data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=3600) as r:
        data = json.loads(r.read().decode("utf-8"))
    print("【视频描述】", data["choices"][0]["message"].get("content"))
    print(f"【用量】 prompt_tokens={data['usage']['prompt_tokens']}  "
          f"耗时 {time.time()-t0:.1f}s")

    # 等价写法：
    #   {"type": "input_video", "input_video": {"url": "file://demo.mp4"}}
    #   {"type": "input_video", "input_video": {"url": "https://example.com/a.mp4"}}


# --------------------------------------------------------------------------
# 方式七：关闭 / 调整思考深度
# --------------------------------------------------------------------------
def example_thinking_control(prompt: str = "9.11 和 9.9 哪个大？"):
    """思考开关与深度控制。

    已验证可用的取值：none（关闭）/ low / medium / xhigh
    ⚠ high / max / minimal 会让 chat template 抛异常 → HTTP 500
    """
    for effort in ("none", "low", "xhigh"):
        body = {
            "model": MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 512,
            "reasoning_effort": effort,
        }
        req = urllib.request.Request(f"{BASE_URL}/chat/completions",
                                     data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                     headers={"Content-Type": "application/json; charset=utf-8"})
        try:
            with urllib.request.urlopen(req, timeout=1800) as r:
                data = json.loads(r.read().decode("utf-8"))
            msg = data["choices"][0]["message"]
            think_len = len(msg.get("reasoning_content") or "")
            print(f"[{effort:<6}] 思考 {think_len:>5} 字符 | 答案: "
                  f"{(msg.get('content') or '').strip()[:60]}")
        except urllib.error.HTTPError as e:
            print(f"[{effort:<6}] HTTP {e.code}")


if __name__ == "__main__":
    print("=" * 62)
    print(" 1) 模型列表")
    print("=" * 62)
    example_list_models()

    print()
    print("=" * 62)
    print(" 2) 标准库调用（含思维链与速度统计）")
    print("=" * 62)
    example_stdlib()

    print()
    print("=" * 62)
    print(" 3) 思考开关与深度")
    print("=" * 62)
    example_thinking_control()

    # 图片 / 视频示例需要先准备素材，取消注释并按需改路径：
    # example_image("images/demo.png")
    # example_video("images/demo.mp4")

    # 若已安装 openai / requests，可取消下面注释体验更多功能：
    # example_openai_sdk()
    # example_stream_requests()
