# maa-cli for Android·Termux

本包包含交叉编译的 maa-cli、官方 Android 版 MaaCore 及资源，可在 [Termux](https://termux.dev/) 中运行。版本信息可通过 `maa version` 查看。

包内结构：

```text
bin/maa                      maa-cli 可执行文件
lib/libMaaCore.so            MaaCore
lib/libMaaUtils.so           依赖
lib/libopencv_world4.so      依赖
lib/libonnxruntime.so        依赖
lib/libc++_shared.so         C++ 运行时
share/maa/resource/          游戏资源
maa-android-connect.sh       连接辅助脚本
README.md                    本文档
```

## 安装

```bash
# 依赖：adb，MaaCore 通过它连接游戏
pkg install -y android-tools

# 解压到 maa-cli 的标准位置
mkdir -p ~/.local/share/maa/lib ~/.local/bin
cp bin/maa ~/.local/bin/ && chmod +x ~/.local/bin/maa
cp lib/*.so ~/.local/share/maa/lib/
cp -r share/maa/resource ~/.local/share/maa/

maa version
```

如果 `~/.local/bin` 不在 `PATH` 中：

```bash
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc && . ~/.bashrc
```

不要设置 `LD_LIBRARY_PATH`。包内的库都已设好 `RPATH`（`lib` 下为 `$ORIGIN`，`bin/maa` 为 `$ORIGIN/../lib`），maa-cli 能自行找到同目录的 MaaCore 及其依赖。把 `LD_LIBRARY_PATH` 指向本包的 `lib` 目录会让该变量传递给子进程，导致 MaaCore 调用的 `adb` 误加载包内的 `libc++_shared.so`（NDK 版），报 `CANNOT LINK EXECUTABLE "adb": cannot locate symbol`，表现为连接失败。

## 连接游戏

Termux 无法使用 Android 原生控制，只能通过 adb 连接游戏。包内附带的 `maa-android-connect.sh` 会按成功率从高到低依次尝试 mDNS 发现、root 设固定端口和扫描常见端口：

```bash
./maa-android-connect.sh
```

也可以只尝试其中一种方式：

```bash
./maa-android-connect.sh --root      # 只试 root 方式
./maa-android-connect.sh --mdns      # 只试 mDNS
./maa-android-connect.sh --verbose   # 查看详细过程
```

全部失败时，手动连接的步骤是：

```bash
# 无 root：使用系统「无线调试」（需要配对码）
adb pair 127.0.0.1:<配对端口>
adb connect 127.0.0.1:<调试端口>

# 有 root：直接设置固定端口，无需配对
su -c 'setprop service.adb.tcp.port 5555; setprop ctl.restart adbd'
adb connect 127.0.0.1:5555
```

连上后即可使用：

```bash
maa startup                        # 开始唤醒
maa fight 1-7 --times 5            # 刷理智
```

## 已知限制

- 必须通过 adb 连接游戏，稳定性和性能受 adb 回环影响；
- 不支持 `git2` 资源后端，`maa update` 通过 HTTP 而非 git 拉取资源，功能可用；
- 不要执行 `maa install` 或 `maa update` 更新 MaaCore 及资源：包内已包含转换后的 ncnn 格式 OCR 模型，而官方分发的资源只含 onnx 格式，在 Android 上无法加载，覆盖后会导致 OCR 失败；
- MAA 只支持 16:9 分辨率，识别异常时先用 `wm size` 查看当前分辨率，必要时用 `wm size 1080x1920` 调整（部分设备需要 root）。

更详细的说明见 maa-cli 文档的[安装及编译](https://github.com/MaaAssistantArknights/maa-cli/blob/main/crates/maa-cli/docs/zh-CN/install.md)和[常见问题](https://github.com/MaaAssistantArknights/maa-cli/blob/main/crates/maa-cli/docs/zh-CN/faq.md)。
