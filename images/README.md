# images/ — 本地媒体目录（`--media-path`）

服务启动时会把这个目录作为 `--media-path` 传给它，用于支持 `file://` 形式的本地媒体引用。

## 用法

把图片或视频放进本目录，然后在请求里用相对路径引用：

```python
# 图片
{"type": "image_url",  "image_url":  {"url": "file://photo.png"}}

# 视频
{"type": "video", "input_video": {"url": "file://clip.mp4"}}
```

服务端会去 `images/photo.png`、`images/clip.mp4` 取文件。

> 目录位置由 `server-config.psd1` 里的 `Vision.MediaPath` 决定（默认 `images`）。
> 如果该目录不存在，`start-server.ps1` 会自动创建。

## 三种媒体传法对比

| 传法 | 写法 | 适用场景 |
|---|---|---|
| base64 | `{"url": "data:image/png;base64,<B64>"}` | 最通用，客户端直接读文件编码，无需服务端配置 |
| 本地文件 | `{"url": "file://photo.png"}` | 服务端本机已有文件，省去 base64 编码开销 |
| 远程 URL | `{"url": "https://example.com/a.jpg"}` | 文件在公网 |

> 视频三种都支持：`{"type": "input_video", "input_video": {"data": "<B64>"}}`、
> `{"url": "file://clip.mp4"}`、`{"url": "https://..."}`。
> 注意是 `input_video` 而不是 `video` —— 类型名写错会返回
> `HTTP 400 unsupported content[].type`。

## ⚠ 安全提示

`--media-path` 允许客户端读取**本目录下任意文件**，因此：

- 不要把这个目录指向敏感位置（如用户主目录、系统目录）。
- 服务默认监听 `0.0.0.0`（局域网可访问）。**局域网共享时请在 `server-config.psd1`
  里设置 `Server.ApiKey`**，否则同网段任何人都能通过 `file://` 读取本目录内容。
- 不打算用 `file://` 的话，把 `Vision.MediaPath` 设为 `""` 即可关闭该功能。

## 目录内容不纳入版本控制

`.gitignore` 已忽略本目录下的所有文件，只保留这个 `README.md`。
放进来的测试素材不会被提交。
