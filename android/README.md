# maa-cli for Android·Termux

由 maa-cli 仓库的 Build Android workflow 构建。

- maa-cli: v{{CLI_VERSION}}
- MaaCore: {{MAA_VERSION}}（取自官方 MAAComponent-{{MAA_VERSION}}-android-{{ABI}}.tar.gz）
- 资源：已随包附带（官方组件包内含）

包内结构：

```text
bin/maa                      maa-cli 可执行文件
lib/libMaaCore.so            MaaCore
lib/libMaaUtils.so           依赖
lib/libopencv_world4.so      依赖
lib/libonnxruntime.so        依赖
lib/libc++_shared.so         C++ 运行时
share/maa/resource/          游戏资源
maa-android-connect.sh       连接辅助脚本（Termux 里一键连本机 adb）
README.md                    本文档
```

## 安装

```bash
# 1. 依赖：adb（MaaCore 用它连游戏）
pkg install -y android-tools

# 2. 解包到 maa-cli 的标准位置
mkdir -p ~/.local/share/maa ~/.local/bin
cp -r bin/maa ~/.local/bin/ && chmod +x ~/.local/bin/maa
cp lib/*.so ~/.local/share/maa/lib/ 2>/dev/null || {
  mkdir -p ~/.local/share/maa/lib && cp lib/*.so ~/.local/share/maa/lib/
}
cp -r share/maa/resource ~/.local/share/maa/

# 3. 验证
maa version
```

> 不需要设置 `LD_LIBRARY_PATH`：包内所有库都已设好 `RPATH=$ORIGIN`（`bin/maa` 为 `$ORIGIN/../lib`），maa-cli 能自行找到同目录的 MaaCore 及其依赖。
>
> 请**不要**用 `LD_LIBRARY_PATH` 指到本包的 lib 目录：该变量会传给子进程，导致 MaaCore 调用的 `adb` 误加载本包的 `libc++_shared.so`（NDK 版），报 `CANNOT LINK EXECUTABLE "adb": cannot locate symbol`，最终表现为连接失败。

若 `~/.local/bin` 不在 PATH：

```bash
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc && . ~/.bashrc
```

## 连接游戏（必须走 adb）

⚠️ Termux 里**无法使用** Android 原生控制，只能通过 adb。原因：原生控制要求 MaaCore 通过 `libbridge.so` 提供截图与输入注入，而官方那份 `libbridge.so` 是 Android App 的 JNI 桥，依赖 MediaProjection（虚拟显示）+ AccessibilityService，需要 Android App 运行时；Termux 是纯 Linux 进程，没有这些能力。（这也是包内不含 `libMaaAndroidNativeControlUnit.so` 的原因——那是给 MAA-Meow 这类 APK 项目用的。）

### 用附带脚本自动连接（推荐）

```bash
./maa-android-connect.sh
```

脚本按成功率依次尝试三种方式：

1. **mDNS 发现**（无需 root，要求此前配对过无线调试）
2. **root 设固定端口**（有 su 时最省事）：`setprop service.adb.tcp.port 5555` + 重启 adbd，然后连 127.0.0.1:5555
3. **扫描常见端口**

全部失败时会提示查看本文档的「手动连接」一节。也可指定单一方式：

```bash
./maa-android-connect.sh --root      # 只试 root 方式
./maa-android-connect.sh --mdns      # 只试 mDNS
./maa-android-connect.sh --verbose   # 看详细过程
```

### 手动连接

```bash
# 无 root：用系统「无线调试」（需配对码）
adb pair 127.0.0.1:<配对端口>
adb connect 127.0.0.1:<调试端口>

# 有 root：直接设固定端口，免配对
su -c 'setprop service.adb.tcp.port 5555; setprop ctl.restart adbd'
adb connect 127.0.0.1:5555
```

连上后即可使用：

```bash
maa startup                        # 开始唤醒
maa fight 1-7 --times 5            # 刷理智
```

> MAA 只支持 16:9 分辨率。识别异常时先 `wm size` 查看，必要时 `wm size 1080x1920` 调整（部分设备需 root）。

## 已知限制

- **必须用 adb**：如上，无法用原生控制，稳定性与性能受 adb 回环影响。
- **无 git2 资源后端**：maa-cli 以 `--no-default-features --features core_installer` 构建（git2 的 openssl 依赖无法在 Android 交叉编译）。影响：`maa update` 走 HTTP 而非 git 拉取，功能可用。
- 若只用官方 MAA-Meow 就够了，可优先考虑它（原生控制、免 adb、带 GUI）。
