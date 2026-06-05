#!/bin/bash
set -e

# 用法:
#   ./scripts/tag.sh 1.0.1          # 创建新版本 tag
#   ./scripts/tag.sh 1.0.1 "消息"   # 创建带消息的 tag

if [ -z "$1" ]; then
  echo "用法: $0 <version> [message]"
  echo "示例: $0 1.0.1"
  echo "示例: $0 1.0.1 '新增简体中文语言支持'"
  exit 1
fi

VERSION="$1"
MESSAGE="${2:-Release version $VERSION}"

# 确保版本号格式正确 (x.y.z)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号格式不正确，应为 x.y.z (例如: 1.0.1)"
  exit 1
fi

TAG="v${VERSION}"

# 检查 tag 是否已存在
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "错误: tag $TAG 已存在"
  echo "现有 tags:"
  git tag -l "v*.*.*"
  exit 1
fi

# 检查是否有未提交的更改
if ! git diff-index --quiet HEAD --; then
  echo "警告: 存在未提交的更改"
  git status --short
  read -p "是否继续创建 tag? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# 创建 annotated tag
echo "创建 tag: $TAG"
git tag -a "$TAG" -m "$MESSAGE"

echo "✓ Tag $TAG 创建成功"
echo ""
echo "下一步:"
echo "  1. 推送 tag: git push origin $TAG"
echo "  2. 或运行 release 脚本: ./scripts/release.sh"
