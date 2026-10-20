# FH Radio Studio · LoopLab

面向 **Forza Horizon 6 PC 版**的自定义电台工具：导入音乐、配置歌曲切入点和循环段、编排电台、构建准备包，再写入游戏。

本仓库是 [FH Radio Studio](https://github.com/Pzzzzz5142/FH-Radio-Studio) 的扩展 Fork，以 **LoopLab** 为主要开发版本。在原项目基础上，加入 SeamlessLoopMusic 循环建议、电台扩容、时间点批量导入导出，以及更完整的歌曲编辑与播放列表操作。原项目及相关依赖的贡献归各自作者所有。

**[功能概览](docs/改动说明-精简版.md) · [详细功能与使用规则](docs/改动说明-详细版.md) · [开发文档](docs/development.md) · [参与贡献](CONTRIBUTING.md)**

## 开发说明与反馈

本 Fork 的扩展与改进由我借助 **ChatGPT 生成代码并持续调整**，全程采用 **Vibe Coding**。这是我的第一次尝试，目前只进行了有限的自动化测试和部分实际运行验证，尚未覆盖所有使用场景、游戏版本和环境，不能据此保证没有问题。

如果遇到任何问题，或有使用建议，欢迎随时在[本 Fork 的 Issues](https://github.com/buuuuuuuuuug/FH-Radio-Studio/issues) 提出。反馈时尽量附上操作步骤、错误提示和环境信息，并隐去个人路径、账号及其他敏感内容。

以上说明针对本 Fork 的扩展开发，不代表原项目作者或第三方组件的开发方式与测试水平。

## 主要功能

| 功能 | 可以做什么 |
| --- | --- |
| 音乐导入 | 导入本地音频，或浏览、试听并导入 MONSTER SIREN 塞壬唱片歌曲；保留歌曲名、艺术家、封面等信息。 |
| 手动与 AI 选点 | 使用波形、节拍和试听配置歌曲时间点；支持无 AI 工作流，也可使用本地 AI 生成候选。 |
| LoopLab 循环建议 · 实验功能 | 使用 SeamlessLoopMusic 原生引擎查找 TL/PL 循环段，支持批量分析、缓存、拼接试听及人工微调。 |
| 播放列表 | 分别编排漫游与比赛列表，支持搜索、筛选、多选、批量分配、拖动排序、保存、撤销和重做。 |
| 电台扩容 · 实验功能 | 在原版槽位之外增加自定义曲目；检查跨场景共用 bank 的实际容量和文件大小。 |
| 时间点导入导出 | 支持文本、CSV、TSV、JSON、XLSX 和 RadioInfo XML 导入；支持 CSV 导出及 48000 Hz 整数采样点。 |
| 准备包构建 | 调整响度和 Vorbis 质量，预估各电台大小；复用未变化电台的 bank，并及时清理已完成电台的构建中间文件。 |
| 界面与快捷键 | 调整表格列宽、电台布局、页面和精修窗口宽度；自定义常用快捷键与界面强调色。 |

![播放列表与歌曲池](docs/images/studio/playlist_regular.png)

## LoopLab 是什么

LoopLab 集成了 [SeamlessLoopMusic](https://github.com/CPUrising/seamless-loop-music) 的循环查找引擎，帮助寻找歌曲中适合反复播放的起点与终点。

- 在“概览 → 基础设置”启用 **SeamlessLoopMusic**。
- 无 AI 模式下可读取波形并查找循环，不要求加载重型 AI 模型。
- AI 模式保留切入点、节拍等分析，TL/PL 循环使用原生引擎候选。
- 在人工精修中选择建议、试听终点回到起点的衔接，必要时调整，再确认保存。
- 已确认时间点与分析建议分开保存；重新分析不会直接替代人工确认。

候选的匹配百分比是算法评分，不代表衔接一定自然。使用该能力需要准备兼容的 `loopfinder` 原生库；源码仓库不等同于已经配好工具链的便携程序。依赖与加载说明见 [LoopLab 技术说明](docs/seamless-loop-lab.md)。

原生库的默认位置如下；自定义工具链目录时，路径随工具链变化。请同时保留对应许可证及所需运行依赖。

- 源码开发：`.fh-radio-studio-dev/toolchain/tools/audio/seamless/loopfinder.dll`
- Windows 便携版：`toolchain/tools/audio/seamless/loopfinder.dll`

## 从导入到写入游戏

1. **创建项目**，设置 FH6 安装目录，在文件校验中创建原始备份。
2. **导入音乐**，添加本地音频或使用塞壬唱片入口。
3. **配置时间点**，使用手动、AI 或 LoopLab 建议，试听并确认下表中的四组配置，然后保存。
4. **分配电台**，安排漫游／比赛列表并保存播放列表。未配置完的歌曲可以先分配，但需要完成确认后才能构建。
5. **构建准备包**，选择响度与质量。Vorbis 质量范围为 1–100，默认 50；构建完成后可直接打开准备包目录。
6. **退出游戏后写入**，确认目标位置和受影响文件，再安装准备好的电台包。

| 配置 | 用途 |
| --- | --- |
| TD · TrackDrop | 比赛开始时的歌曲切入点 |
| PD · PostDrop | 冲线后的歌曲切入点 |
| TL · TrackLoop | 比赛循环的起点和终点 |
| PL · PostLoop | 冲线循环的起点和终点 |

TL 与 PL 各有两个端点，合计六个时间点。可启用 PL 跟随 TL，也可分别配置。

写入默认使用 `mediapc` 覆盖目录，不替换 `media` 中的原始文件；也可明确选择写入 `media`。准备包构建与游戏写入是两个步骤，**构建准备包本身不会修改游戏文件**。游戏更新后仍需重新检查文件状态与兼容性。

![人工精修界面](docs/images/studio/manual_regular.png)

## 常用操作

以下为默认设置，可在应用中修改；精修窗口与主页面的快捷键按各自场景生效。

| 操作 | 快捷键／交互 |
| --- | --- |
| 打开 TD／PD／TL／PL 人工精修 | `Ctrl + 1 / 2 / 3 / 4`，支持主键盘和数字小键盘；也可双击配置卡片 |
| 快速确认一组时间点 | `Ctrl + 右键` 点击配置卡片 |
| 保存歌曲／播放列表 | `Ctrl + S` |
| 播放列表撤销／重做 | `Ctrl + Z` / `Ctrl + Y` |
| 切换上一首／下一首 | `Shift + ↑ / ↓` |
| 快速分配电台 | 歌曲编辑页 `Ctrl + D`；分配弹窗中按 `1–9` 选择电台 |
| 精修中取当前播放位置 | `Tab` |
| 精修中临时自由放置／切换磁吸 | 按住 `Z` / `Shift + Z` |
| 波形缩放 | `Ctrl + 鼠标滚轮` |
| 退出播放列表多选 | `Esc` |

## 项目数据放在哪里

歌曲、配置和准备包放在用户选择的项目目录中，与程序源码分开管理：

```text
sources/          本地导入的音频
siren/            塞壬唱片音频与导入记录
analysis/         波形、分析、响度与时间点等数据
packages/         准备包及构建工作目录
backups/          原始备份与游戏文件记录
.fh-radio-studio/ 项目设置、播放列表及写入记录
```

构建会直接生成按槽位排列并完成响度处理的 WAV；重复槽位优先使用硬链接。每个电台的最终 bank 校验通过后释放对应 WAV／FSB 中间文件，减少临时空间占用。保留的歌曲源文件、原始备份和最终准备包仍会占用磁盘空间。

## 从源码运行

主要开发与验证环境为 **Windows x64**。需要 Git、`uv`、Flutter SDK，以及 Flutter Windows 构建要求的 Visual Studio C++ 桌面开发组件。项目默认使用 Python 3.12，Dart 版本要求见 [app/pubspec.yaml](app/pubspec.yaml)。

在 PowerShell 中执行：

```powershell
git clone --branch improve/looplab-20261020 https://github.com/buuuuuuuuuug/FH-Radio-Studio.git
cd FH-Radio-Studio
uv sync --locked
cd app
flutter pub get
flutter run -d windows
```

`app/` 是 Flutter 桌面界面，`backend/fh_radio_studio_cli/` 是 Python 执行引擎。所有 Python 产品命令通过 `uv` 运行。核心音频工具、可选 AI 环境与模型需按应用提示准备；使用 LoopLab 原生循环还需准备上述原生库。

GitHub 的源码 ZIP 不是可直接运行的 Windows 便携包。需要打包时，从仓库根目录执行：

```powershell
.\tools\build_release.ps1 -CleanBuild
```

完整环境与打包要求见 [开发文档](docs/development.md)。

## AI 与命令行

AI 可按需要启用，并非手动编辑的前提。`local-base` 为轻量兜底，`local-deep` 使用更完整的分析模型，`local-heavy` 在此基础上加入 Demucs。深度模式需要额外依赖、模型缓存和更多计算资源；最终时间点仍需试听确认。

从仓库根目录检查音频工具或分析歌曲：

```powershell
uv run fh-radio-studio check-tools
uv run fh-radio-studio analyze-audio ".\music\Example.flac" --profile local-heavy --json
```

游戏目录扫描、基线、构建与部署命令见 [CLI 工作流](docs/development.md#core-workflows)。

## 开发与贡献

提交前，在仓库根目录运行：

```powershell
uv sync --locked
.\tools\check_submission.ps1
```

检查包括格式、Python 测试、模拟游戏流程、Flutter 静态分析与界面测试。真实音频编码、重型 AI 推理和游戏内播放需要另外验证；模拟测试通过不能替代实际听感与游戏兼容性验证。

欢迎在本 Fork 提交问题或改进建议。向原项目贡献时，请先按 [贡献指南](CONTRIBUTING.md) 确定修改范围并完成验证；本 Fork 的开发与提交不会自动合并到原项目。

## 使用范围与文档

- 面向 FH6 PC 文件结构，不支持主机端；DJ 语音替换不在当前范围内。
- 电台扩容与 SeamlessLoopMusic 集成属于实验功能，受游戏版本、音源及 bank 大小等条件限制。
- 写入前关闭游戏，并保留原始备份；游戏文件更新后的基线确认流程仍需人工复核。
- 音频与第三方组件的使用、分发应遵循各自授权；本仓库不包含个人歌曲和 AI 模型权重。第三方原生引擎不能仅凭顶层许可证统一视为 MIT，见[来源与分发说明](docs/third-party-notices.md)。

| 文档 | 内容 |
| --- | --- |
| [功能概览](docs/改动说明-精简版.md) | 新增能力与应用截图 |
| [详细功能与使用规则](docs/改动说明-详细版.md) | 编辑、导入导出、电台分配等完整说明 |
| [编辑与构建工作流](docs/studio-features.md) | 数据格式、容量与构建行为 |
| [LoopLab 技术说明](docs/seamless-loop-lab.md) | 原生引擎依赖、缓存和候选含义 |
| [开发文档](docs/development.md) | 环境、架构、CLI、测试与打包 |
| [贡献指南](CONTRIBUTING.md) | 分支、提交规范与验证要求 |

## 项目来源

- **基础项目：**[FH Radio Studio](https://github.com/Pzzzzz5142/FH-Radio-Studio)，提供电台编辑、音频分析、准备包与部署工作流。
- **循环引擎：**[SeamlessLoopMusic](https://github.com/CPUrising/seamless-loop-music)，提供原生循环查找能力，其组件按自身许可证使用。
- **在线音乐入口：**[MONSTER SIREN 塞壬唱片](https://monster-siren.hypergryph.com/)，歌曲及相关内容权利归相应权利方所有。

本仓库为第三方工具的独立扩展 Fork，与游戏官方无隶属关系。
