# 来源与分发说明

本页记录 2026-10-21 对当前源码、本机参考材料及公开分发条款的核查结果，不为未明确授权的部分另行指定许可证。

## 原项目与本 Fork

- 本 Fork 基于 [Pzzzzz5142/FH-Radio-Studio](https://github.com/Pzzzzz5142/FH-Radio-Studio)，保留已有提交历史与来源。
- 当前受 Git 管理的源码树未发现根目录 LICENSE；本 Fork 没有擅自添加覆盖整个项目的 MIT、GPL 或其他许可证。
- 修改说明和 Vibe Coding 声明仅针对本 Fork 的扩展工作，不替原作者声明开发方式、测试水平或授权范围。

## SeamlessLoopMusic 原生引擎

- 来源：[CPUrising/seamless-loop-music](https://github.com/CPUrising/seamless-loop-music)。当前适配参考便携版 1.11.0 的 `loopfinder.dll`。
- 顶层 LICENSE 为 MIT；检查到的原生 CMake 配置将 aubio 静态链接到 loopfinder，aubio 的 COPYING 文件为 GPL-3.0。
- 因而仅附 SeamlessLoopMusic 顶层 MIT 文本，不足以说明原生二进制中全部组件的许可情况。还需核对 aubio、KissFFT、dr_libs、stb_vorbis 等实际使用版本的许可证与源码材料。
- 本源码仓库没有附带该 DLL，也没有将其声明为全部按 MIT 授权。公开二进制包前，应按实际打包的组件补全相应材料。

## 音频工具与内容

- ffmpeg、vgmstream、FMOD／FSBank，以及其他运行库分别遵循自身的授权，不纳入本 Fork 自行指定的统一许可证。
- 软件具备下载或调用工具的能力，不等于本 Fork 已获得对其任意重新打包的授权。
- 本仓库不上传个人歌曲、游戏资源、模型权重、已登录账号数据或本机运行环境。塞壬唱片入口不改变歌曲、封面及相关内容的权利归属。

## 发布材料

源码与文档可以追溯到具体 Git 提交；测试和检查结果应注明日期、范围及未覆盖部分。二进制打包需另行完成环境构建、依赖来源核对和实际运行验证，不能把旧便携包直接作为新源码的构建产物。

### 当前 Windows 测试包的公开分发检查

- 本地验证包包含 `fsbankcl.exe`、FMOD 运行库及相关 SDK 组件。FMOD 官方 [EULA](https://www.fmod.com/legal) 的 1.3 条将 SDK 文件分发例外限定为引擎运行库，1.2 条另有限制工具集分发的条件。当前未发现本项目对 SDK 工具进行公开再分发的单独授权；其他 GitHub 仓库中的镜像链接不等于此项授权。
- 当前 `loopfinder.dll` 附有 SeamlessLoopMusic 顶层 MIT 文本，但所检查的原生工程静态链接 aubio，仍需按实际二进制补齐对应许可证、源码版本与构建材料。
- FFmpeg、vgmstream、mpv、Python、Flutter、模型权重及其他随包组件也需保留各自适用的许可、来源及必要的源码材料，不能将其统一归为本项目许可证。
- 因此，现有本地完整测试 ZIP 不能直接等同于已完成公开分发检查的附件。公开 Release 的附件范围以具体发布记录为准；本机验证包与公开发布包分开管理。
