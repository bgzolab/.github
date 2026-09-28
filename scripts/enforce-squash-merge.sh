#!/usr/bin/env bash
#
# 将组织下所有仓库的合并方式统一为「只允许 squash」。
#
# 统一设置的仓库选项：
#   allow_merge_commit          = false      # 禁止 merge commit
#   allow_rebase_merge          = false      # 禁止 rebase merge
#   allow_squash_merge          = true       # 只允许 squash merge
#   squash_merge_commit_title   = PR_TITLE   # squash 提交标题取 PR 标题
#   squash_merge_commit_message = PR_BODY    # squash 提交正文取 PR 描述
#
# 不修改 delete_branch_on_merge（保持现状）。
#
# 用法：
#   scripts/enforce-squash-merge.sh                    # 对默认组织 bgzolab 实际执行
#   scripts/enforce-squash-merge.sh --org other-org    # 指定组织
#   scripts/enforce-squash-merge.sh --dry-run          # 只列出将被修改的仓库
#
# 依赖：gh（已登录，且对目标组织的仓库有 admin 权限）
# 说明：
#   - 脚本是幂等的，可以随时重复执行。
#   - 已归档的仓库会被跳过（归档仓库为只读状态，PR 本身也无法合并）。
#   - 新建仓库不会自动应用这些设置，需要重跑本脚本。
#   - 更彻底的做法是升级到 GitHub Team 后使用组织级 ruleset，详见 docs/merge-settings.md。
set -euo pipefail

readonly DEFAULT_ORG="bgzolab"
readonly ORG_REPOS_PER_PAGE=100

ORG="$DEFAULT_ORG"
DRY_RUN=0

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      ORG="${2:?--org 需要参数}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      echo "使用 --help 查看用法。" >&2
      exit 2
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "缺少依赖：gh（GitHub CLI）" >&2
  exit 1
fi

errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

echo "组织：$ORG"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "模式：dry-run（只列出仓库，不修改）"
else
  echo "模式：实际执行"
fi
echo

total=0
ok=0
skipped=0
failed=0

while IFS=$'\t' read -r name archived; do
  [[ -z "$name" ]] && continue
  total=$((total + 1))

  if [[ "$archived" == "true" ]]; then
    printf '跳过  %-48s（仓库已归档）\n' "$name"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '待改  %-48s\n' "$name"
    continue
  fi

  if gh api -X PATCH "/repos/$ORG/$name" \
      -F allow_merge_commit=false \
      -F allow_rebase_merge=false \
      -F allow_squash_merge=true \
      -F squash_merge_commit_title=PR_TITLE \
      -F squash_merge_commit_message=PR_BODY \
      >/dev/null 2>"$errfile"; then
    printf '完成  %-48s\n' "$name"
    ok=$((ok + 1))
  else
    err="$(head -n 1 "$errfile")"
    if [[ "$err" == *"HTTP 451"* ]]; then
      printf '跳过  %-48s（被 GitHub 封锁，HTTP 451）\n' "$name"
      skipped=$((skipped + 1))
    else
      printf '失败  %-48s（%s）\n' "$name" "$err"
      failed=$((failed + 1))
    fi
  fi
done < <(gh api --paginate "/orgs/$ORG/repos?per_page=$ORG_REPOS_PER_PAGE" \
  --jq '.[] | [.name, (.archived | tostring)] | @tsv')

echo
echo "总计 ${total} 个仓库：成功 ${ok}，跳过 ${skipped}，失败 ${failed}"

if [[ $failed -gt 0 ]]; then
  exit 1
fi
