---
title: Linux块设备驱动
date: 2025-12-15 13:24:11
tags: [Linux, device, driver]
---


>最近在啃 Linux 块设备驱动，说实话，一开始比字符设备要懵不少。字符设备是“read/write → 我来拷数据”，而块设备背后是一整套 I/O 调度、请求队列、bio、request 的体系。

---

## 整体思路

**块设备驱动 ≠ 自己实现 read/write**

块设备驱动的核心是：

> **把上层文件系统的块 I/O 请求，翻译成对底层存储介质的读写操作**

文件系统、页缓存、I/O 合并、调度，这些内核都帮你做好了，你只需要：

* 接住请求
* 处理请求
* 告诉内核：我搞定了（或失败了）

---

## 开始之前 先搞清楚Linux 块设备的整体分层框架

在真正写块设备驱动之前，我吃过一个很大的亏：
**直接看代码，看 `bio`、`request`、`make_request_fn`，越看越乱。**

后来才意识到一个问题：

> **块设备驱动不是“一个层”，而是“整个 I/O 栈的最底层一环”。**

所以我现在习惯，**先在脑子里画一张分层图**。


### 块设备 I/O 的整体分层（自顶向下）

```
┌────────────────────────────┐
│        用户空间              │
│  cp / dd / mount / fsck    │
└────────────┬───────────────┘
             │ read/write
┌────────────▼───────────────┐
│        VFS 层               │
│  struct file / inode       │
└────────────┬───────────────┘
             │
┌────────────▼───────────────┐
│        文件系统层            │
│  ext4 / xfs / f2fs         │
└────────────┬───────────────┘
             │ page cache
┌────────────▼───────────────┐
│        通用块层              │
│  bio / request / elevator  │
│  I/O 合并、调度、重排         │
└────────────┬───────────────┘
             │
┌────────────▼───────────────┐
│     块设备驱动（我写的）       │
│  make_request / queue_rq   │
└────────────┬───────────────┘
             │
┌────────────▼───────────────┐
│      硬件 / 存储介质        │
│  eMMC / SSD / NVMe / RAM   │
└────────────────────────────┘
```

**块设备驱动，只负责最下面这一层**

### 为什么块设备驱动没有 read/write？

这是我最早困惑的问题之一。

字符设备是这样的：

```
用户 read()
  → 驱动 read()
```

但块设备是：

```
用户 read()
  → VFS
    → 文件系统
      → page cache
        → bio
          → 块设备驱动
```

所以：

> **块设备驱动看到的已经不是“文件读写”，而是“块 I/O 请求”**

这也是为什么：

* `struct block_device_operations` 里没有 `.read / .write`
* 真正的数据路径在 `bio` / `request`


### 通用块层：内核帮我做了什么？

在我真正处理 I/O 之前，**通用块层已经干了大量工作**。

它主要负责：

* 把文件 I/O 转换成块 I/O
* 页缓存（page cache）
* bio 合并（I/O 聚合）
* I/O 调度（deadline / bfq / none）
* 顺序优化、重排

我写的驱动 **完全不用关心这些**。


#### 1️⃣ bio：块 I/O 的最小描述单元

```c
struct bio {
    sector_t        bi_sector;
    struct bio_vec *bi_io_vec;
    struct bvec_iter bi_iter;
    ...
};
```

我现在的理解是：

> **bio = “从某个逻辑扇区开始，对一段数据做读/写”**

特点：

* 可能跨多个 page
* 内存不一定连续
* 但逻辑地址（sector）是连续的

---

#### 2️⃣ request：多个 bio 的集合

在 `blk-mq` 之前：

```
多个 bio
   ↓
合并成 request
   ↓
送给驱动
```

在 `blk-mq` 之后：

* request 仍然存在
* 但调度和分发更并行


### 块设备驱动在分层中的位置

现在再回头看块设备驱动，其实非常清晰：

```
通用块层
   │
   │  bio / request
   ▼
块设备驱动
   │
   │  sector → 物理地址
   ▼
硬件操作
```

我在驱动里要做的事，本质只有三步：

1. **解析 I/O 请求**

   * 起始 sector
   * 数据长度
   * 读 or 写

2. **完成数据传输**

   * memcpy（内存盘）
   * DMA（真实设备）

3. **通知内核完成**

   * `bio_endio()` 或 `blk_mq_end_request()`

---

### 两种常见的块设备驱动模型

#### 1️⃣ make_request 模型（简单、好理解）

```
bio
 ↓
make_request_fn
 ↓
设备读写
 ↓
bio_endio
```

特点：

* 驱动直接处理 bio
* 不关心 request
* 非常适合：

  * 内存块设备
  * loop 设备
  * 学习用途

---

#### 2️⃣ blk-mq 模型（现代、高性能）

```
bio
 ↓
request
 ↓
blk_mq_ops.queue_rq
 ↓
设备提交
 ↓
blk_mq_end_request
```

特点：

* 多队列
* 多 CPU 并行
* 几乎所有新存储设备都用它

---

### 从“分层”角度再看 gendisk / queue

现在我再看这几个结构，就非常顺了：

#### gendisk —— “设备对外的门面”

* 设备名
* 容量
* 主次设备号
* 和文件系统打交道

#### request_queue —— “I/O 入口”

* 通用块层 → 驱动的接口
* I/O 在这里排队、下发

