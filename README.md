# 知行快传 · LanDrop

局域网点对点文件传输工具,支持 macOS / iOS / Windows。Flutter 实现,Para 风格 UI。

## 特性

- **零服务器中转** — 局域网直连,文件不上云
- **自动发现** — UDP 组播公告 + HTTP 子网扫描兜底
- **多文件/文件夹** — 保留目录结构,批量传输
- **拖拽投放** — 桌面端直接把文件拖进窗口
- **传输控制** — 实时进度、速度、剩余时间;可中途取消
- **接收策略** — 每次询问 / 全部自动 / 仅收藏设备自动
- **传输历史** — 记录已完成的任务,桌面端可定位到访达

## 运行

```bash
# macOS
flutter run -d macos

# iOS (需要真机/模拟器)
flutter run -d 岛憩的iPhone

# Windows (需要 Windows 开发环境)
flutter run -d windows
```

## 协议设计

### 发现层 (UDP)

- **端口**: 54321 (可配置)
- **组播地址**: 224.0.0.180
- **公告格式**:
  ```json
  {
    "fingerprint": "设备指纹(32 字节 hex)",
    "alias": "设备名",
    "deviceType": "laptop|phone|tablet|desktop",
    "ip": "192.168.1.100",
    "port": 54322,
    "model": "macOS 26.5",
    "announce": true
  }
  ```
- **心跳**: 每 5 秒公告一次,15 秒未收到视为离线
- **响应**: 收到 `announce: true` 时单播回一份自己的信息

### 传输层 (HTTP)

HTTP 明文传输(局域网内,降低实现复杂度)。

#### 端点

1. **GET `/api/v1/info`** — 返回设备信息(子网扫描用)
2. **POST `/api/v1/prepare`** — 发起传输请求
   - 请求体: `{ device: {...}, files: [{id, name, size, relativePath}] }`
   - 响应体: `{ sessionId, tokens: {fileId: token} }`(每个文件一个一次性令牌)
   - 接收方弹窗确认,拒绝返回 403
3. **POST `/api/v1/upload?session=&file=&token=`** — 上传单个文件
   - Body 是文件原始二进制流
   - 令牌一次性,防止重复上传
4. **POST `/api/v1/cancel?session=`** — 发送方取消

#### 安全措施

- **路径清洗**: `relativePath` 中的 `..`、盘符、非法字符、Windows 保留名全部过滤
- **令牌验证**: 每文件一个随机令牌,防止会话劫持
- **接收确认**: 默认需用户点确认,避免自动接收恶意内容

## 项目结构

```
lib/
├── core/          # 协议实现
│   ├── discovery.dart          # UDP 发现 + 子网扫描
│   ├── receive_server.dart     # HTTP 接收服务
│   └── send_client.dart        # HTTP 发送客户端
├── models/        # 数据模型
│   ├── device.dart             # 设备信息
│   ├── transfer.dart           # 传输任务与文件
│   └── settings.dart           # 用户设置
├── services/      # 工具服务
│   ├── storage.dart            # 零依赖 JSON 持久化
│   └── file_service.dart       # 文件选择、目录解析
├── state/         # 状态管理
│   └── app_state.dart          # 核心状态(provider)
├── ui/            # 界面
│   ├── theme.dart              # Para 风格主题
│   ├── widgets.dart            # 通用组件
│   ├── solar_icons.dart        # 图标字体(生成)
│   ├── receive_gate.dart       # 接收请求弹窗
│   └── pages/
│       ├── devices_page.dart   # 设备列表 + 文件选择
│       ├── history_page.dart   # 传输记录
│       ├── settings_page.dart  # 设置
│       └── transfer_sheet.dart # 传输详情
└── utils/
    └── formats.dart            # 格式化工具

assets/fonts/SolarIcons.ttf     # 图标字体(70 个字形)
tool/gen_solar_font.py          # 从 @iconify-json/solar 生成图标
```

## 依赖

- `provider` — 状态管理
- `file_picker` — 跨平台文件选择器
- `desktop_drop` — 桌面端拖拽投放

## 平台配置

### macOS

沙盒权限 (`macos/Runner/*.entitlements`):
- `com.apple.security.network.client` — 发起连接
- `com.apple.security.network.server` — 监听端口
- `com.apple.security.files.user-selected.read-write` — 读写用户选择的文件

### iOS

Info.plist 必须添加:
- `NSLocalNetworkUsageDescription` — 本地网络访问说明
- `NSBonjourServices` — Bonjour 服务声明(避免系统拦截 UDP)

**已知限制**: iOS 14+ 对原始组播有 entitlement 限制,本 App 用 Bonjour 声明规避,实测可用。若仍被拦,子网扫描兜底。

### Windows

无需额外配置,Flutter 生成的默认 manifest 已足够。

## 为什么不用 LocalSend 协议

LocalSend 协议优秀,但默认走 HTTPS 自签证书。纯 Dart 生成证书需要 `basic_utils` 等依赖,且首次配对需用户点「信任」。自研协议走 HTTP,局域网内可接受(无互联网暴露),代码也更简单。

## 许可

本项目代码基于 MIT 许可开源。Solar 图标集基于 CC BY 4.0 授权。
