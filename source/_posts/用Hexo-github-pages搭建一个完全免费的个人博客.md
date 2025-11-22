---
title: 用Hexo & github pages搭建一个完全免费的个人博客
date: 2025-08-15 00:17:51
tags: [Hexo, github]
---

## 准备环境
1. 安装 Node.js（建议 LTS 版本）https://nodejs.org
2. 安装 Git https://git-scm.com

## 创建github repo
1. 新建仓库，命名为`username.github.io`, (username必须是你的github用户名)
2. 选择public （不需要初始化README）

## 安装Hexo
```bash
# 全局安装 Hexo
npm install -g hexo-cli

# 新建博客文件夹
hexo init myblog
cd myblog

# 安装依赖
npm install
```

## 本地预览
```bash
hexo server
```

## 配置部署到 github pages
1. 安装部署插件`npm install hexo-deployer-git --save`
2. 编辑 `_config.yml`（Hexo 根目录下），找到 deploy 部分，修改如下：
```bash
deploy:
  type: git
  repo: https://github.com/yourusername/yourusername.github.io.git
  branch: main
```
3. 生成并部署
```bash
hexo clean
hexo generate
hexo deploy
```
4. 点击访问`https://username.github.io`，就能看到博客的样子啦
这就上线啦！

5. 怎么写文章？用`hexo new post "豆角要不要炖太熟？`  
写完后运行`hexo clean && hexo generate && hexo deploy`

## 最后
github有时候不稳定，有条件的话可以买一个域名（阿里云、腾讯云都行）
在域名 DNS 里添加：
`CNAME  yourusername.github.io`

在 GitHub 仓库的 Settings > Pages 里绑定域名。

在博客根目录的 source 文件夹里加一个 CNAME 文件，写上你的域名。
我当初在阿里云上买的，9块钱一整年，白菜价！

---

>最后的最后。想当初我也是用同样的方法做过个人博客，后来github账号的MFA认证码丢了，账号就再也找不回来了，连带着以前做过的东西也丢了......