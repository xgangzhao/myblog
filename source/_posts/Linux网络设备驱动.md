---
title: Linux网络设备驱动
date: 2025-12-15 13:53:29
tags: [Linux, device, driver]
---

>写网络驱动这件事，一开始真的挺“玄学”的：
`net_device`、`sk_buff`、`ndo_xxx`、NAPI、netif_rx ……名字都认识，但一连起来就迷糊。

后来发现：**网络驱动比字符 / 块设备更“子系统化”**，如果不先理解整体分层，直接啃代码会非常痛苦。

这篇我就按 **“先框架 → 再步骤 → 最后 API”** 的顺序记录一下我的理解。

---

## Linux 网络设备驱动的整体分层框架

从上到下看，Linux 网络子系统大致可以分为 5 层：

```
+-------------------------------+
|        用户空间 (User)          |
|  socket / send / recv         |
+-------------------------------+
|      协议栈 (TCP/IP)           |
|  tcp/ip / udp / icmp          |
+-------------------------------+
|   网络核心层 (net core)         |
|  net_device / sk_buff         |
+-------------------------------+
|  网络设备驱动层 (driver)         |
|  ndo_open / ndo_start_xmit    |
+-------------------------------+
|      硬件层 (MAC / PHY)        |
|  DMA / 中断 / 寄存器            |
+-------------------------------+
```

### 1️⃣ 用户空间

* socket、bind、connect、send、recv
* 完全感知不到“驱动”存在

### 2️⃣ 协议栈

* TCP / UDP / IP / ARP
* 这里处理的是 **“数据语义”**
* 通过 `struct sk_buff` 与下层交互

### 3️⃣ 网络核心层（net core）

这是**驱动最重要的对接层**：

* 维护 `struct net_device`
* 维护网络设备状态
* 调用驱动提供的 `ndo_xxx` 回调

**网络驱动本质上就是：实现 net_device 的一组回调函数**

### 4️⃣ 网络设备驱动层

驱动真正干活的地方：

* 发包：把 skb 转成 DMA 数据
* 收包：把 DMA 数据封装成 skb
* 管理中断、队列、NAPI

### 5️⃣ 硬件层

* MAC（控制以太网帧）
* PHY（物理层，MII / RMII / RGMII）
* DMA / IRQ / 寄存器

---

## 网络设备驱动的核心数据结构

### 1️⃣ struct net_device —— 网络设备的“身份证”

```c
struct net_device {
    char name[IFNAMSIZ];
    unsigned long state;
    const struct net_device_ops *netdev_ops;
    struct ethtool_ops *ethtool_ops;
    ...
};
```

* **每一个网卡 = 一个 net_device**
* `ifconfig` / `ip link` 操作的就是它

### 2️⃣ struct net_device_ops —— 驱动必须实现的回调

```c
struct net_device_ops {
    int  (*ndo_open)(struct net_device *dev);
    int  (*ndo_stop)(struct net_device *dev);
    netdev_tx_t (*ndo_start_xmit)(struct sk_buff *skb,
                                 struct net_device *dev);
    ...
};
```

这是网络驱动的**灵魂**。

---

## Linux 网络设备驱动的主要编写步骤

下面是我自己总结的一个“驱动骨架流程”。

---

### 第一步：分配并初始化 net_device

```c
struct net_device *ndev;

ndev = alloc_etherdev(sizeof(struct priv_data));
```

* `alloc_etherdev()` 会：

  * 分配 `net_device`
  * 初始化以太网相关字段
  * 预留私有数据区

获取私有数据：

```c
struct priv_data *priv = netdev_priv(ndev);
```

---

### 第二步：设置 net_device 的关键字段

```c
ndev->netdev_ops = &my_netdev_ops;
ndev->ethtool_ops = &my_ethtool_ops;
ndev->irq = irq_num;
```

常见还会设置：

```c
ndev->watchdog_timeo = msecs_to_jiffies(5000);
```

---