---


> **块设备驱动不是给“人”用的，而是给“文件系统和块层”用的。**

所以：

* 不要站在 `cp / dd` 的角度想
* 要站在 **bio / sector / page** 的角度想

---


## 理解完框架后，再来看块设备驱动的整体流程

我一般把编写流程拆成下面几步 

```
模块加载
  ↓
申请主设备号
  ↓
分配 gendisk
  ↓
初始化 request_queue
  ↓
绑定 disk 与 queue
  ↓
add_disk()
  ↓
等待 I/O 请求
```

---

## 模块初始化：申请主设备号

### 1️⃣ register_blkdev()

```c
int major;

major = register_blkdev(0, "my_blkdev");
if (major < 0) {
    pr_err("register_blkdev failed\n");
    return major;
}
```

* `0`：让内核动态分配主设备号
* `"my_blkdev"`：在 `/proc/devices` 里看到的名字

> 📌 **块设备一定要有主设备号，没有就没法创建设备节点**

---

## 分配并初始化 gendisk（核心对象）

### 2️⃣ alloc_disk()

```c
struct gendisk *gd;

gd = alloc_disk(1);   // 次设备号数量
```

`gendisk` 是块设备在内核中的“门面”，非常关键。

### 常用成员设置

```c
gd->major = major;
gd->first_minor = 0;
gd->fops = &my_blk_fops;
gd->private_data = dev;
snprintf(gd->disk_name, 32, "myblk");
```

---

## block_device_operations（不像字符设备那么重要）

```c
static const struct block_device_operations my_blk_fops = {
    .owner = THIS_MODULE,
    .open  = my_blk_open,
    .release = my_blk_release,
};
```

注意：

* **块设备驱动并不关心 read/write**
* `open()` 只是打开整个设备（不是文件）

---

## 初始化请求队列（真正的灵魂）

### 3️⃣ blk_alloc_queue() / blk_mq_init_queue()

老接口（简单）：

```c
struct request_queue *queue;

queue = blk_alloc_queue(GFP_KERNEL);
blk_queue_make_request(queue, my_make_request);
```

现代推荐（blk-mq，多队列）：

```c
queue = blk_mq_init_sq_queue(&tag_set,
                             my_queue_rq,
                             128,
                             BLK_MQ_F_SHOULD_MERGE);
```

> 📌 学习阶段，**建议先理解 `make_request_fn` 版本**

---

## 处理 I/O：make_request_fn

### 4️⃣ make_request_fn

```c
static blk_qc_t my_make_request(struct request_queue *q, struct bio *bio)
{
    struct bio_vec bvec;
    struct bvec_iter iter;
    sector_t sector = bio->bi_iter.bi_sector;

    bio_for_each_segment(bvec, bio, iter) {
        void *buf = kmap_atomic(bvec.bv_page) + bvec.bv_offset;
        unsigned int len = bvec.bv_len;

        if (bio_data_dir(bio) == READ) {
            // 从设备读到 buf
        } else {
            // 从 buf 写到设备
        }

        kunmap_atomic(buf);
        sector += len >> 9;
    }

    bio_endio(bio);
    return BLK_QC_T_NONE;
}
```

这里是**块设备驱动最核心的地方**：

* `bio`：一次 I/O 请求
* `bio_vec`：bio 可能是 **非连续内存**
* `bi_sector`：逻辑扇区号（512B 为单位）

---

## 绑定 queue 和 gendisk

### 5️⃣ 连接起来

```c
gd->queue = queue;
set_capacity(gd, dev->size_in_sectors);
```

* `set_capacity()` 决定了 `fdisk -l` 看到的容量

---

## 注册块设备

### 6️⃣ add_disk()

```c
add_disk(gd);
```

到这一步：

* `/dev/myblk` 出现
* 可以 `fdisk`
* 可以 `mkfs`
* 可以 `mount`

🎉 **块设备正式上线**

---

## 模块卸载时的清理顺序

我一般按这个顺序：

```c
del_gendisk(gd);
put_disk(gd);

blk_cleanup_queue(queue);

unregister_blkdev(major, "my_blkdev");
```

**顺序错了，很容易 oops**

---

## 块设备驱动常用 API 总结

### 设备相关

| API             | 作用         |
| --------------- | ---------- |
| register_blkdev | 注册主设备号     |
| alloc_disk      | 分配 gendisk |
| add_disk        | 注册磁盘       |
| del_gendisk     | 删除磁盘       |

---

### 请求队列

| API                    | 作用                 |
| ---------------------- | ------------------ |
| blk_alloc_queue        | 分配 request_queue   |
| blk_queue_make_request | 设置 make_request_fn |
| bio_endio              | 通知 I/O 完成          |

---

### bio 相关

| API                  | 作用     |
| -------------------- | ------ |
| bio_for_each_segment | 遍历 bio |
| bio_data_dir         | 判断读/写  |
| kmap_atomic          | 映射页    |
| kunmap_atomic        | 解除映射   |

---

## 我的一点体会

* **先写一个“内存块设备”**（ramdisk 风格）
* 不要一上来就啃 blk-mq
* 真正理解：

  * `bio` 为什么不是连续内存
  * `sector` 和 `offset` 的关系
* 块设备驱动更像是：

  > **“协议适配层”**，而不是“数据搬运工”
