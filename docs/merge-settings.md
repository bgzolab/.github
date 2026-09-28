# 仓库合并方式：只允许 Squash

本文说明 `bgzolab` 组织下所有仓库为什么以及如何统一为「只允许 squash merge」。

## 目标

- 不允许 **merge commit**（`allow_merge_commit = false`）
- 不允许 **rebase merge**（`allow_rebase_merge = false`）
- 只允许 **squash merge**（`allow_squash_merge = true`）
- squash 提交信息：标题取 PR 标题，正文取 PR 描述
- 保留合并后分支（不开启 `delete_branch_on_merge`）

## 为什么不用「组织级开关」

GitHub 的合并方式（Allow merge commits / Allow squash merging / Allow rebase merging）是**每个仓库各自的设置**，`.github` 仓库无法给其他仓库下发规则，GitHub 也没有组织级的合并方式默认值。

更彻底的方案是使用**组织级 ruleset** 的 `pull_request` 规则限制 `allowed_merge_methods: ["squash"]`，它可以：

- 覆盖组织内**全部仓库**（含以后新建的仓库，无需重跑脚本）
- 让仓库 admin 也无法在仓库设置里改回 merge commit

但组织级 ruleset 需要 **GitHub Team 或 Enterprise 套餐**（本组织目前是 Free 套餐），且操作 token 需要 `admin:org` 权限。升级套餐后可以改为该方案，参考：
<https://docs.github.com/en/organizations/managing-organization-settings/creating-rulesets-for-repositories-in-your-organization>

## 当前方案：批量修改仓库设置

使用 [`scripts/enforce-squash-merge.sh`](../scripts/enforce-squash-merge.sh) 遍历组织下所有仓库并逐一修改设置。

```bash
# 预览会修改哪些仓库
scripts/enforce-squash-merge.sh --dry-run

# 实际执行（幂等，可重复运行）
scripts/enforce-squash-merge.sh

# 指定其他组织
scripts/enforce-squash-merge.sh --org other-org
```

依赖：`gh` 已登录，且账号对目标仓库有 admin 权限。

### 脚本会做什么

对每个非归档仓库调用 `PATCH /repos/{org}/{repo}`：

| 参数 | 值 | 含义 |
| --- | --- | --- |
| `allow_merge_commit` | `false` | 禁止 merge commit |
| `allow_rebase_merge` | `false` | 禁止 rebase merge |
| `allow_squash_merge` | `true` | 允许 squash merge |
| `squash_merge_commit_title` | `PR_TITLE` | squash 提交标题 = PR 标题 |
| `squash_merge_commit_message` | `PR_BODY` | squash 提交正文 = PR 描述 |

已归档的仓库会跳过（归档后为只读，PR 本身也无法合并）。被 GitHub 封锁（HTTP 451，如 DMCA 下架）的仓库同样无法访问，脚本会将其标记为跳过。

## 维护

- **新建仓库后需要重跑脚本**，因为仓库级设置不会继承。

  ```bash
  scripts/enforce-squash-merge.sh
  ```

- 检查某个仓库当前设置：

  ```bash
  gh api /repos/bgzolab/<repo> \
    --jq '{allow_merge_commit, allow_squash_merge, allow_rebase_merge, squash_merge_commit_title, squash_merge_commit_message}'
  ```

- 预先演练（不产生修改）：

  ```bash
  scripts/enforce-squash-merge.sh --dry-run
  ```