### 第三步：注册网络设备

```c
register_netdev(ndev);
```

或者：

```c
register_netdevice(ndev);
```

注册成功后：

* `/sys/class/net/ethX` 出现
* `ifconfig -a` 能看到设备

**从这里开始，协议栈就“认识”这张网卡了**

---

### 第四步：实现 ndo_open / ndo_stop

#### ndo_open（ifconfig ethX up）

```c
static int my_open(struct net_device *ndev)
{
    request_irq(ndev->irq, my_irq_handler, 0,
                ndev->name, ndev);

    netif_start_queue(ndev);
    return 0;
}
```

主要做三件事：

1. 申请中断
2. 初始化 DMA / 硬件
3. 启动发送队列

---

#### ndo_stop（ifconfig ethX down）

```c
static int my_stop(struct net_device *ndev)
{
    netif_stop_queue(ndev);
    free_irq(ndev->irq, ndev);
    return 0;
}
```

---

### 第五步：实现发包函数 ndo_start_xmit

```c
static netdev_tx_t
my_start_xmit(struct sk_buff *skb, struct net_device *ndev)
{
    // 1. 映射 DMA
    // 2. 把 skb->data 交给硬件
    // 3. 通知 MAC 发送

    dev_kfree_skb(skb);
    return NETDEV_TX_OK;
}
```

关键理解点：

* **协议栈已经把数据准备好了**
* 驱动只负责“怎么送到网卡”

---

### 第六步：收包（中断 / NAPI）

典型流程：

```
硬件收到数据
   ↓
触发中断
   ↓
驱动从 DMA 取数据
   ↓
构造 sk_buff
   ↓
netif_rx() / napi_gro_receive()
```

示例：

```c
skb = netdev_alloc_skb(ndev, len);
memcpy(skb_put(skb, len), data, len);

skb->protocol = eth_type_trans(skb, ndev);
netif_rx(skb);
```

---

### 第七步：NAPI（高性能必备）

```c
netif_napi_add(ndev, &priv->napi, my_poll, 64);
napi_enable(&priv->napi);
```

在 `poll()` 中批量收包：

```c
static int my_poll(struct napi_struct *napi, int budget)
{
    int work_done = 0;

    while (work_done < budget) {
        // 收包
        work_done++;
    }

    if (work_done < budget)
        napi_complete(napi);

    return work_done;
}
```

---

### 第八步：卸载驱动

```c
unregister_netdev(ndev);
free_netdev(ndev);
```

---

## 网络驱动中最常见的 API 总结

### 1️⃣ net_device 相关

| API               | 作用      |
| ----------------- | ------- |
| alloc_etherdev    | 分配以太网设备 |
| register_netdev   | 注册设备    |
| unregister_netdev | 注销设备    |
| netdev_priv       | 获取私有数据  |

---

### 2️⃣ skb 相关

| API            | 作用     |
| -------------- | ------ |
| dev_alloc_skb  | 分配 skb |
| skb_put        | 增加数据长度 |
| eth_type_trans | 设置协议类型 |
| dev_kfree_skb  | 释放 skb |

---

### 3️⃣ 发送 / 接收相关

| API               | 作用          |
| ----------------- | ----------- |
| netif_start_queue | 启动发送队列      |
| netif_stop_queue  | 停止发送        |
| netif_rx          | 提交 skb 给协议栈 |
| napi_gro_receive  | NAPI 接收     |

---

### 4️⃣ PHY / MDIO（进阶）

* `mdiobus_register`
* `phy_connect`
* `phy_start`
* `phy_stop`

---

## 总结

> **网络驱动的本质，不是“实现协议”，而是“连接协议栈与硬件”**

* 协议栈关心的是 `sk_buff`
* net core 负责调度
* 驱动只关心：

  * skb 怎么变成 DMA
  * DMA 怎么变成 skb

只要抓住 **net_device + ndo_xxx + sk_buff** 这三条主线，网络驱动就不会乱。
