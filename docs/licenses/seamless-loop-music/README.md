# SeamlessLoopMusic 原生引擎分发材料

本目录对应 **CPUrising / SeamlessLoopMusic v1.11.0** 官方便携版中的 `loopfinder.dll`。

| 项目 | 固定版本／校验值 |
| --- | --- |
| 源码提交 | `8dfc00c8e9a6781babd0ba3a06e68228db5a3267` |
| DLL SHA256 | `c32f872e30d9c4ff17a322a1a2a2dda35c3ea488cd0bcfa10a8ebeb8ca871585` |
| 完整源码 ZIP SHA256 | `5b98a2eb1eeecf2e386116064005f4b6fb8657f74009eedd0101eb7607257cc7` |
| 官方附件 | [SeamlessLoopMusic-Portable-1.11.0.zip](https://github.com/CPUrising/seamless-loop-music/releases/download/v1.11.0/SeamlessLoopMusic-Portable-1.11.0.zip) |
| 固定提交源码 | [完整源码归档](https://github.com/CPUrising/seamless-loop-music/archive/8dfc00c8e9a6781babd0ba3a06e68228db5a3267.zip) |

当前 DLL 已与官方便携附件中的 DLL 做 SHA256 比对，一致。源码依据为同一官方版本标签对应的提交；保留官方 DLL，不修改引擎算法。

## 组件与许可

| 组件 | 许可 | 随附文件 |
| --- | --- | --- |
| SeamlessLoopMusic 自有代码 | MIT | `SeamlessLoopMusic-MIT.txt` |
| aubio，静态链接 | GPL-3.0-or-later | `aubio-GPL-3.0.txt`、`aubio-AUTHORS.txt`、源码内版权头 |
| KissFFT，静态链接 | BSD-3-Clause | `KissFFT-COPYING.txt`、`KissFFT-BSD-3-Clause.txt` |
| dr_wav、dr_flac、dr_mp3 | MIT-0／公有领域双许可，采用 MIT-0 | 三份 `dr_*-LICENSE.txt` |
| stb_vorbis，静态链接 | MIT／公有领域双许可，采用 MIT | `stb_vorbis-LICENSE.txt` |

MIT 只描述相应作者的代码，不替代已链接 aubio 的 GPL 条件。以上保留各自条款，不为整个 FH Radio Studio 仓库重新指定许可证。继续分发原生二进制时，应同时提供本目录和对应源码归档，并遵守适用条款。

KissFFT 的源码版权头声明 BSD-3-Clause，但原生工程中未附其引用的 COPYING 文件；这里补入 [KissFFT 131.1.0 的官方声明](https://github.com/mborgerding/kissfft/tree/131.1.0)，记录补充材料来源，不据此断言原生工程使用了该版本的全部实现。

## 对应源码与重建

Windows 分发包在同目录附有：

`SeamlessLoopMusic-8dfc00c8e9a6781babd0ba3a06e68228db5a3267-source.zip`

它是未经改写的固定提交完整归档，包括 `loopfinder/`、aubio 源码、KissFFT、解码头文件、C API 和 CMake 构建文件。Git 仓库不重复存储此 ZIP；打包工具按校验值取得归档并将它直接放进 Windows 包，用户可以离线查看，无需申请访问。

在安装 Visual Studio 2022 C++ 工具、Windows SDK 和 CMake 的 Windows x64 环境执行：

```powershell
.\rebuild.ps1 -BuildDirectory .\native-rebuild
```

脚本先核对归档 SHA256，再解压并执行上游 CMake Release 构建，启用原生测试入口。也可使用 `-CMake` 指定 CMake 路径。输出在 `native-rebuild/build/Release/`。它不会替换应用当前使用的 DLL。

本次已用该未修改源码在 MSVC 19.44 / Windows x64 实际编译，重建 DLL 的 `.text` 可执行代码段与官方 DLL 一致。48 kHz 立体声、44.1 kHz 单声道和静音输入的端点结果均与官方 DLL 一致，记录见 `native-validation.json`。构建路径与 PE 元数据仍会影响完整 DLL 字节，因此不承诺整个二进制逐字节复现。

## 运行依赖

该 DLL 导入 MSVC C++ 和 OpenMP 运行库。打包时从 Visual Studio 的可再分发运行库复制 `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`、`vcomp140.dll`，与原生 DLL 放在一起，供独立 Python 进程加载。这些运行库遵循 Microsoft 自身条款，不属于上述开源许可证。

构建及来源校验结果见应用原生引擎目录的 `distribution-manifest.json`。许可证与源码记录见本目录的 `provenance.json`。
