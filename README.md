# 阅读 iOS（Legado 书源兼容版）

把 [refgd/legado](https://github.com/refgd/legado)（安卓「阅读R」）的核心能力，用
**Swift / SwiftUI** 重写成一套原生 iOS 工程。书源 JSON 与安卓「阅读」通用，可直接导入。

> 本软件不提供任何书籍内容，只提供解析规则；书源由使用者自行导入，请支持正版。

## 已经实现

| 模块 | 说明 |
| --- | --- |
| 书源导入 | 粘贴 JSON、从剪贴板、从文件（.json/.txt）、从网址导入；同名书源自动更新 |
| 书源管理 | 启用/禁用、滑动删除、搜索、规则查看、单源搜索调试 |
| 搜索 | 多书源并发搜索（默认 5 并发），结果按书源实时返回 |
| 详情 | 书名/作者/分类/字数/封面/简介/最新章节，目录地址解析 |
| 目录 | 分页目录（nextTocUrl）、正序倒序、去重、本地缓存 |
| 正文 | 正文规则、下一页拼接（nextContentUrl）、标题规则、全文替换规则、本地缓存 |
| 主界面 | 与安卓版一致：五页横滑（书架/发现/订阅/阅读记录/我的）+ 48pt 悬浮毛玻璃底栏（23pt 图标、切换闪现 52×40 指示器）+ 右下 48pt 搜索圆钮 |
| 书架 | 24sp 大标题 + 38pt 分组标签栏；列表（默认，66×90 封面、书名/作者/更新时间/已读章节/最新章节）与 2~5 列网格；长按进详情、刷新目录、移出书架 |
| 阅读器 | 仿原版翻页排版（CoreText 分页）、字号/字体/字间距/行距/段距/页边距/缩进、6 种主题、目录、上一章/下一章、进度保存 |
| 我的 | 四组卡片式设置（内容与规则 / 外观与 AI / 同步与服务 / 工具与关于），未移植项明确标注 |
| 阅读界面 | 顶部章节名 + 换源胶囊；底部「上一章 / 进度 / 下一章」+ 功能行（目录 / 朗读 / 界面 / 设置）；页眉时间·电量，页脚章节名·页码·进度 |
| 设置 | 外观（跟随系统/浅色/深色）、阅读排版、替换净化、缓存清理 |

## 规则引擎覆盖范围

移植了 Legado 的 `AnalyzeRule` 规则语义：

- CSS / 标签规则：`@css:`、`@@`、`div.book@a@href`、`@text`、`@textNodes`、`@ownText`、`@html`、`@all`、属性取值
- 索引写法：`div.book.0`、`div.book!0`、`div.book[-1]`、`div.book[0:3]`
- 组合符：`&&`（合并）、`||`（取第一个非空）、`%%`（交叉合并）
- JSON 规则：`@json:`、`$.data[*].name`、`$..name`、`$['key']`
- 正则替换：`选择器##正则##替换`、`###`（只替换第一个匹配）
- JS 规则：`<js>…</js>`、`@js:`、`{{…}}`、`@get:{变量}`、`@put:{…}`，基于 JavaScriptCore，
  提供 `java.ajax / get / put / base64Encode / base64Decode / md5Encode / timeFormat / log`
- URL 规则：`{{key}}`、`{{page}}`、`<js>`、`,{"method":"POST","body":"…","charset":"gbk","headers":{…}}`
- 编码：UTF-8 / GBK / GB18030 / BIG5 自动识别
- XPath：`//div[@class='x']//a/@href` 这类常见写法会转换成 CSS 执行

## 构建（需要一台 Mac）

环境：macOS + Xcode 15 或更高（Xcode 16 也可），iOS 16+ 真机或模拟器。

1. 打开 `LegadoIOS.xcodeproj`
2. 选中 `LegadoIOS` target → Signing & Capabilities → 选择你自己的 Apple ID Team
3. 改掉 `Bundle Identifier`（默认 `com.legado.ios.reader`，重名会签名失败）
4. 连上 iPhone，运行

免费 Apple ID 也能装，但证书 7 天过期，需要重新运行一次；想长期使用请用付费开发者账号
（或用 AltStore / TrollStore 之类的自签工具）。

### 没有 Mac 的替代方案

仓库里带了 GitHub Actions 流水线（`.github/workflows/build-ios.yml`）：把工程推到 GitHub，
在 Actions 里手动运行 `Build iOS`，会产出一个**未签名**的 `LegadoIOS.ipa` 工件。
未签名的 ipa 需要用 Sideloadly / AltStore / TrollStore 之类的工具自签后安装（一般仍需一台电脑）。

如果 Xcode 打不开工程，可以改用 XcodeGen 重新生成：

```bash
brew install xcodegen
xcodegen generate
open LegadoIOS.xcodeproj
```

工程里没有任何第三方二进制依赖：HTML 解析用的是随仓库附带的
[SwiftSoup](https://github.com/scinfu/SwiftSoup) 源码（MIT），JS 用系统的 JavaScriptCore。

## 首次使用

1. 进入「书源」→ 导入书源（网络上有很多「阅读 3.0 书源」合集 JSON）
2. 回到「搜索」，输入书名或作者
3. 点结果进详情，加入书架或直接试读
4. 书架里点书直接续读

## 目录结构

```
LegadoIOS/
  App/        入口与全局状态（AppModel）
  Models/     书源、书籍、章节、阅读设置等数据模型（兼容 Legado JSON 字段）
  Core/       纯逻辑层：网络、编码、规则引擎、URL 解析、抓取引擎、存储
  UI/         SwiftUI 界面：书架、搜索、详情、阅读器、书源、设置
  Resources/  Info.plist、Assets（App 图标、强调色）
Vendor/SwiftSoup/   HTML 解析（vendored 源码）
Tests/        规则引擎单元测试（在 macOS/Linux 上可跑）
tools/        工程文件生成脚本
```

## 开发与验证

`Core` 与 `Models` 是纯 Swift，不依赖 UIKit，可以在 macOS/Linux 上直接编译和测试：

```bash
swift build
swift test
```

改了文件后如果 Xcode 工程里没有，重新执行：

```bash
python3 tools/gen_xcodeproj.py
```

## 已知限制（和安卓原版的差距）

- XPath 只支持常见表达式，`following-sibling`、`count()`、`|` 等会明确报「不支持」
- 需要 `webView` 的书源按普通 HTTP 请求处理（登录态、动态渲染类站点可能拿不到内容）
- 没有实现：发现页/探索、EPUB/TXT 本地导入、音频与视频书源、漫画、段评、换源、
  书源编辑器、阅读手势翻页、听书后台播放
- 正则 JS 依赖 JavaScriptCore 的 Rhino 兼容层，部分使用 `Packages.*`、`org.jsoup` 等
  Java 库的复杂 JS 规则无法运行
- 本仓库的 UI 层在编写环境（Linux）里没有 Xcode，无法真正编译验证；Core 层已通过
  编译与单元测试。首次用 Xcode 打开时如果遇到编译错误，多半是 UI 层的小问题，欢迎提 issue。

## 许可

- 本项目代码：MIT
- `Vendor/SwiftSoup`：MIT，版权归 SwiftSoup 作者所有，见 `Vendor/SwiftSoup/LICENSE.txt`
- 书源规则与「阅读」生态归各自作者所有
