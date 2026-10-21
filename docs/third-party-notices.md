# 来源与分发说明

本页记录 2026-10-21 对当前源码、本机参考材料及公开分发条款的核查结果，不为未明确授权的部分另行指定许可证。

## 原项目与本 Fork

- 本 Fork 基于 [Pzzzzz5142/FH-Radio-Studio](https://github.com/Pzzzzz5142/FH-Radio-Studio)，保留已有提交历史与来源。
- 当前受 Git 管理的源码树未发现根目录 LICENSE；本 Fork 没有擅自添加覆盖整个项目的 MIT、GPL 或其他许可证。
- 修改说明和 Vibe Coding 声明仅针对本 Fork 的扩展工作，不替原作者声明开发方式、测试水平或授权范围。

## SeamlessLoopMusic 原生引擎

- 来源：[CPUrising/seamless-loop-music](https://github.com/CPUrising/seamless-loop-music)。当前适配参考便携版 1.11.0 的 `loopfinder.dll`。
- 当前 DLL 与官方 1.11.0 附件的 SHA256 一致；对应标签的源码提交为 `8dfc00c8e9a6781babd0ba3a06e68228db5a3267`。
- 顶层自有代码为 MIT；原生工程静态链接 aubio（GPL-3.0-or-later）、KissFFT（BSD-3-Clause）和解码组件（MIT／MIT-0 等），不将整个 DLL 统一描述为 MIT。
- 已整理[原生引擎分发材料](licenses/seamless-loop-music/README.md)，包括各组件许可证、版权声明、来源校验、重建脚本及实际验证记录。打包工具同时附上固定提交的完整源码 ZIP，用户可离线取得。
- 对未修改源码的重建已通过，重建 DLL 与官方 DLL 的 `.text` 代码段相同；采样率与声道验证见材料中的记录。该材料不为整个应用重新指定许可证。

## 音频工具与内容

- ffmpeg、vgmstream、FMOD／FSBank，以及其他运行库分别遵循自身的授权，不纳入本 Fork 自行指定的统一许可证。
- 软件具备下载或调用工具的能力，不等于本 Fork 已获得对其任意重新打包的授权。
- 本仓库不上传个人歌曲、游戏资源、模型权重、已登录账号数据或本机运行环境。塞壬唱片入口不改变歌曲、封面及相关内容的权利归属。

## 发布材料

源码与文档可以追溯到具体 Git 提交；测试和检查结果应注明日期、范围及未覆盖部分。二进制打包需另行完成环境构建、依赖来源核对和实际运行验证，不能把旧便携包直接作为新源码的构建产物。

### 当前 Windows 测试包的公开分发检查

- 原项目的工具安装与发行构建也使用同一组 FMOD／FSBank 组件；本 Fork 继承这些调用，没有将 FMOD 改为新依赖。已检查的上游 `v0.2.1-rc.1` 中 `fsbankcl.exe` 的 SHA256 与当前工具相同。
- FMOD 官方 [EULA](https://www.fmod.com/legal) 的 1.3 条对 SDK 文件分发有限制，1.2 条也包含工具集分发条件。目前尚未核实这份旧工具包的具体再分发授权；这不等于断言原作者无权分发，也不能仅凭镜像存在推定授权自动覆盖本 Fork。
- 原生循环引擎的来源、对应源码和组件许可材料已补齐到打包流程，其算法 DLL 保持官方原件；FMOD 的授权核对仍作为独立问题记录。
- FFmpeg、vgmstream、mpv、Python、Flutter、模型权重及其他随包组件也需保留各自适用的许可、来源及必要的源码材料，不能将其统一归为本项目许可证。
- 因此，现有本地完整测试 ZIP 不能直接等同于已完成公开分发检查的附件。公开 Release 的附件范围以具体发布记录为准；本机验证包与公开发布包分开管理。
