#!/bin/bash
# 本工程的 flutter/dart 包装脚本。
#
# 为什么要包一层：这个工程的工具链装在隔离目录里，必须带上 PUB_CACHE /
# PUB_HOSTED_URL / FLUTTER_STORAGE_BASE_URL 三个环境变量。少带一个不会立刻报错——
# `pub get` 会**静默**把依赖重解析到默认的 ~/.pub-cache，而沙箱不允许 Gradle
# 往那里写；于是错误要等到 `flutter build apk` 的 CMake 阶段才冒出来，
# 报的是 `:jni:configureCMake... Operation not permitted`，看起来和 pub 毫无关系。
# 这个坑真实发生过一次，排查成本不低，所以从入口处堵掉。
#
# 用法（等价于直接调 flutter，只是环境一定是对的）：
#   tool/f.sh pub get
#   tool/f.sh analyze
#   tool/f.sh build apk --release --split-per-abi
#   tool/f.sh test                 # 纯 Dart 单测，走 dart test（不拉 flutter_tester，快）
#   tool/f.sh dart <args...>       # 任意 Dart 命令
#
# 注意：`flutter dart test` 是**不存在的**——flutter 没有 `dart` 子命令，它会打印
# "Could not find a command named dart" 然后退出 0。如果调用方再 `| tail -3`，
# 这个失败会被完全吃掉，看起来"测试跑过了"。所以下面把 dart 单独路由到内置 SDK。
set -euo pipefail

# Flutter 安装根目录 F：优先取环境变量 F；未设置时从 PATH 上的 flutter 自动推导，
# 再退到 ~/flutter。兼容两种布局——标准布局（F 即 SDK 根，$F/bin/flutter）与
# 「SDK 外再套一层目录」的布局（$F/flutter/bin/flutter，pub 缓存在 $F/pub_cache）。
if [ -z "${F:-}" ]; then
  if _fb="$(command -v flutter)"; then
    F="$(dirname "$(dirname "$_fb")")"
  elif [ -x "$HOME/flutter/bin/flutter" ]; then
    F="$HOME/flutter"
  else
    echo "f.sh: 找不到 flutter，请设置 F=<flutter 安装根目录> 后重试" >&2
    exit 1
  fi
fi
if [ -x "$F/flutter/bin/flutter" ]; then
  FLUTTER="$F/flutter/bin/flutter"
  DART="$F/flutter/bin/cache/dart-sdk/bin/dart"
elif [ -x "$F/bin/flutter" ]; then
  FLUTTER="$F/bin/flutter"
  DART="$F/bin/cache/dart-sdk/bin/dart"
else
  echo "f.sh: $F 下找不到 flutter 可执行文件" >&2
  exit 1
fi

export PUB_CACHE="$F/pub_cache"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# `test` 默认走 dart test：本工程的单测都是纯 Dart（只 import package:test），
# 用 dart 跑省掉 flutter_tester 的启动开销，也更容易在沙箱里稳定通过。
if [ "${1:-}" = "test" ]; then
  set -- dart test
fi

if [ "${1:-}" = "dart" ]; then
  shift
  exec "$DART" "$@"
fi

exec "$FLUTTER" "$@"
